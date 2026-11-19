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
local MOI = "Belegard Marteaudefer-Kerys"

assert(loadfile("LibCommune/LibStub.lua"))()
assert(loadfile("LibCommune/LibCommune.lua"))()
local lib = LibStub("LibCommune-1.0")

-- GameData présent : la lib lit sa base par GameDataAPI.recettesConnues, recettes connues de tous les personnages.
local base = {
  recettes = { [3307] = { profession = "Minage", name = "Fondre le fer", output = 3575 },
    [2662] = { profession = "Forge", name = "Cuirasse en cuivre", output = 2852 } },
  persos = {
    [MOI] = { Minage = { rank = 140, max = 225, known = { [3307] = "optimal" } } },
    ["Alt Dupont-Kerys"] = { Forge = { rank = 50, max = 75, known = { [2662] = "easy" } } },
  },
}
GameDataAPI = { recettesConnues = function() return base end }
local tous = assert(lib:Lire("recettes connues", "tous"))
assert(tous.persos[MOI].Minage.known[3307] and tous.persos["Alt Dupont-Kerys"].Forge.known[2662], "tous les personnages")
assert(tous.recettes[2662].output == 2852, "et les recettes vues")
local moi = assert(lib:Lire("recettes connues"))
assert(moi.persos[MOI] and not moi.persos["Alt Dupont-Kerys"], "sans personnage : le personnage connecté")
local alt = assert(lib:Lire("recettes connues", "Alt Dupont-Kerys"))
assert(alt.persos["Alt Dupont-Kerys"].Forge.rank == 50 and not alt.persos[MOI], "un personnage donné")
local d, raison = lib:Lire("recettes connues", "Inconnu-Kerys")
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
d, raison = lib:Demander("cours de la bourse")
assert(d == nil and raison == "type inconnu", tostring(raison))
print("LibCommune : type inconnu OK")

-- Catalogue : les types que GameData relève, chacun léger ou lourd, avec son accesseur dans GameDataAPI.
local attendus = { "inventaires", "réputations", "métiers et compétences", "quêtes terminées", "recettes connues",
  "maîtres de métier", "marchands", "prix des vols", "add-ons installés", "cours de l'HV", "objets" }
local nTypes = 0
for _ in pairs(lib.types) do nTypes = nTypes + 1 end
assert(nTypes == #attendus, "catalogue : " .. nTypes .. " types")
for _, nom in ipairs(attendus) do assert(lib.types[nom] and type(lib.types[nom].gamedata) == "string", "au catalogue : " .. nom) end
assert(not lib.types.objets.leger and not lib.types["cours de l'HV"].leger and lib.types.inventaires.leger, "lourds : HV et objets")
-- Demande avec GameData : transmise à GameDataAPI.demander (qui la retient pour le joueur), et gardée pour la session.
local transmis = {}
GameDataAPI.demander = function(t) transmis[#transmis + 1] = t end
for _, nom in ipairs(attendus) do assert(lib:Demander(nom), "demande : " .. nom) end
assert(#transmis == #attendus and transmis[1] == "inventaires", "chaque demande transmise à GameData")
assert(lib.demandes.objets and lib.demandes["recettes connues"], "et retenue pour la session")
-- Lecture d'un type par personnage autre que les recettes, et d'un type pour tout le joueur.
GameDataAPI.inventaires = function() return { persos = { [MOI] = { bags = { Backpack = { size = 16 } } }, ["Alt Dupont-Kerys"] = { bank = {} } } } end
local inv = assert(lib:Lire("inventaires"))
assert(inv.persos[MOI].bags.Backpack.size == 16 and not inv.persos["Alt Dupont-Kerys"], "inventaires du personnage connecté")
assert(lib:Lire("inventaires", "tous").persos["Alt Dupont-Kerys"], "inventaires de tous")
GameDataAPI.marchands = function() return { [1234] = { name = "Marchand", items = {} } } end
assert(assert(lib:Lire("marchands", "Alt Dupont-Kerys"))[1234].name == "Marchand", "marchands : une table pour le joueur")
GameDataAPI.marchands = function() return {} end
d, raison = lib:Lire("marchands")
assert(d == nil and raison == "pas encore relevé", "aucun marchand : " .. tostring(raison))
GameDataAPI.objets = function() return nil end
d, raison = lib:Lire("objets")
assert(d == nil and raison == "pas encore relevé", "objets absents : " .. tostring(raison))
lib.demandes = {}
print("LibCommune : catalogue et demandes avec GameData OK")

-- GameData absent : relevé de repli du personnage connecté, en mémoire ; rien n'est écrit chez l'hôte.
GameDataAPI = nil
HoteDB = { reglages = { x = 1 } } -- les SavedVariables de l'add-on hôte
local avant = {}
for k in pairs(_G) do avant[k] = true end
d, raison = lib:Lire("recettes connues")
assert(d == nil and raison == "pas encore relevé", "rien de relevé : " .. tostring(raison))
assert(lib:Demander("recettes connues"))
-- Sans GameData, pas de relevé de repli pour les autres types (lourds, ou pas encore écrits) ; la demande reste acceptée.
assert(lib:Demander("objets") and lib:Demander("inventaires"), "demande sans GameData")
for _, nom in ipairs({ "objets", "cours de l'HV", "inventaires", "marchands" }) do
  d, raison = lib:Lire(nom)
  assert(d == nil and raison == "pas de GameData", nom .. " sans GameData : " .. tostring(raison))
end
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
d, raison = lib:Lire("recettes connues", "Alt Dupont-Kerys")
assert(d == nil and raison == "pas de GameData", "un autre personnage sans GameData : " .. tostring(raison))
for k in pairs(_G) do assert(avant[k] or k == "Enum" or k == "C_TradeSkillUI", "global écrit par la lib : " .. k) end
assert(HoteDB.reglages.x == 1 and next(HoteDB, next(HoteDB)) == nil, "SavedVariables de l'hôte intactes")
print("LibCommune : GameData absent, relevé de repli OK")

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
print("LibCommune : recettes connues sans fenêtre OK")

-- Puis la fenêtre de métier s'ouvre (3307 apprise, 3308 non) : sa liste prime, sans doublon ni perte.
C_Timer.After = function(_, fn) fn() end
cadre.onEvent(cadre, "TRADE_SKILL_LIST_UPDATE")
local apres = lib:Lire("recettes connues").persos[MOI].Minage
n = 0 for _ in pairs(apres.known) do n = n + 1 end
assert(apres.known[3307] == "optimal" and not apres.known[3308] and apres.rank == 140, "la fenêtre prime")
assert(apres.known[9001] and apres.known[10100] and n == 3, "rien de perdu, rien en double : " .. n)
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
