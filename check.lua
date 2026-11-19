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
assert(loadfile("GameData/GameData.lua"))("GameData", ns)

local bags = ns.containers(ns.isBag)
assert(bags.Backpack and bags.Bag_1 and bags.Keyring and bags.ReagentBag, "sacs manquants")
assert(not bags.Bag_2, "un sac de 0 place ne doit pas apparaître")
assert(not bags.Bank and not bags.Reagentbank, "la banque n'est pas un sac")
local bank, n = ns.containers(ns.isBank), 0
for _ in pairs(bank) do n = n + 1 end
assert(n == 3, "banque : Bank, Reagentbank et un seul des deux noms de l'onglet 1, trouvé " .. n)
assert(bags.Backpack.items[1].id == 100 and bags.Backpack.items[1].count == 3)

GameDataItems = {}
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
GameDataDB = { recipes = {}, errors = {}, chars = {} }
C_Timer.After = function(_, fn) fn() end -- le scan différé part tout de suite dans le test
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Minage", skillLevel = 140, maxSkillLevel = 225 } end,
  GetAllRecipeIDs = function() return { 3307, 3308 } end,
  GetRecipeInfo = function(id) return { name = id == 3307 and "Fondre le fer" or "Fondre l'or", learned = id == 3307, relativeDifficulty = 0 } end,
  GetRecipeSchematic = function(id) return { outputItemID = id == 3307 and 3575 or 3577, quantityMin = 1, quantityMax = 1,
    reagentSlotSchematics = { { reagents = { { itemID = id == 3307 and 2772 or 2776 } }, quantityRequired = 1, required = true } } } end,
}
local c = { errors = {}, scanned = {} }
ns.run = function(_, fn) fn(c) end
local frames = {}
CreateFrame = function() local fr = { RegisterEvent = noop }; fr.SetScript = function(self, _, fn) self.fn = fn end; frames[#frames + 1] = fr; return fr end
assert(loadfile("GameData/Commerce.lua"))("GameData", ns)
local commerce = frames[#frames]
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
local neuf, char0, run0 = { errors = {}, scanned = {} }, ns.char, ns.run
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
GetRealmName, UnitFactionGroup, time, GameDataMarket = function() return "R" end, function() return "Alliance" end, os.time, {}
local scanned, realPrint = 0, print
ns.marketScanned = function() scanned = scanned + 1 end
print = noop
commerce.fn(commerce, "AUCTION_HOUSE_SHOW")
commerce.fn(commerce, "REPLICATE_ITEM_LIST_UPDATE")
print = realPrint
assert(GameDataMarket["R-Alliance"].items[2772].min == 100 and scanned == 1, "HV lu, puis marketScanned appelé une fois")
assert(ns.exports and ns.exports.hv, "registre des exports, ouvert aux consommateurs")
print("GameData : vérifications OK")
-- Fenêtre, tableaux, montants, noms d'objets : dans LibCommune (testés par LibCommune/check.lua), plus de copie ici.
assert(loadfile("GameData/Window.lua"))("GameData", ns)
assert(ns.exportList and ns.hubTools and ns.hubTools[1][1] == "Acheter ou fabriquer", "boutons d'export et outils du hub, ouverts aux consommateurs")
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
assert(not ns.exports.journal and not ns.exports.mecreant and #ns.hubTools == 1, "plus d'export ni d'outil du négoce")
for _, e in ipairs(ns.exportList) do assert(e[1] ~= "journal" and e[1] ~= "mecreant", "bouton d'export du négoce") end
print("GameData : sans négoce OK")
