-- Vérification hors jeu (non chargée par le TOC) : luajit GameData/check.lua
-- Simule juste ce qu'il faut de l'API WoW pour tester le filtre des conteneurs et le scan des objets.
local ns = {}
local noop = function() end
CreateFrame = function() return { RegisterEvent = noop, SetScript = noop } end
SlashCmdList = {}
C_Timer = { After = noop, NewTicker = noop }
InCombatLockdown = function() return false end
GetTime = function() return 100 end
date = os.date
local BUILD = "64000"
GetBuildInfo = function() return "1.16.1", BUILD, "Nov 1 2026", 11601 end

-- Conteneurs : deux noms pour le même sac (Characterbanktab = CharacterBankTab_1), un sac vide.
Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Keyring = -2, ReagentBag = 5,
  Bank = -1, CharacterBankTab_1 = 6, Characterbanktab = 6, Reagentbank = -3 } }
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 2 and 0 or 2 end,
  GetContainerItemInfo = function(bag, slot) if slot == 1 then return { itemID = 100 + bag, stackCount = 3, hyperlink = "l" } end end,
}

-- Objets : le client connaît 1, 2 et 5 ; le serveur a 1 en cache, ne connaît pas 5.
local requested = {}
C_Item = {
  DoesItemExistByID = function(id) return id == 1 or id == 2 or id == 5 end,
  GetItemInfoInstant = function(id) if id == 1 or id == 2 or id == 5 then return id, "t", "s", "INVTYPE_HEAD", 1234, 4, 1 end end,
  GetItemInfo = function(id) if id == 1 then return "Casque", "lien", 2, 10, 5, nil, nil, 1, nil, nil, 50, nil, nil, 1 end end,
  RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
}

-- La lib commune (dépôt voisin, chargée avant GameData comme dans le jeu) : GameData y prend le relevé des recettes.
assert(loadfile("LibCommune/LibStub.lua"))()
assert(loadfile("LibCommune/LibCommune.lua"))()
assert(loadfile("LibCommune/Fournisseurs.lua"))()
assert(loadfile("LibCommune/Regroupement.lua"))() -- bouton commun, outils et exports déclarés (LibCommune#3, #21)
assert(loadfile("GameData/GameData.lua"))("GameData", ns)
-- Un export déclaré à la lib (lib.Exports), par sa clé.
local function export(cle)
  for _, e in ipairs(LibStub("LibCommune-1.0").Exports()) do if e.cle == cle then return e end end
end

GameDataItems, GameDataDB = {}, { lots = {} }
ns.itemsReady()
ns.itemTick()
local items = GameDataItems.items
assert(items[1] and items[2] and items[5] and not items[3], "catalogue local")
assert(items[1].name == "Casque" and items[1].price == 50, "objet en cache enregistré tout de suite")
assert(items[1].slot == "INVTYPE_HEAD" and items[1].class == 4)
assert(#requested == 2 and requested[1] == 2 and requested[2] == 5, "seuls les objets hors cache sont demandés")
assert(GameDataItems.next_id == 2001)

ns.itemLoaded(5, false)
assert(items[5].unknown, "inconnu du serveur : marqué pour ne pas redemander")
ns.itemTick() -- rien de neuf à demander
assert(#requested == 2)

-- Commerce : clés de recettes, et agrégation des enchères en prix unitaires et paliers.
assert(loadfile("GameData/Commerce.lua"))("GameData", ns)
assert(ns.itemIDOf("|cff|Hitem:3575::::|h[Barre de fer]|h|r") == 3575)
assert(ns.recipeKey("|Henchant:3307|h[Fondre le fer]|h", "Minage", "Fondre le fer") == 3307)
assert(ns.recipeKey(nil, "Minage", "Fondre le fer") == "Minage:Fondre le fer")
local m = ns.aggregate({
  { id = 2772, count = 20, buyout = 2000 },  -- 100 l'unité
  { id = 2772, count = 5, buyout = 400 },    -- 80 l'unité : le moins cher
  { id = 2772, count = 10, buyout = 1000 },  -- 100 : même palier que le premier
  { id = 2772, count = 1, buyout = 0 },      -- enchère sans achat immédiat : ignorée
  { id = 3575, count = 0, buyout = 150 },    -- quantité 0 lue comme 1
})
assert(m[2772].min == 80 and m[2772].qty == 35 and m[2772].auctions == 3)
assert(#m[2772].tiers == 2 and m[2772].tiers[1].price == 80 and m[2772].tiers[2].qty == 30)
assert(m[3575].min == 150)

-- Fenêtre de métier simulée (API moderne de Forever) : recette apprise et recette pas encore apprise.
GameDataDB = { recipes = {}, errors = {}, chars = {}, lots = {} }
C_Timer.After = function(_, fn) fn() end -- le scan différé part tout de suite dans le test
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Minage", skillLevel = 140, maxSkillLevel = 225 } end,
  GetAllRecipeIDs = function() return { 3307, 3308 } end,
  GetRecipeInfo = function(id) return { name = id == 3307 and "Fondre le fer" or "Fondre l'or", learned = id == 3307, relativeDifficulty = 0 } end,
  GetRecipeSchematic = function(id) return { outputItemID = id == 3307 and 3575 or 3577, quantityMin = 1, quantityMax = 1,
    reagentSlotSchematics = { { reagents = { { itemID = id == 3307 and 2772 or 2776 } }, quantityRequired = 1, required = true } } } end,
}
local c = { errors = {}, lots = {} }
ns.run = function(_, fn) fn(c) end
local frames = {}
CreateFrame = function() local fr = { RegisterEvent = noop }; fr.SetScript = function(self, _, fn) self.fn = fn end; frames[#frames + 1] = fr; return fr end
assert(loadfile("GameData/Commerce.lua"))("GameData", ns)
local commerce = frames[#frames]
-- Rien n'est relevé sans souscription (Souscriptions.lua, testé plus bas) : ici, souscription à tous les types.
time = os.time
assert(loadfile("GameData/Souscriptions.lua"))("GameData", ns)
for nom in pairs(ns.rangement) do ns.souscrire(nom) end
commerce.fn(commerce, "TRADE_SKILL_LIST_UPDATE")
local r = GameDataDB.recipes[3307]
assert(r and r.output == 3575 and r.reagents[1].id == 2772 and r.reagents[1].qty == 1, "recette lue")
assert(GameDataDB.recipes[3308] and GameDataDB.recipes[3308].output == 3577, "recette pas encore apprise : lue aussi")
assert(c.recipes.Minage.rank == 140 and c.recipes.Minage.known[3307] == "optimal" and not c.recipes.Minage.known[3308])
-- Ce que lit LibCommune (type « recettes connues ») : les recettes vues et, par perso, ses métiers.
GameDataDB.chars["Belegard-Test"], GameDataDB.chars["Sans-Metier"] = c, { errors = {} }
local rc = ns.recettesConnues()
assert(rc.recettes[3307].output == 3575 and rc.persos["Belegard-Test"].Minage.known[3307], "recettes connues pour la lib")
assert(rc.persos["Sans-Metier"] == nil, "un perso sans métier relevé n'apparaît pas")
assert(LibStub("LibCommune-1.0"):Lire("recettes connues", "Belegard-Test").persos["Belegard-Test"].Minage, "lu par la lib")
-- Connexion : recettes connues relevées sans fenêtre (IsPlayerSpell, recettes déjà vues), pour un perso jamais passé par
-- sa fenêtre de métier, et sauvegardées dans son perso. Puis la fenêtre s'ouvre : elle prime, sans rien perdre.
local neuf, char0, run0 = { errors = {}, lots = {} }, ns.char, ns.run
ns.char, ns.run = function() return neuf end, function(_, fn) fn(neuf) end
GameDataDB.recipes[3310] = { profession = "Minage", name = "Fondre le thorium" } -- vue chez un autre perso
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Minage", "icône", 150, 225 end
IsPlayerSpell = function(id) return id == 3307 or id == 3310 end
commerce.fn(commerce, "PLAYER_LOGIN")
local mn = neuf.recipes and neuf.recipes.Minage
assert(mn and mn.rank == 150 and mn.known[3307] == true and mn.known[3310] and not mn.known[3308], "relevé sans fenêtre sauvegardé")
commerce.fn(commerce, "TRADE_SKILL_LIST_UPDATE")
mn = neuf.recipes.Minage
assert(mn.known[3307] == "optimal" and mn.rank == 140 and mn.scanned and not mn.known[3308], "la fenêtre prime")
assert(mn.known[3310], "connue mais absente de la liste de la fenêtre : gardée")
ns.char, ns.run = char0, run0
-- Lecture de l'HV : GameData appelle ns.marketScanned ensuite, où un consommateur (le Négoce) s'accroche.
C_AuctionHouse = { ReplicateItems = noop, GetNumReplicateItems = function() return 1 end,
  GetReplicateItemInfo = function() return nil, nil, 5, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 2772 end }
-- La maison de l'HV vient de la lib (lib.MaisonHV) : la même qu'avant, « royaume-faction » au royaume rendu (GameData#24).
local MAISON = "CAMWOW EU4 Realm 8 PvP-Alliance"
GetRealmName, UnitFactionGroup, time, GameDataMarket = function() return "CAMWOW EU4 Realm 8 PvP" end, function() return "Alliance" end, os.time, {}
local scanned, realPrint = 0, print
ns.marketScanned = function() scanned = scanned + 1 end
print = noop
commerce.fn(commerce, "AUCTION_HOUSE_SHOW")
commerce.fn(commerce, "REPLICATE_ITEM_LIST_UPDATE")
print = realPrint
assert(GameDataMarket[MAISON].items[2772].min == 100 and scanned == 1, "HV lu, puis marketScanned appelé une fois")
-- Sans fournisseur, le scan de l'HV marche comme avant : GameData relève tout (prix, quantité, paliers, historique).
local hvR = GameDataMarket[MAISON]
assert(hvR.items[2772].qty == 5 and hvR.items[2772].auctions == 1 and hvR.items[2772].tiers[1].price == 100, "tout relevé")
assert(#hvR.hist[2772] == 1 and hvR.hist[2772][1][2] == 100 and hvR.hist[2772][1][3] == 5, "historique relevé")
local hvLib, lotLib = LibStub("LibCommune-1.0"):Lire("cours de l'HV")
assert(hvLib.objet(2772).min == 100 and hvLib.objet(2772).sources.min == "GameData" and lotLib.provenance == "relevé direct", "lu par la lib")

-- Fournisseurs (GameData#6, option B). Un nouveau scan, 15 min plus tard, avec Auctionator et AuctionDB frais : GameData
-- garde ce que son scan vient de voir (prix, quantité, annonces, paliers : comme avant, ils font foi en relevé direct),
-- mais pas de copie de l'historique, qu'AuctionDB tient.
local horloge = 100
GetTime = function() return horloge end
local function scanHV()
  horloge = horloge + 1000
  print = noop
  commerce.fn(commerce, "AUCTION_HOUSE_SHOW")
  commerce.fn(commerce, "REPLICATE_ITEM_LIST_UPDATE")
  print = realPrint
end
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return ({ [2772] = 95, [9999] = 70 })[id] end,
  GetAuctionAgeByItemID = function(_, id) if id == 2772 or id == 9999 then return 0 end end } } } -- 9999 vu aujourd'hui
local T = os.time() - 600
AuctionDBForeverSaved = { houses = { ["na-forever-rp Alliance"] = { scans = { { T } }, items = { [2772] = ("%d,90,95,300"):format(T) } } } }
scanHV()
hvR = GameDataMarket[MAISON]
assert(scanned == 2 and hvR.items[2772].min == 100 and hvR.items[2772].qty == 5 and hvR.items[2772].tiers[1].price == 100, "prix, quantité, paliers gardés comme avant")
assert(hvR.hist == nil, "AuctionDB frais : pas de copie de l'historique")
hvLib, lotLib = LibStub("LibCommune-1.0"):Lire("cours de l'HV")
local l = hvLib.objet(2772)
assert(l.min == 100 and l.sources.min == "GameData" and l.qty == 5 and l.hist[1][1] == T and l.sources.hist == "AuctionDB", "lu : scan de GameData, historique d'AuctionDB")
assert(lotLib.provenance == "relevé direct" and lotLib.champs.hist == "AuctionDB", "relevé direct")
local retire = hvLib.objet(9999)
assert(retire.min == nil and retire.qty == 0, "absent du scan de GameData : plus en vente, même vu aujourd'hui par Auctionator")
assert(export("hv").donnees().items == "2772,100,5,1,100:5", "export comme avant")
-- AuctionDB plus frais (son dernier scan il y a 7 h) : GameData garde son historique, comme avant ; à la lecture,
-- celui d'AuctionDB (plusieurs jours) passe quand même avant le point unique de GameData (relecture de Negoce#1).
AuctionDBForeverSaved.houses["na-forever-rp Alliance"].scans = { { os.time() - 7 * 3600 } }
scanHV()
hvR = GameDataMarket[MAISON]
assert(scanned == 3 and #hvR.hist[2772] == 1 and hvR.hist[2772][1][2] == 100, "historique gardé par GameData")
assert(LibStub("LibCommune-1.0"):Lire("cours de l'HV").objet(2772).sources.hist == "AuctionDB", "lu : l'historique d'AuctionDB d'abord")
Auctionator, AuctionDBForeverSaved = nil, nil
print("GameData : fournisseurs des cours de l'HV OK")
-- Royaume et faction relevés par la lib, qui les sonde (GameData#24) : plus d'appel direct dans le code chargé.
for _, f in ipairs({ "GameData.lua", "Commerce.lua", "Souscriptions.lua", "Window.lua" }) do
  local code = io.open("GameData/" .. f):read("*a")
  for _, appel in ipairs({ "GetRealmName", "GetNormalizedRealmName", "UnitFactionGroup" }) do
    local n = select(2, code:gsub(appel .. "%(", ""))
    assert(n == 0, f .. " : appel direct à " .. appel)
  end
end
print("GameData : royaume et faction par la lib OK")
print("GameData : vérifications OK")
-- Fenêtre, tableaux, montants, noms d'objets : dans LibCommune (testés par LibCommune/check.lua), plus de copie ici.
assert(loadfile("GameData/Window.lua"))("GameData", ns)
local regroupe = LibStub("LibCommune-1.0").regroupes[1]
GameDataDB = GameDataDB or {}
local ouverte = 0
local toggle = ns.toggleExportWindow
ns.toggleExportWindow = function() ouverte = ouverte + 1 end
regroupe.ouvrir()
ns.toggleExportWindow = toggle
assert(regroupe and regroupe.nom == "GameData" and ouverte == 1 and regroupe.store() == GameDataDB,
  "GameData regroupé : sa fenêtre au clic, l'angle du bouton dans GameDataDB")
assert(not io.open("GameData/Window.lua"):read("*a"):find("GameDataMinimapButton", 1, true), "plus de bouton de minicarte à lui")
-- Ses exports déclarés à la lib comme ceux de tout add-on ; plus de registre ni d'outils à lui (LibCommune#21).
local cles = {}
for _, e in ipairs(LibStub("LibCommune-1.0").Exports()) do
  assert(e.addon == "GameData" and e.libelle and e.description and type(e.donnees) == "function", e.cle)
  cles[#cles + 1] = e.cle
end
assert(table.concat(cles, ",") == "perso,persos,recettes,marchands,maitres,hv,addons,erreurs", table.concat(cles, ","))
assert(ns.exports == nil and ns.exportList == nil and ns.hubTools == nil, "plus de registre d'exports ni d'outils dans GameData")
local window = io.open("GameData/Window.lua"):read("*a")
for _, mot in ipairs({ "Handshake", "Négoce", "Negoce", "Acheter ou fabriquer", "openCraftWindow" }) do
  assert(not window:find(mot, 1, true), "Window.lua mentionne encore " .. mot)
end
assert(not io.open("GameData/GameData.lua"):read("*a"):find("Be a Good Pal Commandes", 1, true), "aide de /gdata : plus de module de Handshake")
for _, k in ipairs({ "newWindow", "newTable", "sortRows", "money", "moneyShort", "moneySigned", "itemLabel", "findItem" }) do
  assert(ns[k] == nil, "copie de l'outil commun " .. k .. " encore dans GameData")
end
for _, f in ipairs({ "GameData.lua", "Window.lua" }) do
  assert(not io.open("GameData/" .. f):read("*a"):find("BeAGoodPal", 1, true), f .. " : l'export passe par LibCommune")
end
print("GameData : outils communs pris dans LibCommune OK")

-- Le négoce vit dans l'add-on Négoce (#2) : ni ses fichiers dans le TOC, ni ses exports, ni ses outils dans le hub.
local toc = io.open("GameData/GameData.toc"):read("*a")
for _, f in ipairs({ "Flip", "Ledger", "Alerts", "BulkBuy" }) do assert(not toc:find(f .. ".lua", 1, true), f .. ".lua encore dans le TOC") end
assert(not export("journal") and not export("mecreant"), "plus d'export du négoce")
print("GameData : sans négoce OK")

-- Souscriptions (GameData#4), sur plusieurs sessions qui partagent les SavedVariables : une souscription faite sur le
-- personnage A fait relever le type sur le personnage B à sa connexion, même sans l'add-on qui a souscrit ; un type sans
-- souscription n'est pas relevé ; après 30 jours sans souscription il ne l'est plus, ses données restent ;
-- /gdata effacer <type> les efface.
GameDataDB, GameDataItems, GameDataMarket = nil, nil, nil
time, GetRealmName = os.time, function() return "Kerys" end
local tickers
C_Timer = { After = function(_, fn) fn() end, NewTicker = function(t) tickers[#tickers + 1] = t return { Cancel = noop } end }
local sortie = {}
local GUID = { Alice = "Player-1-0000A11C", Bob = "Player-1-00000B0B", Carl = "Player-1-0000CA71" }
local NOM_DE_FAMILLE = {} -- 2e retour de UnitName sur Forever
local function session(nom, souscriptions)
  UnitName = function() return nom, NOM_DE_FAMILLE[nom] end
  UnitGUID = function(u) if u == "player" then return GUID[nom] end end
  tickers, sortie = {}, {}
  LibStub = nil -- nouvelle session : la lib repart de zéro, seules les SavedVariables restent
  assert(loadfile("LibCommune/LibStub.lua"))()
  assert(loadfile("LibCommune/LibCommune.lua"))()
  assert(loadfile("LibCommune/Fournisseurs.lua"))()
  assert(loadfile("LibCommune/Regroupement.lua"))() -- les exports déclarés (lib.Exports)
  frames = {} -- ceux de GameData : GameData.lua puis Commerce.lua
  local gns = {}
  for _, f in ipairs({ "GameData", "Commerce", "Souscriptions" }) do assert(loadfile("GameData/" .. f .. ".lua"))("GameData", gns) end
  frames[1].fn(frames[1], "ADDON_LOADED", "GameData")
  local lib = LibStub("LibCommune-1.0")
  for _, t in ipairs(souscriptions or {}) do assert(lib:Souscrire(t)) end -- l'add-on qui souscrit, chargé après GameData
  print = function(...) sortie[#sortie + 1] = table.concat({ ... }, " ") end
  for _, fr in ipairs(frames) do if fr.fn then fr.fn(fr, "PLAYER_LOGIN") end end
  print = realPrint
  return gns, lib
end
local function gdata(cmd) print = function(...) sortie[#sortie + 1] = table.concat({ ... }, " ") end; SlashCmdList.GAMEDATA(cmd); print = realPrint end
local function objetsScannes() for _, t in ipairs(tickers) do if t == 0.5 then return true end end return false end
local A, B, C = GUID.Alice, GUID.Bob, GUID.Carl -- les fiches sont rangées par GUID (LibCommune#19)

local gns, glib = session("Alice", { "inventaires" })
assert(type(GameDataDB.souscriptions.inventaires) == "number", "souscription retenue avec sa date")
assert(GameDataDB.chars[A].bags.Backpack, "A : inventaires relevés")

-- Sacs et banque relevés par lib.Conteneurs (LibCommune#20) : exactement ce que rendait la copie de GameData d'avant,
-- gardée ici comme référence.
local function avant(keep)
  local out, seen = {}, {}
  for name, bag in pairs(Enum.BagIndex) do
    if keep(name) and not seen[bag] then
      seen[bag] = true
      local size = C_Container.GetContainerNumSlots(bag)
      if size and size > 0 then
        local items = {}
        for slot = 1, size do
          local it = C_Container.GetContainerItemInfo(bag, slot)
          if it then items[#items + 1] = { id = it.itemID, count = it.stackCount, link = it.hyperlink } end
        end
        out[name] = { size = size, items = items }
      end
    end
  end
  return out
end
local function isBag(n) return n == "Backpack" or n == "Keyring" or n == "ReagentBag" or n:find("^Bag_") ~= nil end
local function isBank(n) return n:find("[Bb]ank") ~= nil end
local function pareil(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not pareil(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local bags = GameDataDB.chars[A].bags
assert(bags.Backpack and bags.Bag_1 and bags.Keyring and bags.ReagentBag, "sacs manquants")
assert(not bags.Bag_2, "un sac de 0 place ne doit pas apparaître")
assert(not bags.Bank and not bags.Reagentbank, "la banque n'est pas un sac")
assert(bags.Backpack.items[1].id == 100 and bags.Backpack.items[1].count == 3 and bags.Backpack.items[1].link == "l")
assert(pareil(bags, avant(isBag)), "sacs : le même relevé qu'avant")
frames[1].fn(frames[1], "BANKFRAME_OPENED")
local bank, n = GameDataDB.chars[A].bank, 0
for _ in pairs(bank) do n = n + 1 end
assert(n == 3, "banque : Bank, Reagentbank et un seul des deux noms de l'onglet 1, trouvé " .. n)
assert(pareil(bank, avant(isBank)), "banque : le même relevé qu'avant")
-- Sans LibCommune : ni sacs ni banque relevés, la raison dans errors, la dernière banque vue reste.
local vraiLibStub = LibStub
LibStub = nil
frames[1].fn(frames[1], "PLAYERBANKSLOTS_CHANGED")
LibStub = vraiLibStub
assert(GameDataDB.chars[A].errors.bank == "LibCommune absente : sacs et banque pas relevés" and GameDataDB.chars[A].bank == bank,
  "sans LibCommune : " .. tostring(GameDataDB.chars[A].errors.bank))
frames[1].fn(frames[1], "BANKFRAME_CLOSED")
print("GameData : sacs et banque par lib.Conteneurs, comme avant OK")
assert(not objetsScannes(), "objets sans souscription : pas de scan des objets")
for _, t in pairs(glib.types) do assert(type(gns[t.gamedata]) == "function", "accesseur de GameData : " .. t.gamedata) end
for nom in pairs(gns.rangement) do assert(glib.types[nom], "rangé mais pas au catalogue : " .. nom) end

session("Bob") -- l'add-on qui a souscrit n'est pas activé sur B
local b = GameDataDB.chars[B]
assert(b and b.bags.Backpack.items[1].id == 100, "B : inventaires relevés à sa connexion, souscrits sur A")
assert(b.reputations == nil and b.errors.reputations == nil and b.quests_done == nil, "B : un type sans souscription n'est pas relevé")
assert(glib.types and LibStub("LibCommune-1.0"):Lire("inventaires", B).persos[B].bags, "lu par la lib")
gdata("souscriptions")
local liste = table.concat(sortie, "\n")
assert(liste:find("inventaires : souscrit le", 1, true) and liste:find("objets : aucune souscription", 1, true), liste)

GameDataDB.souscriptions.inventaires = os.time() - 31 * 24 * 3600
session("Carl")
assert(not (GameDataDB.chars[C] and GameDataDB.chars[C].bags), "C : plus de souscription depuis 31 jours, plus relevé")
assert(GameDataDB.chars[B].bags.Backpack and GameDataDB.chars[A].bags, "les données relevées restent")
gdata("souscriptions")
assert(table.concat(sortie, "\n"):find("plus relevé", 1, true), "la liste dit qu'il n'est plus relevé")

gdata("effacer inventaires")
assert(GameDataDB.chars[A].bags == nil and GameDataDB.chars[B].bags == nil and GameDataDB.chars[B].lots.bags == nil, "inventaires effacés")
gdata("effacer pas un type")
assert(table.concat(sortie, "\n"):find("inconnu", 1, true), "type inconnu refusé")

-- Types globaux : recettes, maîtres, marchands, HV, objets. Le joueur souscrit lui-même aux objets (/gdata souscrire).
gdata("souscrire objets")
gdata("souscrire cours de l'HV")
assert(gns.souscrit("cours de l'HV"), "/gdata souscrire cours de l'HV : le nom tapé tel quel")
session("Bob")
assert(objetsScannes(), "objets souscrits : scan des objets lancé")
GameDataDB.vendors[42] = { items = {} }
GameDataItems.items[7] = { name = "x" }
gdata("effacer objets")
assert(next(GameDataItems.items) == nil and GameDataItems.next_id == 1, "objets effacés, le balayage repart de 1")
gns.itemTick() -- un ID encore en file d'attente, effacé entre-temps : ignoré sans erreur
gdata("effacer marchands")
assert(next(GameDataDB.vendors) == nil, "marchands effacés")
print("GameData : souscriptions OK")

-- Provenance (GameData#5) : chaque lot porte sa provenance, son build et sa date. Une base d'avant les lots est migrée
-- (relevé direct, build inconnu donc peut-être périmé) ; un build différent marque les lots figés peut-être périmés ;
-- dans le lot mixte des marchands, la provenance la plus fiable gagne.
GameDataDB = { souscriptions = { inventaires = os.time(), marchands = os.time() },
  chars = { [A] = { errors = {}, scanned = { bags = "2026-11-01 12:00:00" }, bags = { Backpack = { size = 16, items = {} } } } },
  vendors = { [42] = { name = "Vu en jeu", items = { { id = 159, price = 30, stack = 5 } } } } }
GameDataItems, GameDataMarket = nil, nil
gns, glib = session("Carl")
local la = GameDataDB.chars[A].lots.bags
assert(la.provenance == "relevé direct" and la.date == "2026-11-01 12:00:00" and la.perime and la.build == nil, "migration d'un champ de perso")
assert(GameDataDB.chars[A].scanned == nil, "la date du relevé est passée dans le lot")
assert(GameDataDB.lots.marchands.provenance == "relevé direct" and GameDataDB.lots.marchands.perime, "migration d'un type du joueur")
local _, lot = glib:Lire("inventaires")
lot = lot.persos[C]
assert(lot.provenance == "relevé direct" and lot.build == 64000 and lot.version == "1.16.1" and lot.date and not lot.perime, "lire un type rend provenance, build et date")
_, lot = glib:Lire("inventaires", "tous")
assert(lot.persos[A].perime and lot.persos[C].build == 64000, "lots de chaque perso")

-- Lot mixte : le marchand 42 vu en jeu garde sa liste, le 7 (seulement dans VendorData) vient de la base, marqué.
-- Le 8 n'est amical que pour la Horde : absent pour un personnage de l'Alliance ; le 9 (Alliance) reste.
gns.VENDOR_DB = { [159] = { 25, 5, "42,7,8H,9A", 1, 20 } }
local m7
m, lot = glib:Lire("marchands")
m7 = m[7]
assert(m[42].items[1].price == 30 and m[42].provenance == nil and lot == GameDataDB.lots.marchands, "vu en jeu > VendorData")
assert(m7.provenance == "source externe" and m7.items[1].price == 25 and GameDataDB.vendors[7] == nil, "marchand pas vu : la base, sans rien sauvegarder")
assert(m7.items[1].sell == 1 and m7.items[1].maxStack == 20, "ligne de la base : revente et taille de pile")
assert(m[8] == nil and m[9].items[1].id == 159, "base : pas de PNJ amical pour la seule faction adverse")
gdata("effacer marchands")
m, lot = glib:Lire("marchands")
assert(m[42].provenance == nil and m[42].items[1].price == 25 and lot.provenance == "source externe" and lot.perime, "seule la base : lot source externe, build inconnu")

-- Nouveau build du client : les lots figés sous l'ancien sont marqués peut-être périmés, rien n'est effacé.
gns.noterLot("marchands") -- un marchand vu sous le build 64000
assert(GameDataDB.lots.marchands.build == 64000 and not GameDataDB.lots.marchands.perime)
BUILD = "64100"
gns, glib = session("Alice")
local lm = GameDataDB.lots.marchands
assert(lm.perime and lm.build == 64000, "lot du joueur figé sous l'ancien build : peut-être périmé")
assert(GameDataDB.chars[C].lots.bags.perime and GameDataDB.chars[C].bags, "lot d'un perso pas connecté : marqué, gardé")
assert(GameDataDB.chars[A].lots.bags.build == 64100 and not GameDataDB.chars[A].lots.bags.perime, "perso connecté : relevé à nouveau, plus périmé")
local figeLe = lm.date
lm.date = "2026-11-01 12:00:00"
gns.noterLot("marchands") -- un autre marchand vu : les autres restent d'avant
assert(lm.perime and lm.build == 64000 and GameDataDB.lots.marchands == lm, "relevé partiel : le lot reste peut-être périmé")
assert(lm.date == "2026-11-01 12:00:00" and figeLe, "relevé partiel d'un lot périmé : sa date reste celle où il a été figé")
gns.noterLot("marchands", true)
assert(GameDataDB.lots.marchands.build == 64100 and not GameDataDB.lots.marchands.perime, "relevé entier : plus périmé")
print("GameData : provenance, build et date des lots OK")

-- Recettes connues sous un nouveau build (64100) : la fenêtre d'un métier ne relève que ce métier. Une fenêtre qui ne
-- relève rien (liste pas à jour, métier d'un autre) ne touche pas au lot ; le lot n'est plus périmé que quand chaque
-- métier a été relevé sous ce build. Le relevé sans fenêtre note son lot à la fin.
GameDataDB.souscriptions["recettes connues"] = os.time()
local ca = GameDataDB.chars[A]
ca.recipes = { Minage = { rank = 100, max = 150, known = {} }, Couture = { rank = 50, max = 75, known = {} } }
ca.lots.recipes = { provenance = "relevé direct", build = 64000, date = "2026-11-01 12:00:00", perime = true }
local lr = ca.lots.recipes
local commerceS = frames[2]
local function fenetre() commerceS.fn(commerceS, "TRADE_SKILL_LIST_UPDATE") end
local function inchange(quoi)
  assert(ca.lots.recipes == lr and lr.perime and lr.build == 64000 and lr.date == "2026-11-01 12:00:00", quoi)
  assert(ca.errors.recipes == nil, tostring(ca.errors.recipes))
end
C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { professionName = "Forge" } end
fenetre()
inchange("liste pas à jour : rien de relevé, lot inchangé")
C_TradeSkillUI.GetProfessionInfoByRecipeID, C_TradeSkillUI.IsTradeSkillLinked = nil, function() return true end
fenetre()
inchange("métier d'un autre : rien de relevé, lot inchangé")
C_TradeSkillUI.IsTradeSkillLinked = nil
fenetre()
assert(ca.recipes.Minage.known[3307] and ca.recipes.Minage.build == 64100, "Minage relevé sous le nouveau build")
inchange("un métier relevé, Couture encore d'avant : relevé partiel, lot toujours peut-être périmé")
local base0 = C_TradeSkillUI.GetBaseProfessionInfo
C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionName = "Couture", skillLevel = 60, maxSkillLevel = 75 } end
fenetre()
C_TradeSkillUI.GetBaseProfessionInfo = base0
assert(ca.lots.recipes.build == 64100 and not ca.lots.recipes.perime, "chaque métier relevé sous ce build : lot entier, plus périmé")
local fini
glib.ReleverRecettesSansFenetre = function(_, _, _, f) fini = f return true end
ca.lots.recipes = nil
commerceS.fn(commerceS, "PLAYER_LOGIN")
assert(fini and ca.lots.recipes == nil, "relevé sans fenêtre en cours : lot pas encore noté")
fini()
assert(ca.lots.recipes and ca.lots.recipes.build == 64100, "relevé sans fenêtre fini : lot noté")
print("GameData : lot des recettes connues, par métier OK")

-- Fiches par GUID (LibCommune#19) : une base d'avant, rangée sous « Prénom Nom-Royaume » (le cas de Forever : prénom et
-- nom de famille), sort de chars au chargement ; la fiche du perso connecté est reprise sous son GUID à sa connexion,
-- avec son adresse et son nom, et ses lots figés sous un autre build sont marqués peut-être périmés ; celle d'un perso
-- pas encore connecté attend dans anciensPersos, sans être lue par la lib, et /gdata effacer la touche aussi.
-- La clé d'Alice porte le royaume affiché d'alors (« Ker ys ») : la reprise compare les formes normalisées, et tient quand
-- lib.Royaume() passe au normalisé (LibCommune#35).
GetNormalizedRealmName = function() return "Kerys" end
NOM_DE_FAMILLE.Alice = "Dupont"
GameDataDB = { souscriptions = { inventaires = os.time() }, chars = {
  ["Alice Dupont-Ker ys"] = { errors = {}, mail = { { subject = "d'Alice" } },
    lots = { mail = { provenance = "relevé direct", build = 64000, date = "2026-11-01 12:00:00" } } },
  ["Bob-Kerys"] = { errors = {}, lots = {}, mail = { { subject = "gardé" } }, quests_done = { 1 } } } }
GameDataItems, GameDataMarket = nil, nil
gns, glib = session("Alice")
local fa = GameDataDB.chars[A]
assert(fa and fa.mail[1].subject == "d'Alice", "fiche « Prénom Nom-Royaume » reprise sous le GUID")
assert(fa.adresse == "Alice-Kerys" and fa.nom == "Alice Dupont", "adresse sans le nom de famille, nom avec : " .. tostring(fa.adresse))
assert(fa.lots.mail.perime and fa.lots.mail.build == 64000, "reprise sous un nouveau build (64100) : lot peut-être périmé")
assert(GameDataDB.chars["Alice Dupont-Ker ys"] == nil and GameDataDB.chars["Bob-Kerys"] == nil, "plus d'ancienne clé dans chars")
assert(GameDataDB.anciensPersos["Bob-Kerys"] and not GameDataDB.anciensPersos["Alice Dupont-Ker ys"], "Bob attend sa connexion")
for k in pairs(GameDataDB.chars) do assert(k:find("^Player%-"), "chars : seulement des GUID, pas " .. k) end
local tousInv = glib:Lire("inventaires", "tous")
for k in pairs(tousInv.persos) do assert(k:find("^Player%-"), "lu par la lib : seulement des GUID, pas " .. k) end
assert(glib:Lire("inventaires", A).persos[A].mail, "Lire par GUID")
local pa = glib.Personnage(A)
assert(pa.guid == A and pa.adresse == "Alice-Kerys" and pa.nom == "Alice Dupont", "lib.Personnage : le perso connecté")
assert(gns.personnage(A).nom == "Alice Dupont" and gns.personnage("Player-1-0000DEAD") == nil, "accesseur personnage de GameData")
gdata("effacer quêtes terminées")
assert(GameDataDB.anciensPersos["Bob-Kerys"].quests_done == nil, "effacer : aussi les fiches qui attendent leur perso")
gns, glib = session("Bob")
local fb = GameDataDB.chars[B]
assert(fb.mail[1].subject == "gardé" and fb.quests_done == nil and GameDataDB.anciensPersos == nil, "Bob repris à sa connexion, champ effacé pas revenu")
assert(glib.Personnage(A).nom == "Alice Dupont" and glib.Personnage(A).adresse == "Alice-Kerys", "un autre perso du joueur : sa fiche dans GameData")
local exportPerso
for _, e in ipairs(glib.Exports()) do if e.cle == "perso" then exportPerso = e end end
assert(next(exportPerso.donnees()) == B, "export perso : sous le GUID")
NOM_DE_FAMILLE.Alice = nil
print("GameData : fiches par GUID, migration OK")
