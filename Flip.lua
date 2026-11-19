-- GameData, « Mécréant » : acheter chez un marchand ce qu'il vend en illimité, le revendre à l'hôtel des ventes
-- (les gens ont la flemme d'aller le chercher). Calcul seulement : acheter et mettre en vente restent à la main.
--
-- Prix d'achat : ce que tu as vu chez un marchand (GameDataDB.vendors), sinon la base cMaNGOS (VendorData.lua, prix
-- sans remise de réputation : tu paieras un peu moins). Qui le vend sur Forever : QuestieDB (corrigé pour Forever),
-- en ne gardant que les PNJ amicaux pour ta faction.
-- Historique de l'HV : AuctionDB s'il est installé (chaque scan des 7 derniers jours : heure, min, médiane,
-- quantité), sinon le nôtre (GameDataMarket[...].hist).
--
-- Le calcul, pour chaque objet :
--   débit D       unités qui quittent l'HV par jour = somme des baisses de quantité entre scans successifs / durée
--                 (ventes, mais aussi annulations et expirations : une estimation haute, d'où la prudence plus bas)
--   prix sûr P    1er quartile des prix minimum observés (le marché est resté au-dessus 3 fois sur 4), et un cuivre
--                 sous le moins cher actuel s'il est plus bas : tu es devant dans la file, à un prix qui tient.
--                 (Essayé puis retiré le 18/11/2026 : un « prix de file » qui visait l'étage haut d'un marché à deux
--                 étages. Les ventes réelles de charbon se sont faites à 4 pa 63, pas à 13 pa : la couche bon marché
--                 se renouvelle et l'étage haut ne part pas.)
--   gain unitaire P × 0,95 (part de l'HV : 5 % de chaque vente) − prix marchand − dépôt d'annonce (24 h) ;
--                 on écarte sous 15 % de marge
--   stock J       jours pour écouler ce qui est déjà en vente (quantité / D) ; au-delà de 5 jours, marché saturé
--   quantité N    la moitié de 2 jours de débit, réduite d'autant que le stock est déjà gros, arrondie aux lots du
--                 marchand
--   confiance     A : 8 scans et plus sur 48 h et plus, prix stable (écart-type < 25 % de la moyenne) ;
--                 B : 4 scans sur 12 h, écart < 50 % ; C sinon (à prendre avec des pincettes)
local _, ns = ...

local AH_CUT, MIN_MARGIN, WINDOW_DAYS, SHARE, MAX_STOCK_DAYS = 0.05, 0.15, 2, 0.5, 5
-- Dépôt d'une annonce de 24 h : un pourcentage du prix de revente au marchand (20 % mesuré sur Forever le 18/11/2026,
-- 30 % sur le WoW moderne), avec un minimum par annonce (1 pa au lancement de Forever, retiré depuis). Un objet empilable se poste en une annonce pour toute la quantité ; un objet non empilable,
-- une annonce par objet. Taux et minimum vérifiés auprès du jeu HV ouvert (GameDataDB.deposit, Commerce.lua).
-- Rendu si l'objet se vend ; compté quand même, comme s'il était perdu : le calcul reste du côté sûr.
-- Mesuré le 18/11/2026 (HV ouvert et tes propres mises en vente) : 20 % pour 24 h, et plus de minimum à 1 pa
-- (80 épices douces = 16 pc de dépôt) : Blizzard l'a bien baissé.
local DEPOSIT_RATE24, DEPOSIT_MIN = 0.20, 1

local function depositRule()
  local d = GameDataDB.deposit or {}
  -- une mesure sans minimum détecté veut dire qu'il n'y en a plus (et pas « reprendre l'ancien de 1 pa »)
  return d.rate24 or DEPOSIT_RATE24, d.min or (d.checked and 1) or DEPOSIT_MIN
end

local function house() return GetRealmName() .. "-" .. UnitFactionGroup("player") end

---------------------------------------------------------------------------------------------------
-- Historique d'AuctionDB (AHDB, GPL) : AuctionDBForeverSaved.houses["<royaume> <faction>"].items[itemID] =
-- "heure,min,médiane,quantité heure,…" (format décrit dans son History.lua). Renvoie { {heure, min, quantité, médiane}, … }.
local function ahdbHouse()
  local saved = AuctionDBForeverSaved
  if type(saved) ~= "table" or type(saved.houses) ~= "table" then return nil end
  local faction, best, bestTime = " " .. UnitFactionGroup("player"), nil, -1
  for name, h in pairs(saved.houses) do
    if name:sub(-#faction) == faction and type(h.items) == "table" then
      local last = h.scans and h.scans[#h.scans] and h.scans[#h.scans][1] or 0
      if last > bestTime then best, bestTime = h, last end
    end
  end
  return best
end

local function ahdbHistory(h, id)
  local s = h and h.items[id]
  if type(s) ~= "string" then return nil end
  local list = {}
  for ts, min, median, qty in s:gmatch("(%d+),(%d+),(%d+),(%d+)") do
    list[#list + 1] = { tonumber(ts), tonumber(min), tonumber(qty), tonumber(median) }
  end
  return #list > 0 and list or nil
end
ns.ahdbHistory, ns.ahdbHouse = ahdbHistory, ahdbHouse

---------------------------------------------------------------------------------------------------
-- Statistiques
local function percentile(values, p)
  if #values == 0 then return nil end
  local s = {}
  for i, v in ipairs(values) do s[i] = v end
  table.sort(s)
  local pos = 1 + (#s - 1) * p
  local lo = math.floor(pos)
  return s[lo] + (s[math.min(lo + 1, #s)] - s[lo]) * (pos - lo)
end

-- Débit par jour et durée couverte (heures), d'après { {heure, min, quantité, …}, … }.
local function turnover(hist)
  if not hist or #hist < 2 then return nil, 0 end
  local gone = 0
  for i = 2, #hist do
    local drop = (hist[i - 1][3] or 0) - (hist[i][3] or 0)
    if drop > 0 then gone = gone + drop end
  end
  local hours = (hist[#hist][1] - hist[1][1]) / 3600
  return hours > 0 and gone / hours * 24 or nil, hours
end
ns.turnover = turnover

local function grade(n, hours, mins)
  if #mins < 2 then return "C" end
  local mean, var = 0, 0
  for _, v in ipairs(mins) do mean = mean + v end
  mean = mean / #mins
  for _, v in ipairs(mins) do var = var + (v - mean) ^ 2 end
  local cv = math.sqrt(var / #mins) / mean
  if n >= 8 and hours >= 48 and cv < 0.25 then return "A" end
  if n >= 4 and hours >= 12 and cv < 0.5 then return "B" end
  return "C"
end

-- Le plan pour un objet : unit = prix marchand d'une unité, lot = unités par achat chez le marchand,
-- cur = dernier scan { min, qty } (ou nil), hist = historique. Renvoie nil si l'affaire ne tient pas.
-- Gain pour qty unités : un objet empilable part en une annonce, dont le dépôt ne descend pas sous le minimum.
function ns.profitOf(e, qty)
  if e.stackable and qty * (e.rateDep or 0) < (e.minDep or 0) then
    return qty * (e.net + e.rateDep) - e.minDep
  end
  return qty * e.net
end

-- dep = { sell = revente au marchand, stack = taille de pile, rate = taux 24 h, min = minimum par annonce } ou nil.
function ns.flipPlan(unit, lot, cur, hist, dep)
  local mins = {}
  for _, h in ipairs(hist or {}) do
    if h[2] and h[2] > 0 then mins[#mins + 1] = h[2] end
  end
  local nowMin = cur and cur.min or (hist and hist[#hist] and hist[#hist][2])
  if not nowMin or nowMin <= 0 then return nil end
  local safe = percentile(mins, 0.25) or nowMin
  if nowMin - 1 < safe then safe = nowMin - 1 end
  -- dépôt par unité : empilable = le taux seul (le minimum de l'annonce est réparti sur la quantité plus bas) ;
  -- non empilable = une annonce par objet, donc au moins le minimum par unité
  local rate, minimum, stackable = 0, 0, false
  if dep then rate, minimum, stackable = (dep.rate or 0) * (dep.sell or 0), dep.min or 0, (dep.stack or 1) > 1 end
  local deposit = stackable and rate or math.max(minimum, rate)
  local net = safe * (1 - AH_CUT) - unit - deposit
  if net <= 0 or net / unit < MIN_MARGIN then return nil end
  local perDay, hours = turnover(hist)
  local stock = (cur and cur.qty) or (hist and hist[#hist] and hist[#hist][3]) or 0
  local plan = { unit = unit, lot = math.max(1, lot or 1), safe = safe, net = net, deposit = deposit,
    rateDep = rate, minDep = minimum, stackable = stackable,
    cut = safe * AH_CUT, margin = net / unit, perDay = perDay, stock = stock,
    scans = hist and #hist or 0, hours = hours, grade = grade(hist and #hist or 0, hours, mins) }
  if not perDay or perDay <= 0 then return plan end -- pas assez d'historique pour une quantité
  plan.stockDays = stock / perDay
  if plan.stockDays > MAX_STOCK_DAYS then return nil end -- marché saturé
  local n = perDay * WINDOW_DAYS * SHARE * math.max(0.25, 1 - plan.stockDays / MAX_STOCK_DAYS)
  lot = math.max(1, lot or 1)
  plan.qty = math.floor(n / lot) * lot
  if plan.qty <= 0 then return nil end
  plan.cost, plan.profit = plan.qty * unit, ns.profitOf(plan, plan.qty)
  plan.sellDays = plan.qty / (perDay * SHARE)
  return plan
end

-- Ramène l'affaire à ce que le budget permet d'acheter (en lots entiers du marchand) ; false si même un lot est
-- hors de prix. Sans quantité calculée, il suffit de pouvoir payer un lot.
function ns.capToBudget(e, budget)
  local lot = e.lot or 1
  local most = math.floor(budget / e.unit / lot) * lot
  if most <= 0 then return false end
  if e.qty then
    if e.qty > most then e.qty, e.capped = most, true end
    e.cost, e.profit = e.qty * e.unit, ns.profitOf(e, e.qty)
    e.sellDays = e.perDay and e.qty / (e.perDay * SHARE) or e.sellDays
  end
  return true
end

---------------------------------------------------------------------------------------------------
-- Où acheter : le marchand vu le moins cher, sinon les PNJ de QuestieDB amicaux pour ta faction.
local function questieVendors(id, dbNpcs)
  local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
  local ids = {}
  local ok, list = pcall(function() return ItemDB and ItemDB.vendors(id) end)
  if ok and list then ids = list
  elseif dbNpcs then for n in dbNpcs:gmatch("%d+") do ids[#ids + 1] = tonumber(n) end end
  -- Strict : un PNJ dont QuestieDB ne connaît pas la faction est écarté (les marchands de la Horde passaient
  -- comme « inconnus » le 18/11/2026). Sans QuestieDB du tout, on ne peut rien vérifier : on garde, signalé.
  local canCheck = NpcDB and type(NpcDB.friendlyToFaction) == "function"
  -- Signalés absents par toi (clic droit dans Mécréant) : QuestieDB garde des PNJ qui n'existent pas sur Forever
  -- (Wagner Hammerstrike, 18/11/2026).
  local friendly, absent = {}, GameDataDB.flip_absent or {}
  for _, npc in ipairs(ids) do
    local okF, f = true, nil
    if canCheck then okF, f = pcall(NpcDB.friendlyToFaction, npc) end
    if not absent[npc] and (not canCheck or (okF and type(f) == "string" and f:find(faction, 1, true))) then
      friendly[#friendly + 1] = npc
    end
  end
  return friendly, ok and list ~= nil and canCheck
end

ns.questieVendors = questieVendors

-- Pour le diagnostic (export « mecreant ») : les PNJ d'un objet et la faction que QuestieDB leur donne.
function ns.vendorFactions(id)
  local out = {}
  local ok, list = pcall(function() return ItemDB and ItemDB.vendors(id) end)
  for i, npc in ipairs(ok and list or {}) do
    if i > 8 then break end
    local okF, f = pcall(function() return NpcDB.friendlyToFaction(npc) end)
    local okN, name = pcall(function() return NpcDB.name(npc) end)
    out[#out + 1] = { npc = npc, name = okN and name or nil, faction = okF and f or nil }
  end
  return out, ok and list ~= nil
end

local function npcLabel(npc)
  local ok, name = pcall(function() return NpcDB and NpcDB.name(npc) end)
  local okZ, zone = pcall(function() return NpcDB and NpcDB.zoneID(npc) end)
  local zoneName = okZ and zone and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zone)
  return ((ok and name) or ("PNJ " .. npc)) .. (zoneName and (", " .. zoneName) or "")
end

local function candidates()
  local out = {}
  for npc, v in pairs(GameDataDB.vendors or {}) do -- vu en jeu : prix réel, remise comprise
    for _, it in ipairs(v.items or {}) do
      if it.id and it.price and it.price > 0 and not it.limited and not it.cost_items then
        local unit = it.price / math.max(1, it.stack or 1)
        if not out[it.id] or unit < out[it.id].unit then
          out[it.id] = { unit = unit, lot = it.stack or 1, seen = true,
            where = (v.name or "?") .. ", " .. ((v.subzone and v.subzone ~= "") and v.subzone or v.zone or "?"),
            point = v.map and v.x and { v.map, v.x / 100, v.y / 100, v.name } }
        end
      end
    end
  end
  for id, d in pairs(ns.VENDOR_DB or {}) do -- base cMaNGOS : prix de base
    if not out[id] then out[id] = { unit = d[1] / d[2], lot = d[2], npcs = d[3], sell = d[4] } end
  end
  return out
end

---------------------------------------------------------------------------------------------------
-- Trajet depuis ta position (ShortestPathForever, GPL : son API publique Estimate tient compte de tes points de vol
-- connus, des bateaux, du tram, des portails et de la marche). Emplacements des PNJ : QuestieDB (NpcDB.spawns, en %
-- de la carte de leur zone), zone -> carte du jeu par ZoneDB de Questie. Prix des vols : ceux notés chez les maîtres
-- de vol (GameDataDB.taxi), sinon une estimation. On ne calcule le trajet que pour les meilleures affaires, et pour
-- chacune les 3 marchands les plus proches à vol d'oiseau sur ton continent.
local TRAVEL_TOP, NEAREST, POST_SECONDS, FLIGHT_GUESS = 20, 3, 120, 2000 -- 2 min de mise en vente ; 20 pa par vol inconnu
local areaMap

-- Zone de QuestieDB -> carte du jeu. La table est dans QuestieDB lui-même (texte Lua « return {…} ») : on la décode
-- une fois. Questie n'est pas nécessaire — il était désactivé sur Belegard et plus aucun marchand n'avait
-- d'emplacement (« Y aller » : pas d'emplacement connu, 18/11/2026).
local function uiMapOfArea(area)
  if areaMap == nil then
    areaMap = false
    local ok, zone = pcall(function() return LibQuestieDB.Support.Get("ZoneDB").private end)
    if ok and type(zone) == "table" then
      local map = {}
      for _, field in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        local src = zone[field]
        local fn = type(src) == "string" and loadstring(src)
        local okT, t = pcall(fn or function() return src end)
        if okT and type(t) == "table" then for a, m in pairs(t) do map[a] = m end end
      end
      if next(map) then areaMap = map end
    end
  end
  local m = areaMap and areaMap[area]
  return (m and m > 0) and m or nil
end

local function npcPoints(npc)
  local out = {}
  local ok, spawns = pcall(function() return NpcDB and NpcDB.spawns(npc) end)
  if ok and type(spawns) == "table" then
    for area, list in pairs(spawns) do
      local map, p = uiMapOfArea(area), list[1]
      if map and p and p[1] and p[2] and p[1] >= 0 then out[#out + 1] = { map, p[1] / 100, p[2] / 100, npc } end
    end
  end
  return out
end

local function world(map, x, y)
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if ok and cont and pos then
    local wx, wy = pos:GetXY()
    return cont, wx, wy
  end
end

-- Prix des vols d'un trajet : le prix le plus bas noté vers chaque destination, sinon l'estimation.
local function flights(legs)
  local cost, n, guessed = 0, 0, false
  for _, leg in ipairs(legs or {}) do
    if leg.mode == "flight" then
      local known
      for _, dests in pairs(GameDataDB.taxi or {}) do
        local c = dests[leg.to]
        if c and (not known or c < known) then known = c end
      end
      n, cost, guessed = n + 1, cost + (known or FLIGHT_GUESS), guessed or not known
    end
  end
  return cost, n, guessed
end

local function playerPoint()
  local map = C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition(map, "player")
  if pos then
    local x, y = pos:GetXY()
    return map, x, y
  end
end

-- Aller-retour vers le marchand le plus rapide à atteindre. Renvoie { seconds, flights, flightCost, guessed, npc } ou
-- nil, et « pending » si ShortestPathForever n'a pas encore pu répondre.
local function travelFor(plan, from)
  local api = ShortestPathForever and ShortestPathForever.API
  if not (api and api.EstimateDetail and from) then return nil end
  local points = {}
  if plan.point then points[1] = plan.point end
  for i, npc in ipairs(plan.npcs or {}) do
    if i > 30 then break end
    for _, p in ipairs(npcPoints(npc)) do points[#points + 1] = p end
  end
  local pc, px, py = world(from[1], from[2], from[3])
  for _, p in ipairs(points) do
    local c, x, y = world(p[1], p[2], p[3])
    p.d = (c and c == pc and x) and ((x - px) ^ 2 + (y - py) ^ 2) or math.huge
  end
  table.sort(points, function(a, b) return a.d < b.d end)
  local best, pending
  for i = 1, math.min(NEAREST, #points) do
    local p = points[i]
    local ok, detail, reason = pcall(api.EstimateDetail, from[1], from[2], from[3], p[1], p[2], p[3])
    if ok and detail and detail.seconds then
      if not best or detail.seconds < best.oneWay then
        local cost, n, guessed = flights(detail.legs)
        best = { oneWay = detail.seconds, seconds = 2 * detail.seconds + POST_SECONDS, flights = 2 * n,
          flightCost = 2 * cost, guessed = guessed, npc = p[4], point = { p[1], p[2], p[3] } }
      end
    elseif ok and reason ~= "invalid" then
      pending = true
    end
  end
  return best, pending
end

ns.travelFor = travelFor

-- « Y aller » : le marchand puis ton HV (noté à sa dernière ouverture). Avec ShortestPathForever, sa flèche guide tout
-- l'itinéraire (vols, bateaux…) ; sans lui, le repère du jeu sur le marchand (carte + boussole).
local function vendorPoint(e)
  if e.travel and e.travel.point then return e.travel.point end
  if e.point then return e.point end
  for _, npc in ipairs(e.npcs or {}) do
    local pts = npcPoints(npc)
    if pts[1] then return pts[1] end
  end
end

function ns.goTo(e)
  local p = vendorPoint(e)
  if not p then return print("GameData : pas d'emplacement connu pour ce marchand.") end
  local name = (C_Item.GetItemNameByID(e.id) or ("objet " .. e.id))
  local stops = { { map = p[1], x = p[2], y = p[3], title = ("Acheter %s × %s — %s"):format(e.qty or "?", name, e.where or "marchand") } }
  local ah = GameDataDB.ah_spot
  if ah then stops[2] = { map = ah.map, x = ah.x, y = ah.y, title = "Revendre à l'HV — " .. (ah.zone or "") } end
  ns.navigate(stops, ah and ", puis l'HV." or " (ouvre l'HV une fois pour qu'il y revienne).")
end

-- Itinéraire ShortestPathForever par ces étapes { {map, x, y, title}, … }, sinon un repère natif sur la première.
function ns.navigate(stops, suffix)
  local api, p = ShortestPathForever and ShortestPathForever.API, stops[1]
  if api and api.NavigateRoute then
    local ok, res = pcall(api.NavigateRoute, "GameData", stops)
    if ok and res ~= false then return print("GameData : itinéraire lancé — " .. p.title .. (suffix or ".")) end
  end
  if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(p.map) then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(p.map, p.x, p.y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    print("GameData : repère posé — " .. p.title .. ".")
  else
    print("GameData : impossible de poser un repère sur cette carte.")
  end
end

function ns.flipOpportunities()
  local m = GameDataMarket[house()]
  local market, hist, ahdb = m and m.items, m and m.hist, ahdbHouse()
  local list, waiting = {}, 0
  for id, c in pairs(candidates()) do
    local cur = market and market[id]
    local h = ahdbHistory(ahdb, id) or (hist and hist[id])
    if cur or h then
      local sell = c.sell or (ns.VENDOR_DB and ns.VENDOR_DB[id] and ns.VENDOR_DB[id][4])
        or (GameDataItems.items and GameDataItems.items[id] and GameDataItems.items[id].price) or 0
      local rate, minimum = depositRule()
      local vdb = ns.VENDOR_DB and ns.VENDOR_DB[id]
      local stack = (vdb and vdb[5]) or (GameDataItems.items and GameDataItems.items[id] and GameDataItems.items[id].stack) or 1
      local plan = ns.flipPlan(c.unit, c.lot, cur, h, { sell = sell, stack = stack, rate = rate, min = minimum })
      if plan then
        if not c.seen then
          local friendly, fromQuestie = questieVendors(id, c.npcs)
          if #friendly == 0 then plan = nil -- personne d'amical ne le vend sur Forever
          else
            plan.where = npcLabel(friendly[1]) .. (#friendly > 1 and (" (+%d autres)"):format(#friendly - 1) or "")
            plan.base, plan.npcs = true, friendly
            plan.unverified = not fromQuestie
          end
        else
          plan.where, plan.point = c.where, c.point
        end
        -- Que du solide : sans historique (moins de 2 scans), pas de quantité ni de débit, et une seule annonce
        -- délirante suffit à faire croire à une affaire (un tabard à 30 po, le 18/11/2026) : on attend.
        if plan and not plan.qty then waiting, plan = waiting + 1, nil end
        if plan then plan.id = id list[#list + 1] = plan end
      end
    end
  end
  -- Ce que ton or permet : chaque affaire est ramenée à ce que tu peux payer, celles hors de portée disparaissent.
  -- Le fond de roulement (GameDataDB.flip_reserve, en cuivre) n'est jamais entamé.
  local money, affordable = math.max(0, GetMoney() - (GameDataDB.flip_reserve or 0)), {}
  for _, e in ipairs(list) do
    if ns.capToBudget(e, money) then affordable[#affordable + 1] = e end
  end
  list = affordable
  -- La place dans les sacs : 12 430 épices proposées le 18/11/2026, soit 622 piles de 20, impossible à porter.
  if ns.freeUnits then
    local fits = {}
    for _, e in ipairs(list) do
      local vdb = ns.VENDOR_DB and ns.VENDOR_DB[e.id]
      local stack = math.max(1, (vdb and vdb[5]) or 1)
      local most = math.floor(ns.freeUnits(e.id, stack) / e.lot) * e.lot
      if e.qty and e.qty > most then e.qty, e.spaceCapped = most, true end
      if not e.qty or e.qty > 0 then
        if e.qty then e.cost, e.profit = e.qty * e.unit, ns.profitOf(e, e.qty) end
        fits[#fits + 1] = e
      end
    end
    list = fits
  end
  table.sort(list, function(a, b)
    if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
    return (a.profit or a.net) > (b.profit or b.net)
  end)
  local from, pending = { playerPoint() }, false
  if #from == 3 then
    for i = 1, math.min(TRAVEL_TOP, #list) do
      local e = list[i]
      if e.profit then
        local t, wait = travelFor(e, from)
        pending = pending or wait
        if t and ns.capToBudget(e, money - t.flightCost) then -- les vols se paient aussi avec ton or
          e.travel = t
          if t.npc and e.npcs then e.where = npcLabel(t.npc) end -- le marchand retenu : le plus rapide à atteindre
          e.netTravel = e.profit - t.flightCost
          e.perHour = e.netTravel / (t.seconds / 3600)
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if (a.perHour ~= nil) ~= (b.perHour ~= nil) then return a.perHour ~= nil end
    if a.perHour then return a.perHour > b.perHour end
    if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
    return (a.profit or a.net) > (b.profit or b.net)
  end)
  return list, m, ahdb, pending, money, waiting
end

---------------------------------------------------------------------------------------------------
local frame, tbl, refresh
local GRADE_COLOR = { A = "59cc73", B = "e6c84d", C = "e66b4d" }
local GRADE_RANK = { A = 3, B = 2, C = 1 }
local function gain(e) return e.netTravel or e.profit end

local COLUMNS = {
  { key = "item", title = "Objet", w = 150, asc = true, get = function(e) return C_Item.GetItemNameByID(e.id) or "" end,
    fmt = function(_, e) return ns.itemLabel(e.id) end, icon = function(e) return C_Item.GetItemIconByID(e.id) end },
  { key = "grade", title = "Note", w = 32, get = function(e) return GRADE_RANK[e.grade] end,
    fmt = function(_, e) return ("|cff%s%s|r"):format(GRADE_COLOR[e.grade], e.grade) end,
    tip = "A fiable, B correct, C peu de données sur le marché." },
  { key = "qty", title = "Qté", w = 40, align = "RIGHT", get = function(e) return e.qty end,
    tip = "Quantité prudente : la moitié de ce qui part en 2 jours, ramenée à ton or et à tes sacs." },
  { key = "cost", title = "Mise", w = 62, align = "RIGHT", get = function(e) return e.cost end, fmt = ns.moneyShort,
    tip = "Ce que coûte l'achat chez le marchand." },
  { key = "safe", title = "Revente", w = 58, align = "RIGHT", get = function(e) return e.safe end, fmt = ns.moneyShort,
    tip = "Prix de vente conseillé à l'unité : celui où le marché est resté 3 fois sur 4." },
  { key = "net", title = "Net/u", w = 52, align = "RIGHT", get = function(e) return e.net end, fmt = ns.moneyShort,
    tip = "Gagné par unité, part de l'HV et dépôt déduits." },
  { key = "margin", title = "Marge", w = 42, align = "RIGHT", get = function(e) return e.margin end,
    fmt = function(v) return v and ("%d %%"):format(math.floor(v * 100)) or "–" end },
  { key = "gain", title = "Gain", w = 62, align = "RIGHT", get = gain, fmt = ns.moneyShort,
    tip = "Gain total sur la quantité, vols déduits." },
  { key = "trip", title = "Trajet", w = 44, align = "RIGHT", get = function(e) return e.travel and e.travel.seconds end,
    fmt = function(v) return v and ("%d min"):format(math.max(1, math.floor(v / 60 + 0.5))) or "–" end,
    tip = "Aller-retour depuis ta position : marchand, puis HV." },
  { key = "flights", title = "Vols", w = 52, align = "RIGHT", get = function(e) return e.travel and e.travel.flightCost end,
    fmt = function(v, e)
      if not v then return "–" end
      if e.travel.flights == 0 then return "|cff999999à pied|r" end
      return (e.travel.guessed and "~" or "") .. ns.moneyShort(v)
    end, tip = "Prix des griffons aller-retour (~ = estimé : ouvre la carte d'un maître de vol pour le vrai prix)." },
  { key = "perHour", title = "Gain/h", w = 66, align = "RIGHT", get = function(e) return e.perHour end, fmt = ns.moneyShort,
    tip = "Gain divisé par le temps du trajet (+2 min d'achat et de mise en vente)." },
  { key = "sellDays", title = "Écoul.", w = 42, align = "RIGHT", get = function(e) return e.sellDays end,
    fmt = function(v) return v and ("%.1f j"):format(v) or "–" end, tip = "Temps estimé pour tout vendre." },
  { key = "where", title = "Marchand", w = 110, asc = true, get = function(e) return e.where or "" end, fmt = function(v) return v end },
  { key = "go", title = "", w = 58, button = function(e)
      if not e.qty then return nil end
      local here = MerchantFrame and MerchantFrame:IsShown() and ns.merchantIndex and ns.merchantIndex(e.id)
      return here and "Acheter" or "Y aller"
    end, click = function(e)
      local here = MerchantFrame and MerchantFrame:IsShown() and ns.merchantIndex and ns.merchantIndex(e.id)
      if here then ns.bulkBuy(e.id, e.qty) else ns.goTo(e) end
    end },
}

-- Le PNJ que la ligne propose : le plus rapide à atteindre, sinon le premier de la liste. Nil = marchand vu en jeu.
local function chosenNpc(e) return e.npcs and ((e.travel and e.travel.npc) or e.npcs[1]) or nil end

local function onRowClick(e, button)
  if button ~= "RightButton" then return end
  local npc = chosenNpc(e)
  if not npc then return print("GameData : ce marchand, tu l'as vu toi-même en jeu : il existe.") end
  GameDataDB.flip_absent = GameDataDB.flip_absent or {}
  GameDataDB.flip_absent[npc] = e.where or true
  print(("GameData : %s noté absent de Forever, il ne sera plus proposé (/gdata absents pour la liste)."):format(e.where or ("PNJ " .. npc)))
  frame.retries = 0
  refresh()
end

local function tooltip(e, tt)
  tt:SetItemByID(e.id)
  tt:AddLine(" ")
  tt:AddDoubleLine("Achat chez " .. (e.where or "?"), ns.money(e.unit) .. (e.base and " (prix de base)" or ""), 1, 1, 1, 1, 1, 1)
  if e.qty then tt:AddDoubleLine(("Acheter %d"):format(e.qty), ns.money(e.cost), 1, 1, 1, 1, 1, 1) end
  if e.capped then tt:AddLine("Quantité limitée par ton or.", 0.9, 0.6, 0.3) end
  if e.spaceCapped then tt:AddLine("Quantité limitée par la place dans tes sacs.", 0.9, 0.6, 0.3) end
  tt:AddDoubleLine("Revendre à", ns.money(e.safe), 1, 1, 1, 1, 1, 1)
  tt:AddDoubleLine("Part de l'HV / dépôt", ns.money(e.cut) .. " / " .. ns.money(e.deposit or 0), 1, 1, 1, 1, 1, 1)
  if e.perDay then tt:AddDoubleLine("Part par jour / stock en vente", ("~%d / %.1f j"):format(e.perDay, e.stockDays or 0), 1, 1, 1, 1, 1, 1) end
  if e.travel then
    tt:AddDoubleLine("Vols", e.travel.flights == 0 and "aucun" or (("%d (%s%s)"):format(e.travel.flights,
      e.travel.guessed and "~" or "", ns.money(e.travel.flightCost))), 1, 1, 1, 1, 1, 1)
  end
  if not e.qty then tt:AddLine("Quantité : il faut au moins 2 scans de l'HV.", 0.6, 0.6, 0.6) end
  if chosenNpc(e) then tt:AddLine("Clic droit : ce marchand n'existe pas sur Forever", 0.6, 0.6, 0.6) end
end

function refresh()
  if not (frame and frame:IsShown()) then return end
  local list, m, ahdb, pending, money, waiting = ns.flipOpportunities()
  if pending and (frame.retries or 0) < 3 then -- ShortestPathForever calcule encore : on repasse dans un instant
    frame.retries = (frame.retries or 0) + 1
    C_Timer.After(1.5, refresh)
  end
  local reserve = GameDataDB.flip_reserve or 0
  frame.status:SetText(("À dépenser : %s%s — %d affaire(s) à ta portée — %s%s"):format(ns.money(money),
    reserve > 0 and (" (fond de roulement de " .. ns.money(reserve) .. " gardé)") or "", #list,
    m and ("HV du " .. m.scanned) or "HV jamais scanné",
    ahdb and ", historique AuctionDB" or (" — |cffe6994dAuctionDB absent : %d objet(s) attendent un 2e scan de l'HV|r"):format(waiting)))
  -- Filtre des notes (cases A / B / C), gardé dans GameDataDB.flip_grades.
  local keep, shown = GameDataDB.flip_grades or {}, {}
  for _, e in ipairs(list) do if keep[e.grade] ~= false then shown[#shown + 1] = e end end
  if #shown < #list then frame.status:SetText(frame.status:GetText() .. (" — %d masquée(s) par le filtre"):format(#list - #shown)) end
  tbl:SetData(shown)
end

local function build()
  frame = ns.newWindow("GameDataFlipFrame", "Mécréant", 620, 520)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -36)
  hint:SetJustifyH("LEFT")
  hint:SetText("Vendu en illimité par un marchand amical, revendable à l'HV. Clic sur un en-tête : trier ; survol d'une ligne : le détail.")
  local width
  tbl, width = ns.newTable(frame, COLUMNS, { name = "mecreant", sort = "perHour", top = 58, rowH = 20, tooltip = tooltip, onClick = onRowClick })
  frame:SetWidth(width + 50)
  hint:SetWidth(width - 150)
  -- Cases à cocher des notes : ne montrer que les A, que les A et B, etc.
  local x, last = -14, nil
  for _, g in ipairs({ "C", "B", "A" }) do
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetText(("|cff%s%s|r"):format(GRADE_COLOR[g], g))
    text:SetPoint("TOPRIGHT", x, -38)
    cb:SetPoint("RIGHT", text, "LEFT", 0, 0)
    x, last = x - 40, cb
    cb:SetChecked((GameDataDB.flip_grades or {})[g] ~= false)
    cb:SetScript("OnClick", function(self)
      GameDataDB.flip_grades = GameDataDB.flip_grades or {}
      GameDataDB.flip_grades[g] = self:GetChecked() and true or false
      refresh()
    end)
  end
  local notes = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  notes:SetPoint("RIGHT", last, "LEFT", -2, 0)
  notes:SetText("Notes :")
  -- Fond de roulement : l'or à ne jamais entamer, en pièces d'or.
  local reserve = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  reserve:SetSize(56, 20)
  reserve:SetPoint("TOPRIGHT", -62, -10)
  reserve:SetAutoFocus(false)
  reserve:SetNumeric(true)
  reserve:SetText(tostring(math.floor((GameDataDB.flip_reserve or 0) / 10000)))
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("RIGHT", reserve, "LEFT", -8, 0)
  label:SetText("Fond de roulement à garder (po) :")
  local function save(self)
    GameDataDB.flip_reserve = (tonumber(self:GetText()) or 0) * 10000
    self:ClearFocus()
    frame.retries = 0
    refresh()
  end
  reserve:SetScript("OnEnterPressed", save)
  reserve:SetScript("OnEditFocusLost", function(self)
    if (tonumber(self:GetText()) or 0) * 10000 ~= (GameDataDB.flip_reserve or 0) then save(self) end
  end)
  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.status:SetPoint("BOTTOMLEFT", 14, 10)
  frame:SetScript("OnShow", function() frame.retries = 0; refresh() end)
  -- Le bouton passe de « Y aller » à « Acheter » quand on ouvre ou ferme le bon marchand.
  frame:RegisterEvent("MERCHANT_SHOW")
  frame:RegisterEvent("MERCHANT_CLOSED")
  frame:SetScript("OnEvent", function() if frame:IsShown() then tbl:Refresh() end end)
end

function ns.toggleFlipWindow()
  if not frame then build() end
  frame:SetShown(not frame:IsShown())
end
