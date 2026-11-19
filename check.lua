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
print("GameData : vérifications OK")
-- Mécréant : le plan d'achat d'un objet (prix sûr, débit, quantité).
assert(loadfile("GameData/Flip.lua"))("GameData", ns)
local H = 3600
local hist = { { 0, 1000, 2000 }, { 16 * H, 1100, 1500 }, { 32 * H, 1200, 1800 }, { 48 * H, 1300, 1200 } } -- 1 100 partis en 48 h
local plan = ns.flipPlan(450, 1, { min = 1400, qty = 1285 }, hist)
assert(plan and math.abs(plan.safe - 1075) < 0.01, "prix sûr = 1er quartile des minimums")
assert(math.abs(plan.perDay - 550) < 0.01 and math.abs(plan.net - (1075 * 0.95 - 450)) < 0.01)
assert(plan.qty == 293 and plan.grade == "B", "moitié de 2 jours de débit, réduite par le stock (" .. tostring(plan.qty) .. ")")
assert(ns.flipPlan(450, 20, { min = 1400, qty = 1285 }, hist).qty == 280, "arrondi aux lots du marchand")
assert(ns.flipPlan(450, 1, { min = 900, qty = 1285 }, hist).safe == 899, "creux actuel : un cuivre sous le moins cher")
assert(ns.flipPlan(450, 1, { min = 1400, qty = 5000 }, hist) == nil, "plus de 5 jours de stock : saturé")
assert(ns.flipPlan(1000, 1, { min = 1400, qty = 100 }, hist) == nil, "marge sous 15 %")
local alone = ns.flipPlan(450, 1, { min = 1400, qty = 100 }, nil)
assert(alone and not alone.qty and alone.grade == "C", "sans historique : marge seulement, pas de quantité")
print("GameData : Mécréant OK")
local h = { items = { [3857] = "1794652988,440,580,412 1794654915,475,500,601 1794660135,329,484,752" } }
local long = ns.ahdbHistory(h, 3857)
assert(#long == 3 and long[3][2] == 329 and long[3][3] == 752 and long[3][4] == 484, "historique AuctionDB lu")
print("GameData : historique AuctionDB OK")

-- Trajet : le marchand le plus rapide parmi les plus proches, vols au prix noté chez le maître de vol.
CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
C_Map = C_Map or {}
C_Map.GetWorldPosFromMapPos = function(map, v) local x, y = v:GetXY() return 0, CreateVector2D(x * 1000, y * 1000) end
GameDataDB.taxi = { ["Forgefer"] = { ["Hurlevent"] = 1500 } }
ShortestPathForever = { API = { EstimateDetail = function(_, _, _, map, x)
  if x > 0.5 then return { seconds = 900, legs = { { mode = "walk" } } } end                         -- loin, à pied
  return { seconds = 300, legs = { { mode = "walk" }, { mode = "flight", to = "Hurlevent" } } }      -- proche, un vol
end } }
local t = ns.travelFor({ point = { 1, 0.2, 0.2, "Garyl" } }, { 1, 0.1, 0.1 })
assert(t and t.seconds == 2 * 300 + 120 and t.flights == 2 and t.flightCost == 3000 and not t.guessed, "aller-retour, 2 vols notés")
GameDataDB.taxi = {}
assert(ns.travelFor({ point = { 1, 0.2, 0.2 } }, { 1, 0.1, 0.1 }).guessed, "prix de vol inconnu : estimé")
-- Emplacement d'un PNJ sans Questie : zone QuestieDB (1519) -> carte 1453, table décodée depuis QuestieDB.
LibQuestieDB = { Support = { Get = function() return { private = {
  areaIdToUiMapId = "return { [1519] = 1453, [2257] = 7 }", areaIdToUiMapIdOverride = "return { [2257] = 0 }" } } end } }
NpcDB = { spawns = function(npc) return npc == 1286 and { [1519] = { { 64.6, 71.3 } }, [2257] = { { 1, 1 } } } or nil end }
local viaNpc = ns.travelFor({ npcs = { 1286 } }, { 1453, 0.6, 0.7 })
assert(viaNpc and viaNpc.point[1] == 1453 and math.abs(viaNpc.point[2] - 0.646) < 1e-9, "marchand placé sans Questie (tram ignoré)")
print("GameData : trajet OK")

-- Budget : 293 charbons à 4 pa 50 = 13 po 18 ; avec 5 po on en prend 111, gain recalculé ; un lot hors de prix : écarté.
local deal = ns.flipPlan(450, 1, { min = 1400, qty = 1285 }, hist)
assert(ns.capToBudget(deal, 50000) and deal.qty == 111 and deal.capped and deal.cost == 111 * 450, "ramené à ton or")
assert(math.abs(deal.profit - 111 * deal.net) < 0.01)
local lotDeal = ns.flipPlan(450, 20, { min = 1400, qty = 1285 }, hist)
assert(not ns.capToBudget(lotDeal, 5000), "un lot de 20 à 90 pa avec 50 pa : hors de portée")
print("GameData : budget OK")
-- Dépôt : charbon (revente 125, pile de 10) = 30 % de 125 = 37,5 par unité, minimum 1 pa pour l'annonce entière ;
-- pioche (revente 16, non empilable) = une annonce par pioche, donc 1 pa chacune.
local withDep = ns.flipPlan(450, 1, { min = 1400, qty = 1285 }, hist, { sell = 125, stack = 10, rate = 0.30, min = 100 })
assert(math.abs(withDep.net - (1075 * 0.95 - 450 - 37.5)) < 0.01, "dépôt au taux")
assert(math.abs(ns.profitOf(withDep, 2) - (2 * (withDep.net + 37.5) - 100)) < 0.01, "2 charbons : une annonce au minimum 1 pa")
assert(math.abs(ns.profitOf(withDep, 100) - 100 * withDep.net) < 0.01, "100 charbons : le taux dépasse le minimum")
local pick = ns.flipPlan(9, 1, { min = 300, qty = 50 }, hist, { sell = 16, stack = 1, rate = 0.30, min = 100 })
assert(pick and pick.deposit == 100, "non empilable : 1 pa par objet")
print("GameData : dépôt OK")

-- Journal : bilan par objet (achat chez le marchand, mise en vente, vente lue dans le courrier).
hooksecurefunc = function() end
C_Container, C_AuctionHouse = C_Container or {}, C_AuctionHouse or {}
assert(loadfile("GameData/Ledger.lua"))("GameData", ns)
time = os.time
GameDataDB.ledger = {
  { t = time(), kind = "achat_marchand", id = 3857, qty = 100, money = -45000 },
  { t = time(), kind = "mise_hv", id = 3857, qty = 100, money = -3750 },
  { t = time(), kind = "vente_hv", id = 3857, qty = 60, money = 79800 + 3750 }, -- 60 × 14 pa − 5 % + dépôt rendu
  { t = time(), kind = "retour_hv", id = 3857, qty = 10, money = 0 },
}
local sum, total = ns.ledgerSummary()
assert(#sum == 1 and sum[1].bought == 100 and sum[1].sold == 60 and sum[1].onSale == 30, "quantités")
assert(total == -45000 - 3750 + 83550 and sum[1].money == total, "bilan = entrées − sorties")
print("GameData : journal OK")

-- Achat en gros : épices par lots de 5, 20 par appel, 3 cases libres ; on en veut 100 -> 3 piles puis « sacs pleins ».
local calls, free, tick = {}, 3, nil
MerchantFrame = { IsShown = function() return true end }
GetMerchantNumItems = function() return 1 end
GetMerchantItemID = function() return 2678 end
C_MerchantFrame = { GetItemInfo = function() return { price = 9, stackCount = 5 } end }
GetMerchantItemMaxStack = function() return 20 end
GetMoney = function() return 1000000 end
NUM_BAG_SLOTS = 0
C_Container.GetContainerNumFreeSlots = function() return free, 0 end
C_Container.GetContainerNumSlots = function() return 0 end
BuyMerchantItem = function(_, q) calls[#calls + 1] = q; free = free - 1 end
C_Timer.NewTicker = function(_, fn) tick = fn return { Cancel = function() tick = nil end } end
C_Item.GetItemNameByID = function() return "Epices douces" end
StaticPopupDialogs = {}
local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end
assert(loadfile("GameData/BulkBuy.lua"))("GameData", ns)
local clock = 1000
GetTime = function() clock = clock + 1 return clock end -- chaque tick avance d'une seconde : l'attente des sacs passe
ns.bulkBuy(2678, 100)
for _ = 1, 10 do if tick then tick() end end
print = realPrint
assert(#calls == 3 and calls[1] == 20 and calls[3] == 20, "3 piles de 20")
assert(printed[#printed]:find("60 acheté") and printed[#printed]:find("sacs pleins"), printed[#printed])
print("GameData : achat en gros OK")

-- Charbon réel (18/11/2026) : couche bon marché à 4-4,6 pa, l'étage haut à 13,5 pa ne part pas -> écarté (4 pa < achat).
local coalHist = { { 0, 440, 3000, 1349 }, { 12 * 3600, 450, 2500, 1349 }, { 24 * 3600, 400, 2030, 1349 } }
local coalNow = { min = 400, qty = 2179, tiers = { { price = 400, qty = 14 }, { price = 465, qty = 300 }, { price = 1349, qty = 800 } } }
assert(ns.flipPlan(450, 1, coalNow, coalHist, { sell = 125, stack = 10, rate = 0.20, min = 1 }) == nil, "charbon écarté")
print("GameData : charbon écarté OK")

-- Ventes vues dans l'onglet « Ventes » de l'HV : 26 charbons à 4 pa 63 (total 12 038), inscrits tout de suite.
Enum = Enum or {}
Enum.AuctionStatus = { Active = 0, Sold = 1 }
C_AuctionHouse.GetNumOwnedAuctions = function() return 1 end
C_AuctionHouse.GetOwnedAuctionInfo = function() return { auctionID = 77, status = 1, quantity = 26, buyoutAmount = 12038, itemKey = { itemID = 3857 } } end
GameDataDB.ledger, GameDataDB.ledger_sold = { { t = time(), kind = "mise_hv", id = 3857, qty = 26, money = -650, deposit = 650 } }, {}
local frames2 = {}
CreateFrame = function() local fr = { RegisterEvent = function() end }; fr.SetScript = function(self, _, fn) self.fn = fn end; frames2[#frames2 + 1] = fr; return fr end
assert(loadfile("GameData/Ledger.lua"))("GameData", ns)
ns.charKey = function() return "Belegard-Test" end
local lf = frames2[#frames2]
lf.fn(lf, "OWNED_AUCTIONS_UPDATED")
lf.fn(lf, "OWNED_AUCTIONS_UPDATED") -- deuxième passage : pas de doublon
local sales = {}
for _, e in ipairs(GameDataDB.ledger) do if e.kind == "vente_hv" then sales[#sales + 1] = e end end
assert(#sales == 1 and sales[1].money == math.floor(12038 * 0.95) + 650 and sales[1].unit == 463, "vente inscrite une fois")
print("GameData : ventes de l'onglet HV OK")

-- Tableaux : tri par colonne, cases vides toujours en bas, égalités dans l'ordre d'arrivée.
assert(loadfile("GameData/Window.lua"))("GameData", ns)
local cols = { { key = "h", get = function(r) return r.h end }, { key = "n", get = function(r) return r.n end } }
local rows = { { n = "b", h = 5 }, { n = "a" }, { n = "c", h = 9 }, { n = "d", h = 5 } }
ns.sortRows(rows, cols, { key = "h", desc = true })
assert(rows[1].n == "c" and rows[2].n == "b" and rows[3].n == "d" and rows[4].n == "a", "gain/h décroissant, vide en bas")
ns.sortRows(rows, cols, { key = "h", desc = false })
assert(rows[1].n == "b" and rows[2].n == "d" and rows[3].n == "c" and rows[4].n == "a", "croissant, vide toujours en bas")
ns.sortRows(rows, cols, { key = "n", desc = false })
assert(rows[1].n == "a" and rows[4].n == "d")
print("GameData : tri des tableaux OK")

-- Marchand signalé absent (clic droit dans Mécréant) : écarté des PNJ proposés.
UnitFactionGroup = function() return "Alliance" end
ItemDB = { vendors = function() return { 15011, 1286 } end }
NpcDB.friendlyToFaction = function() return "AH" end
GameDataDB.flip_absent = { [15011] = "Wagner Hammerstrike" }
local vend = ns.questieVendors(3857)
assert(#vend == 1 and vend[1] == 1286, "Wagner écarté")
print("GameData : marchands absents OK")

-- Alertes HV : charbon habituellement à ~4 pa 60, 40 en sac.
CreateFrame = function() return { RegisterEvent = noop, SetScript = noop } end
assert(loadfile("GameData/Alerts.lua"))("GameData", ns)
local H = 3600
local coalUsual = { { 0, 460, 2000 }, { 6 * H, 450, 1900 }, { 12 * H, 470, 1800 }, { 18 * H, 455, 1700 }, { 24 * H, 700, 300 } }
local s = ns.sellSignal({ min = 700, qty = 300 }, coalUsual, 125, 40, 0.20, 24 * H)
assert(s and s.price == 699 and s.usual == 457.5 and s.owned == 40, "charbon à 7 pa : alerte")
assert(not ns.sellSignal({ min = 500, qty = 300 }, coalUsual, 125, 40, 0.20, 24 * H), "4 pa 99 : pas assez au-dessus")
assert(not ns.sellSignal({ min = 700, qty = 300 }, coalUsual, 125, 5, 0.20, 24 * H), "5 charbons : moins de 50 pa, pas d'alerte")
assert(not ns.sellSignal({ min = 700, qty = 300 }, { coalUsual[1], coalUsual[2], coalUsual[5] }, 125, 40, 0.20, 24 * H), "2 scans : habituel inconnu")
print("GameData : alertes HV OK")
