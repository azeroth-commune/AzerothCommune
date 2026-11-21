-- Vérification hors jeu (non chargée par le TOC) : luajit LibCommune/check.lua (depuis le dossier parent)
-- Juste assez de l'API WoW pour l'accès aux données relevées : avec GameData, sans GameData (relevé de repli),
-- et deux copies de la lib de mineures différentes.
local noop = function() end
local cadres = {}
CreateFrame = function()
  local f = { RegisterEvent = noop }
  f.SetScript = function(self, _, fn) self.onEvent = fn end
  cadres[#cadres + 1] = f
  return f
end
C_Timer = { After = function(_, fn) fn() end } -- le relevé différé part tout de suite dans le test
UnitName = function() return "Belegard", "Marteaudefer" end
GetRealmName = function() return "Kerys" end
GetBuildInfo = function() return "1.16.1", "64000", "Nov 1 2026", 11601 end
date = os.date
-- Un personnage est identifié par son GUID (LibCommune#19) : persos est rangé par GUID.
local MOI, ALT = "Player-1-0000BE1E", "Player-1-00000A17"
UnitGUID = function(u) if u == "player" then return MOI end end

assert(loadfile("LibCommune/LibStub.lua"))()
assert(loadfile("LibCommune/LibCommune.lua"))()
assert(loadfile("LibCommune/Fournisseurs.lua"))()
local lib = LibStub("LibCommune-1.0")
UnitFactionGroup = function() return "Alliance" end
-- Sondes (#30), avant tout relevé : chacune « pas encore vue ».
local IDENTITE = { "royaume", "royaume normalisé", "maison de l'HV", "GUID", "nom", "faction", "build" }
for _, nom in ipairs({ "emplacements d'un conteneur", "objet d'un conteneur", "recettes", "prix Auctionator",
  "prix TSM", "prix AuctionDB", unpack(IDENTITE) }) do
  assert(lib.Sondes()[nom] and lib.Sondes()[nom].etat == "pas encore vue", "jamais vérifiée : " .. nom)
end

-- GameData présent : la lib lit sa base par GameDataAPI.recettesConnues, recettes connues de tous les personnages.
local base = {
  recettes = { [3307] = { profession = "Minage", name = "Fondre le fer", output = 3575 },
    [2662] = { profession = "Forge", name = "Cuirasse en cuivre", output = 2852 } },
  persos = {
    [MOI] = { Minage = { rank = 140, max = 225, known = { [3307] = "optimal" } } },
    [ALT] = { Forge = { rank = 50, max = 75, known = { [2662] = "easy" } } },
  },
}
GameDataAPI = { recettesConnues = function() return base end }
local tous = assert(lib:Lire("recettes connues", "tous"))
assert(tous.persos[MOI].Minage.known[3307] and tous.persos[ALT].Forge.known[2662], "tous les personnages")
assert(tous.recettes[2662].output == 2852, "et les recettes vues")
local moi = assert(lib:Lire("recettes connues"))
assert(moi.persos[MOI] and not moi.persos[ALT], "sans personnage : le personnage connecté")
local alt = assert(lib:Lire("recettes connues", ALT))
assert(alt.persos[ALT].Forge.rank == 50 and not alt.persos[MOI], "un personnage donné")
local d, raison = lib:Lire("recettes connues", "Player-1-0000DEAD")
assert(d == nil and raison == "pas encore relevé", "personnage jamais connecté : " .. tostring(raison))
local seules = { recettes = base.recettes, persos = {} } -- recettes vues, aucun perso relevé (perso supprimé…)
GameDataAPI.recettesConnues = function() return seules end
assert(lib:Lire("recettes connues", "tous").recettes[3307], "« tous » rend les recettes vues même sans perso")
GameDataAPI.recettesConnues = function() return { recettes = {}, persos = {} } end
d, raison = lib:Lire("recettes connues", "tous")
assert(d == nil and raison == "pas encore relevé", "base vide : " .. tostring(raison))
print("LibCommune : GameData présent OK")

-- Type absent du catalogue : indisponible, avec sa raison.
d, raison = lib:Lire("cours de la bourse")
assert(d == nil and raison == "type inconnu", tostring(raison))
d, raison = lib:Souscrire("cours de la bourse")
assert(d == nil and raison == "type inconnu", tostring(raison))
print("LibCommune : type inconnu OK")

-- Personnage : GUID, adresse « Prénom-Royaume » (royaume normalisé, jamais le nom de famille), nom « Prénom Nom ».
GetNormalizedRealmName = function() return "CAMWOWEU4Realm8PvP" end
local R = "CAMWOWEU4Realm8PvP"
assert(lib.Adresse("Solarin") == "Solarin-" .. R, "sans royaume : le nôtre")
assert(lib.Adresse("Solarin Ydenah") == "Solarin-" .. R, "nom de famille (GetUnitName(true) sur Forever) : pas un royaume")
assert(lib.Adresse("Belegard Marteaudefer-" .. R) == "Belegard-" .. R, "nom de famille et royaume")
assert(lib.Adresse("Bob-AutreRoyaume") == "Bob-AutreRoyaume", "avec royaume")
assert(lib.Adresse("Riwanon", "Kerys des Bois") == "Riwanon-KerysdesBois" and lib.Adresse("Bob", "CAMWOW EU4 Realm 8 PvP") == "Bob-" .. R,
  "prénom et royaume brut : normalisé")
assert(lib.Adresse("Bob|cff") == nil and lib.Adresse("") == nil and lib.Adresse(nil) == nil, "nom piégé ou vide : nil")
assert(lib.Destinataire("Bob-" .. R) == "Bob" and lib.Destinataire("Bob") == "Bob", "chuchotement sur notre royaume : prénom seul")
assert(lib.Destinataire("Bob-AutreRoyaume") == "Bob-AutreRoyaume" and lib.Destinataire("Bob|cff") == "Bob|cff", "autre royaume ; illisible tel quel")
local moiP = lib.Personnage()
assert(moiP.guid == MOI and moiP.adresse == "Belegard-" .. R and moiP.nom == "Belegard Marteaudefer", "personnage connecté")
assert(lib.Personnage(MOI).nom == "Belegard Marteaudefer", "par son GUID")
local gdAvant = GameDataAPI
GameDataAPI = nil
assert(lib.Personnage(ALT) == nil, "autre GUID sans GameData : inconnu")
GameDataAPI = { personnage = function(g) if g == ALT then return { guid = ALT, adresse = "Alt-" .. R, nom = "Alt Dupont" } end end }
assert(lib.Personnage(ALT).nom == "Alt Dupont" and lib.Personnage("Player-1-0000DEAD") == nil, "un personnage du joueur : la fiche de GameData")
GameDataAPI = gdAvant
print("LibCommune : personnage OK")

-- Sondes (#30) : le build 71037 rend un royaume vide sans erreur. La sonde est rouge, avec la valeur reçue et le build ;
-- un seul avertissement par session ; la valeur rendue ne change pas (pas de refus, pas de secours).
local dits, vraiPrint = {}, print
print = function(m) dits[#dits + 1] = m end
local buildAvant = GetBuildInfo
GetBuildInfo = function() return "1.16.1", "71037", "Nov 21 2026", 11601 end
lib.buildLu = nil -- une mise à jour du jeu : le build de la session est relu
GetNormalizedRealmName = function() return "" end
local s = lib.Sondes()["royaume normalisé"]
assert(s.etat == "vert" and s.valeur == R, "avant : verte, " .. tostring(s.valeur))
assert(lib.RoyaumeNormalise() == "", "valeur rendue inchangée : vide")
s = lib.Sondes()["royaume normalisé"]
assert(s.etat == "rouge" and s.valeur == "" and s.build == "71037" and s.heure:match("^%d%d:%d%d:%d%d$"), "rouge, valeur et build")
assert(lib.Adresse("Bob") == nil, "adresse sans royaume : rien d'inventé")
assert(#dits == 1 and dits[1]:find("^Azeroth Commune : ") and dits[1]:find("royaume normalisé", 1, true) and dits[1]:find("71037"),
  "un avertissement qui nomme la sonde et le build : " .. tostring(dits[1]))
lib.RoyaumeNormalise()
assert(#dits == 1, "deux relevés de suite : un seul avertissement")
GetNormalizedRealmName = function() return R end
assert(lib.RoyaumeNormalise() == R and lib.Sondes()["royaume normalisé"].etat == "vert", "le royaume revient : verte")
-- Royaume affiché, normalisé et maison de l'HV : rendus par la lib, sondés ; la clé de l'HV reste celle des scans.
GetRealmName = function() return "CAMWOW EU4 Realm 8 PvP" end
assert(lib.Royaume() == "CAMWOW EU4 Realm 8 PvP" and lib.Sondes().royaume.etat == "vert", "royaume affiché")
assert(lib.MaisonHV() == "CAMWOW EU4 Realm 8 PvP-Alliance" and lib.Sondes()["maison de l'HV"].etat == "vert", "maison de l'HV")
assert(lib.Faction() == "Alliance" and lib.Build() == 71037 and lib.Personnage().guid == MOI, "faction, build, GUID")
for _, nom in ipairs({ "faction", "build", "GUID", "nom" }) do assert(lib.Sondes()[nom].etat == "vert", "verte : " .. nom) end
assert(lib.Sondes().nom.valeur[1] == "Belegard" and lib.Sondes().nom.valeur[2] == "Marteaudefer", "nom : les deux retours gardés")
GetRealmName = function() return "" end
assert(lib.MaisonHV() == "-Alliance", "royaume vide : la clé telle que le jeu la donne, pas de secours")
assert(lib.Sondes().royaume.etat == "rouge" and lib.Sondes()["maison de l'HV"].etat == "rouge", "royaume et maison rouges")
UnitFactionGroup = function() return nil end
assert(lib.MaisonHV() == nil and lib.Sondes().faction.etat == "rouge", "faction inconnue : pas de maison, faction rouge")
UnitFactionGroup = function() return "Alliance" end
UnitName = function() return "Belegard" end
assert(lib.Personnage().nom == "Belegard" and lib.Sondes().nom.etat == "rouge", "sans nom de famille : rouge, nom inchangé")
UnitName = function() return "Belegard", "Marteaudefer" end
-- Relancer : les relevés sans contexte refaits, sans rien rendre de plus à l'appelant que l'état des sondes.
GetRealmName = function() return "Kerys" end
local etat = lib.RelancerSondes()
for _, nom in ipairs(IDENTITE) do assert(etat[nom].etat == "vert", "relancée verte : " .. nom .. " " .. tostring(etat[nom].valeur)) end
assert(#dits == 5, "un avertissement par sonde rouge (royaume normalisé, royaume, maison, faction, nom) : " .. #dits)
print = vraiPrint
GetBuildInfo = buildAvant
lib.buildLu = nil
print("LibCommune : sondes, royaume vide OK")

-- Catalogue : les types que GameData relève, chacun léger ou lourd, avec son accesseur dans GameDataAPI.
local attendus = { "inventaires", "réputations", "métiers et compétences", "quêtes terminées", "recettes connues",
  "maîtres de métier", "marchands", "prix des vols", "add-ons installés", "cours de l'HV", "objets" }
local nTypes = 0
for _ in pairs(lib.types) do nTypes = nTypes + 1 end
assert(nTypes == #attendus, "catalogue : " .. nTypes .. " types")
for _, nom in ipairs(attendus) do assert(lib.types[nom] and type(lib.types[nom].gamedata) == "string", "au catalogue : " .. nom) end
assert(not lib.types.objets.leger and not lib.types["cours de l'HV"].leger and lib.types.inventaires.leger, "lourds : HV et objets")
-- Souscription avec GameData : transmise à GameDataAPI.souscrire (qui la retient pour le joueur), et gardée pour la session.
local transmis = {}
GameDataAPI.souscrire = function(t) transmis[#transmis + 1] = t end
for _, nom in ipairs(attendus) do assert(lib:Souscrire(nom), "souscription : " .. nom) end
assert(#transmis == #attendus and transmis[1] == "inventaires", "chaque souscription transmise à GameData")
assert(lib.souscriptions.objets and lib.souscriptions["recettes connues"], "et retenue pour la session")
assert(lib.Demander == lib.Souscrire, "ancien nom gardé")
-- Lecture d'un type par personnage autre que les recettes, et d'un type pour tout le joueur.
GameDataAPI.inventaires = function() return { persos = { [MOI] = { bags = { Backpack = { size = 16 } } }, [ALT] = { bank = {} } } } end
local inv = assert(lib:Lire("inventaires"))
assert(inv.persos[MOI].bags.Backpack.size == 16 and not inv.persos[ALT], "inventaires du personnage connecté")
assert(lib:Lire("inventaires", "tous").persos[ALT], "inventaires de tous")
GameDataAPI.marchands = function() return { [1234] = { name = "Marchand", items = {} } } end
assert(assert(lib:Lire("marchands", ALT))[1234].name == "Marchand", "marchands : une table pour le joueur")
GameDataAPI.marchands = function() return {} end
d, raison = lib:Lire("marchands")
assert(d == nil and raison == "pas encore relevé", "aucun marchand : " .. tostring(raison))
GameDataAPI.objets = function() return nil end
d, raison = lib:Lire("objets")
assert(d == nil and raison == "pas encore relevé", "objets absents : " .. tostring(raison))
lib.souscriptions = {}
print("LibCommune : catalogue et souscriptions avec GameData OK")

-- Provenance (GameData#5) : lire un type rend son lot, provenance, build et date ; par personnage pour un type par perso.
local lotM = { provenance = "relevé direct", build = 64000, version = "1.16.1", date = "2026-11-19 10:00:00" }
GameDataAPI.marchands = function() return { [1234] = { items = {} } }, lotM end
local _, lot = lib:Lire("marchands")
assert(lot == lotM and lot.provenance == "relevé direct" and lot.build == 64000 and lot.date, "lot d'un type pour le joueur")
local lotA, lotB = { provenance = "relevé direct", build = 63000, perime = true }, { provenance = "relevé direct", build = 64000 }
GameDataAPI.inventaires = function()
  return { persos = { [MOI] = { bags = {} }, [ALT] = { bags = {} } } }, { persos = { [MOI] = lotB, [ALT] = lotA } }
end
_, lot = lib:Lire("inventaires")
assert(lot.persos[MOI] == lotB and lot.persos[ALT] == nil, "lot du personnage lu seulement")
_, lot = lib:Lire("inventaires", "tous")
assert(lot.persos[ALT].perime and lot.persos[ALT].build == 63000, "lots de tous, figé sous un autre build : peut-être périmé")
GameDataAPI.inventaires = function() return { persos = { [MOI] = {} } } end -- un GameData d'avant les lots
d, lot = lib:Lire("inventaires")
assert(d and lot.persos[MOI] == nil, "sans lot fourni : les données quand même")
_, lot = lib:Lire("inventaires", "tous")
assert(type(lot.persos) == "table", "sans lot fourni, « tous » : lot.persos lisible quand même")
GameDataAPI.marchands = function() return { [1234] = { items = {} } } end
_, lot = lib:Lire("marchands")
assert(type(lot) == "table" and lot.provenance == nil, "sans lot fourni, type du joueur : un lot vide, pas nil")
-- Lot mixte : pour chaque clé, la provenance la plus fiable gagne ; une ligne d'une autre provenance porte la sienne.
local vu, base = { [1] = { price = 90 } }, { [1] = { price = 100 }, [2] = { price = 50 } }
local autre = { [2] = { price = 60 }, [3] = { price = 70 } }
local mixte, tete = lib.Fusionner({ { donnees = base, provenance = "source externe" }, { donnees = autre, provenance = "autre add-on" },
  { donnees = vu, provenance = "relevé direct" } })
assert(tete == "relevé direct" and mixte[1] == vu[1] and mixte[1].provenance == nil, "vu en jeu > base externe")
assert(mixte[2].price == 60 and mixte[2].provenance == "autre add-on", "autre add-on > source externe")
assert(mixte[3].provenance == "autre add-on" and base[2].provenance == nil, "les sources ne sont pas touchées")
mixte, tete = lib.Fusionner({ { donnees = {}, provenance = "relevé direct" }, { donnees = base, provenance = "source externe" } })
assert(tete == "source externe" and mixte[2].provenance == nil, "une seule source avec des données : c'est la provenance du lot")
assert(lib.provenances[1] == "relevé direct" and lib.provenances[4] == "source externe", "du plus fiable au moins fiable")
local sources = { { donnees = { [1] = { x = "inconnue" } }, provenance = "rumeur" }, { donnees = base, provenance = "source externe" },
  { donnees = vu, provenance = "relevé direct" } }
mixte, tete = lib.Fusionner(sources)
assert(sources[1].provenance == "rumeur" and sources[3].provenance == "relevé direct", "le tableau des sources de l'appelant n'est pas trié")
assert(tete == "relevé direct" and mixte[1] == vu[1], "provenance inconnue : classée en dernier, sans erreur")
mixte, tete = lib.Fusionner({ { donnees = { [9] = { x = 1 } }, provenance = "rumeur" } })
assert(tete == "rumeur" and mixte[9].x == 1, "seule source, provenance inconnue")
print("LibCommune : provenance, build et date des lots OK")

-- GameData absent : relevé de repli du personnage connecté, en mémoire ; rien n'est écrit chez l'hôte.
GameDataAPI = nil
HoteDB = { reglages = { x = 1 } } -- les SavedVariables de l'add-on hôte
local avant = {}
for k in pairs(_G) do avant[k] = true end
d, raison = lib:Lire("recettes connues")
assert(d == nil and raison == "pas encore relevé", "rien de relevé : " .. tostring(raison))
assert(lib:Souscrire("recettes connues"))
-- Sans GameData, pas de relevé de repli pour les autres types (lourds, ou pas encore écrits) ; la souscription reste acceptée.
assert(lib:Souscrire("objets") and lib:Souscrire("inventaires"), "souscription sans GameData")
for _, nom in ipairs({ "objets", "marchands" }) do
  d, raison = lib:Lire(nom)
  assert(d == nil and raison == "pas de GameData", nom .. " sans GameData : " .. tostring(raison))
end
-- Cours de l'HV sans GameData ni fournisseur : indisponible avec la raison, jamais un relevé de repli.
d, raison = lib:Lire("cours de l'HV")
assert(d == nil and raison == "pas de GameData ni de fournisseur", "HV sans GameData ni fournisseur : " .. tostring(raison))
assert(lib.repli.hv == nil, "pas de relevé de repli de l'HV")
local cadre = cadres[#cadres]
Enum = {}
C_TradeSkillUI = { -- fenêtre de métier ouverte : une recette apprise, une pas encore apprise
  GetBaseProfessionInfo = function() return { professionName = "Minage", skillLevel = 140, maxSkillLevel = 225 } end,
  GetAllRecipeIDs = function() return { 3307, 3308 } end,
  GetRecipeInfo = function(id) return { name = id == 3307 and "Fondre le fer" or "Fondre l'or", learned = id == 3307, relativeDifficulty = 0 } end,
  GetRecipeSchematic = function(id) return { outputItemID = id == 3307 and 3575 or 3577, quantityMin = 1, quantityMax = 1,
    reagentSlotSchematics = { { reagents = { { itemID = id == 3307 and 2772 or 2776 } }, quantityRequired = 1, required = true } } } end,
}
cadre.onEvent(cadre, "TRADE_SKILL_LIST_UPDATE")
local repli = assert(lib:Lire("recettes connues"))
local minage = repli.persos[MOI].Minage
assert(minage.rank == 140 and minage.known[3307] == "optimal" and not minage.known[3308], "recettes connues du personnage connecté")
assert(repli.recettes[3307].output == 3575 and repli.recettes[3307].reagents[1].id == 2772, "recette lue")
assert(repli.recettes[3308], "recette pas encore apprise : lue aussi")
assert(lib:Lire("recettes connues", "tous").persos[MOI], "tous = le personnage connecté seulement")
local _, lotRepli = lib:Lire("recettes connues")
lotRepli = lotRepli.persos[MOI]
assert(lotRepli.provenance == "relevé direct" and lotRepli.build == 64000 and lotRepli.version == "1.16.1" and lotRepli.date, "lot du relevé de repli")
d, raison = lib:Lire("recettes connues", ALT)
assert(d == nil and raison == "pas de GameData", "un autre personnage sans GameData : " .. tostring(raison))
-- Inventaires sans GameData (Handshake#1) : le personnage connecté, ses sacs lus à l'instant et sa banque vue cette
-- session (relevée à l'ouverture, en mémoire ; fermée, elle n'est plus lue).
Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bank = -1, BankBag_1 = 5 } }
local CHARBON = "|cffffffff|Hitem:2772::::::::60:::::::|h[Minerai de fer]|h|r"
local slots = { [0] = { { itemID = 2772, stackCount = 5, hyperlink = CHARBON } }, [1] = {}, [-1] = { { itemID = 2840, stackCount = 7, hyperlink = "|Hitem:2840|h" }, false } }
C_Container = { GetContainerNumSlots = function(b) return slots[b] and #slots[b] or 0 end,
  GetContainerItemInfo = function(b, s) return slots[b][s] or nil end }
local inv = assert(lib:Lire("inventaires"))
assert(inv.persos[MOI].bags.Backpack.items[1].id == 2772 and inv.persos[MOI].bags.Backpack.items[1].count == 5, "sacs lus à l'instant")
assert(not inv.persos[MOI].bags.Bag_1 and not inv.persos[MOI].bags.Bank and not inv.persos[MOI].bank, "sac vide ignoré ; banque pas encore vue")
assert(lib.EstSac("Bag_1") and lib.EstSac("ReagentBag") and not lib.EstSac("Bank") and lib.EstBanque("BankBag_1"), "sacs et banque")
-- lib.Conteneurs rend aussi le lien de chaque objet (LibCommune#20 : seule lecture des sacs, GameData compris).
local sacs = lib.Conteneurs(lib.EstSac)
assert(sacs.Backpack.size == 1 and sacs.Backpack.items[1].link == CHARBON and sacs.Backpack.items[1].count == 5, "lien de l'objet")
assert(inv.persos[MOI].bags.Backpack.items[1].link == CHARBON, "lien aussi dans le relevé de repli des inventaires")
cadre.onEvent(cadre, "BANKFRAME_OPENED")
slots[-1][1] = { itemID = 2840, stackCount = 9, hyperlink = "|Hitem:2840|h" }
local banque = lib:Lire("inventaires", "tous").persos[MOI].bank
assert(banque.Bank.size == 2 and #banque.Bank.items == 1 and banque.Bank.items[1].count == 7, "banque relevée à l'ouverture")
cadre.onEvent(cadre, "PLAYERBANKSLOTS_CHANGED")
assert(lib:Lire("inventaires").persos[MOI].bank.Bank.items[1].count == 9, "banque ouverte : suivie")
cadre.onEvent(cadre, "BANKFRAME_CLOSED")
slots[-1] = {}
cadre.onEvent(cadre, "PLAYERBANKSLOTS_CHANGED")
local _, lotInv = lib:Lire("inventaires")
assert(lib:Lire("inventaires").persos[MOI].bank.Bank.items[1].count == 9, "banque fermée : la dernière vue reste")
assert(lotInv.persos[MOI].provenance == "relevé direct" and lotInv.persos[MOI].date, "lot des inventaires de repli")
d, raison = lib:Lire("inventaires", ALT)
assert(d == nil and raison == "pas de GameData", "inventaires d'un autre personnage sans GameData : " .. tostring(raison))
for k in pairs(_G) do assert(avant[k] or k == "Enum" or k == "C_TradeSkillUI" or k == "C_Container", "global écrit par la lib : " .. k) end
assert(HoteDB.reglages.x == 1 and next(HoteDB, next(HoteDB)) == nil, "SavedVariables de l'hôte intactes")
print("LibCommune : GameData absent, relevé de repli OK")

-- Fournisseurs des cours de l'HV (GameData#6, option B). Sans GameData, la lib passe directement par un fournisseur : une
-- fausse API d'Auctionator donne les prix, provenance « autre add-on ». Son âge 0 veut dire « vu aujourd'hui ».
time = os.time
local appels = {}
local PRIX, AGE = { [2772] = 95, [2840] = 40, [2841] = 300 }, { [2772] = 0, [2840] = 0, [2841] = 3 }
local function fausseAPI()
  return { API = { v1 = {
    GetAuctionPriceByItemID = function(appelant, id) appels[#appels + 1] = appelant return PRIX[id] end,
    GetAuctionAgeByItemID = function(appelant, id) appels[#appels + 1] = appelant return AGE[id] end } } }
end
Auctionator = fausseAPI()
local hv, lotHV = lib:Lire("cours de l'HV")
assert(hv and hv.objet(2772).min == 95 and hv.objet(2772).age == 0 and hv.objet(2772).sources.min == "Auctionator", "prix venus d'Auctionator")
assert(appels[1] == "LibCommune", "l'API d'Auctionator reçoit le nom de l'appelant")
local vieux = hv.objet(2841)
assert(vieux and vieux.min == nil and vieux.age == 3, "pas vu aujourd'hui (âge 3 j) : plus en vente, l'âge reste")
assert(hv.objet(1) == nil and hv.hv == nil and hv.depot == nil, "objet inconnu d'Auctionator ; rien de GameData")
assert(lotHV.provenance == "autre add-on" and lotHV.fournisseur == "Auctionator" and lotHV.champs.min == "Auctionator", "lot autre add-on")
assert(lotHV.build == nil and lotHV.releve == nil and not lotHV.fragile, "un autre add-on ne dit pas son build ; API publique : pas fragile")
local reste = lib:ChampsARelever("cours de l'HV")
assert(reste.min and reste.qty and reste.auctions and reste.tiers and reste.hist, "Auctionator là : GameData relève quand même tout")
-- Un fournisseur qui plante ne fait pas planter la lecture (ni ne prive des autres).
Auctionator.API.v1.GetAuctionPriceByItemID = function() error("Auctionator cassé") end
assert(lib:Lire("cours de l'HV").objet(2772) == nil, "fournisseur en erreur : ignoré")
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 95 end } } } -- sans l'âge : on ne sait pas s'il est du jour
assert(lib:Lire("cours de l'HV") == nil, "Auctionator sans GetAuctionAgeByItemID : pas fournisseur")
Auctionator = nil

-- TSM (API publique documentée, pas installé ici) : prix par TSM_API.GetCustomPriceValue("dbminbuyout", "i:<id>").
TSM_API = { GetCustomPriceValue = function(source, item) if source == "dbminbuyout" and item == "i:2772" then return 88 end end }
hv, lotHV = lib:Lire("cours de l'HV")
assert(hv.objet(2772).min == 88 and lotHV.fournisseur == "TSM", "prix venus de TSM")
TSM_API = nil

-- AuctionDB : pas d'API publique, ses SavedVariables (fragile). La maison de la faction la plus récemment scannée ; un
-- point qui n'est pas du dernier scan de la maison : plus en vente (min nil, quantité 0), l'historique reste.
local T = os.time() - 600 -- dernier scan d'AuctionDB il y a 10 min
AuctionDBForeverSaved = { houses = {
  ["na-forever-rp Alliance"] = { scans = { { T }, { T - 900 } }, items = {
    [2772] = ("%d,90,95,300 %d,0,0,10"):format(T - 900, T), [2840] = ("%d,41,45,800"):format(T),
    [44] = ("%d,20100,20100,1"):format(T - 900), [45] = ("%d,7,7,7"):format(T + 5) } },
  ["na-forever-pvp Alliance"] = { scans = { { 1000 } }, items = { [2772] = "1000,1,1,1" } },
  ["na-forever-rp Horde"] = { scans = { { T + 60 } }, items = { [2772] = ("%d,7,7,7"):format(T + 60) } } } }
hv, lotHV = lib:Lire("cours de l'HV")
local cuivre = hv.objet(2772)
assert(cuivre.min == nil and cuivre.qty == 10 and #cuivre.hist == 2 and cuivre.hist[1][2] == 90 and cuivre.hist[1][3] == 300, "AuctionDB : quantité et historique")
assert(hv.objet(2840).min == 41 and hv.objet(2840).qty == 800, "AuctionDB : prix du dernier scan")
local retire = hv.objet(44)
assert(retire.min == nil and retire.qty == 0 and #retire.hist == 1, "plus à l'HV au dernier scan : plus en vente, historique gardé")
assert(hv.objet(45).min == 7, "point d'un perso de confiance plus récent que le dernier scan : frais")
assert(lotHV.fournisseur == "AuctionDB" and lotHV.fragile and lotHV.champs.hist == "AuctionDB", "SavedVariables : marqué fragile")
-- Pas de copie du lourd : AuctionDB a scanné il y a moins de 6 h, GameData ne garde pas l'historique ; le reste, si.
reste = lib:ChampsARelever("cours de l'HV")
assert(not reste.hist and reste.min and reste.qty and reste.auctions and reste.tiers, "AuctionDB frais : tout sauf l'historique")
AuctionDBForeverSaved.houses["na-forever-rp Alliance"].scans = { { os.time() - 7 * 3600 } }
assert(lib:ChampsARelever("cours de l'HV").hist, "dernier scan d'AuctionDB il y a 7 h : GameData garde l'historique")
AuctionDBForeverSaved = { houses = "format changé" }
assert(lib:Lire("cours de l'HV") == nil, "format d'AuctionDB changé : plus de fournisseur, rien ne plante")

-- Sans GameData, Auctionator puis AuctionDB : prix d'Auctionator, quantité et historique d'AuctionDB.
Auctionator = fausseAPI()
local SV_ADB = { houses = { ["na-forever-rp Alliance"] = { scans = { { T } }, items = {
  [2772] = ("%d,90,95,300"):format(T), [2841] = ("%d,280,290,12"):format(T) } } } }
AuctionDBForeverSaved = SV_ADB
hv, lotHV = lib:Lire("cours de l'HV")
cuivre = hv.objet(2772)
assert(cuivre.min == 95 and cuivre.qty == 300 and cuivre.sources.min == "Auctionator" and cuivre.sources.qty == "AuctionDB", "Auctionator > AuctionDB")
assert(hv.objet(2841).min == 280 and hv.objet(2841).sources.min == "AuctionDB", "Auctionator pas du jour : le prix d'AuctionDB")
assert(lotHV.fournisseur == "Auctionator" and lotHV.champs.qty == "AuctionDB" and lotHV.fragile, "lot sans GameData")

-- Avec GameData : son dernier scan fait foi pour prix, quantité, annonces, paliers (relevé direct) ; un objet absent de ce
-- scan est plus en vente, même si Auctionator l'a vu aujourd'hui. L'historique : AuctionDB s'il est frais (pas de copie).
local lotGD = { provenance = "relevé direct", build = 64000, date = "2026-11-19 10:00:00" }
local marche = { items = { [2772] = { min = 100, qty = 5, auctions = 1, tiers = { { price = 100, qty = 5 } } } },
  hist = { [2840] = { { 1, 40, 3 } } }, time = T, scanned = "2026-11-19 10:00:00" }
GameDataAPI = { coursHV = function() return { hv = { ["Kerys-Alliance"] = marche }, depot = { rate24 = 0.3 } }, lotGD end }
lib.sondes["maison de l'HV"].valeur = nil
hv, lotHV = lib:Lire("cours de l'HV")
assert(lib.Sondes()["maison de l'HV"].valeur == "Kerys-Alliance", "la maison de l'HV des fournisseurs : celle de la lib, sondée")
cuivre = hv.objet(2772)
assert(cuivre.min == 100 and cuivre.qty == 5 and cuivre.auctions == 1 and cuivre.tiers[1].price == 100, "le scan de GameData fait foi")
assert(cuivre.sources.min == "GameData" and cuivre.sources.qty == "GameData" and cuivre.hist[1][1] == T and cuivre.sources.hist == "AuctionDB", "historique d'AuctionDB frais")
retire = hv.objet(2841)
assert(retire.min == nil and retire.qty == 0 and retire.sources.qty == "GameData" and #retire.hist == 1, "absent du scan de GameData : plus en vente")
assert(lotHV.provenance == "relevé direct" and lotHV.build == 64000 and lotHV.fournisseur == nil and lotHV.releve == lotGD, "lot : relevé direct")
assert(lotHV.champs.min == "GameData" and lotHV.champs.qty == "GameData" and lotHV.champs.hist == "AuctionDB" and lotHV.fragile, "d'où vient chaque champ")
assert(hv.depot.rate24 == 0.3 and hv.hv["Kerys-Alliance"], "dépôt et relevé de GameData")
assert(lotHV.scan.time == T and lotHV.scan.scanned == "2026-11-19 10:00:00" and lotHV.scan.items == nil, "lot : le dernier scan de ton HV (#13)")
-- AuctionDB plus frais (7 h) : son historique reste le bon (des jours de points ; GameData vient peut-être de recommencer
-- le sien, un seul point) ; celui de GameData seulement pour un objet qu'AuctionDB n'a pas. (Relecture de Negoce#1 : avec
-- l'historique de GameData d'abord, Mécréant passait de 97 affaires à 3 et les Alertes de 51 à 0 sur les vraies données.)
SV_ADB.houses["na-forever-rp Alliance"].scans = { { os.time() - 7 * 3600 } }
marche.hist[2772] = { { T + 3600, 100, 5 } } -- GameData vient de recommencer son historique : un seul point
hv, lotHV = lib:Lire("cours de l'HV")
assert(hv.objet(2772).sources.hist == "AuctionDB" and hv.objet(2772).hist[1][1] == T, "historique : AuctionDB même pas frais, avant le point unique de GameData")
assert(hv.objet(2840).sources.hist == "GameData", "historique de GameData pour un objet qu'AuctionDB n'a pas")
marche.hist[2772] = nil
assert(lotHV.champs.hist == "AuctionDB", "lot : historique d'AuctionDB")
-- GameData sans scan de cet HV : les fournisseurs seuls.
marche = nil
GameDataAPI.coursHV = function() return { hv = { ["Kerys-Horde"] = {} } }, lotGD end
hv, lotHV = lib:Lire("cours de l'HV")
assert(hv.objet(2772).min == 95 and lotHV.fournisseur == "Auctionator" and lotHV.scan == nil, "pas de scan de cet HV : fournisseurs")
-- HV neutre ou faction inconnue : rien ne plante.
local faction = UnitFactionGroup
UnitFactionGroup = function() return nil end
assert(pcall(lib.Lire, lib, "cours de l'HV") and pcall(lib.ChampsARelever, lib, "cours de l'HV"), "faction inconnue")
UnitFactionGroup = faction
-- Sans fournisseur, avec GameData : son relevé ; rien de relevé : « pas encore relevé ».
Auctionator, AuctionDBForeverSaved = nil, nil
GameDataAPI.coursHV = function() return { hv = { ["Kerys-Alliance"] = { items = { [2841] = { min = 500, qty = 4 } } } } }, lotGD end
hv, lotHV = lib:Lire("cours de l'HV")
assert(hv.objet(2841).min == 500 and lotHV.provenance == "relevé direct" and lotHV.champs.min == "GameData", "GameData seul")
reste = lib:ChampsARelever("cours de l'HV")
assert(reste.min and reste.qty and reste.auctions and reste.tiers and reste.hist, "sans fournisseur : GameData relève tout")
GameDataAPI.coursHV = function() end
local d, raison = lib:Lire("cours de l'HV")
assert(d == nil and raison == "pas encore relevé", "GameData sans relevé, sans fournisseur : " .. tostring(raison))
GameDataAPI = nil
print("LibCommune : fournisseurs des cours de l'HV OK")

-- Signal « type relevé à nouveau » (#14) : rappels par type ; avec GameData, son scan de l'HV (marketScanned), accroché
-- une seule fois, à l'enregistrement ou à la connexion s'il est chargé après ; un rappel qui plante ne prive pas les autres.
hooksecurefunc = function(t, nom, fn) local avant = t[nom]; t[nom] = function(...) avant(...); fn(...) end end
local erreurs, recus = {}, {}
geterrorhandler = function() return function(e) erreurs[#erreurs + 1] = e end end
assert(select(2, lib:QuandReleve("pas un type", print)) == "type inconnu", "type inconnu")
assert(lib:QuandReleve("cours de l'HV", function() error("rappel cassé") end))
assert(lib:QuandReleve("cours de l'HV", function(t) recus[#recus + 1] = t end))
assert(not lib.accrocheGameData, "sans GameData : rien à accrocher")
GameDataAPI = { marketScanned = noop, recettesConnues = function() return base end } -- GameData chargé après
lib.sondes.build.etat = nil
lib.cadre.onEvent(lib.cadre, "PLAYER_LOGIN")
assert(lib.Sondes().build.etat == "vert", "sondes relancées à la connexion")
GameDataAPI.marketScanned()
assert(#recus == 1 and recus[1] == "cours de l'HV" and #erreurs == 1, "scan de l'HV : rappels appelés, erreur rendue au jeu")
lib:QuandReleve("cours de l'HV", noop) -- accroché une seule fois
GameDataAPI.marketScanned()
assert(#recus == 2, "un seul crochet : " .. #recus)
lib.rappels["cours de l'HV"], GameDataAPI = nil, nil
print("LibCommune : signal « type relevé à nouveau » OK")

-- Deux copies de la lib (deux add-ons qui l'embarquent), mineures différentes : la plus récente sert, quel que soit
-- l'ordre de chargement, et elle reprend le relevé de repli de la précédente.
local source = assert(io.open("LibCommune/LibCommune.lua")):read("*a")
local mineure = tonumber(source:match('local MAJOR, MINOR = "LibCommune%-1%.0", (%d+)'))
local function copie(m, marque)
  local s = source:gsub('(local MAJOR, MINOR = "LibCommune%-1%.0", )%d+', "%1" .. m) .. ("\nlib.marque = %q\n"):format(marque)
  assert(loadstring(s))()
end
local premier = cadre.onEvent
copie(mineure + 1, "récente")
local recent = cadre.onEvent
copie(mineure - 1, "ancienne") -- chargée après, mais plus vieille : ignorée
local servie, m = LibStub("LibCommune-1.0")
assert(servie == lib and m == mineure + 1 and servie.marque == "récente", "la plus récente sert : " .. tostring(servie.marque))
assert(servie:Lire("recettes connues").persos[MOI].Minage.known[3307], "le relevé de repli survit à la mise à niveau")
assert(servie.Sondes().royaume.etat == "vert" and servie.Sondes().royaume.valeur == "Kerys", "les sondes de la session survivent aussi")
assert(servie.Sondes()["prix AuctionDB"] and servie.Sondes()[#servie.Sondes()].nom == "prix AuctionDB",
  "les sondes des autres fichiers (pas rechargés) restent déclarées, à leur place")
local noms = {}
for _, x in ipairs(servie.Sondes()) do assert(not noms[x.nom], "sonde en double : " .. x.nom); noms[x.nom] = true end
local nouveau = cadres[#cadres]
assert(nouveau == cadre and recent ~= premier and cadre.onEvent == recent, "un seul cadre d'événements, mené par la copie récente")
print("LibCommune : deux copies, la plus récente sert OK")

-- Recettes connues sans fenêtre de métier (IsPlayerSpell, interrogé à la connexion), sans GameData : un personnage
-- jamais passé par sa fenêtre. Candidates : les recettes déjà relevées (3307, 3308) et la réserve Classic de Handshake.
lib.repli.metiers = {}
local images = {}
C_Timer = { After = function(_, fn) images[#images + 1] = fn end } -- une image à la fois, pompée à la main
local function image() local fns = images; images = {}; for _, fn in ipairs(fns) do fn() end; return #fns end
local enCombat = false
InCombatLockdown = function() return enCombat end
GetProfessions = function() return 1, nil, nil, 2 end -- des trous, comme en jeu
GetProfessionInfo = function(i) if i == 1 then return "Minage", "icône", 150, 225 end return "Pêche", "icône", 1, 75 end
local connues, demandees, parImage = { [3307] = true, [9001] = true, [10100] = true }, {}, 0
IsPlayerSpell = function(id) demandees[id] = true; parImage = parImage + 1; return connues[id] or false end
HandshakeClassicRecipes = { [9001] = { 2840, 1, 1, "Minage", "Barre de cuivre", { 2770, 1 } },
  [9002] = { 4255, 1, 1, "Travail du cuir", "Armure verte en cuir", { 4234, 9 } } }
for id = 10000, 10149 do HandshakeClassicRecipes[id] = { 1, 1, 1, "Minage", "Recette " .. id, {} } end
local signaux = 0
lib:QuandReleve("recettes connues", function() signaux = signaux + 1 end)
cadre.onEvent(cadre, "PLAYER_LOGIN")
assert(#images == 1 and parImage == 0, "relevé différé après la connexion")
local nImages, maxParImage = 0, 0
repeat
  parImage = 0
  local n = image()
  if parImage > 0 then nImages, maxParImage = nImages + 1, math.max(maxParImage, parImage) end
  if nImages == 1 and not enCombat then -- combat après la 1re image : plus rien n'est interrogé
    enCombat, parImage = true, 0
    assert(image() == 1 and parImage == 0, "en combat : rien d'interrogé")
    assert(image() == 0, "en combat : relevé en pause, pas d'image en attente")
    enCombat = false
    cadre.onEvent(cadre, "PLAYER_REGEN_ENABLED") -- fin du combat : reprise, une image tout de suite
    assert(parImage > 0, "reprise après le combat")
    nImages, maxParImage = nImages + 1, math.max(maxParImage, parImage)
  end
until n == 0
assert(nImages >= 3 and maxParImage <= 60, ("étalé : %d images, %d au plus par image"):format(nImages, maxParImage))
assert(not demandees[9002], "un métier que le personnage n'a pas n'est pas interrogé")
local sans = assert(lib:Lire("recettes connues")).persos[MOI].Minage
assert(sans.rank == 150 and sans.max == 225, "rang et maximum du métier")
local n = 0 for _ in pairs(sans.known) do n = n + 1 end
assert(sans.known[3307] and sans.known[9001] and sans.known[10100] and n == 3, "recettes connues relevées sans fenêtre : " .. n)
assert(not lib:Lire("recettes connues").persos[MOI]["Pêche"], "aucune recette connue trouvée : métier pas inventé")
assert(signaux == 1, "relevé de repli sans fenêtre fini : signalé une fois")
print("LibCommune : recettes connues sans fenêtre OK")

-- Puis la fenêtre de métier s'ouvre (3307 apprise, 3308 non) : sa liste prime, sans doublon ni perte.
C_Timer.After = function(_, fn) fn() end
cadre.onEvent(cadre, "TRADE_SKILL_LIST_UPDATE")
local apres = lib:Lire("recettes connues").persos[MOI].Minage
n = 0 for _ in pairs(apres.known) do n = n + 1 end
assert(apres.known[3307] == "optimal" and not apres.known[3308] and apres.rank == 140, "la fenêtre prime")
assert(apres.known[9001] and apres.known[10100] and n == 3, "rien de perdu, rien en double : " .. n)
assert(signaux == 2, "relevé de repli en fenêtre : signalé")
lib.rappels["recettes connues"] = nil
-- Fenêtre déjà relevée, relevé sans fenêtre ensuite (ex. ouverte pendant le relevé) : rien d'écrasé.
lib:ReleverRecettesSansFenetre(lib.repli.metiers, lib.repli.recettes)
assert(lib.repli.metiers.Minage.known[3307] == "optimal", "la difficulté lue en fenêtre reste")
HandshakeClassicRecipes = nil
print("LibCommune : fenêtre après le relevé sans fenêtre OK")

---------------------------------------------------------------------------------------------------
-- Outils communs (Interface.lua, Capture.lua) : tri des tableaux, montants, noms d'objets, pages et grilles d'export.
assert(loadfile("LibCommune/Interface.lua"))()
assert(loadfile("LibCommune/Capture.lua"))()
local versions = { interface = lib.versions.interface, capture = lib.versions.capture }
lib.Argent = "marque"
assert(loadfile("LibCommune/Interface.lua"))() -- une 2e copie de même version (un autre add-on) : ignorée
assert(lib.Argent == "marque" and lib.versions.interface == versions.interface, "une copie pas plus récente n'écrase rien")
assert(loadfile("LibCommune/Interface.lua"))()
lib.versions.interface = 0
assert(loadfile("LibCommune/Interface.lua"))() -- la version chargée était plus vieille : la nouvelle la remplace
assert(type(lib.Argent) == "function" and lib.versions.interface == versions.interface, "une copie plus récente remplace")
print("LibCommune : outils, la plus récente sert OK")

-- Tri : par colonne, cases vides toujours en bas, égalités dans l'ordre d'arrivée.
local cols = { { key = "h", get = function(r) return r.h end }, { key = "n", get = function(r) return r.n end } }
local rows = { { n = "b", h = 5 }, { n = "a" }, { n = "c", h = 9 }, { n = "d", h = 5 } }
lib.TrierLignes(rows, cols, { key = "h", desc = true })
assert(rows[1].n == "c" and rows[2].n == "b" and rows[3].n == "d" and rows[4].n == "a", "décroissant, vide en bas")
lib.TrierLignes(rows, cols, { key = "h", desc = false })
assert(rows[1].n == "b" and rows[2].n == "d" and rows[3].n == "c" and rows[4].n == "a", "croissant, vide toujours en bas")
lib.TrierLignes(rows, cols, { key = "n", desc = false })
assert(rows[1].n == "a" and rows[4].n == "d")
assert(lib.TrierLignes(rows, cols, { key = "inconnue" })[1].n == "a", "colonne inconnue : ordre gardé")
print("LibCommune : tri des tableaux OK")

-- Montants : arrondis, version courte (pc oubliés au-delà d'1 po, pa au-delà de 100 po), signée.
GetCoinTextureString = function(c, taille) return c .. (taille and ("@" .. taille) or "") end
assert(lib.Argent(1234.6) == "1235" and lib.Argent(nil) == "?")
assert(lib.ArgentCourt(nil) == "–" and lib.ArgentCourt(0.2) == "0" and lib.ArgentCourt(9999) == "9999@10")
assert(lib.ArgentCourt(12345) == "12300@10" and lib.ArgentCourt(-1234567) == "1230000@10", "arrondis : " .. lib.ArgentCourt(12345))
assert(lib.ArgentSigne(150) == "|cff59cc73+150@10|r" and lib.ArgentSigne(-150) == "|cffe64d4d-150@10|r" and lib.ArgentSigne(nil) == "–")
C_CurrencyInfo = { GetCoinTextureString = function(c) return "moderne " .. c end }
assert(lib.Argent(5) == "moderne 5", "l'API moderne d'abord")
C_CurrencyInfo = nil
print("LibCommune : montants OK")

-- Noms d'objets : base de l'add-on, puis client, sinon demandé au serveur et retenu (dans garde) à son arrivée.
local client, demandesServeur = { [3] = { "Cuivre", "|lien3|" } }, {}
C_Item = { GetItemInfo = function(id) local i = client[id]; if i then return i[1], i[2] end end,
  RequestLoadItemDataByID = function(id) demandesServeur[#demandesServeur + 1] = id end }
local objets = { [1] = { name = "Barre de fer", link = "|lien1|" }, [2] = { name = "Toile de lin" } }
assert(lib.NomObjet(1, objets) == "|lien1|" and lib.NomObjet(2, objets) == "Toile de lin" and lib.NomObjet(3, objets) == "|lien3|")
assert(#demandesServeur == 0, "un objet connu n'est pas demandé")
local garde = {}
assert(lib.NomObjet(4, objets, garde) == "objet 4" and lib.NomObjet(4, objets, garde) == "objet 4")
assert(#demandesServeur == 1 and demandesServeur[1] == 4, "demandé une seule fois au serveur")
client[4] = { "Épice", "|lien4|" }
local cadreObjets = cadres[#cadres]
assert(cadreObjets == lib.cadreObjets, "écoute ITEM_DATA_LOAD_RESULT")
cadreObjets.onEvent(cadreObjets, "ITEM_DATA_LOAD_RESULT", 4, true)
assert(garde[4] and garde[4].link == "|lien4|" and lib.NomObjet(4, objets) == "|lien4|", "nom arrivé : retenu dans garde")
assert(select(2, lib.RetenirObjet(3, garde)) == "|lien3|" and garde[3].name == "Cuivre", "connu du client : retenu tout de suite")
local recettes = { [7] = { name = "Fonte du cuivre", output = 2840 } }
assert(lib.TrouverObjet("|Hitem:2589:0|h", objets) == 2589 and lib.TrouverObjet("42") == 42, "lien, ID")
assert(lib.TrouverObjet("barre DE fer", objets, recettes) == 1 and lib.TrouverObjet("fonte du cuivre", objets, recettes) == 2840)
assert(lib.TrouverObjet("rien", objets, recettes) == nil and lib.TrouverObjet("rien") == nil)
print("LibCommune : noms d'objets OK")

-- Export : pages (en-tête + morceau), grille de couleurs, et retour grille -> octets -> donnée, comme le décodeur.
local N = lib.EXPORT_N
local data = {}
for i = 1, lib.EXPORT_PAGE_BYTES * 2 + 77 do data[i] = string.char((i * 37 + math.floor(i / 7)) % 256) end
data = table.concat(data)
local pages = lib.PagesExport(data, 4242)
assert(#pages == 3 and pages[1]:sub(1, 4) == "BGP1", "3 pages")
local relu = {}
for p, page in ipairs(pages) do
  local g = lib.GrilleExport(page)
  assert(#g == N * N)
  for c = 0, N - 1 do assert(g[c + 1] == (c % 2 == 0 and 0 or 7), "damier de la ligne 0") end
  for c = 1, N - 2 do assert(g[(N - 1) * N + c + 1] == c % 8, "palette de la dernière ligne") end
  local bits, octets, acc, n = {}, {}, 0, 0
  for r = 1, N - 2 do for c = 1, N - 2 do bits[#bits + 1] = g[r * N + c + 1] end end
  for _, s in ipairs(bits) do
    acc, n = acc * 8 + s, n + 3
    if n >= 8 then n = n - 8; local d = 2 ^ n; octets[#octets + 1] = string.char(math.floor(acc / d)); acc = acc % d end
  end
  local b = table.concat(octets)
  local function u16(i) return b:byte(i) * 256 + b:byte(i + 1) end
  assert(b:sub(1, 4) == "BGP1" and u16(5) * 65536 + u16(7) == 4242 and u16(9) == p and u16(11) == #pages, "en-tête page " .. p)
  local chunk = b:sub(17, 16 + u16(13))
  local somme = 0
  for i = 1, #chunk do somme = (somme + chunk:byte(i)) % 65536 end
  assert(somme == u16(15), "somme de contrôle page " .. p)
  relu[p] = chunk
end
assert(table.concat(relu) == data, "aller-retour de l'export")
local trou = lib.JsonSur({ [0] = "a", [5] = { 1, 2 }, liste = { "x", "y" } })
assert(trou["0"] == "a" and trou["5"][2] == 2 and trou.liste[2] == "y", "clés numériques à trous en texte, listes gardées")
local boucle = {}
boucle.moi = boucle
assert(lib.JsonSur(boucle).moi == nil, "boucle coupée")
print("LibCommune : pages et grilles d'export OK")

---------------------------------------------------------------------------------------------------
-- Regroupement (Regroupement.lua, LibCommune#3) : un seul bouton de minicarte, une seule entrée des options, une
-- sous-page par add-on ; seul, un add-on n'a qu'un bouton et une entrée. Cadres factices : toute méthode existe.
local function regroupement()
  local etat = { boutons = {}, categories = {}, sous = {}, inscrites = 0, ouvertes = {}, menus = {} }
  local function cadre(nom)
    local f = { scripts = {}, points = {} }
    setmetatable(f, { __index = function() return noop end })
    f.SetScript = function(self, quoi, fn) self.scripts[quoi] = fn end
    f.SetPoint = function(self, ...) self.points = { ... } end
    f.CreateTexture = function() return cadre() end
    f.CreateFontString = function() local t = cadre(); t.SetText = function(s, x) s.texte = x end; return t end
    f.SetTexture = function(self, t) self.texture = t end
    if nom then _G[nom] = f end
    return f
  end
  CreateFrame = function(_, nom)
    local f = cadre(nom)
    if nom == "AzerothCommuneMinimapButton" then etat.boutons[#etat.boutons + 1] = f end
    return f
  end
  Minimap = cadre()
  Minimap.GetWidth = function() return 140 end
  Minimap.GetCenter = function() return 500, 500 end
  Minimap.GetEffectiveScale = function() return 1 end
  GameTooltip = cadre()
  local connecte = false
  IsLoggedIn = function() return connecte end
  C_AddOns = { GetAddOnMetadata = function(d, k) return k == "Notes" and ("notes de " .. d) or nil end }
  local id = 0
  local function categorie(page, nom) id = id + 1; return { page = page, nom = nom, GetID = function() return "cat" .. id end } end
  Settings = {
    RegisterCanvasLayoutCategory = function(page, nom) local c = categorie(page, nom); etat.categories[#etat.categories + 1] = c; return c end,
    RegisterAddOnCategory = function() etat.inscrites = etat.inscrites + 1 end,
    RegisterCanvasLayoutSubcategory = function(parent, page, nom)
      local c = categorie(page, nom); c.parent = parent; etat.sous[#etat.sous + 1] = c; return c
    end,
    OpenToCategory = function(i) etat.ouvertes[#etat.ouvertes + 1] = i end,
  }
  MenuUtil = { CreateContextMenu = function(_, gen)
    local m = {}
    local menu = { CreateTitle = function(_, t) m[#m + 1] = { titre = t } end, CreateDivider = noop,
      CreateButton = function(_, t, fn) m[#m + 1] = { t, fn } end }
    gen(nil, menu)
    etat.menus[#etat.menus + 1] = m
  end }
  for _, k in ipairs({ "regroupes", "boutonCommun", "categorie", "cadreRegroupement" }) do lib[k] = nil end
  lib.versions.regroupement = nil
  assert(loadfile("LibCommune/Regroupement.lua"))()
  local function connexion()
    connecte = true
    lib.cadreRegroupement.scripts.OnEvent(lib.cadreRegroupement, "PLAYER_LOGIN")
  end
  return etat, connexion
end

-- Deux add-ons (GameData puis Handshake, dans l'ordre de chargement) : rien avant l'entrée en jeu, puis un bouton,
-- une entrée « Azeroth Commune », deux sous-pages dans l'ordre d'arrivée.
GameDataDB, HandshakeDB = { minimap_angle = 90 }, {}
local ouverts = {}
local etat, connexion = regroupement()
local gd = { nom = "GameData", dossier = "GameData", icone = "icone-gd", ouvrir = function() ouverts[#ouverts + 1] = "gd" end,
  store = function() return GameDataDB end }
local reglagesFaits = 0
local hs = { nom = "Handshake", dossier = "Handshake", icone = "icone-hs", ouvrir = function() ouverts[#ouverts + 1] = "hs" end,
  store = function() return HandshakeDB end, reglages = function(page, ancre) reglagesFaits = reglagesFaits + 1; assert(page and ancre) end }
lib.Regrouper(gd)
lib.Regrouper(hs)
assert(#etat.boutons == 0 and #etat.categories == 0, "rien de construit avant l'entrée en jeu")
connexion()
assert(#etat.boutons == 1 and #etat.categories == 1 and etat.inscrites == 1, "un bouton, une entrée")
assert(etat.categories[1].nom == "Azeroth Commune", etat.categories[1].nom)
assert(#etat.sous == 2 and etat.sous[1].nom == "GameData" and etat.sous[2].nom == "Handshake", "une sous-page par add-on, dans l'ordre")
assert(etat.sous[1].parent == etat.categories[1] and gd.categorie == etat.sous[1], "sous Azeroth Commune")
assert(reglagesFaits == 1, "les réglages de l'add-on posés une fois sur sa page")
local bouton = etat.boutons[1]
assert(bouton.icone.texture ~= "icone-gd", "plusieurs add-ons : l'icône commune")
-- Position : l'angle d'avant (GameDataDB.minimap_angle = 90°) est gardé ; glisser l'écrit chez chaque add-on.
assert(math.abs(bouton.points[4]) < 1e-6 and math.abs(bouton.points[5] - 76) < 1e-6, "angle gardé : en haut de la carte")
GetCursorPosition = function() return 400, 500 end -- à gauche du centre : 180°
bouton.scripts.OnDragStart(bouton)
bouton.scripts.OnUpdate(bouton)
bouton.scripts.OnDragStop(bouton)
assert(GameDataDB.minimap_angle == 180 and HandshakeDB.minimap_angle == 180, "nouvel angle écrit chez chaque add-on")
assert(math.abs(bouton.points[4] + 76) < 1e-6, "bouton déplacé")
-- Clic : la liste des add-ons ; chaque ligne ouvre le sien ; clic droit : les réglages.
bouton.scripts.OnClick(bouton, "LeftButton")
local m = etat.menus[1]
assert(m and m[1].titre == "Azeroth Commune" and m[2][1]:find("GameData") and m[3][1]:find("Handshake") and m[4][1] == "Réglages", "menu")
m[3][2]()
assert(ouverts[1] == "hs", "la ligne Handshake ouvre Handshake")
bouton.scripts.OnClick(bouton, "RightButton")
assert(etat.ouvertes[1] == etat.categories[1]:GetID(), "clic droit : l'entrée Azeroth Commune")
-- Une 2e entrée en jeu (ou un add-on chargé plus tard) : toujours un bouton, une entrée ; le retardataire a sa sous-page.
connexion()
lib.Regrouper({ nom = "Négoce", ouvrir = noop })
assert(#etat.boutons == 1 and #etat.categories == 1 and etat.inscrites == 1 and #etat.sous == 3 and etat.sous[3].nom == "Négoce", "tard")
-- Une 2e copie du fichier, même version (un autre add-on qui embarque la lib) : ignorée.
local avantCopie = lib.Regrouper
assert(loadfile("LibCommune/Regroupement.lua"))()
assert(lib.Regrouper == avantCopie, "copie pas plus récente ignorée")
lib.versions.regroupement = 0 -- la copie chargée était plus vieille : la nouvelle la remplace et reprend bouton et entrée
assert(loadfile("LibCommune/Regroupement.lua"))()
connexion()
assert(lib.Regrouper ~= avantCopie and #lib.regroupes == 3 and #etat.boutons == 1 and #etat.categories == 1 and #etat.sous == 3, "reprise")
print("LibCommune : regroupement de plusieurs add-ons OK")

-- Un seul add-on : un bouton (son icône, le clic l'ouvre), une entrée qui est sa page, aucune sous-page.
etat, connexion = regroupement()
ouverts = {}
GameDataDB, gd.categorie = { minimap_angle = 90 }, nil
lib.Regrouper(gd)
connexion()
assert(#etat.boutons == 1 and #etat.categories == 1 and #etat.sous == 0, "un bouton, une entrée, rien de plus")
assert(etat.categories[1].nom == "Azeroth Commune" and gd.categorie == etat.categories[1], "l'entrée est la page de l'add-on")
bouton = etat.boutons[1]
assert(bouton.icone.texture == "icone-gd", "seul : son icône")
bouton.scripts.OnClick(bouton, "LeftButton")
assert(ouverts[1] == "gd" and #etat.menus == 0, "seul : le clic l'ouvre, sans menu")
print("LibCommune : un seul add-on OK")

-- Outils et exports déclarés par chaque add-on (LibCommune#21) : les outils sous la ligne de leur add-on dans le menu,
-- les exports de tous les add-ons regroupés par lib.Exports(), un retardataire compris.
etat, connexion = regroupement()
local ouvertsOutils, devant = {}, 0
local fenetreJournal = { shown = false, IsShown = function(s) return s.shown end, Raise = function() devant = devant + 1 end }
NegoceLedgerFrame = fenetreJournal
local gdx = { nom = "GameData", ouvrir = noop,
  exports = { { cle = "perso", libelle = "Mon perso", description = "fiche", donnees = function() return { a = 1 } end } } }
local neg = { nom = "Négoce", ouvrir = noop,
  outils = { { libelle = "Mécréant", ouvrir = function() ouvertsOutils[#ouvertsOutils + 1] = "mecreant" end },
             { libelle = "Journal", ouvrir = function() ouvertsOutils[#ouvertsOutils + 1] = "journal" end, fenetre = "NegoceLedgerFrame" } },
  exports = { { cle = "journal", libelle = "Journal", donnees = function() return { b = 2 } end } } }
lib.Regrouper(gdx)
lib.Regrouper(neg)
lib.Regrouper({ nom = "Handshake", ouvrir = noop })
connexion()
etat.boutons[1].scripts.OnClick(etat.boutons[1], "LeftButton")
m = etat.menus[1]
local lignes = {}
for i = 2, #m do lignes[#lignes + 1] = (m[i][1]:gsub("|T.-|t ", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
assert(table.concat(lignes, ",") == "GameData,Négoce,        Mécréant,        Journal,Handshake,Réglages", table.concat(lignes, ","))
m[4][2]()
assert(ouvertsOutils[1] == "mecreant", "la ligne Mécréant ouvre Mécréant")
m[5][2]()
assert(ouvertsOutils[2] == "journal" and devant == 0, "fenêtre fermée : l'outil s'ouvre")
fenetreJournal.shown = true
m[5][2]()
assert(#ouvertsOutils == 2 and devant == 1, "fenêtre déjà ouverte : elle passe devant, sans se refermer")
local ex = lib.Exports()
assert(#ex == 2 and ex[1].cle == "perso" and ex[1].addon == "GameData" and ex[1].libelle == "Mon perso" and ex[1].description == "fiche"
  and ex[1].donnees().a == 1, "export de GameData")
assert(ex[2].cle == "journal" and ex[2].addon == "Négoce" and ex[2].donnees().b == 2, "export du Négoce, après")
-- Regroupé après l'entrée en jeu : ses outils au prochain clic, ses exports dans la liste.
lib.Regrouper({ nom = "Tard", ouvrir = noop, outils = { { libelle = "Outil tardif", ouvrir = noop } },
  exports = { { cle = "tard", libelle = "Tard", donnees = function() return {} end } } })
etat.boutons[1].scripts.OnClick(etat.boutons[1], "LeftButton")
assert(etat.menus[2][#etat.menus[2] - 1][1]:find("Outil tardif", 1, true), "outil du retardataire dans le menu")
assert(lib.Exports()[3].cle == "tard", "export du retardataire")
-- Déclarations incomplètes : refusées tout de suite, pas au clic.
assert(not pcall(lib.Regrouper, { nom = "X", ouvrir = noop, outils = { { libelle = "sans ouvrir" } } }), "outil sans ouvrir")
assert(not pcall(lib.Regrouper, { nom = "X", ouvrir = noop, exports = { { cle = "x", libelle = "x" } } }), "export sans donnees")
-- Seul, un add-on avec des outils reste discret : le clic l'ouvre, sans menu.
etat, connexion = regroupement()
ouverts = {}
lib.Regrouper({ nom = "Seul", ouvrir = function() ouverts[#ouverts + 1] = "seul" end, outils = neg.outils })
connexion()
etat.boutons[1].scripts.OnClick(etat.boutons[1], "LeftButton")
assert(ouverts[1] == "seul" and #etat.menus == 0, "seul avec des outils : le clic l'ouvre")
NegoceLedgerFrame = nil
print("LibCommune : outils et exports des add-ons regroupés OK")

-- Prix d'achat (Negoce#14, LibCommune#27) : le moins cher entre marchand et HV, palier par palier ; règle reprise de Handshake.
local hvTest = {
  [3575] = { tiers = { { price = 300, qty = 10 }, { price = 310, qty = 30 } }, qty = 40 }, -- barres : deux paliers
  [2772] = { tiers = { { price = 100, qty = 5 } }, qty = 5 },                             -- minerai : pas assez
  [2880] = { min = 500, qty = 50 },                                                       -- fournisseur sans paliers
  [2770] = { min = 20 },                                                                  -- sans quantité connue
}
local marchandsTest = { [2880] = 100 }
local c, src, partiel = lib:PrixAchat(3575, 20, hvTest, marchandsTest)
assert(c == 10 * 300 + 10 * 310 and src == "HV" and partiel == false, "palier par palier : " .. tostring(c))
c, src, partiel = lib:PrixAchat(2772, 8, hvTest, marchandsTest)
assert(c == 8 * 100 and src == "HV" and partiel == true, "pas assez à l'HV : reste au dernier palier, partiel")
c, src = lib:PrixAchat(2880, 2, hvTest, marchandsTest)
assert(c == 200 and src == "marchand", "marchand moins cher que l'HV")
c, src, partiel = lib:PrixAchat(2770, 7, hvTest, marchandsTest)
assert(c == 140 and src == "HV" and partiel == false, "fournisseur sans paliers ni quantité : son prix pour tout")
assert(lib:PrixAchat(1, 3, hvTest, marchandsTest) == nil, "ni marchand ni HV : rien")
assert(lib:PrixAchat(9, 1, { [9] = { tiers = {} } }, {}) == nil, "paliers vides : rien, sans erreur")
-- Marchands lus par la lib : le moins cher à l'unité, hors stock limité et monnaies spéciales.
GameDataAPI = { marchands = function() return {
  [1] = { items = { { id = 2880, price = 600, stack = 5 }, { id = 159, price = 25 } } },
  [2] = { items = { { id = 2880, price = 100, limited = true }, { id = 159, price = 30 }, { id = 17, price = 10, cost_items = { 1 } } } },
} end }
local pm = lib:PrixMarchands()
assert(pm[2880] == 120 and pm[159] == 25 and pm[17] == nil, "prix marchands à l'unité")
-- Sans hv ni marchands passés : la lib lit elle-même (ici sans GameData, par Auctionator).
GameDataAPI = nil
Auctionator = fausseAPI()
c, src = lib:PrixAchat(2772, 3)
assert(c == 3 * 95 and src == "HV", "lu par la lib : " .. tostring(c))
print("LibCommune : prix d'achat OK")

-- Sondes des autres relevés (LibCommune#31) : sacs, recettes, noms d'objets, fournisseurs de prix. Une réponse de forme
-- inattendue met la sonde au rouge avec un seul avertissement, sans changer la valeur rendue ; un relevé en masse ne vérifie
-- que sa première ligne. Une sonde qui demande un contexte (fenêtre, fournisseur) reste « pas encore vue » sans lui.
do
  local dits, vraiPrint = {}, print
  print = function(m) dits[#dits + 1] = m end
  local function etat(nom) return lib.Sondes()[nom].etat end
  -- Rouge après deux relevés, avec un seul avertissement qui la nomme ; réarmée pour le cas suivant.
  local function rougeUneFois(nom, relever)
    lib.sondes[nom] = nil
    local avant = #dits
    relever(); relever()
    assert(etat(nom) == "rouge", nom .. " : rouge, " .. etat(nom))
    assert(#dits == avant + 1 and dits[#dits]:find(nom, 1, true), nom .. " : un seul avertissement, " .. (#dits - avant))
  end

  -- Sacs (sans contexte : relancés par RelancerSondes) : un nombre d'emplacements ; un objet a son ID et son lien.
  local LIEN = "|cffffffff|Hitem:2772::::::::60:::::::|h[Minerai de fer]|h|r"
  Enum = { BagIndex = { Backpack = 0, Bag_1 = 1 } }
  local sac = { [0] = { false, { itemID = 2772, stackCount = 5, hyperlink = LIEN } }, [1] = {} }
  local taille = function(b) return #sac[b] end
  C_Container = { GetContainerNumSlots = function(b) return taille(b) end, GetContainerItemInfo = function(b, s) return sac[b][s] or nil end }
  lib.sondes["emplacements d'un conteneur"], lib.sondes["objet d'un conteneur"] = nil, nil
  local relance = lib.RelancerSondes()
  assert(relance["emplacements d'un conteneur"].etat == "vert" and relance["objet d'un conteneur"].etat == "vert", "sacs relancés : verts")
  assert(relance["objet d'un conteneur"].valeur[1] == 2772 and relance["objet d'un conteneur"].valeur[2] == LIEN, "valeur : ID et lien")
  sac[0][2] = { itemID = 2772, stackCount = 5 } -- sans lien
  rougeUneFois("objet d'un conteneur", function() lib.Conteneurs(lib.EstSac) end)
  local lu = lib.Conteneurs(lib.EstSac).Backpack.items[1]
  assert(lu.id == 2772 and lu.count == 5 and lu.link == nil, "objet sans lien : rendu tel quel")
  sac[0][2] = { itemID = 2772, stackCount = 5, hyperlink = LIEN }
  taille = function() return nil end
  rougeUneFois("emplacements d'un conteneur", function() lib.Conteneurs(lib.EstSac) end)
  assert(next(lib.Conteneurs(lib.EstSac)) == nil, "pas de nombre d'emplacements : rien de lu, comme avant")
  taille = function(b) return #sac[b] end
  assert(lib.RelancerSondes()["emplacements d'un conteneur"].etat == "vert", "le nombre revient : verte")

  -- Recettes (fenêtre ouverte : pas relancées) : la fiche de la première recette lisible a un nom, un produit (sauf un
  -- enchantement) et des composants ; les lignes suivantes ne sont pas vérifiées.
  Enum = {}
  local fiches = {
    [3307] = { outputItemID = 3575, reagentSlotSchematics = { { reagents = { { itemID = 2772 } }, quantityRequired = 1 } } },
    [3308] = { outputItemID = 3577, reagentSlotSchematics = { { reagents = { { itemID = 2776 } }, quantityRequired = 1 } } },
  }
  C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionName = "Minage", skillLevel = 140, maxSkillLevel = 225 } end,
    GetAllRecipeIDs = function() return { 3307, 3308 } end,
    GetRecipeInfo = function(id) return { name = "Recette " .. id, learned = true, relativeDifficulty = 0, isEnchantingRecipe = id == 7 } end,
    GetRecipeSchematic = function(id) return fiches[id] end,
  }
  lib.sondes.recettes = nil
  assert(lib.RelancerSondes().recettes.etat == "pas encore vue", "recettes sans fenêtre : pas relancées, pas encore vues")
  assert(lib:ReleverRecettes() and etat("recettes") == "vert", "recettes : verte")
  fiches[3308] = { reagentSlotSchematics = {} } -- 2e ligne cassée : pas vérifiée
  assert(lib:ReleverRecettes() and etat("recettes") == "vert", "seule la première ligne est vérifiée")
  fiches[3307] = { reagentSlotSchematics = {} } -- ni produit ni composants
  rougeUneFois("recettes", function() lib:ReleverRecettes() end)
  local r = lib:ReleverRecettes()
  assert(r.recettes[3307] and r.recettes[3307].output == nil and #r.recettes[3307].reagents == 0 and r.total == 2, "recette rendue telle quelle")
  C_TradeSkillUI.GetAllRecipeIDs = function() return { 7 } end -- un enchantement : pas de produit, c'est attendu
  fiches[7] = { reagentSlotSchematics = { { reagents = { { itemID = 10940 } }, quantityRequired = 1 } } }
  assert(lib:ReleverRecettes() and etat("recettes") == "vert", "enchantement sans produit : verte")
  C_TradeSkillUI = nil

  -- Noms d'objets (un objet en cache : pas relancés) : le client rend son nom ; un objet pas encore en cache n'est pas vérifié.
  local client = { [3] = { "Cuivre", "|lien3|" } }
  C_Item = { GetItemInfo = function(id) local i = client[id]; if i then return i[1], i[2] end end, RequestLoadItemDataByID = noop }
  lib.sondes["nom d'objet"] = nil
  assert(lib.NomObjet(99) == "objet 99" and etat("nom d'objet") == "pas encore vue", "pas en cache : pas vérifié")
  assert(lib.NomObjet(3) == "|lien3|" and etat("nom d'objet") == "vert", "en cache : verte")
  client[5] = { "", "|lien5|" }
  rougeUneFois("nom d'objet", function() lib.NomObjet(5) end)
  assert(lib.NomObjet(5) == "|lien5|" and select(2, lib.RetenirObjet(5)) == "|lien5|", "nom vide : lien rendu tel quel")
  -- Le serveur dit l'avoir envoyé (ITEM_DATA_LOAD_RESULT réussi) et le client ne rend rien : rouge aussi.
  lib.RetenirObjet(6)
  rougeUneFois("nom d'objet", function() lib.cadreObjets.onEvent(lib.cadreObjets, "ITEM_DATA_LOAD_RESULT", 6, true) end)
  lib.sondes["nom d'objet"] = nil
  lib.RetenirObjet(8)
  lib.cadreObjets.onEvent(lib.cadreObjets, "ITEM_DATA_LOAD_RESULT", 8, false) -- objet inexistant : le serveur dit non
  assert(etat("nom d'objet") == "pas encore vue", "chargement refusé : pas vérifié")

  -- Fournisseurs de prix, quand ils sont présents : leur API rend un prix numérique ou rien ; la première ligne seulement.
  GameDataAPI, AuctionDBForeverSaved, TSM_API = nil, nil, nil
  for _, nom in ipairs({ "prix Auctionator", "prix TSM", "prix AuctionDB" }) do lib.sondes[nom] = nil end
  local avant = #dits
  Auctionator = fausseAPI()
  local hv = lib:Lire("cours de l'HV")
  assert(hv.objet(2772).min == 95 and etat("prix Auctionator") == "vert", "Auctionator : verte")
  for _, nom in ipairs({ "prix TSM", "prix AuctionDB" }) do
    assert(lib.RelancerSondes()[nom].etat == "pas encore vue", "fournisseur absent : pas encore vue, " .. nom)
  end
  assert(#dits == avant, "fournisseur absent : aucun avertissement")
  PRIX[2840] = "40" -- 2e ligne d'une lecture : pas vérifiée
  assert(hv.objet(2840).min == "40" and etat("prix Auctionator") == "vert", "seule la première ligne est vérifiée")
  rougeUneFois("prix Auctionator", function() lib:Lire("cours de l'HV").objet(2840) end)
  assert(lib:Lire("cours de l'HV").objet(2840).min == "40", "prix pas numérique : rendu tel quel")
  PRIX[2840], Auctionator = 40, nil
  TSM_API = { GetCustomPriceValue = function() return 88 end }
  assert(lib:Lire("cours de l'HV").objet(2772).min == 88 and etat("prix TSM") == "vert", "TSM : verte")
  TSM_API.GetCustomPriceValue = function() return { 88 } end
  rougeUneFois("prix TSM", function() lib:Lire("cours de l'HV").objet(2772) end)
  TSM_API = nil
  local maison = { scans = { { os.time() } }, items = { [2772] = ("%d,90,95,300"):format(os.time()), [2840] = 42 } }
  AuctionDBForeverSaved = { houses = { ["na-forever-rp Alliance"] = maison } }
  assert(lib:Lire("cours de l'HV").objet(2772).min == 90 and etat("prix AuctionDB") == "vert", "AuctionDB : verte")
  assert(lib:Lire("cours de l'HV").objet(1) == nil and etat("prix AuctionDB") == "vert", "objet absent d'AuctionDB : rien, verte")
  rougeUneFois("prix AuctionDB", function() lib:Lire("cours de l'HV").objet(2840) end)
  assert(lib:Lire("cours de l'HV").objet(2840) == nil, "point illisible : rien rendu, comme avant")
  AuctionDBForeverSaved = nil

  print = vraiPrint
end
print("LibCommune : sondes des sacs, recettes, noms d'objets et fournisseurs OK")
