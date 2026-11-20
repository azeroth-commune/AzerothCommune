-- GameData : une base de données du jeu, scannée en jouant, écrite dans les SavedVariables
-- (WTF/Account/<COMPTE>/SavedVariables/GameData.lua, au /reload ou à la déconnexion).
--   GameDataDB.chars[GUID]          : chaque perso, sous son GUID (UnitGUID, LibCommune#19), avec son adresse
--                                     (« Prénom-Royaume ») et son nom (« Prénom Nom ») ; fiche, équipement, sacs, banque,
--                                     courrier, monnaies, réputations, métiers, compétences, recettes connues, quêtes.
--   GameDataDB.recipes / trainers / vendors, GameDataMarket : voir Commerce.lua.
--   GameDataDB.addons               : les add-ons installés (titre, version, auteur, dépendances, état).
--   GameDataItems.items[itemID]     : tous les objets du jeu.
-- Un perso n'est lisible que connecté : chaque perso apparaît après une connexion. La banque, le courrier
-- et les recettes ne se lisent que fenêtre ouverte : ouvre-les une fois par perso.
-- Chaque lecture tourne sous pcall : une API absente sur ce client devient une ligne dans `errors`.
-- Seuls les types de données auxquels un add-on a souscrit sont relevés (Souscriptions.lua, /gdata souscriptions).
-- Chaque lot relevé porte sa provenance, le build du client et sa date (ns.lot) : GameDataDB.lots[type] pour un type du
-- joueur, chars[perso].lots[champ] pour un champ de perso. Au chargement, un lot figé sous un autre build est marqué
-- perime = true, « peut-être périmé » (Souscriptions.lua, ns.verifierLots).

local _, ns = ...
GameDataAPI = ns -- lu par Handshake (prix, stocks), le Négoce et LibCommune (recettesConnues)

local lib = LibStub("LibCommune-1.0") -- embarquée (OptionalDeps en développement) : personnage, relevé des recettes

local function now() return date("%Y-%m-%d %H:%M:%S") end

-- Le lot d'un relevé fait maintenant, par GameData en jeu.
local function build() return tonumber((select(2, GetBuildInfo()))) end
local function lot()
  return { provenance = "relevé direct", build = build(), version = (GetBuildInfo()), date = now() }
end
-- Note un relevé dans le lot nom de lots (GameDataDB.lots par défaut). entier : le relevé remplace tout le lot ; sinon il
-- n'en remplace qu'une partie (un marchand, un objet…) et un lot figé sous un autre build reste peut-être périmé, avec sa
-- date d'alors (quand il a été figé).
local function noterLot(nom, entier, lots)
  lots = lots or GameDataDB.lots
  local l = lots[nom]
  if l and l.perime and not entier then return end
  if l and not l.perime then l.date = now() return end -- ponytail: un lot de GameData est toujours un relevé direct
  lots[nom] = lot()
end
ns.build, ns.lot, ns.noterLot = build, lot, noterLot

-- Sacs et banque : lus par LibCommune (lib.Conteneurs, avec les liens), seule lecture des sacs des add-ons. Sans elle,
-- pas relevés : la raison va dans errors (run), comme pour les recettes.
local function containers(filtre)
  local lib = LibStub and LibStub("LibCommune-1.0", true)
  if not (lib and lib.Conteneurs) then error("LibCommune absente : sacs et banque pas relevés", 0) end
  return lib.Conteneurs(lib[filtre])
end

-- Lisible à tout moment hors combat : à la connexion, puis toutes les 60 s.
local scan = {}

function scan.character()
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  return {
    name = lib.Personnage().nom, realm = GetRealmName(), class = class, race = race, level = UnitLevel("player"),
    faction = UnitFactionGroup("player"), guild = GetGuildInfo("player"), money = GetMoney(),
    xp = UnitXP("player"), xp_max = UnitXPMax("player"), zone = GetZoneText(),
  }
end

function scan.equipped() -- 0 = munitions, 1-19 = équipement
  local t = {}
  for slot = 0, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link then t[slot] = link end
  end
  return t
end

function scan.bags() return containers("EstSac") end

-- ponytail: monnaies, réputations et recettes repliées sous un en-tête ne sont pas lues (les déplier
-- toucherait à l'interface du joueur) ; déplie-les une fois si une ligne manque.
function scan.currencies()
  local t = {}
  for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
    local c = C_CurrencyInfo.GetCurrencyListInfo(i)
    if c and not c.isHeader then t[#t + 1] = { name = c.name, quantity = c.quantity, max = c.maxQuantity, icon = c.iconFileID } end
  end
  return t
end

function scan.reputations()
  local t = {}
  if C_Reputation and C_Reputation.GetNumFactions then
    for i = 1, C_Reputation.GetNumFactions() do
      local f = C_Reputation.GetFactionDataByIndex(i)
      if f and f.name then
        t[#t + 1] = { id = f.factionID, name = f.name, header = f.isHeader or nil, standing = f.reaction,
          value = f.currentStanding, min = f.currentReactionThreshold, max = f.nextReactionThreshold }
      end
    end
  else
    for i = 1, GetNumFactions() do
      local name, _, standing, low, high, value, _, _, isHeader, _, _, _, _, id = GetFactionInfo(i)
      if name then t[#t + 1] = { id = id, name = name, header = isHeader or nil, standing = standing, value = value, min = low, max = high } end
    end
  end
  return t
end

function scan.professions()
  local t = {}
  for i = 1, select("#", GetProfessions()) do
    local index = select(i, GetProfessions())
    if index then
      local name, _, rank, max = GetProfessionInfo(index)
      t[#t + 1] = { name = name, rank = rank, max = max }
    end
  end
  return t
end

function scan.skills() -- compétences façon vanilla : armes, défense, langues, métiers (C_SkillInfo sur Forever)
  local t = {}
  for i = 1, C_SkillInfo.GetNumSkillLines() do
    local s = C_SkillInfo.GetSkillLineInfo(i)
    if s and not s.isHeader then
      t[#t + 1] = { id = s.skillID, name = s.name, rank = s.rank, bonus = s.modifier ~= 0 and s.modifier or nil, max = s.maxRank }
    end
  end
  return t
end

function scan.quests_done() return C_QuestLog.GetAllCompletedQuestIDs() end

-- Lisibles seulement fenêtre ouverte : lancées par les événements plus bas.
local window = {}

function window.bank() return containers("EstBanque") end

function window.mail()
  local t = {}
  for i = 1, GetInboxNumItems() do
    local _, _, sender, subject, money, cod, daysLeft, hasItem = GetInboxHeaderInfo(i)
    local items = {}
    if hasItem then
      for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local link = GetInboxItemLink(i, a)
        if link then
          local _, _, _, count = GetInboxItem(i, a)
          items[#items + 1] = { link = link, count = count }
        end
      end
    end
    t[i] = { sender = sender, subject = subject, money = money, cod = cod, days_left = daysLeft, items = items }
  end
  return t
end

-- La fiche du perso connecté, sous son GUID, avec son adresse et son nom à jour (un renommage les change, pas le GUID).
-- Une fiche d'avant le GUID (anciensPersos, clé « Prénom Nom-Royaume ») est reprise à la connexion de son perso.
local function char()
  local p = lib.Personnage()
  local c = GameDataDB.chars[p.guid]
  if not c then
    local anciens = GameDataDB.anciensPersos or {}
    local ancienne = p.nom .. "-" .. GetRealmName() -- la clé d'avant
    c, anciens[ancienne] = anciens[ancienne] or { errors = {}, lots = {} }, nil
    if not next(anciens) then GameDataDB.anciensPersos = nil end
    ns.verifierFiche(c) -- reprise : ses lots figés sous un autre build sont peut-être périmés, comme au chargement
    GameDataDB.chars[p.guid] = c
  end
  c.adresse, c.nom = p.adresse, p.nom
  return c
end

-- Au chargement : les fiches d'avant le GUID sortent de chars (rangé par GUID) et attendent leur perso dans anciensPersos.
-- ponytail: une fiche jamais reprise y reste (données relevées, rescannables) ; /gdata effacer ne la touche pas.
local function rangerAnciensPersos()
  for k, c in pairs(GameDataDB.chars) do
    if not k:find("^Player%-") then
      GameDataDB.anciensPersos = GameDataDB.anciensPersos or {}
      GameDataDB.anciensPersos[k], GameDataDB.chars[k] = c, nil
    end
  end
end

-- fn(c) rend le champ relevé, et en 2e retour false s'il n'a rien relevé, "partiel" s'il n'en a relevé qu'une partie.
local function run(name, fn)
  if not ns.champSouscrit(name) then return end -- aucune souscription à son type (Souscriptions.lua)
  local c = char()
  local ok, result, releve = pcall(fn, c)
  if ok then
    c[name], c.errors[name] = result, nil
    if releve ~= false then noterLot(name, releve ~= "partiel", c.lots) end
  else c.errors[name] = tostring(result) end
end

ns.now, ns.char, ns.run = now, char, run

local function scanAddons()
  if not ns.souscrit("add-ons installés") then return end
  local t = {}
  for i = 1, C_AddOns.GetNumAddOns() do
    local name, title, notes, _, reason = C_AddOns.GetAddOnInfo(i)
    t[name] = {
      title = title, notes = notes, reason = reason, loaded = C_AddOns.IsAddOnLoaded(i),
      version = C_AddOns.GetAddOnMetadata(i, "Version"), author = C_AddOns.GetAddOnMetadata(i, "Author"),
      dependencies = { C_AddOns.GetAddOnDependencies(i) },
    }
  end
  GameDataDB.addons, GameDataDB.addons_scanned = t, now()
  noterLot("add-ons installés", true)
end

local function scanAll()
  if InCombatLockdown() then return end
  for name, fn in pairs(scan) do run(name, fn) end
end

---------------------------------------------------------------------------------------------------
-- Objets du jeu, en deux passes et en tâche de fond :
--   1. catalogue local : chaque ID que le client connaît (GetItemInfoInstant), avec catégorie,
--      emplacement et icône (GetItemInfoInstant). Aucune question au serveur, 2000 IDs par tick.
--   2. détails : nom, qualité, niveau, niveau requis, prix de vente, pile, lien. Il faut les demander
--      au serveur : 5 questions par demi-seconde (le rythme de ForeverDungeonJournal sur ce client),
--      jamais en combat, ni pendant 5 s autour d'un écran de chargement ou d'une fenêtre de quête,
--      de PNJ ou de marchand, pour que leurs propres objets passent d'abord.
-- La progression est sauvée : le scan reprend où il en était à la session suivante.
-- ponytail: borne fixe de 260 000 IDs ; à remonter si le catalogue trouve des objets jusqu'au bout.
local MAX_ITEM_ID, LOCAL_PER_TICK, ASK_PER_TICK, TICK = 260000, 2000, 5, 0.5
local todo, pos, quietUntil = {}, 1, 0
ns.MAX_ITEM_ID = MAX_ITEM_ID

local function record(id)
  local it = GameDataItems.items[id]
  if not it then return true end -- effacé entre-temps (/gdata effacer objets)
  local name, link, quality, ilvl, minLevel, _, _, stack, _, _, price, _, _, bind = C_Item.GetItemInfo(id)
  if not name then return false end
  it.name, it.link, it.quality, it.ilvl, it.min_level, it.stack, it.price, it.bind = name, link, quality, ilvl, minLevel, stack, price, bind
  noterLot("objets")
  return true
end

local function quiet()
  if InCombatLockdown() then return true end
  for _, f in ipairs({ QuestFrame, GossipFrame, MerchantFrame }) do
    if f and f:IsShown() then quietUntil = GetTime() + 5 end
  end
  return GetTime() < quietUntil
end

local function itemTick()
  local items = GameDataItems.items
  local first = GameDataItems.next_id
  local last = math.min(first + LOCAL_PER_TICK - 1, MAX_ITEM_ID)
  for id = first, last do
    if not items[id] then
      -- Sur Forever, DoesItemExistByID ne répond vrai que pour une poignée d'objets (89 sur 54 000 IDs le
      -- 18/11/2026) : GetItemInfoInstant, local et sans serveur, ne renvoie rien pour un ID qui n'existe pas.
      local _, _, _, slot, icon, class, subclass = C_Item.GetItemInfoInstant(id)
      if class then
        items[id] = { class = class, subclass = subclass, slot = slot ~= "" and slot or nil, icon = icon }
        todo[#todo + 1] = id
      end
    end
  end
  GameDataItems.next_id = last + 1
  if quiet() then return end
  local asked = 0
  while pos <= #todo and asked < ASK_PER_TICK do
    local id = todo[pos]
    pos = pos + 1
    if not record(id) then C_Item.RequestLoadItemDataByID(id); asked = asked + 1 end
  end
end
ns.itemTick = itemTick

local function itemLoaded(id, success)
  local it = GameDataItems.items[id]
  if not it or it.name then return end
  if success then record(id) else it.unknown = true end -- le serveur ne le connaît pas : on ne redemandera pas
end
ns.itemLoaded = itemLoaded

local function itemsReady() -- à la connexion : reprendre les objets encore sans détails
  GameDataItems.items = GameDataItems.items or {}
  GameDataItems.next_id = GameDataItems.next_id or 1
  if GameDataItems.scan_version ~= 2 then GameDataItems.next_id, GameDataItems.scan_version = 1, 2 end -- balayage corrigé : on repart de 1
  for id, it in pairs(GameDataItems.items) do
    if not it.name and not it.unknown then todo[#todo + 1] = id end
  end
  table.sort(todo)
end
ns.itemsReady = itemsReady

---------------------------------------------------------------------------------------------------
-- Pas de scan au PLAYER_LOGOUT : à la déconnexion le perso est déjà vidé (or 0, sacs vides).
local bankOpen = false
local f = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
  "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE", "ITEM_DATA_LOAD_RESULT" }) do
  pcall(f.RegisterEvent, f, e) -- un événement absent de ce client ne doit pas bloquer les autres
end

local itemTicker
local function setItemScan(on)
  GameDataDB.item_scan = on
  if itemTicker then itemTicker:Cancel(); itemTicker = nil end
  if on and ns.souscrit("objets") then
    itemTicker = C_Timer.NewTicker(TICK, function()
      local ok, err = pcall(itemTick)
      if not ok then
        itemTicker:Cancel(); itemTicker = nil
        GameDataDB.errors.item_scan = now() .. " " .. tostring(err)
        print("GameData : scan des objets arrêté, " .. tostring(err))
      end
    end)
  end
end

f:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "ADDON_LOADED" then
    if a1 ~= "GameData" then return end
    GameDataDB = GameDataDB or {}
    for _, k in ipairs({ "chars", "recipes", "trainers", "vendors", "errors", "lots" }) do GameDataDB[k] = GameDataDB[k] or {} end
    GameDataMarket = GameDataMarket or {}
    if GameDataDB.item_scan == nil then GameDataDB.item_scan = true end
    GameDataItems = GameDataItems or {}
    itemsReady()
    rangerAnciensPersos()
    ns.verifierLots()
  elseif event == "PLAYER_LOGIN" then
    char() -- la fiche du perso connecté, reprise tout de suite sous son GUID
    ns.retenirSouscriptions()
    C_Timer.After(5, function() scanAll(); pcall(scanAddons) end)
    C_Timer.NewTicker(60, scanAll)
    setItemScan(GameDataDB.item_scan)
  elseif event == "PLAYER_ENTERING_WORLD" then
    quietUntil = GetTime() + 5
  elseif event == "ITEM_DATA_LOAD_RESULT" then
    itemLoaded(a1, a2)
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    run("bank", window.bank)
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" or (event == "BAG_UPDATE_DELAYED" and bankOpen) then
    if bankOpen then run("bank", window.bank) end
  elseif event == "MAIL_INBOX_UPDATE" then
    run("mail", window.mail)
  end
end)

-- Les exports de GameData (/gdata export <clé>, la fenêtre GameData) : chacun photographie une partie de la base en
-- grilles (export de LibCommune), sans /reload. Déclarés à LibCommune comme ceux de tout add-on regroupé.
-- HV en lignes compactes (65 pages en JSON complet avec l'historique, le 18/11/2026) : le dernier scan de ton HV,
-- une ligne par objet « id,min,quantité,enchères,prix:qté prix:qté prix:qté » (3 premiers paliers).
local function exportHV()
  local h = GetRealmName() .. "-" .. UnitFactionGroup("player")
  local m = GameDataMarket[h]
  if not m then return { hv = h, absent = true } end
  local lines = {}
  for id, it in pairs(m.items or {}) do
    local tiers = {}
    for i = 1, math.min(3, #(it.tiers or {})) do tiers[i] = it.tiers[i].price .. ":" .. it.tiers[i].qty end
    -- %.0f et pas %d : une annonce au prix maximum (~10 milliards de cuivre) dépasse les entiers de %d sur ce client
    lines[#lines + 1] = ("%.0f,%.0f,%.0f,%.0f,%s"):format(id, it.min or 0, it.qty or 0, it.auctions or 0, table.concat(tiers, " "))
  end
  return { hv = h, scanned = m.scanned, auctions = m.auctions, format = "id,min,qty,auctions,tiers", items = table.concat(lines, "\n") }
end
local EXPORTS = {
  { cle = "perso", libelle = "Mon perso", description = "fiche, sacs, banque, courrier, équipement, monnaies, réputations, métiers, quêtes",
    donnees = function() scanAll() return { [lib.Personnage().guid] = char() } end },
  { cle = "persos", libelle = "Tous mes persos", description = "la même chose pour chaque perso déjà connecté",
    donnees = function() scanAll() return GameDataDB.chars end },
  { cle = "recettes", libelle = "Recettes", description = "toutes les recettes vues, avec produit et composants",
    donnees = function() return GameDataDB.recipes end },
  { cle = "marchands", libelle = "Marchands", description = "ce que chaque marchand visité vend, et à quel prix",
    donnees = function() return GameDataDB.vendors end },
  { cle = "maitres", libelle = "Maîtres", description = "ce que chaque maître enseigne, prix et niveau requis",
    donnees = function() return GameDataDB.trainers end },
  { cle = "hv", libelle = "Hôtel des ventes", description = "le dernier scan : prix le plus bas, quantité, 3 premiers paliers",
    donnees = exportHV },
  { cle = "addons", libelle = "Add-ons", description = "les add-ons installés : version, auteur, dépendances",
    donnees = function() return GameDataDB.addons end },
  { cle = "erreurs", libelle = "Diagnostic", description = "erreurs de scan et derniers événements vus",
    donnees = function() return { base = GameDataDB.errors, perso = char().errors, events = GameDataDB.events } end },
}

-- /gdata export <clé> : l'export déclaré sous cette clé par n'importe quel add-on regroupé (lib.Exports) ; sans clé, la
-- fenêtre GameData.
function ns.exportCommand(what)
  local lib = LibStub and LibStub("LibCommune-1.0", true)
  if not (lib and lib.Exporter and lib.Exports) then return print("GameData : l'export par image demande LibCommune.") end
  if what == "" and ns.toggleExportWindow then return ns.toggleExportWindow() end
  local e, cles = nil, {}
  for _, x in ipairs(lib.Exports()) do
    cles[#cles + 1] = x.cle
    if x.cle == what then e = e or x end
  end
  if not e then
    table.sort(cles)
    return print("GameData : /gdata export " .. table.concat(cles, " | "))
  end
  print("GameData : préparation de l'export « " .. what .. " »…")
  local ok, err = pcall(function() lib.Exporter(e.donnees(), "gamedata-" .. what) end)
  if not ok then
    GameDataDB.errors.export = ns.now() .. " " .. what .. " : " .. tostring(err)
    print("|cffe64d4dGameData : l'export « " .. what .. " » a planté :|r " .. tostring(err))
  end
end

-- Bouton de la minicarte et entrée des options : ceux d'Azeroth Commune, communs aux add-ons présents (LibCommune#3).
-- Clic (GameData seul) ou sa ligne du menu = la fenêtre GameData (Window.lua). L'angle reste dans GameDataDB.minimap_angle.
local lib = LibStub and LibStub("LibCommune-1.0", true)
if lib and lib.Regrouper then
  lib.Regrouper({ nom = "GameData", dossier = "GameData", icone = "Interface\\Icons\\INV_Scroll_03",
    ouvrir = function() ns.toggleExportWindow() end, store = function() return GameDataDB end, exports = EXPORTS })
end

SLASH_GAMEDATA1 = "/gdata"
SlashCmdList.GAMEDATA = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)$")
  if cmd:lower() == "cout" and ns.costCommand then return ns.costCommand(rest) end
  if cmd:lower() == "export" then return ns.exportCommand(rest:lower()) end
  if ns.souscriptionsCommand(cmd:lower(), rest) then return end
  msg = (msg or ""):lower()
  if msg == "objets" then
    setItemScan(not GameDataDB.item_scan)
    return print("GameData : scan des objets " .. (GameDataDB.item_scan and "en marche." or "en pause."))
  end
  scanAll(); pcall(scanAddons)
  local chars, total, named, unknown = 0, 0, 0, 0
  for _ in pairs(GameDataDB.chars) do chars = chars + 1 end
  for _, it in pairs(GameDataItems.items) do
    total = total + 1
    if it.name then named = named + 1 elseif it.unknown then unknown = unknown + 1 end
  end
  print(("GameData : %d perso(s). Objets : %d connus du client (IDs lus jusqu'à %d sur %d), %d avec détails, %d inconnus du serveur. Scan %s (/gdata objets)."):format(
    chars, total, math.min(GameDataItems.next_id - 1, MAX_ITEM_ID), MAX_ITEM_ID, named, unknown, GameDataDB.item_scan and "en marche" or "en pause"))
  print("  " .. (ns.commerceStatus and ns.commerceStatus() or "Commerce.lua n'est pas chargé : recettes, marchands et HV ne sont pas lus."))
  for name, err in pairs(char().errors) do print("  erreur", name, err) end
  for name, err in pairs(GameDataDB.errors) do print("  erreur", name, err) end
  print("  /reload pour écrire la base sur le disque. /gdata export : la fenêtre des exports.")
end
