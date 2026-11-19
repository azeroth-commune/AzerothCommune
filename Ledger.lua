-- GameData, journal de tes opérations : pour juger après coup ce qui a rapporté et ce qui n'a pas marché.
--   GameDataDB.ledger = { { t, who, kind, id, name, qty, money, … }, … }   (les 5 000 dernières)
--   money : ce qui entre (+) ou sort (−) de ta bourse, en cuivre. La somme par objet est donc le vrai bilan.
--   kind :
--     achat_marchand   acheté chez un marchand (BuyMerchantItem)
--     vente_marchand   vendu à un marchand (clic droit sur un objet, marchand ouvert)
--     mise_hv          mis en vente à l'HV : money = −dépôt ; unit, duration
--     achat_hv         acheté à l'HV (objets en lot : ConfirmCommoditiesPurchase, au prix annoncé par le jeu)
--     vente_hv         vendu à l'HV : inscrit dès l'onglet « Ventes » de l'HV (src = "hv", montants estimés), puis
--                      corrigé par la facture du courrier (mail = true) : money = prix − part de l'HV + dépôt rendu
--     retour_hv        annonce expirée ou annulée, revenue par courrier (le dépôt est perdu : déjà compté à la mise)
-- Les courriers ne sont lus que boîte aux lettres ouverte ; chaque courrier n'est compté qu'une fois.
local _, ns = ...

local MAX = 5000
local DURATION_FACTOR = { 0.5, 1, 2 } -- 12 h, 24 h, 48 h, par rapport au dépôt de 24 h

local function log(kind, id, qty, money, extra)
  GameDataDB.ledger = GameDataDB.ledger or {}
  local e = { t = time(), who = ns.charKey(), kind = kind, id = id, qty = qty, money = money }
  e.name = id and C_Item.GetItemNameByID(id) or nil
  for k, v in pairs(extra or {}) do e[k] = v end
  local l = GameDataDB.ledger
  l[#l + 1] = e
  while #l > MAX do table.remove(l, 1) end
end
ns.ledgerLog = log

local function sellPrice(id)
  local p = select(11, C_Item.GetItemInfo(id))
  if p and p > 0 then return p end
  local vdb = ns.VENDOR_DB and ns.VENDOR_DB[id]
  return vdb and vdb[4] or 0
end

-- Dépôt selon la règle mesurée (Flip.lua) : 20 % du prix de revente pour 24 h sur Forever, plus de minimum à 1 pa.
local function deposit(id, duration, qty)
  local d = GameDataDB.deposit or {}
  local per = sellPrice(id) * (d.rate24 or 0.20) * (DURATION_FACTOR[duration] or 1)
  return math.max(d.min or 1, math.floor(per * qty))
end

---------------------------------------------------------------------------------------------------
-- Marchands
hooksecurefunc("BuyMerchantItem", function(index, quantity)
  local ok = pcall(function()
    local info = C_MerchantFrame.GetItemInfo(index)
    local id = GetMerchantItemID(index)
    if not (info and id and info.price and info.price > 0) or info.hasExtendedCost then return end
    local stack = math.max(1, info.stackCount or 1)
    local qty = quantity or stack
    log("achat_marchand", id, qty, -math.floor(info.price * qty / stack + 0.5), { unit = info.price / stack })
  end)
  if not ok then GameDataDB.errors.ledger_buy = ns.now() end
end)

hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  pcall(function()
    local it = C_Container.GetContainerItemInfo(bag, slot)
    if not (it and it.itemID) or it.hasNoValue then return end
    local p = sellPrice(it.itemID)
    if p > 0 then log("vente_marchand", it.itemID, it.stackCount or 1, p * (it.stackCount or 1), { unit = p }) end
  end)
end)

---------------------------------------------------------------------------------------------------
-- Hôtel des ventes
hooksecurefunc(C_AuctionHouse, "PostCommodity", function(item, duration, quantity, unitPrice)
  pcall(function()
    local id = C_Item.GetItemID(item)
    local dep = C_AuctionHouse.CalculateCommodityDeposit(id, duration, quantity) or deposit(id, duration, quantity)
    log("mise_hv", id, quantity, -dep, { unit = unitPrice, duration = duration, deposit = dep })
  end)
end)

hooksecurefunc(C_AuctionHouse, "PostItem", function(item, duration, quantity, bid, buyout)
  pcall(function()
    local id = C_Item.GetItemID(item)
    local dep = deposit(id, duration, 1) * quantity -- objet non empilable : une annonce par objet
    log("mise_hv", id, quantity, -dep, { unit = buyout or bid, duration = duration, deposit = dep })
  end)
end)

local quote = {} -- itemID -> prix total annoncé par le jeu pour l'achat en cours
local buying
hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(id) buying = id end)
hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(id, quantity)
  pcall(function()
    local total = quote[id]
    if total then log("achat_hv", id, quantity, -total, { unit = total / math.max(1, quantity) }) end
  end)
end)

---------------------------------------------------------------------------------------------------
-- Courriers : factures de l'HV (ventes) et annonces revenues (expirées, annulées).
local nameIndex
local function idByName(name)
  if not name then return nil end
  for i = #(GameDataDB.ledger or {}), 1, -1 do -- d'abord ce qu'on a mis en vente
    local e = GameDataDB.ledger[i]
    if e.name == name and e.id then return e.id end
  end
  if not nameIndex then
    nameIndex = {}
    for id, it in pairs(GameDataItems.items or {}) do if it.name then nameIndex[it.name] = id end end
  end
  return nameIndex[name]
end

local function subjectPattern(fmt)
  return fmt and ("^" .. fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$")
end

-- Onglet « Ventes » de l'HV : une annonce vendue y apparaît tout de suite (bien avant le courrier), avec son prix de
-- vente total (buyoutAmount, avant la part de l'HV : 26 charbons = 1 po 20 pa 38, soit 4 pa 63 l'unité, le 18/11/2026).
-- On l'inscrit aussitôt (prix − 5 % + dépôt rendu estimé) ; la facture du courrier, plus tard, remplace ces montants
-- par les vrais au lieu d'ajouter une deuxième vente.
local function scanOwned()
  GameDataDB.ledger_sold = GameDataDB.ledger_sold or {}
  local done = GameDataDB.ledger_sold
  for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
    local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
    if a and a.status == Enum.AuctionStatus.Sold and not done[a.auctionID] then
      done[a.auctionID] = time()
      local id, gross = a.itemKey and a.itemKey.itemID, tonumber(a.buyoutAmount or a.bidAmount) or 0
      local refund = 0
      for j = #(GameDataDB.ledger or {}), 1, -1 do -- dépôt par unité de la dernière mise en vente de cet objet
        local e = GameDataDB.ledger[j]
        if e.kind == "mise_hv" and e.id == id and e.qty > 0 then refund = math.floor((e.deposit or 0) / e.qty * a.quantity) break end
      end
      log("vente_hv", id, a.quantity, math.floor(gross * 0.95) + refund,
        { gross = gross, cut = gross - math.floor(gross * 0.95), deposit = refund, src = "hv", unit = gross / math.max(1, a.quantity) })
    end
  end
  for k, t in pairs(done) do if time() - t > 40 * 86400 then done[k] = nil end end
end

-- La facture d'une vente déjà inscrite depuis l'onglet « Ventes » : on corrige ses montants plutôt que d'en ajouter une.
local function matchSale(id, name, qty)
  for i = #(GameDataDB.ledger or {}), 1, -1 do
    local e = GameDataDB.ledger[i]
    if e.kind == "vente_hv" and e.src == "hv" and not e.mail and e.qty == qty and ((id and e.id == id) or e.name == name) then return e end
  end
end

local function scanMail()
  GameDataDB.ledger_seen = GameDataDB.ledger_seen or {}
  local seen = GameDataDB.ledger_seen
  local returned = { subjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT), subjectPattern(AUCTION_REMOVED_MAIL_SUBJECT) }
  for i = 1, GetInboxNumItems() do
    local _, _, _, subject, money, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
    -- clé stable d'une session à l'autre : sujet, argent et heure d'expiration du courrier
    local key = ("%s|%.0f|%.0f"):format(subject or "", money or 0, math.floor((time() + (daysLeft or 0) * 86400) / 3600))
    if subject and not seen[key] then
      local kind, name, _, bid, _, dep, cut, _, _, _, count = GetInboxInvoiceInfo(i)
      if kind == "seller" then
        seen[key] = time()
        local id = idByName(name)
        local e = matchSale(id, name, count or 1)
        if e then e.money, e.gross, e.cut, e.deposit, e.mail = money or 0, bid, cut, dep, true
        else log("vente_hv", id, count or 1, money or 0, { name = name, gross = bid, cut = cut, deposit = dep, mail = true }) end
      elseif (itemCount or 0) > 0 and (money or 0) == 0 and not kind then
        for _, pat in ipairs(returned) do
          local itemName = pat and subject:match(pat)
          if itemName then
            seen[key] = time()
            local _, _, _, qty = GetInboxItem(i, 1)
            log("retour_hv", idByName(itemName), qty or 1, 0, { name = itemName })
            break
          end
        end
      end
    end
  end
  for k, t in pairs(seen) do if time() - t > 40 * 86400 then seen[k] = nil end end -- un courrier vit 30 jours
end

local f = CreateFrame("Frame")
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:RegisterEvent("COMMODITY_PRICE_UPDATED")
f:RegisterEvent("OWNED_AUCTIONS_UPDATED")
f:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "COMMODITY_PRICE_UPDATED" then
    if buying then quote[buying] = a2 end -- prix total de l'achat en cours
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    local ok, err = pcall(scanOwned)
    GameDataDB.errors.ledger_owned = (not ok) and tostring(err) or nil
  else
    local ok, err = pcall(scanMail)
    GameDataDB.errors.ledger_mail = (not ok) and tostring(err) or nil
  end
end)

---------------------------------------------------------------------------------------------------
-- Bilan par objet : ce qui est entré et sorti, ce qui est encore en vente.
function ns.ledgerSummary(days)
  local since = days and (time() - days * 86400) or 0
  local by, total = {}, 0
  for _, e in ipairs(GameDataDB.ledger or {}) do
    if e.t >= since then
      local key = e.id or e.name or "?"
      local s = by[key] or { id = e.id, name = e.name, money = 0, bought = 0, spent = 0, sold = 0, earned = 0, posted = 0, back = 0, deposits = 0, last = 0 }
      s.money, s.last = s.money + (e.money or 0), math.max(s.last, e.t)
      if e.kind == "achat_marchand" or e.kind == "achat_hv" then s.bought, s.spent = s.bought + e.qty, s.spent - e.money
      elseif e.kind == "vente_hv" or e.kind == "vente_marchand" then s.sold, s.earned = s.sold + e.qty, s.earned + e.money
      elseif e.kind == "mise_hv" then s.posted, s.deposits = s.posted + e.qty, s.deposits - e.money
      elseif e.kind == "retour_hv" then s.back = s.back + e.qty end
      by[key] = s
      total = total + (e.money or 0)
    end
  end
  local list = {}
  for _, s in pairs(by) do
    s.onSale = math.max(0, s.posted - s.back - s.sold) -- grossier : les ventes au marchand comptent aussi
    list[#list + 1] = s
  end
  table.sort(list, function(a, b) return a.last > b.last end)
  return list, total
end

local frame, byItem, ops
local PERIODS = { { 1, "24 h" }, { 7, "7 jours" }, { 30, "30 jours" }, { nil, "tout" } }
local KIND = { achat_marchand = "Achat marchand", vente_marchand = "Vente marchand", mise_hv = "Mise en vente",
  achat_hv = "Achat HV", vente_hv = "Vente HV", retour_hv = "Retour HV" }
local function date(t) return t and t > 0 and _G.date("%d/%m %H:%M", t) or "–" end
local function itemName(e) return e.id and (C_Item.GetItemNameByID(e.id) or e.name) or e.name or "" end
local function itemText(_, e) return e.id and ns.itemLabel(e.id) or (e.name or "?") end
local function itemIcon(e) return e.id and C_Item.GetItemIconByID(e.id) or 134400 end
local function count(v) return (v and v > 0) and tostring(v) or "|cff666666–|r" end
local function avg(total, n) if n and n > 0 then return total / n end end

local BY_ITEM = {
  { key = "item", title = "Objet", w = 170, asc = true, get = itemName, fmt = itemText, icon = itemIcon },
  { key = "bought", title = "Acheté", w = 46, align = "RIGHT", get = function(s) return s.bought end, fmt = count },
  { key = "buyAvg", title = "Prix moy.", w = 60, align = "RIGHT", get = function(s) return avg(s.spent, s.bought) end,
    fmt = ns.moneyShort, tip = "Prix d'achat moyen à l'unité." },
  { key = "sold", title = "Vendu", w = 46, align = "RIGHT", get = function(s) return s.sold end, fmt = count },
  { key = "sellAvg", title = "Prix moy.", w = 60, align = "RIGHT", get = function(s) return avg(s.earned, s.sold) end,
    fmt = ns.moneyShort, tip = "Encaissé en moyenne par unité vendue (part de l'HV déduite, dépôt rendu compris)." },
  { key = "deposits", title = "Dépôts", w = 56, align = "RIGHT", get = function(s) return s.deposits end, fmt = ns.moneyShort,
    tip = "Dépôts versés à la mise en vente (rendus si l'objet se vend)." },
  { key = "onSale", title = "En vente", w = 50, align = "RIGHT", get = function(s) return s.onSale end, fmt = count,
    tip = "Estimation : mis en vente − revenus − vendus." },
  { key = "money", title = "Bilan", w = 70, align = "RIGHT", get = function(s) return s.money end, fmt = ns.moneySigned,
    tip = "Tout ce qui est entré moins tout ce qui est sorti pour cet objet." },
  { key = "yield", title = "Rend.", w = 46, align = "RIGHT", get = function(s) return s.spent > 0 and s.money / s.spent or nil end,
    fmt = function(v) return v and ((v >= 0 and "|cff59cc73" or "|cffe64d4d") .. ("%+d %%|r"):format(math.floor(v * 100 + 0.5))) or "–" end,
    tip = "Bilan rapporté à ce qui a été dépensé en achats." },
  { key = "last", title = "Dernière", w = 74, align = "RIGHT", get = function(s) return s.last end, fmt = date },
}

local OPS = {
  { key = "t", title = "Date", w = 74, get = function(e) return e.t end, fmt = date },
  { key = "who", title = "Perso", w = 90, asc = true, get = function(e) return (e.who or ""):match("^[^-]+") or "" end,
    fmt = function(v) return v end },
  { key = "kind", title = "Opération", w = 96, asc = true, get = function(e) return KIND[e.kind] or e.kind end,
    fmt = function(v, e) return (e.money or 0) >= 0 and v or ("|cffcccccc" .. v .. "|r") end },
  { key = "item", title = "Objet", w = 170, asc = true, get = itemName, fmt = itemText, icon = itemIcon },
  { key = "qty", title = "Qté", w = 40, align = "RIGHT", get = function(e) return e.qty end },
  { key = "unit", title = "Prix/u", w = 60, align = "RIGHT",
    get = function(e) return (e.qty or 0) > 0 and math.abs(e.money or 0) / e.qty or nil end, fmt = ns.moneyShort },
  { key = "money", title = "Montant", w = 70, align = "RIGHT", get = function(e) return e.money end, fmt = ns.moneySigned },
  { key = "src", title = "", w = 60, get = function(e) return e.kind == "vente_hv" and (e.mail and "facture" or "estimé") or nil end,
    fmt = function(v) return v and ("|cff999999" .. v .. "|r") or "" end,
    tip = "Vente HV : « estimé » tant que la facture du courrier n'a pas confirmé le montant." },
}

local function refresh()
  if not (frame and frame:IsShown()) then return end
  local days = PERIODS[frame.period][1]
  local list, total = ns.ledgerSummary(days)
  local since, entries = days and (time() - days * 86400) or 0, {}
  for _, e in ipairs(GameDataDB.ledger or {}) do if e.t >= since then entries[#entries + 1] = e end end
  frame.status:SetText(("Bilan sur %s : %s — %d objet(s), %d opération(s)"):format(PERIODS[frame.period][2],
    ns.moneySigned(total), #list, #entries))
  byItem:SetShown(frame.view == 1)
  ops:SetShown(frame.view == 2)
  if frame.view == 1 then byItem:SetData(list) else ops:SetData(entries) end
  for i, b in ipairs(frame.periodButtons) do b:SetEnabled(i ~= frame.period) end
  for i, b in ipairs(frame.viewButtons) do b:SetEnabled(i ~= frame.view) end
end

local function build()
  frame = ns.newWindow("GameDataLedgerFrame", "Journal", 600, 460)
  frame.period, frame.view = 2, 1
  frame.periodButtons, frame.viewButtons = {}, {}
  for i, p in ipairs(PERIODS) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(76, 20)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 80, -40)
    b:SetText(p[2])
    b:SetScript("OnClick", function() frame.period = i; refresh() end)
    frame.periodButtons[i] = b
  end
  for i, label in ipairs({ "Par objet", "Opérations" }) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(90, 20)
    b:SetPoint("TOPRIGHT", -14 - (2 - i) * 94, -40)
    b:SetText(label)
    b:SetScript("OnClick", function() frame.view = i; refresh() end)
    frame.viewButtons[i] = b
  end
  local w1, w2
  byItem, w1 = ns.newTable(frame, BY_ITEM, { name = "journal_objets", sort = "money", top = 70 })
  ops, w2 = ns.newTable(frame, OPS, { name = "journal_ops", sort = "t", top = 70 })
  frame:SetWidth(math.max(w1, w2) + 50)
  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.status:SetPoint("BOTTOMLEFT", 14, 10)
  frame:SetScript("OnShow", refresh)
end

function ns.toggleLedgerWindow()
  if not frame then build() end
  frame:SetShown(not frame:IsShown())
end
