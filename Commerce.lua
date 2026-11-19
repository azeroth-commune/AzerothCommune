-- GameData, partie commerce : recettes, maîtres de métier, marchands et hôtel des ventes.
--   GameDataDB.recipes[clé]  : chaque recette vue dans une fenêtre de métier, avec ce qu'elle produit et ses
--                              composants. Clé = ID du sort de la recette quand le jeu le donne, sinon « Métier:Nom ».
--   chars[perso].recipes      : par métier, rang, maximum et recettes connues (clé -> difficulté,
--                              ou true quand relevée sans fenêtre).
--   GameDataDB.trainers[npc]  : ce que chaque maître enseigne, à quel prix, quel rang et quel niveau requis.
--   GameDataDB.vendors[npc]   : ce que chaque marchand vend, à quel prix, par combien, en stock limité ou non.
--   GameDataDB.taxi[départ]   : prix des vols depuis chaque maître de vol ouvert.
--   GameDataMarket[royaume-faction] : dernier scan complet de l'hôtel des ventes : par objet, le prix unitaire le
--                              plus bas, la quantité en vente et les paliers de prix les moins chers.
-- Rien ne se lit sans la fenêtre ouverte (sauf les recettes connues, relevées aussi à la connexion parmi celles déjà
-- vues) : ouvre tes métiers, parle aux maîtres et aux marchands, ouvre l'HV.
local _, ns = ...

local function itemIDOf(link) return tonumber(link and link:match("item:(%d+)")) end

-- L'ID du sort d'une recette se lit dans son lien (« |Henchant:2662| » ou « |Hspell:…| ») ;
-- sans lien, le métier et le nom servent de clé.
local function recipeKey(link, prof, name)
  return tonumber(link and (link:match("enchant:(%d+)") or link:match("spell:(%d+)"))) or (prof .. ":" .. name)
end
ns.itemIDOf, ns.recipeKey = itemIDOf, recipeKey

local function safe(name, fn, ...)
  local ok, err = pcall(fn, ...)
  GameDataDB.errors[name] = (not ok) and tostring(err) or nil
end

-- Le PNJ de la fenêtre ouverte : son ID (6e champ du GUID « Creature-0-…-npcID-… ») et où on l'a vu.
local function npc()
  local guid = UnitGUID("npc")
  local id = guid and tonumber((select(6, strsplit("-", guid))))
  local map = C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition(map, "player")
  local x, y = nil, nil
  if pos then x, y = pos:GetXY() end
  return id or UnitName("npc"), {
    name = UnitName("npc"), zone = GetZoneText(), subzone = GetSubZoneText(), map = map,
    x = x and math.floor(x * 1000) / 10, y = y and math.floor(y * 1000) / 10,
    faction = UnitFactionGroup("player"), seen = ns.now(),
  }
end

---------------------------------------------------------------------------------------------------
-- Recettes. Sur Forever les métiers passent par l'API moderne C_TradeSkillUI (GetTradeSkillLine n'existe pas). Le
-- relevé de la fenêtre ouverte est dans LibCommune (lib:ReleverRecettes, partagé avec le relevé de repli des add-ons
-- sans GameData) ; GameData sauvegarde ce qu'il rend.
-- Une fenêtre ne relève qu'un métier : le lot des recettes d'un perso n'est relevé entier (plus peut-être périmé) que
-- quand chacun de ses métiers a été relevé sous ce build (build noté par métier). Rend le 2e retour attendu par ns.run.
local function releveRecettes(c)
  for _, m in pairs(c.recipes) do if m.build ~= ns.build() then return "partiel" end end
  return true
end

local function saveProfession(c, prof, rank, max, known)
  c.recipes = c.recipes or {}
  c.recipes[prof] = { rank = rank, max = max, known = known, scanned = ns.now(), build = ns.build() }
  return releveRecettes(c)
end

-- Rend false si rien n'a été relevé, sinon le 2e retour de ns.run.
local function scanTradeSkill(c)
  local lib = LibStub and LibStub("LibCommune-1.0", true)
  if not lib then GameDataDB.errors.recipes = "LibCommune absente : recettes pas relevées" return false end
  GameDataDB.errors.recipes = nil
  local r, why, prof = lib:ReleverRecettes()
  if why == "liste pas à jour" then ns.retryTrade() return false end
  GameDataDB.trade_seen = GameDataDB.trade_seen or {}
  if r or why == "liste vide" then
    GameDataDB.trade_seen[r and r.metier or prof] = ns.now() .. " : " .. (r and r.total or "aucune") .. " recette(s) données par le jeu"
  end
  if not r then return false end -- pas notre métier, ou données pas prêtes : TRADE_SKILL_LIST_UPDATE suivra
  for id, rec in pairs(r.recettes) do GameDataDB.recipes[id] = rec end
  GameDataDB.errors["recipes:" .. r.metier] = r.premiereErreur and (r.illisibles .. " recette(s) illisible(s), ex. " .. r.premiereErreur) or nil
  c.recipes = c.recipes or {}
  if not lib.RangerRecettes then return saveProfession(c, r.metier, r.rang, r.max, r.connues) end -- LibCommune mineure 1
  local m = lib:RangerRecettes(c.recipes, r) -- la liste de la fenêtre prime, sans perdre une connue relevée sans elle
  m.scanned, m.build = ns.now(), ns.build()
  return releveRecettes(c)
end

-- À la connexion, sans fenêtre : les recettes connues parmi celles déjà vues (tous persos), relevées par LibCommune.
local function scanKnownRecipes()
  local lib = LibStub and LibStub("LibCommune-1.0", true)
  if not (lib and lib.ReleverRecettesSansFenetre) or not ns.souscrit("recettes connues") then return end -- absente, ou mineure 1
  local c = ns.char()
  c.recipes = c.recipes or {}
  -- ajoute des connues sans rien retirer : relevé partiel, noté une fois fini (il court sur plusieurs images)
  lib:ReleverRecettesSansFenetre(c.recipes, GameDataDB.recipes, function() ns.noterLot("recipes", false, c.lots) end)
end

-- Lu par LibCommune (type « recettes connues ») : les recettes vues et, par perso, ses métiers et recettes connues.
function ns.recettesConnues()
  local persos, lots = {}, {}
  for k, c in pairs(GameDataDB.chars) do persos[k], lots[k] = c.recipes, c.recipes and c.lots and c.lots.recipes end
  return { recettes = GameDataDB.recipes, persos = persos }, { persos = lots }
end

local function scanCraft(c) -- la fenêtre « Craft » de vanilla (Enchantement), si ce client l'a encore
  if not GetCraftDisplaySkillLine then return false end
  local prof, rank, max = GetCraftDisplaySkillLine()
  if not prof then return false end
  local known = {}
  for i = 1, GetNumCrafts() do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local key = recipeKey(link, prof, name)
      local reagents = {}
      for r = 1, GetCraftNumReagents(i) do
        local rname, _, qty = GetCraftReagentInfo(i, r)
        reagents[r] = { id = itemIDOf(GetCraftReagentItemLink(i, r)), qty = qty, name = rname }
      end
      GameDataDB.recipes[key] = { profession = prof, name = name, output = itemIDOf(link), made_min = 1, reagents = reagents }
      known[key] = kind
    end
  end
  return saveProfession(c, prof, rank, max, known)
end

---------------------------------------------------------------------------------------------------
-- Maîtres de métier (et de classe). Les filtres « disponible / indisponible / déjà appris » du joueur
-- cachent des lignes : on les note pour savoir si la liste est complète.
local function scanTrainer()
  local id, info = npc()
  local services = {}
  for i = 1, GetNumTrainerServices() do
    local name, rank, category = GetTrainerServiceInfo(i)
    if name and category ~= "header" then
      local skill, skillRank = GetTrainerServiceSkillReq(i)
      services[#services + 1] = {
        name = name, rank = rank ~= "" and rank or nil, category = category, cost = (GetTrainerServiceCost(i)),
        skill = skill, skill_rank = skillRank, level = GetTrainerServiceLevelReq(i),
        item = GetTrainerServiceItemLink and itemIDOf(GetTrainerServiceItemLink(i)) or nil,
      }
    end
  end
  info.services = services
  info.filters = {}
  for _, f in ipairs({ "available", "unavailable", "used" }) do
    info.filters[f] = GetTrainerServiceTypeFilter and (GetTrainerServiceTypeFilter(f) and true or false) or nil
  end
  info.tradeskill = IsTradeskillTrainer and IsTradeskillTrainer() or nil
  GameDataDB.trainers[id] = info
  ns.noterLot("maîtres de métier")
end

---------------------------------------------------------------------------------------------------
-- Marchands : tout ce qu'ils vendent, au prix que paie ce perso (remises de réputation comprises).
local function scanMerchant()
  local id, info = npc()
  local items = {}
  for i = 1, GetMerchantNumItems() do
    local m = C_MerchantFrame.GetItemInfo(i)
    if m then
      local row = {
        id = (GetMerchantItemID and GetMerchantItemID(i)) or itemIDOf(GetMerchantItemLink(i)), name = m.name, price = m.price,
        stack = m.stackCount, limited = (m.numAvailable or -1) >= 0 and m.numAvailable or nil,
      }
      if m.hasExtendedCost then -- payé en objets ou en monnaie (insignes, réputation…)
        row.cost_items = {}
        for j = 1, GetMerchantItemCostInfo(i) do
          local _, value, link, currency = GetMerchantItemCostItem(i, j)
          row.cost_items[j] = { id = itemIDOf(link), currency = currency, qty = value }
        end
      end
      items[#items + 1] = row
    end
  end
  info.items = items
  GameDataDB.vendors[id] = info
  ns.noterLot("marchands")
end

---------------------------------------------------------------------------------------------------
-- Maîtres de vol : le prix de chaque destination depuis celui-ci. GameDataDB.taxi[départ][arrivée] = prix (cuivre).
local function scanTaxi()
  local here, costs = nil, {}
  for i = 1, NumTaxiNodes() do
    local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
    if kind == "CURRENT" then here = name
    elseif kind == "REACHABLE" then costs[name] = TaxiNodeCost(i) end
  end
  if here then
    GameDataDB.taxi = GameDataDB.taxi or {}
    GameDataDB.taxi[here] = costs
    ns.noterLot("prix des vols")
  end
end

---------------------------------------------------------------------------------------------------
-- Hôtel des ventes : scan complet (C_AuctionHouse.ReplicateItems). Ce qu'on sait de Forever (AuctionDB, GPL,
-- commentaires de son Scan.lua) : environ 85 000 entrées, données en ~10 s, index 0..n-1, un scan par 15 min
-- et par session (une 2e demande est ignorée), REPLICATE_ITEM_LIST_UPDATE arrive une fois avec les données
-- puis des milliers de fois pendant que les infos d'objets chargent ; itemID, quantité et prix d'achat
-- immédiat sont toujours là. Le prix d'achat immédiat vaut pour toute la pile.
-- Le scan est demandé à l'ouverture de l'HV si le dernier date de plus de 15 min ; si un autre add-on
-- (AuctionDB) l'a déjà demandé, on lit simplement les mêmes données.
-- Paliers gardés : jusqu'à couvrir 60 % de ce qui est en vente (et au moins 2 000 unités), au plus 60 prix. Les 8
-- premiers ne voyaient que la fine couche bon marché d'un marché à deux étages (le charbon : 530 unités à 4-5 pa,
-- le gros à 13 pa, le 18/11/2026) ; le Négoce lit l'échelle entière.
local SCAN_COOLDOWN, BATCH, TIERS = 15 * 60, 2000, 60
local ahOpen, reading, lastRequest, readAt = false, false, 0, nil

local function house() return GetRealmName() .. "-" .. UnitFactionGroup("player") end
-- ponytail: un HV par royaume et faction ; les HV neutres (gobelins) se mélangent à celui de la faction.

-- rows : { {id, count, buyout}, … } -> { [itemID] = { min, qty, auctions, tiers = { {price, qty}, … } } }
local function aggregate(rows)
  local by = {}
  for _, r in ipairs(rows) do
    local count = (r.count and r.count > 0) and r.count or 1
    if r.id and r.buyout and r.buyout > 0 then
      local t = by[r.id] or {}
      t[#t + 1] = { math.floor(r.buyout / count), count }
      by[r.id] = t
    end
  end
  local out = {}
  for id, list in pairs(by) do
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local tiers, qty, cover = {}, 0, math.max(2000, total * 0.6)
    for _, e in ipairs(list) do
      local last = tiers[#tiers]
      if last and last.price == e[1] then last.qty = last.qty + e[2]
      elseif #tiers < TIERS and qty < cover then tiers[#tiers + 1] = { price = e[1], qty = e[2] } end
      qty = qty + e[2]
    end
    out[id] = { min = list[1][1], qty = qty, auctions = #list, tiers = tiers }
  end
  return out
end
ns.aggregate = aggregate

local function readReplicate()
  local n = C_AuctionHouse.GetNumReplicateItems()
  local rows, i = {}, 0
  local function step()
    for idx = i, math.min(i + BATCH, n) - 1 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
      rows[#rows + 1] = { id = itemID, count = count, buyout = buyout }
    end
    i = i + BATCH
    if i < n then return C_Timer.After(0, step) end -- 2000 entrées par frame : pas de gel
    local items = aggregate(rows)
    local h = house()
    -- Historique : prix le plus bas et quantité en vente à chaque scan (les 12 derniers), pour estimer ce qui part.
    local hist = GameDataMarket[h] and GameDataMarket[h].hist or {}
    local stamp = time()
    for id, it in pairs(items) do
      local list = hist[id] or {}
      list[#list + 1] = { stamp, it.min, it.qty }
      while #list > 12 do table.remove(list, 1) end
      hist[id] = list
    end
    for id, list in pairs(hist) do -- plus rien en vente : tout est parti (ou retiré)
      if not items[id] and list[#list][1] ~= stamp then
        list[#list + 1] = { stamp, nil, 0 }
        while #list > 12 do table.remove(list, 1) end
      end
    end
    GameDataMarket[h] = { scanned = ns.now(), time = stamp, auctions = n, items = items, hist = hist }
    -- ponytail: lot entier, un seul HV relevé en pratique ; un lot par HV si un joueur en relève plusieurs (sinon l'HV
    -- de l'autre faction passe pour frais après un nouveau build)
    ns.noterLot("cours de l'HV", true)
    reading, readAt = false, GetTime()
    print(("GameData : hôtel des ventes lu, %d enchères. /reload pour l'écrire sur le disque."):format(n))
    safe("market_scanned", ns.marketScanned)
  end
  step()
end

-- Dépôt d'une annonce. Règle : 15 % du prix de revente au marchand par tranche de 12 h (30 % pour 24 h), avec sur
-- Forever un minimum de 1 pa par annonce (voulu par Blizzard, annoncé à 1 pc « bientôt » ; Icy Veins, nov. 2026).
-- HV ouvert, on vérifie avec le jeu (C_AuctionHouse.CalculateCommodityDeposit, 24 h) : le taux sur 1 000 unités
-- (le minimum n'y joue pas) et le minimum sur une seule unité d'un objet bon marché. Résultats : GameDataDB.deposit.
local function learnDeposit()
  local rates, mins = {}, {}
  for id, d in pairs(ns.VENDOR_DB or {}) do
    local sell = d[4]
    if sell and sell > 0 then
      local many = C_AuctionHouse.CalculateCommodityDeposit(id, 2, 1000)
      if many and many > 0 then
        local rate = many / (1000 * sell)
        rates[#rates + 1] = rate
        local one = C_AuctionHouse.CalculateCommodityDeposit(id, 2, 1)
        if one and one > rate * sell + 1 then mins[#mins + 1] = one end -- le minimum l'a emporté
      end
      if #rates >= 20 then break end
    end
  end
  if #rates == 0 then return end
  local function median(t) table.sort(t) return t[math.floor((#t + 1) / 2)] end
  GameDataDB.deposit = { rate24 = median(rates), min = #mins > 0 and median(mins) or nil, checked = ns.now() }
end

-- Appelé après chaque lecture de l'HV. Un add-on qui veut réagir au scan frais (le Négoce) s'y accroche :
-- hooksecurefunc(GameDataAPI, "marketScanned", fn).
function ns.marketScanned() end

local function requestScan()
  if GetTime() - lastRequest < SCAN_COOLDOWN then return end
  lastRequest = GetTime()
  C_AuctionHouse.ReplicateItems()
end

---------------------------------------------------------------------------------------------------
-- Ces événements arrivent en rafale : un seul scan, une demi-seconde après le dernier.
local tradeToken, retries = 0, 0
local function queueTrade()
  tradeToken = tradeToken + 1
  local mine = tradeToken
  C_Timer.After(0.5, function()
    if mine == tradeToken then ns.run("recipes", function(c) local releve = scanTradeSkill(c); return c.recipes, releve end) end
  end)
end
function ns.retryTrade() -- liste pas encore à jour : jusqu'à 4 nouveaux essais
  retries = retries + 1
  if retries <= 4 then C_Timer.After(0.6, queueTrade) end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE",
  "TRAINER_SHOW", "TRAINER_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TAXIMAP_OPENED",
  "REPLICATE_ITEM_LIST_UPDATE" }) do
  pcall(f.RegisterEvent, f, e)
end

-- Le type de données que relève chaque fenêtre : rien n'est lu sans souscription à ce type (Souscriptions.lua). Les recettes
-- passent par ns.run, qui vérifie lui-même.
local TYPE_DE = { TRAINER_SHOW = "maîtres de métier", TRAINER_UPDATE = "maîtres de métier", MERCHANT_SHOW = "marchands",
  MERCHANT_UPDATE = "marchands", TAXIMAP_OPENED = "prix des vols", AUCTION_HOUSE_SHOW = "cours de l'HV",
  REPLICATE_ITEM_LIST_UPDATE = "cours de l'HV" }

f:SetScript("OnEvent", function(_, event)
  -- diagnostic : la dernière fois que chaque événement est arrivé (pour savoir si une fenêtre a bien été vue)
  GameDataDB.events = GameDataDB.events or {}
  GameDataDB.events[event] = ns.now()
  if TYPE_DE[event] and not ns.souscrit(TYPE_DE[event]) then return end
  if event == "PLAYER_LOGIN" then
    C_Timer.After(5, function() safe("recipes_login", scanKnownRecipes) end)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    retries = 0
    queueTrade()
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    ns.run("recipes", function(c) local releve = scanCraft(c); return c.recipes, releve end)
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    safe("trainer", scanTrainer)
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
    safe("merchant", scanMerchant)
  elseif event == "TAXIMAP_OPENED" then
    safe("taxi", scanTaxi)
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    safe("auction_request", requestScan)
    C_Timer.After(2, function() safe("auction_deposit", learnDeposit) end)
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" and ahOpen and not reading then
    -- une lecture par scan : les milliers d'événements suivants (infos d'objets qui chargent) sont ignorés
    if readAt and GetTime() - readAt < SCAN_COOLDOWN then return end
    reading = true
    safe("auction_read", readReplicate)
  end
end)

function ns.commerceStatus()
  local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
  local m = GameDataMarket[house()]
  return ("Recettes : %d. Maîtres : %d. Marchands : %d. Hôtel des ventes : %s."):format(
    count(GameDataDB.recipes), count(GameDataDB.trainers), count(GameDataDB.vendors),
    m and (count(m.items) .. " objets, scan du " .. m.scanned) or "pas encore scanné (ouvre l'HV)")
end
