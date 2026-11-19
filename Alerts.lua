-- GameData, alertes d'hôtel des ventes : pas un tableau à surveiller, une fenêtre qui s'ouvre à côté de l'HV quand
-- il y a un coup à jouer, avec un bouton par ligne. Calculées dès que l'HV est lu (scan frais), ou à l'ouverture si
-- le dernier scan a moins de 15 min.
--
--   à vendre   ce que tu as (sacs du perso + sa banque vue la dernière fois) dont le moins cher en vente dépasse
--              d'au moins 25 % son prix habituel = médiane des prix minimum des scans d'avant (AuctionDB sur 7 jours,
--              sinon les nôtres ; au moins 4 scans sur 12 h, sinon on ne sait pas ce qui est « habituel »).
--              Prix proposé : 1 pc sous le moins cher. On garde si la vente rapporte plus que le marchand et au
--              moins 50 pa en tout (part de l'HV et dépôt 24 h déduits).
--              Bouton « Vendre » (HV ouvert, objet dans les sacs) : l'onglet Vendre de Blizzard reçoit l'objet, le
--              prix proposé et la quantité des sacs ; tu n'as plus qu'à cliquer « Mettre en vente ».
--              « Banque » : l'objet n'est qu'à la banque, itinéraire jusqu'à elle. « Y aller » : HV fermé, itinéraire.
--   Mécréant   les 3 meilleures affaires marchand -> HV ; « Y aller » = l'itinéraire de Mécréant.
-- La mise en vente elle-même reste un clic à toi (ToS). /gdata alertes = activer / couper,
-- /gdata opportunites = la fenêtre.
-- ponytail: les sacs des rerolls ne comptent pas (pas sous la main à l'HV) ; les ajouter si tu fais tes ventes depuis
-- un perso banque.
local _, ns = ...

local RISE, MIN_TOTAL, MIN_SCANS, MIN_HOURS, AH_CUT, FLIPS = 1.25, 5000, 4, 12, 0.05, 3

local function median(t)
  table.sort(t)
  local n = #t
  return n % 2 == 1 and t[(n + 1) / 2] or (t[n / 2] + t[n / 2 + 1]) / 2
end

-- cur = { min, qty }, hist = { {heure, min, quantité}, … }, sell = revente marchand d'une unité, owned = quantité,
-- rate = taux du dépôt 24 h, now = heure du scan courant. Renvoie l'alerte ou nil.
function ns.sellSignal(cur, hist, sell, owned, rate, now)
  if not cur or not cur.min or cur.min <= 1 or not hist or owned <= 0 then return nil end
  local mins, first = {}, nil
  for _, h in ipairs(hist) do
    if h[2] and h[2] > 0 and h[1] < now - 1800 then -- le scan courant ne compte pas dans « l'habituel »
      mins[#mins + 1] = h[2]
      first = first or h[1]
    end
  end
  if #mins < MIN_SCANS or (now - first) / 3600 < MIN_HOURS then return nil end
  local usual = median(mins)
  local price = cur.min - 1
  if price < usual * RISE then return nil end
  local net = price * (1 - AH_CUT) - (rate or 0) * (sell or 0)
  if net <= (sell or 0) then return nil end -- le marchand paie mieux
  local total = net * owned
  if total < MIN_TOTAL then return nil end
  local perDay = ns.turnover and ns.turnover(hist)
  return { price = price, usual = usual, rise = price / usual, owned = owned, total = total,
    extra = (price - usual) * (1 - AH_CUT) * owned, onSale = cur.qty, perDay = perDay }
end

local function count(conts)
  local n = {}
  for _, c in pairs(conts or {}) do
    for _, it in ipairs(c.items or {}) do
      if it.id then n[it.id] = (n[it.id] or 0) + (it.count or 1) end
    end
  end
  return n
end

local function house() return GetRealmName() .. "-" .. UnitFactionGroup("player") end
local function ahOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end

-- Les lignes « à vendre », recalculées à chaque changement des sacs (une vente faite disparaît de la liste).
local function sellRows()
  local m = GameDataMarket[house()]
  if not m or not m.items then return {} end
  local ahdb = ns.ahdbHouse and ns.ahdbHouse()
  local rate = (GameDataDB.deposit and GameDataDB.deposit.rate24) or 0.20
  local bags, bank, all = count(ns.containers(ns.isBag)), count(ns.char().bank), {}
  for id, q in pairs(bags) do all[id] = q end
  for id, q in pairs(bank) do all[id] = (all[id] or 0) + q end
  local rows = {}
  for id, qty in pairs(all) do
    local h = (ns.ahdbHistory and ns.ahdbHistory(ahdb, id)) or (m.hist and m.hist[id])
    local vdb = ns.VENDOR_DB and ns.VENDOR_DB[id]
    local it = GameDataItems.items and GameDataItems.items[id]
    local s = ns.sellSignal(m.items[id], h, (vdb and vdb[4]) or (it and it.price) or 0, qty, rate, m.time or time())
    if s then
      s.id, s.kind, s.bags, s.bank = id, "vente", bags[id] or 0, bank[id] or 0
      rows[#rows + 1] = s
    end
  end
  return rows
end

---------------------------------------------------------------------------------------------------
-- Actions des boutons
local function bagLocation(id)
  for name, bag in pairs(Enum.BagIndex) do
    if ns.isBag(name) then
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        local it = C_Container.GetContainerItemInfo(bag, slot)
        if it and it.itemID == id then return ItemLocation:CreateFromBagAndSlot(bag, slot) end
      end
    end
  end
end

local function sell(r)
  local loc = bagLocation(r.id)
  if not loc then return print("GameData : plus dans tes sacs.") end
  AuctionHouseFrame:SetPostItem(loc)
  local f = AuctionHouseFrame.CommoditiesSellFrame
  if not (f and f:IsShown()) then f = AuctionHouseFrame.ItemSellFrame end
  if not (f and f:IsShown() and f:GetItem()) then
    return print("GameData : le jeu n'a pas encore les infos de cet objet, reclique dans une seconde.")
  end
  -- Un prix différent du prix par défaut n'est plus écrasé par le « moins cher » que Blizzard sélectionne ensuite.
  f.PriceInput:SetAmount(r.price)
  if f.QuantityInput and f.QuantityInput:IsShown() then
    f.QuantityInput:SetQuantity(math.min(r.bags, f:GetMaxQuantity()))
  end
  f:UpdatePostState()
end

local function goSpot(spot, title, missing)
  if not spot then return print("GameData : " .. missing) end
  ns.navigate({ { map = spot.map, x = spot.x, y = spot.y, title = title .. (spot.zone and (" — " .. spot.zone) or "") } })
end

local function action(r)
  if r.kind == "mecreant" then return "Y aller", function() ns.goTo(r.deal) end end
  if r.bags > 0 and ahOpen() then return "Vendre", function() sell(r) end end
  if r.bags > 0 then
    return "Y aller", function() goSpot(GameDataDB.ah_spot, "Vendre à l'HV", "ouvre l'HV une fois pour que je sache où il est.") end
  end
  return "Banque", function()
    goSpot(GameDataDB.bank_spot, "Prendre à la banque", "ouvre ta banque une fois pour que je sache où elle est.")
  end
end

---------------------------------------------------------------------------------------------------
-- Fenêtre
local frame, tbl, flips = nil, nil, {}

local function name(r) return C_Item.GetItemNameByID(r.id) or "" end
local COLUMNS = {
  { key = "item", title = "Objet", w = 150, asc = true, get = name, fmt = function(_, r) return ns.itemLabel(r.id) end,
    icon = function(r) return C_Item.GetItemIconByID(r.id) end },
  { key = "kind", title = "Coup", w = 62, asc = true, get = function(r) return r.kind end,
    fmt = function(v) return v == "vente" and "|cff59cc73Vendre|r" or "|cffb4a0ffMécréant|r" end,
    tip = "Vendre : tu l'as et il se vend cher en ce moment. Mécréant : acheter chez un marchand, revendre ici." },
  { key = "where", title = "Où", w = 70, asc = true, get = function(r)
      if r.kind == "mecreant" then return r.deal.where or "" end
      return r.bags > 0 and (r.bank > 0 and "sacs + banque" or "sacs") or "banque"
    end, fmt = function(v) return v end },
  { key = "qty", title = "Qté", w = 40, align = "RIGHT", get = function(r) return r.kind == "vente" and r.owned or r.deal.qty end },
  { key = "price", title = "Prix", w = 58, align = "RIGHT", get = function(r) return r.price or r.deal.safe end, fmt = ns.moneyShort,
    tip = "Prix de vente à l'unité : 1 pc sous le moins cher (Mécréant : son prix sûr)." },
  { key = "usual", title = "Habituel", w = 58, align = "RIGHT", get = function(r) return r.usual end, fmt = ns.moneyShort,
    tip = "Médiane des prix minimum des scans précédents." },
  { key = "rise", title = "Hausse", w = 46, align = "RIGHT", get = function(r) return r.rise end,
    fmt = function(v) return v and ("+%d %%"):format(math.floor((v - 1) * 100 + 0.5)) or "–" end },
  { key = "gain", title = "Gain", w = 62, align = "RIGHT",
    get = function(r) return r.total or r.deal.netTravel or r.deal.profit end, fmt = ns.moneyShort,
    tip = "Vendre : ce que la vente rapporte (part de l'HV et dépôt déduits). Mécréant : gain net, vols déduits." },
  { key = "go", title = "", w = 62, button = function(r) return (action(r)) end,
    click = function(r) local _, fn = action(r) fn() end },
}

local function tooltip(r, tt)
  tt:SetItemByID(r.id)
  if r.kind ~= "vente" then return end
  tt:AddLine(" ")
  tt:AddDoubleLine("Dans tes sacs / à la banque", ("%d / %d"):format(r.bags, r.bank), 1, 1, 1, 1, 1, 1)
  tt:AddDoubleLine("En vente à l'HV", tostring(r.onSale or "?"), 1, 1, 1, 1, 1, 1)
  if r.perDay then tt:AddDoubleLine("Part par jour", ("~%d"):format(r.perDay), 1, 1, 1, 1, 1, 1) end
  if r.perDay and r.owned > r.perDay * 2 then
    tt:AddLine("Tu en as plus que 2 jours de ventes : n'en poste qu'une partie.", 0.9, 0.6, 0.3)
  end
end

local function refresh()
  if not (frame and frame:IsShown()) then return end
  local rows = sellRows()
  for _, d in ipairs(flips) do rows[#rows + 1] = { kind = "mecreant", id = d.id, deal = d } end
  local m = GameDataMarket[house()]
  frame.status:SetText(#rows == 0 and "Rien à saisir pour l'instant." or
    (("%d coup(s) — HV du %s"):format(#rows, m and m.scanned or "?")))
  tbl:SetData(rows)
  return #rows
end

local function build()
  frame = ns.newWindow("GameDataAlertFrame", "Alertes HV", 560, 300)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -36)
  hint:SetText("« Vendre » remplit l'onglet de vente de l'HV : il ne reste qu'à cliquer « Mettre en vente ».")
  local width
  tbl, width = ns.newTable(frame, COLUMNS, { name = "alertes", sort = "gain", top = 58, rowH = 20, tooltip = tooltip })
  frame:SetWidth(width + 50)
  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.status:SetPoint("BOTTOMLEFT", 14, 10)
  frame:SetScript("OnShow", refresh)
  -- sacs qui changent (objet mis en vente) et HV ouvert / fermé : les lignes et les boutons suivent
  frame:RegisterEvent("BAG_UPDATE_DELAYED")
  frame:RegisterEvent("AUCTION_HOUSE_SHOW")
  frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
  frame:SetScript("OnEvent", refresh)
end

local function showBesideAH()
  if not frame then build() end
  frame:ClearAllPoints()
  if ahOpen() then frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 8, 0) else frame:SetPoint("CENTER") end
  frame:Show()
  refresh()
end

function ns.toggleAlertWindow()
  if frame and frame:IsShown() then return frame:Hide() end
  showBesideAH()
end

local alertedFor -- une alerte par scan : pas de doublon si l'ouverture et la lecture tombent sur le même
function ns.ahAlerts()
  if GameDataDB.alerts_off then return end
  local m = GameDataMarket[house()]
  if not m or not m.items or m.time == alertedFor then return end
  alertedFor = m.time
  flips = {}
  if ns.flipOpportunities then
    local ok, deals = pcall(ns.flipOpportunities)
    for i = 1, ok and deals and math.min(FLIPS, #deals) or 0 do
      if deals[i].qty then flips[#flips + 1] = deals[i] end
    end
  end
  local n = #sellRows() + #flips
  if n == 0 then return end
  showBesideAH()
  pcall(RaidNotice_AddMessage, RaidWarningFrame, ("GameData : %d coup(s) à jouer à l'HV"):format(n),
    ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 0.7, g = 0.6, b = 1 })
  pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
end

-- Ouverture de l'HV sans nouveau scan (le jeu n'en accepte qu'un par 15 min) : on alerte sur le scan récent.
-- Ouverture de la banque : on retient où elle est, pour le bouton « Banque ».
local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("BANKFRAME_OPENED")
f:SetScript("OnEvent", function(_, event)
  if event == "BANKFRAME_OPENED" then
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
      local x, y = pos:GetXY()
      GameDataDB.bank_spot = { map = map, x = x, y = y, zone = GetSubZoneText() ~= "" and GetSubZoneText() or GetZoneText() }
    end
    return
  end
  alertedFor = nil -- chaque passage à l'HV a droit à son alerte
  C_Timer.After(1, function()
    local m = GameDataMarket[house()]
    if m and m.time and time() - m.time < 15 * 60 then pcall(ns.ahAlerts) end
  end)
end)
