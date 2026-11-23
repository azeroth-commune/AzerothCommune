-- Vérification hors jeu (non chargée par le TOC) : luajit AzerothCommune/check.lua, depuis le dossier des add-ons.
-- Juste assez de l'API WoW pour le socle. Deux parties : l'API publique (AzerothCommune.lua, Fournisseurs.lua, Interface.lua,
-- Capture.lua, Regroupement.lua), puis la base (Base.lua, Commerce.lua, Souscriptions.lua : l'ex-GameData).
-- Avec des dossiers en arguments (luajit AzerothCommune/check.lua Handshake Negoce BeAGoodPal/BeAGoodPal …), vérifie aussi
-- que leurs fichiers chargés n'appellent plus LibStub("LibCommune-1.0") ni GameDataAPI (ADR 0002).

-- Les fichiers .lua que charge la TOC d'un add-on (dossier/dossier.toc, la règle du jeu).
-- ponytail: lignes de la TOC seulement ; un .lua inclus par un .xml n'est pas vu (aucun de nos add-ons n'en a).
local function fichiersCharges(dossier)
  local toc = assert(io.open(dossier .. "/" .. dossier:match("[^/]+$") .. ".toc"), "pas de TOC : " .. dossier)
  local t = {}
  for ligne in toc:lines() do
    ligne = ligne:gsub("\r$", ""):match("^%s*(.-)%s*$")
    if ligne:match("%.lua$") and not ligne:match("^#") then t[#t + 1] = dossier .. "/" .. ligne:gsub("\\", "/") end
  end
  toc:close()
  return t
end
-- Rend la liste des « fichier : texte » trouvés tels quels dans le code (commentaires ôtés) des fichiers chargés de dossier (un
-- fichier absent est sauté : VendorData.lua, généré, peut manquer).
local function appelsInterdits(dossier, textes)
  local trouves = {}
  for _, f in ipairs(fichiersCharges(dossier)) do
    local h = io.open(f)
    if h then
      local code = h:read("*a"):gsub("%-%-[^\n]*", "")
      h:close()
      for _, m in ipairs(textes) do if code:find(m, 1, true) then trouves[#trouves + 1] = f .. " : " .. m end end
    end
  end
  return trouves
end
-- Le socle : ni LibStub, ni GameDataAPI, ni MINOR ou VERSION par fichier, ni les emplacements que Handshake remplissait.
-- Ni aucun global d'un consommateur (#48 : le socle porte lui-même la réserve des recettes, plus rien ne lui est remis) ; « Diagnostic » est aussi
-- le libellé d'un export du socle, pas cherché.
local interdits = appelsInterdits("AzerothCommune", { "LibStub", "GameDataAPI", "MINOR", "local VERSION", "lib.versions",
  "costCommand", "openCraftWindow", "SLASH_GAMEDATA", "GameDataDB", "GameDataItems", "GameDataMarket",
  "Handshake", "Negoce", "BeAGoodPal", "GameContext", "Compagnie" })
assert(#interdits == 0, "dans le socle : " .. table.concat(interdits, ", "))
assert(#fichiersCharges("AzerothCommune") == 11, "les fichiers des deux, dans une seule TOC (et la réserve des recettes, #48, le catalogue des objets, #52)")
local nos = {}
for _, dossier in ipairs(arg or {}) do
  for _, x in ipairs(appelsInterdits(dossier, { 'LibStub("LibCommune-1.0"', "GameDataAPI" })) do nos[#nos + 1] = x end
end
assert(#nos == 0, "encore la lib ou GameData dans nos add-ons : " .. table.concat(nos, ", "))
print("Azeroth Commune : ni LibStub ni GameDataAPI dans les fichiers chargés" .. (#(arg or {}) > 0 and (" (socle et " .. table.concat(arg, ", ") .. ")") or "") .. " OK")

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
GetRealmName, GetNormalizedRealmName = nil, nil -- le build 71037 les rend vides : le socle ne s'en sert plus (#35)
GetBuildInfo = function() return "1.16.1", "64000", "Nov 1 2026", 11601 end
date = os.date
-- Un personnage est identifié par son GUID (LibCommune#19) : persos est rangé par GUID.
-- Numéro de serveur 6942, celui de nos quatre personnages en jeu (21/11/2026).
local MOI, ALT = "Player-6942-0000BE1E", "Player-6942-00000A17"
UnitGUID = function(u) if u == "player" then return MOI end end

-- L'espace de noms privé de l'add-on (le 2e argument que le jeu passe à chaque fichier). Dans cette partie, la base n'est
-- pas chargée : fausseBase(lire, personnage) y pose ses accesseurs privés, ns.lire[type] (ceux de lire ; les autres ne
-- rendent rien : rien de relevé) et ns.personnage.
local ns = {}
local function charger(f) assert(loadfile("AzerothCommune/" .. f .. ".lua"))("AzerothCommune", ns) end
local function fausseBase(lire, personnage)
  ns.lire = setmetatable(lire or {}, { __index = function() return noop end })
  ns.personnage = personnage or noop
end
charger("AzerothCommune")
local cadre = cadres[#cadres] -- celui d'AzerothCommune.lua : connexion, fin du combat
charger("Fournisseurs")
local lib = AzerothCommune
UnitFactionGroup = function() return "Alliance" end
-- Sondes (#30), avant tout relevé : chacune « pas encore vue ».
local IDENTITE = { "royaume", "maison de l'HV", "GUID", "nom", "faction", "build" }
for _, nom in ipairs({ "emplacements d'un conteneur", "objet d'un conteneur", "recettes", "prix Auctionator",
  "prix TSM", "prix AuctionDB", unpack(IDENTITE) }) do
  assert(lib.Sondes()[nom] and lib.Sondes()[nom].etat == "pas encore vue", "jamais vérifiée : " .. nom)
end

-- AC:Lire passe par l'accesseur privé de la base (ns.lire["recettes connues"]), recettes connues de tous les personnages.
local base = {
  recettes = { [3307] = { profession = "Minage", name = "Fondre le fer", output = 3575 },
    [2662] = { profession = "Forge", name = "Cuirasse en cuivre", output = 2852 } },
  persos = {
    [MOI] = { Minage = { rank = 140, max = 225, known = { [3307] = "optimal" } } },
    [ALT] = { Forge = { rank = 50, max = 75, known = { [2662] = "easy" } } },
  },
}
fausseBase({ ["recettes connues"] = function() return base end })
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
ns.lire["recettes connues"] = function() return seules end
assert(lib:Lire("recettes connues", "tous").recettes[3307], "« tous » rend les recettes vues même sans perso")
ns.lire["recettes connues"] = function() return { recettes = {}, persos = {} } end
d, raison = lib:Lire("recettes connues", "tous")
assert(d == nil and raison == "pas encore relevé", "base vide : " .. tostring(raison))
print("Azeroth Commune : lecture par l'accesseur de la base OK")

-- Type absent du catalogue : indisponible, avec sa raison.
d, raison = lib:Lire("cours de la bourse")
assert(d == nil and raison == "type inconnu", tostring(raison))
d, raison = lib:Souscrire("cours de la bourse")
assert(d == nil and raison == "type inconnu", tostring(raison))
print("Azeroth Commune : type inconnu OK")

-- Souscription avant le chargement de la base (un add-on sans « ## Dependencies: AzerothCommune », #45) : refusée, pas
-- perdue en silence ; un seul avertissement par session, qui nomme l'add-on (sa pile) et rappelle la dépendance.
do
  local dits, vraiPrint = {}, print
  print = function(m) dits[#dits + 1] = m end
  debugstack = function() return '[string "@Interface/AddOns/Essai/Essai.lua"]:3: in main chunk\n' end
  d, raison = lib:Souscrire("inventaires")
  assert(d == nil and raison == "socle pas chargé", "trop tôt : " .. tostring(raison))
  assert(lib:Souscrire("objets") == nil and #dits == 1, "un seul avertissement par session : " .. #dits)
  assert(dits[1]:find("Essai", 1, true) and dits[1]:find("## Dependencies: AzerothCommune", 1, true), dits[1])
  print, debugstack = vraiPrint, nil
end
print("Azeroth Commune : souscription avant la base OK")

-- Personnage : GUID et nom « Prénom Nom », plus d'adresse (#35 : le jeu ne donne plus le royaume). Un chuchotement part
-- vers « Prénom Nom », la forme que le serveur accepte (au prénom seul : « Aucun joueur nommé 'Belegard' », 21/11/2026).
assert(lib.Destinataire("Belegard Marteaudefer") == "Belegard Marteaudefer", "chuchotement : le nom complet")
assert(lib.Destinataire("Belegard Marteaudefer-CAMWOWEU4Realm8PvP") == "Belegard Marteaudefer",
  "« -Royaume » retiré : Forever le lit comme un nom de famille")
assert(lib.Destinataire("Bob|cff") == "Bob|cff" and lib.Destinataire(nil) == nil, "illisible : tel quel")
local moiP = lib.Personnage()
assert(moiP.guid == MOI and moiP.nom == "Belegard Marteaudefer" and moiP.adresse == nil, "personnage connecté : GUID et nom")
assert(lib.Adresse == nil, "plus d'adresse « Prénom-Royaume » (dernier appelant parti avec Handshake#29)")
assert(lib.Personnage(MOI).nom == "Belegard Marteaudefer", "par son GUID")
assert(lib.Personnage(ALT) == nil, "autre GUID sans fiche dans la base : inconnu")
fausseBase(nil, function(g) if g == ALT then return { guid = ALT, nom = "Alt Dupont" } end end)
assert(lib.Personnage(ALT).nom == "Alt Dupont" and lib.Personnage("Player-6942-0000DEAD") == nil, "un personnage du joueur : la fiche de la base")
fausseBase()
print("Azeroth Commune : personnage OK")

-- Royaume (#35) : le numéro de serveur du GUID du personnage, « 6942 » ; maison de l'HV « 6942-Alliance ». Rien n'est
-- deviné : GetRealmName et GetNormalizedRealmName (vides depuis le build 71037) ne sont plus appelés.
assert(lib.Royaume() == "6942" and lib.Sondes().royaume.etat == "vert", "royaume : le numéro de serveur du GUID")
assert(lib.MaisonHV() == "6942-Alliance" and lib.Sondes()["maison de l'HV"].etat == "vert", "maison de l'HV")
assert(lib.RoyaumeNormalise == nil and lib.Sondes()["royaume normalisé"] == nil, "plus de royaume normalisé")
-- Sondes (#30) : un GUID au numéro 0 (ou pas de GUID) est une réponse inattendue. La sonde est rouge, avec la valeur
-- reçue et le build ; un seul avertissement par session ; la valeur rendue ne change pas (pas de refus, pas de secours).
local dits, vraiPrint = {}, print
print = function(m) dits[#dits + 1] = m end
local buildAvant = GetBuildInfo
GetBuildInfo = function() return "1.16.1", "71037", "Nov 21 2026", 11601 end
ns.buildLu = nil -- une mise à jour du jeu : le build de la session est relu
UnitGUID = function(u) if u == "player" then return "Player-0-0000BE1E" end end
assert(lib.Royaume() == "0", "valeur rendue inchangée : 0")
local s = lib.Sondes().royaume
assert(s.etat == "rouge" and s.valeur == "0" and s.build == "71037" and s.heure:match("^%d%d:%d%d:%d%d$"), "rouge, valeur et build")
assert(#dits == 1 and dits[1]:find("^Azeroth Commune : ") and dits[1]:find("royaume", 1, true) and dits[1]:find("71037"),
  "un avertissement qui nomme la sonde et le build : " .. tostring(dits[1]))
lib.Royaume()
assert(#dits == 1, "deux relevés de suite : un seul avertissement")
assert(lib.MaisonHV() == "0-Alliance" and lib.Sondes()["maison de l'HV"].etat == "rouge", "maison au numéro 0 : telle quelle, rouge")
UnitGUID = function() return nil end
assert(lib.Royaume() == nil and lib.Sondes().royaume.etat == "rouge", "sans GUID : pas de royaume, rouge")
assert(lib.MaisonHV() == nil, "sans royaume : pas de maison")
UnitGUID = function(u) if u == "player" then return MOI end end
assert(lib.Royaume() == "6942" and lib.Sondes().royaume.etat == "vert", "le GUID revient : verte")
assert(lib.Faction() == "Alliance" and lib.Build() == 71037 and lib.Personnage().guid == MOI, "faction, build, GUID")
for _, nom in ipairs({ "faction", "build", "GUID", "nom" }) do assert(lib.Sondes()[nom].etat == "vert", "verte : " .. nom) end
assert(lib.Sondes().nom.valeur[1] == "Belegard" and lib.Sondes().nom.valeur[2] == "Marteaudefer", "nom : les deux retours gardés")
UnitFactionGroup = function() return nil end
assert(lib.MaisonHV() == nil and lib.Sondes().faction.etat == "rouge", "faction inconnue : pas de maison, faction rouge")
UnitFactionGroup = function() return "Alliance" end
UnitName = function() return "Belegard" end
assert(lib.Personnage().nom == "Belegard" and lib.Sondes().nom.etat == "rouge", "sans nom de famille : rouge, nom inchangé")
UnitName = function() return "Belegard", "Marteaudefer" end
-- Relancer : les relevés sans contexte refaits, sans rien rendre de plus à l'appelant que l'état des sondes.
local etat = lib.RelancerSondes()
for _, nom in ipairs(IDENTITE) do assert(etat[nom].etat == "vert", "relancée verte : " .. nom .. " " .. tostring(etat[nom].valeur)) end
assert(#dits == 4, "un avertissement par sonde rouge (royaume, maison, faction, nom) : " .. #dits)
print = vraiPrint
GetBuildInfo = buildAvant
ns.buildLu = nil
print("Azeroth Commune : sondes, royaume vide OK")

-- Catalogue : les types que la base relève (leur accesseur privé : plus bas, avec la base).
local attendus = { "inventaires", "réputations", "métiers et compétences", "quêtes terminées", "recettes connues",
  "base des recettes", "maîtres de métier", "marchands", "prix des vols", "add-ons installés", "cours de l'HV", "objets" }
local nTypes = 0
for _ in pairs(lib.types) do nTypes = nTypes + 1 end
assert(nTypes == #attendus, "catalogue : " .. nTypes .. " types")
for _, nom in ipairs(attendus) do assert(lib.types[nom], "au catalogue : " .. nom) end
-- Souscription : transmise à ns.souscrire, qui la retient dans la base pour le joueur ; rien de gardé à côté (#41).
local transmis = {}
ns.souscrire = function(t) transmis[#transmis + 1] = t end
AzerothCommuneDB = {} -- la base chargée (ses SavedVariables lues)
for _, nom in ipairs(attendus) do assert(lib:Souscrire(nom), "souscription : " .. nom) end
AzerothCommuneDB = nil
assert(#transmis == #attendus and transmis[1] == "inventaires", "chaque souscription transmise à GameData")
assert(lib.souscriptions == nil, "pas de copie des souscriptions pour la session")
-- Lecture d'un type par personnage autre que les recettes, et d'un type pour tout le joueur.
ns.lire.inventaires = function() return { persos = { [MOI] = { bags = { Backpack = { size = 16 } } }, [ALT] = { bank = {} } } } end
local inv = assert(lib:Lire("inventaires"))
assert(inv.persos[MOI].bags.Backpack.size == 16 and not inv.persos[ALT], "inventaires du personnage connecté")
assert(lib:Lire("inventaires", "tous").persos[ALT], "inventaires de tous")
ns.lire.marchands = function() return { [1234] = { name = "Marchand", items = {} } } end
assert(assert(lib:Lire("marchands", ALT))[1234].name == "Marchand", "marchands : une table pour le joueur")
ns.lire.marchands = function() return {} end
d, raison = lib:Lire("marchands")
assert(d == nil and raison == "pas encore relevé", "aucun marchand : " .. tostring(raison))
ns.lire.objets = function() return nil end
d, raison = lib:Lire("objets")
assert(d == nil and raison == "pas encore relevé", "objets absents : " .. tostring(raison))
print("Azeroth Commune : catalogue et souscriptions OK")

-- Provenance (GameData#5) : lire un type rend son lot, provenance, build et date ; par personnage pour un type par perso.
local lotM = { provenance = "relevé direct", build = 64000, version = "1.16.1", date = "2026-11-19 10:00:00" }
ns.lire.marchands = function() return { [1234] = { items = {} } }, lotM end
local _, lot = lib:Lire("marchands")
assert(lot == lotM and lot.provenance == "relevé direct" and lot.build == 64000 and lot.date, "lot d'un type pour le joueur")
local lotA, lotB = { provenance = "relevé direct", build = 63000, perime = true }, { provenance = "relevé direct", build = 64000 }
ns.lire.inventaires = function()
  return { persos = { [MOI] = { bags = {} }, [ALT] = { bags = {} } } }, { persos = { [MOI] = lotB, [ALT] = lotA } }
end
_, lot = lib:Lire("inventaires")
assert(lot.persos[MOI] == lotB and lot.persos[ALT] == nil, "lot du personnage lu seulement")
_, lot = lib:Lire("inventaires", "tous")
assert(lot.persos[ALT].perime and lot.persos[ALT].build == 63000, "lots de tous, figé sous un autre build : peut-être périmé")
ns.lire.inventaires = function() return { persos = { [MOI] = {} } } end -- des données sans lot
d, lot = lib:Lire("inventaires")
assert(d and lot.persos[MOI] == nil, "sans lot fourni : les données quand même")
_, lot = lib:Lire("inventaires", "tous")
assert(type(lot.persos) == "table", "sans lot fourni, « tous » : lot.persos lisible quand même")
ns.lire.marchands = function() return { [1234] = { items = {} } } end
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
print("Azeroth Commune : provenance, build et date des lots OK")

-- Sacs lus à l'instant (lib.Conteneurs, seule lecture des sacs, la base comprise : LibCommune#20), avec le lien de chaque
-- objet ; un sac vide est ignoré.
Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bank = -1, BankBag_1 = 5 } }
local CHARBON = "|cffffffff|Hitem:2772::::::::60:::::::|h[Minerai de fer]|h|r"
local slots = { [0] = { { itemID = 2772, stackCount = 5, hyperlink = CHARBON } }, [1] = {}, [-1] = { { itemID = 2840, stackCount = 7, hyperlink = "|Hitem:2840|h" }, false } }
C_Container = { GetContainerNumSlots = function(b) return slots[b] and #slots[b] or 0 end,
  GetContainerItemInfo = function(b, s) return slots[b][s] or nil end }
local sacs = lib.Conteneurs(lib.EstSac)
assert(sacs.Backpack.size == 1 and sacs.Backpack.items[1].link == CHARBON and sacs.Backpack.items[1].count == 5, "lien de l'objet")
assert(not sacs.Bag_1 and not sacs.Bank, "sac vide ignoré ; la banque n'est pas un sac")
assert(lib.Conteneurs(lib.EstBanque).Bank.items[1].count == 7, "banque")
assert(lib.EstSac("Bag_1") and lib.EstSac("ReagentBag") and not lib.EstSac("Bank") and lib.EstBanque("BankBag_1"), "sacs et banque")
print("Azeroth Commune : sacs lus à l'instant OK")

-- Fournisseurs des cours de l'HV (GameData#6, option B). Sans scan du socle, la lib passe directement par un fournisseur :
-- une fausse API d'Auctionator donne les prix, provenance « autre add-on ». Son âge 0 veut dire « vu aujourd'hui ».
fausseBase() -- la base n'a pas scanné l'HV
d, raison = lib:Lire("cours de l'HV")
assert(d == nil and raison == "pas encore relevé", "ni scan ni fournisseur : " .. tostring(raison))
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
assert(appels[1] == "AzerothCommune", "l'API d'Auctionator reçoit le nom de l'appelant")
local vieux = hv.objet(2841)
assert(vieux and vieux.min == nil and vieux.age == 3, "pas vu aujourd'hui (âge 3 j) : plus en vente, l'âge reste")
assert(hv.objet(1) == nil and hv.hv == nil and hv.depot == nil, "objet inconnu d'Auctionator ; rien de la base")
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

-- Sans scan du socle, Auctionator puis AuctionDB : prix d'Auctionator, quantité et historique d'AuctionDB.
Auctionator = fausseAPI()
local SV_ADB = { houses = { ["na-forever-rp Alliance"] = { scans = { { T } }, items = {
  [2772] = ("%d,90,95,300"):format(T), [2841] = ("%d,280,290,12"):format(T) } } } }
AuctionDBForeverSaved = SV_ADB
hv, lotHV = lib:Lire("cours de l'HV")
cuivre = hv.objet(2772)
assert(cuivre.min == 95 and cuivre.qty == 300 and cuivre.sources.min == "Auctionator" and cuivre.sources.qty == "AuctionDB", "Auctionator > AuctionDB")
assert(hv.objet(2841).min == 280 and hv.objet(2841).sources.min == "AuctionDB", "Auctionator pas du jour : le prix d'AuctionDB")
assert(lotHV.fournisseur == "Auctionator" and lotHV.champs.qty == "AuctionDB" and lotHV.fragile, "lot sans scan du socle")

-- Avec GameData : son dernier scan fait foi pour prix, quantité, annonces, paliers (relevé direct) ; un objet absent de ce
-- scan est plus en vente, même si Auctionator l'a vu aujourd'hui. L'historique : AuctionDB s'il est frais (pas de copie).
local lotGD = { provenance = "relevé direct", build = 64000, date = "2026-11-19 10:00:00" }
local marche = { items = { [2772] = { min = 100, qty = 5, auctions = 1, tiers = { { price = 100, qty = 5 } } } },
  hist = { [2840] = { { 1, 40, 3 } } }, time = T, scanned = "2026-11-19 10:00:00" }
fausseBase({ ["cours de l'HV"] = function() return { hv = { ["6942-Alliance"] = marche }, depot = { rate24 = 0.3 } }, lotGD end })
ns.sondes["maison de l'HV"].valeur = nil
hv, lotHV = lib:Lire("cours de l'HV")
assert(lib.Sondes()["maison de l'HV"].valeur == "6942-Alliance", "la maison de l'HV des fournisseurs : celle de la lib, sondée")
cuivre = hv.objet(2772)
assert(cuivre.min == 100 and cuivre.qty == 5 and cuivre.auctions == 1 and cuivre.tiers[1].price == 100, "le scan de GameData fait foi")
assert(cuivre.sources.min == "GameData" and cuivre.sources.qty == "GameData" and cuivre.hist[1][1] == T and cuivre.sources.hist == "AuctionDB", "historique d'AuctionDB frais")
retire = hv.objet(2841)
assert(retire.min == nil and retire.qty == 0 and retire.sources.qty == "GameData" and #retire.hist == 1, "absent du scan de GameData : plus en vente")
assert(lotHV.provenance == "relevé direct" and lotHV.build == 64000 and lotHV.fournisseur == nil and lotHV.releve == lotGD, "lot : relevé direct")
assert(lotHV.champs.min == "GameData" and lotHV.champs.qty == "GameData" and lotHV.champs.hist == "AuctionDB" and lotHV.fragile, "d'où vient chaque champ")
assert(hv.depot.rate24 == 0.3 and hv.hv["6942-Alliance"], "dépôt et relevé de GameData")
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
ns.lire["cours de l'HV"] = function() return { hv = { ["6942-Horde"] = {} } }, lotGD end
hv, lotHV = lib:Lire("cours de l'HV")
assert(hv.objet(2772).min == 95 and lotHV.fournisseur == "Auctionator" and lotHV.scan == nil, "pas de scan de cet HV : fournisseurs")
-- HV neutre ou faction inconnue : rien ne plante.
local faction = UnitFactionGroup
UnitFactionGroup = function() return nil end
assert(pcall(lib.Lire, lib, "cours de l'HV") and pcall(lib.ChampsARelever, lib, "cours de l'HV"), "faction inconnue")
UnitFactionGroup = faction
-- Sans fournisseur, avec GameData : son relevé ; rien de relevé : « pas encore relevé ».
Auctionator, AuctionDBForeverSaved = nil, nil
ns.lire["cours de l'HV"] = function() return { hv = { ["6942-Alliance"] = { items = { [2841] = { min = 500, qty = 4 } } } } }, lotGD end
hv, lotHV = lib:Lire("cours de l'HV")
assert(hv.objet(2841).min == 500 and lotHV.provenance == "relevé direct" and lotHV.champs.min == "GameData", "GameData seul")
reste = lib:ChampsARelever("cours de l'HV")
assert(reste.min and reste.qty and reste.auctions and reste.tiers and reste.hist, "sans fournisseur : GameData relève tout")
ns.lire["cours de l'HV"] = function() end
d, raison = lib:Lire("cours de l'HV")
assert(d == nil and raison == "pas encore relevé", "GameData sans relevé, sans fournisseur : " .. tostring(raison))
fausseBase()
print("Azeroth Commune : fournisseurs des cours de l'HV OK")

-- Signal « type relevé à nouveau » (#14) : rappels par type, appelés par le relevé lui-même (le scan de l'HV : plus bas,
-- avec la base) ; un rappel qui plante ne prive pas les autres.
local erreurs, recus = {}, {}
geterrorhandler = function() return function(e) erreurs[#erreurs + 1] = e end end
assert(select(2, lib:QuandReleve("pas un type", print)) == "type inconnu", "type inconnu")
assert(lib:QuandReleve("cours de l'HV", function() error("rappel cassé") end))
assert(lib:QuandReleve("cours de l'HV", function(t) recus[#recus + 1] = t end))
ns.sondes.build.etat = nil
cadre.onEvent(cadre, "PLAYER_LOGIN")
assert(lib.Sondes().build.etat == "vert", "sondes relancées à la connexion")
lib:Signaler("cours de l'HV")
assert(#recus == 1 and recus[1] == "cours de l'HV" and #erreurs == 1, "rappels appelés, erreur rendue au jeu")
ns.rappels["cours de l'HV"] = nil
print("Azeroth Commune : signal « type relevé à nouveau » OK")

-- Recettes connues sans fenêtre de métier (IsPlayerSpell ; la base le lance à la connexion) : un personnage jamais passé
-- par sa fenêtre. Candidates : celles que la base lui passe (les recettes vues et la réserve, #48).
local metiers, vues = {}, { [3307] = { profession = "Minage" }, [3308] = { profession = "Minage" } }
local images = {}
C_Timer = { After = function(_, fn) images[#images + 1] = fn end } -- une image à la fois, pompée à la main
local function image() local fns = images; images = {}; for _, fn in ipairs(fns) do fn() end; return #fns end
local enCombat = false
InCombatLockdown = function() return enCombat end
GetProfessions = function() return 1, nil, nil, 2 end -- des trous, comme en jeu
GetProfessionInfo = function(i) if i == 1 then return "Minage", "icône", 150, 225 end return "Pêche", "icône", 1, 75 end
local connues, demandees, parImage = { [3307] = true, [9001] = true, [10100] = true }, {}, 0
IsPlayerSpell = function(id) demandees[id] = true; parImage = parImage + 1; return connues[id] or false end
-- Peu de candidates : relevées d'un coup (moins de 60), seulement elles.
local seul = {}
assert(lib:ReleverRecettesSansFenetre(seul, vues) and image() == 0, "peu de candidates : une seule image")
assert(seul.Minage.known[3307] and not demandees[9001] and not next(seul.Minage.known, next(seul.Minage.known)), "seulement les candidates")
demandees, parImage = {}, 0
-- Plus aucune remise par un add-on (#48 : le socle porte la réserve, il ne lit aucune donnée d'un consommateur).
assert(lib.RemettreRecettes == nil, "plus de remise des recettes")
local candidates = { [9001] = { profession = "Minage", name = "Barre de cuivre" }, [9002] = { profession = "Travail du cuir" } }
for id = 10000, 10149 do candidates[id] = { profession = "Minage" } end
for id, r in pairs(vues) do candidates[id] = r end
local finis = 0
assert(lib:ReleverRecettesSansFenetre(metiers, candidates, function() finis = finis + 1 end))
local nImages, maxParImage = 1, parImage
repeat
  parImage = 0
  local n = image()
  if parImage > 0 then nImages, maxParImage = nImages + 1, math.max(maxParImage, parImage) end
  if nImages == 2 and not enCombat then -- combat après la 2e image : plus rien n'est interrogé
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
local sans = metiers.Minage
assert(sans.rank == 150 and sans.max == 225, "rang et maximum du métier")
local n = 0 for _ in pairs(sans.known) do n = n + 1 end
assert(sans.known[3307] and sans.known[9001] and sans.known[10100] and n == 3, "recettes connues relevées sans fenêtre : " .. n)
assert(not metiers["Pêche"], "aucune recette connue trouvée : métier pas inventé")
assert(finis == 1, "fini une fois")
print("Azeroth Commune : recettes connues sans fenêtre OK")

-- Puis la fenêtre de métier s'ouvre (3307 apprise, 3308 non) : sa liste prime, sans doublon ni perte.
C_Timer.After = function(_, fn) fn() end
Enum = {}
C_TradeSkillUI = { -- fenêtre de métier ouverte : une recette apprise, une pas encore apprise
  GetBaseProfessionInfo = function() return { professionName = "Minage", skillLevel = 140, maxSkillLevel = 225 } end,
  GetAllRecipeIDs = function() return { 3307, 3308 } end,
  GetRecipeInfo = function(id) return { name = id == 3307 and "Fondre le fer" or "Fondre l'or", learned = id == 3307, relativeDifficulty = 0 } end,
  GetRecipeSchematic = function(id) return { outputItemID = id == 3307 and 3575 or 3577, quantityMin = 1, quantityMax = 1,
    reagentSlotSchematics = { { reagents = { { itemID = id == 3307 and 2772 or 2776 } }, quantityRequired = 1, required = true } } } end,
}
local fen = assert(lib:ReleverRecettes())
assert(fen.recettes[3307].output == 3575 and fen.recettes[3307].reagents[1].id == 2772 and fen.recettes[3308], "recettes lues, apprises ou non")
local apres = lib:RangerRecettes(metiers, fen)
n = 0 for _ in pairs(apres.known) do n = n + 1 end
assert(apres.known[3307] == "optimal" and not apres.known[3308] and apres.rank == 140, "la fenêtre prime")
assert(apres.known[9001] and apres.known[10100] and n == 3, "rien de perdu, rien en double : " .. n)
-- Fenêtre déjà relevée, relevé sans fenêtre ensuite (ex. ouverte pendant le relevé) : rien d'écrasé.
lib:ReleverRecettesSansFenetre(metiers, vues)
assert(metiers.Minage.known[3307] == "optimal", "la difficulté lue en fenêtre reste")
C_TradeSkillUI = nil
print("Azeroth Commune : fenêtre après le relevé sans fenêtre OK")

---------------------------------------------------------------------------------------------------
-- Outils communs (Interface.lua, Capture.lua) : tri des tableaux, montants, noms d'objets, pages et grilles d'export.
charger("Interface")
charger("Capture")

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
print("Azeroth Commune : tri des tableaux OK")

-- Montants : arrondis, version courte (pc oubliés au-delà d'1 po, pa au-delà de 100 po), signée.
GetCoinTextureString = function(c, taille) return c .. (taille and ("@" .. taille) or "") end
assert(lib.Argent(1234.6) == "1235" and lib.Argent(nil) == "?")
assert(lib.ArgentCourt(nil) == "–" and lib.ArgentCourt(0.2) == "0" and lib.ArgentCourt(9999) == "9999@10")
assert(lib.ArgentCourt(12345) == "12300@10" and lib.ArgentCourt(-1234567) == "1230000@10", "arrondis : " .. lib.ArgentCourt(12345))
assert(lib.ArgentSigne(150) == "|cff59cc73+150@10|r" and lib.ArgentSigne(-150) == "|cffe64d4d-150@10|r" and lib.ArgentSigne(nil) == "–")
C_CurrencyInfo = { GetCoinTextureString = function(c) return "moderne " .. c end }
assert(lib.Argent(5) == "moderne 5", "l'API moderne d'abord")
C_CurrencyInfo = nil
print("Azeroth Commune : montants OK")

-- Noms d'objets : base de l'add-on, puis client, sinon demandé au serveur et retenu (dans garde) à son arrivée.
local client, demandesServeur = { [3] = { "Cuivre", "|lien3|" } }, {}
C_Item = { GetItemInfo = function(id) local i = client[id]; if i then return i[1], i[2] end end,
  RequestLoadItemDataByID = function(id) demandesServeur[#demandesServeur + 1] = id end }
local objets = { [1] = { name = "Barre de fer", link = "|lien1|" }, [2] = { name = "Toile de lin" } }
assert(lib.NomObjet(1, objets) == "|lien1|" and lib.NomObjet(2, objets) == "Toile de lin" and lib.NomObjet(3, objets) == "|lien3|")
assert(#demandesServeur == 1 and demandesServeur[1] == 2,
  "un objet connu avec son lien n'est pas demandé ; connu par son seul nom (catalogue, #52), il l'est, pour avoir son lien")
local garde = {}
assert(lib.NomObjet(4, objets, garde) == "objet 4" and lib.NomObjet(4, objets, garde) == "objet 4")
assert(#demandesServeur == 2 and demandesServeur[2] == 4, "demandé une seule fois au serveur")
client[4] = { "Épice", "|lien4|" }
local cadreObjets = cadres[#cadres] -- le cadre privé d'Interface.lua, créé à la première demande au serveur
cadreObjets.onEvent(cadreObjets, "ITEM_DATA_LOAD_RESULT", 4, true)
assert(garde[4] and garde[4].link == "|lien4|" and lib.NomObjet(4, objets) == "|lien4|", "nom arrivé : retenu dans garde")
assert(select(2, lib.RetenirObjet(3, garde)) == "|lien3|" and garde[3].name == "Cuivre", "connu du client : retenu tout de suite")
local recettes = { [7] = { name = "Fonte du cuivre", output = 2840 } }
assert(lib.TrouverObjet("|Hitem:2589:0|h", objets) == 2589 and lib.TrouverObjet("42") == 42, "lien, ID")
assert(lib.TrouverObjet("barre DE fer", objets, recettes) == 1 and lib.TrouverObjet("fonte du cuivre", objets, recettes) == 2840)
assert(lib.TrouverObjet("rien", objets, recettes) == nil and lib.TrouverObjet("rien") == nil)
print("Azeroth Commune : noms d'objets OK")

-- Recherche d'objets (#49) : objets vus et objets fabriqués de la base des recettes, sans doublon ; fabricables d'abord,
-- puis ceux qui commencent par le texte, puis les noms courts, puis l'ID. L'index est refait au plus toutes les 5 s.
do
local horloge = 0
GetTime = function() return horloge end
ns.lire.objets = function() return { [1] = { name = "Barre de bronze" }, [2] = { name = "Bronze" },
  [3] = { name = "Lame en bronze" }, [4] = { name = "Fer" }, [5] = {} } end
ns.lire["base des recettes"] = function() return { [9] = { name = "Lame en bronze", output = 3 },
  [8] = { name = "Cuirasse changeante", output = 210794 } } end
local trouves = lib.ChercherObjets("  BRON ")
assert(#trouves == 3 and trouves[1].id == 3 and trouves[1].fabricable and trouves[2].id == 2 and trouves[3].id == 1
  and not trouves[2].fabricable, "ordre, sans doublon")
assert(trouves[1].name == "Lame en bronze", trouves[1].name)
local change = lib.ChercherObjets("chang")
assert(#change == 1 and change[1].id == 210794 and change[1].name == "Cuirasse changeante" and change[1].fabricable,
  "objet fabriqué jamais vu : trouvé par le nom de sa recette")
assert(#lib.ChercherObjets("b") == 0 and #lib.ChercherObjets(nil) == 0, "au moins 2 lettres")
assert(#lib.ChercherObjets("bron", 1) == 1 and lib.ChercherObjets("bron", 1)[1].id == 3, "en nombre limité")
local beaucoup = {}
for i = 1, 20 do beaucoup[100 + i] = { name = "Objet " .. i } end
ns.lire.objets = function() return beaucoup end
assert(#lib.ChercherObjets("objet") == 0, "index gardé moins de 5 s")
horloge = 5
assert(#lib.ChercherObjets("objet") == 8 and #lib.ChercherObjets("objet", 30) == 20, "8 par défaut")
ns.lire.objets, ns.lire["base des recettes"] = function() return nil end, function() return {} end
horloge = 10
assert(#lib.ChercherObjets("objet") == 0, "rien de relevé : rien")
GetTime = nil
end
print("Azeroth Commune : recherche d'objets OK")

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
print("Azeroth Commune : pages et grilles d'export OK")

---------------------------------------------------------------------------------------------------
-- Regroupement (Regroupement.lua, LibCommune#3) : un seul bouton de minicarte, une seule entrée des options, une
-- sous-page par add-on ; seul, un add-on n'a qu'un bouton et une entrée. Cadres factices : toute méthode existe.
local function regroupement()
  local etat = { boutons = {}, categories = {}, sous = {}, inscrites = 0, ouvertes = {}, menus = {} }
  local cadresR = {}
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
    cadresR[#cadresR + 1] = f
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
  local n = #cadresR
  charger("Regroupement")
  local cadreR = cadresR[n + 1] -- le cadre de Regroupement.lua, privé : le seul créé à son chargement
  local function connexion()
    connecte = true
    cadreR.scripts.OnEvent(cadreR, "PLAYER_LOGIN")
  end
  return etat, connexion
end

-- Deux add-ons (Compagnie puis Handshake, dans l'ordre de chargement) : rien avant l'entrée en jeu, puis un bouton,
-- une entrée « Azeroth Commune » (la page du socle), deux sous-pages dans l'ordre d'arrivée.
CompagnieDB, HandshakeDB = { minimap_angle = 90 }, {}
local ouverts = {}
ns.lignesSouscriptions = function() return { "inventaires : souscrit le 2026-11-21, relevé", "objets : aucune souscription" } end
local etat, connexion = regroupement()
local cp = { nom = "Compagnie", dossier = "Compagnie", icone = "icone-cp", ouvrir = function() ouverts[#ouverts + 1] = "cp" end,
  store = function() return CompagnieDB end }
local reglagesFaits = 0
local hs = { nom = "Handshake", dossier = "Handshake", icone = "icone-hs", ouvrir = function() ouverts[#ouverts + 1] = "hs" end,
  store = function() return HandshakeDB end, reglages = function(page, ancre) reglagesFaits = reglagesFaits + 1; assert(page and ancre) end }
lib.Regrouper(cp)
lib.Regrouper(hs)
assert(#etat.boutons == 0 and #etat.categories == 0, "rien de construit avant l'entrée en jeu")
connexion()
assert(#etat.boutons == 1 and #etat.categories == 1 and etat.inscrites == 1, "un bouton, une entrée")
assert(etat.categories[1].nom == "Azeroth Commune", etat.categories[1].nom)
assert(#etat.sous == 2 and etat.sous[1].nom == "Compagnie" and etat.sous[2].nom == "Handshake", "une sous-page par add-on, dans l'ordre")
assert(etat.sous[1].parent == etat.categories[1] and cp.categorie == etat.sous[1], "sous Azeroth Commune")
assert(reglagesFaits == 1, "les réglages de l'add-on posés une fois sur sa page")
-- La page du socle : les souscriptions et l'état des données relevées (ce que dit /ac souscriptions).
local texteSouscriptions = etat.categories[1].page.souscriptions.texte
assert(next(etat.categories[1].page.scripts) == nil, "page du socle : ni OnShow ni OnRefresh, aucun code à l'ouverture")
assert(texteSouscriptions == "inventaires : souscrit le 2026-11-21, relevé\nobjets : aucune souscription", tostring(texteSouscriptions))
local bouton = etat.boutons[1]
assert(bouton.icone.texture ~= "icone-cp", "plusieurs add-ons : l'icône commune")
-- Position : l'angle d'avant (CompagnieDB.minimap_angle = 90°) est gardé ; glisser l'écrit chez chaque add-on.
assert(math.abs(bouton.points[4]) < 1e-6 and math.abs(bouton.points[5] - 76) < 1e-6, "angle gardé : en haut de la carte")
GetCursorPosition = function() return 400, 500 end -- à gauche du centre : 180°
bouton.scripts.OnDragStart(bouton)
bouton.scripts.OnUpdate(bouton)
bouton.scripts.OnDragStop(bouton)
assert(CompagnieDB.minimap_angle == 180 and HandshakeDB.minimap_angle == 180, "nouvel angle écrit chez chaque add-on")
assert(math.abs(bouton.points[4] + 76) < 1e-6, "bouton déplacé")
-- Clic : la liste des add-ons, sans ligne pour le socle ; chaque ligne ouvre le sien ; clic droit : les réglages.
bouton.scripts.OnClick(bouton, "LeftButton")
local m = etat.menus[1]
assert(m and m[1].titre == "Azeroth Commune" and m[2][1]:find("Compagnie") and m[3][1]:find("Handshake") and m[4][1] == "Réglages" and #m == 4,
  "menu : les deux add-ons et les réglages, pas de ligne du socle")
m[3][2]()
assert(ouverts[1] == "hs", "la ligne Handshake ouvre Handshake")
bouton.scripts.OnClick(bouton, "RightButton")
assert(etat.ouvertes[1] == etat.categories[1]:GetID(), "clic droit : l'entrée Azeroth Commune")
-- Une 2e entrée en jeu (ou un add-on chargé plus tard) : toujours un bouton, une entrée ; le retardataire a sa sous-page.
connexion()
lib.Regrouper({ nom = "Négoce", ouvrir = noop })
assert(#etat.boutons == 1 and #etat.categories == 1 and etat.inscrites == 1 and #etat.sous == 3 and etat.sous[3].nom == "Négoce", "tard")
print("Azeroth Commune : regroupement de plusieurs add-ons OK")

-- Un seul add-on à côté du socle : un bouton (son icône, le clic l'ouvre), l'entrée du socle et sa sous-page.
etat, connexion = regroupement()
ouverts = {}
CompagnieDB, cp.categorie = { minimap_angle = 90 }, nil
lib.Regrouper(cp)
connexion()
assert(#etat.boutons == 1 and #etat.categories == 1 and #etat.sous == 1, "un bouton, l'entrée du socle, une sous-page")
assert(etat.categories[1].nom == "Azeroth Commune" and etat.categories[1].page.souscriptions and cp.categorie == etat.sous[1],
  "l'entrée est la page du socle, l'add-on a la sienne dessous")
bouton = etat.boutons[1]
assert(bouton.icone.texture == "icone-cp", "seul : son icône")
bouton.scripts.OnClick(bouton, "LeftButton")
assert(ouverts[1] == "cp" and #etat.menus == 0, "seul : le clic l'ouvre, sans menu")
print("Azeroth Commune : un seul add-on OK")

-- Le socle seul : pas de bouton (rien à ouvrir), mais sa page des options, avec les souscriptions.
etat, connexion = regroupement()
connexion()
assert(#etat.boutons == 0 and #etat.categories == 1 and etat.categories[1].page.souscriptions, "socle seul : sa page, pas de bouton")
ns.lignesSouscriptions = nil
print("Azeroth Commune : le socle seul OK")

-- Outils et exports déclarés par chaque add-on (LibCommune#21) : les outils sous la ligne de leur add-on dans le menu,
-- les exports du socle puis ceux de tous les add-ons regroupés par lib.Exports(), un retardataire compris.
etat, connexion = regroupement()
ns.exportsSocle = { { cle = "hv", libelle = "Hôtel des ventes", donnees = function() return { c = 3 } end } }
local ouvertsOutils, devant = {}, 0
local fenetreJournal = { shown = false, IsShown = function(s) return s.shown end, Raise = function() devant = devant + 1 end }
NegoceLedgerFrame = fenetreJournal
local gdx = { nom = "Compagnie", ouvrir = noop,
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
assert(table.concat(lignes, ",") == "Compagnie,Négoce,        Mécréant,        Journal,Handshake,Réglages", table.concat(lignes, ","))
m[4][2]()
assert(ouvertsOutils[1] == "mecreant", "la ligne Mécréant ouvre Mécréant")
m[5][2]()
assert(ouvertsOutils[2] == "journal" and devant == 0, "fenêtre fermée : l'outil s'ouvre")
fenetreJournal.shown = true
m[5][2]()
assert(#ouvertsOutils == 2 and devant == 1, "fenêtre déjà ouverte : elle passe devant, sans se refermer")
local ex = lib.Exports()
assert(#ex == 3 and ex[1].cle == "hv" and ex[1].addon == "Azeroth Commune" and ex[1].donnees().c == 3, "les exports du socle d'abord")
assert(ex[2].cle == "perso" and ex[2].addon == "Compagnie" and ex[2].libelle == "Mon perso" and ex[2].description == "fiche"
  and ex[2].donnees().a == 1, "export d'un add-on regroupé")
assert(ex[3].cle == "journal" and ex[3].addon == "Négoce" and ex[3].donnees().b == 2, "export du Négoce, après")
-- Regroupé après l'entrée en jeu : ses outils au prochain clic, ses exports dans la liste.
lib.Regrouper({ nom = "Tard", ouvrir = noop, outils = { { libelle = "Outil tardif", ouvrir = noop } },
  exports = { { cle = "tard", libelle = "Tard", donnees = function() return {} end } } })
etat.boutons[1].scripts.OnClick(etat.boutons[1], "LeftButton")
assert(etat.menus[2][#etat.menus[2] - 1][1]:find("Outil tardif", 1, true), "outil du retardataire dans le menu")
assert(lib.Exports()[4].cle == "tard", "export du retardataire")
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
NegoceLedgerFrame, ns.exportsSocle = nil, nil
print("Azeroth Commune : outils et exports des add-ons regroupés OK")

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
fausseBase({ marchands = function() return {
  [1] = { items = { { id = 2880, price = 600, stack = 5 }, { id = 159, price = 25 } } },
  [2] = { items = { { id = 2880, price = 100, limited = true }, { id = 159, price = 30 }, { id = 17, price = 10, cost_items = { 1 } } } },
} end })
local pm = lib:PrixMarchands()
assert(pm[2880] == 120 and pm[159] == 25 and pm[17] == nil, "prix marchands à l'unité")
-- Sans hv ni marchands passés : la lib lit elle-même (ici sans scan du socle, par Auctionator).
fausseBase()
Auctionator = fausseAPI()
c, src = lib:PrixAchat(2772, 3)
assert(c == 3 * 95 and src == "HV", "lu par la lib : " .. tostring(c))
print("Azeroth Commune : prix d'achat OK")

-- Sondes des autres relevés (LibCommune#31) : sacs, recettes, noms d'objets, fournisseurs de prix. Une réponse de forme
-- inattendue met la sonde au rouge avec un seul avertissement, sans changer la valeur rendue ; un relevé en masse ne vérifie
-- que sa première ligne. Une sonde qui demande un contexte (fenêtre, fournisseur) reste « pas encore vue » sans lui.
do
  local dits, vraiPrint = {}, print
  print = function(m) dits[#dits + 1] = m end
  local function etat(nom) return lib.Sondes()[nom].etat end
  -- Rouge après deux relevés, avec un seul avertissement qui la nomme ; réarmée pour le cas suivant.
  local function rougeUneFois(nom, relever)
    ns.sondes[nom] = nil
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
  ns.sondes["emplacements d'un conteneur"], ns.sondes["objet d'un conteneur"] = nil, nil
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
  ns.sondes.recettes = nil
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
  ns.sondes["nom d'objet"] = nil
  assert(lib.NomObjet(99) == "objet 99" and etat("nom d'objet") == "pas encore vue", "pas en cache : pas vérifié")
  assert(lib.NomObjet(3) == "|lien3|" and etat("nom d'objet") == "vert", "en cache : verte")
  client[5] = { "", "|lien5|" }
  rougeUneFois("nom d'objet", function() lib.NomObjet(5) end)
  assert(lib.NomObjet(5) == "|lien5|" and select(2, lib.RetenirObjet(5)) == "|lien5|", "nom vide : lien rendu tel quel")
  -- Le serveur dit l'avoir envoyé (ITEM_DATA_LOAD_RESULT réussi) et le client ne rend rien : rouge aussi.
  lib.RetenirObjet(6)
  rougeUneFois("nom d'objet", function() cadreObjets.onEvent(cadreObjets, "ITEM_DATA_LOAD_RESULT", 6, true) end)
  ns.sondes["nom d'objet"] = nil
  lib.RetenirObjet(8)
  cadreObjets.onEvent(cadreObjets, "ITEM_DATA_LOAD_RESULT", 8, false) -- objet inexistant : le serveur dit non
  assert(etat("nom d'objet") == "pas encore vue", "chargement refusé : pas vérifié")

  -- Fournisseurs de prix, quand ils sont présents : leur API rend un prix numérique ou rien ; la première ligne seulement.
  fausseBase()
  AuctionDBForeverSaved, TSM_API = nil, nil
  for _, nom in ipairs({ "prix Auctionator", "prix TSM", "prix AuctionDB" }) do ns.sondes[nom] = nil end
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

  -- La première ligne non nulle d'une lecture est vérifiée (#45) : une lecture qui commence par un objet sans prix ne
  -- passe pas au vert sans avoir vu le format ; deux lignes sans prix : « pas encore vue ».
  local function lecture(premier, second) local hv = lib:Lire("cours de l'HV"); hv.objet(premier); hv.objet(second) end
  local fournisseurs = {
    { "prix Auctionator", function() Auctionator = fausseAPI() end, function() Auctionator = nil end },
    { "prix TSM", function() TSM_API = { GetCustomPriceValue = function(_, i) return PRIX[tonumber(i:match("%d+"))] end } end,
      function() TSM_API = nil end },
    { "prix AuctionDB", function()
        local items = {}
        for id, p in pairs(PRIX) do items[id] = type(p) == "number" and ("%d,%d,1,1"):format(os.time(), p) or p end
        AuctionDBForeverSaved = { houses = { ["na-forever-rp Alliance"] = { scans = { { os.time() } }, items = items } } }
      end, function() AuctionDBForeverSaved = nil end },
  }
  for _, f in ipairs(fournisseurs) do
    local nom, poser, oter = f[1], f[2], f[3]
    PRIX[2840] = "40" -- mal formé
    poser()
    ns.sondes[nom] = nil
    lecture(1, 2)
    assert(etat(nom) == "pas encore vue", nom .. " : deux lignes sans prix, pas encore vue")
    lecture(1, 2840)
    assert(etat(nom) == "rouge", nom .. " : 1re ligne sans prix, 2e mal formée : rouge, " .. etat(nom))
    PRIX[2840] = 40
    oter()
  end

  print = vraiPrint
end
print("Azeroth Commune : sondes des sacs, recettes, noms d'objets et fournisseurs OK")

-- Le global ne porte que l'API publique et les champs documentés (#45) : cadres et états de session sont privés (ns ou
-- locaux), après un regroupement, des noms d'objets demandés au serveur, des sondes vérifiées et des rappels posés.
do
  local documentes = {}
  for nom in ([[Argent ArgentCourt ArgentSigne BoutonCapture Build Capturer ChampsARelever ChercherObjets Conteneurs DeclarerSonde
    Destinataire EXPORT_N EXPORT_PAGE_BYTES EstBanque EstSac Exporter Exports Faction Fenetre Fusionner GrilleExport JsonSur
    Lire LireParFournisseurs MaisonHV NomObjet PagesExport Personnage PrixAchat PrixMarchands QuandReleve RangerRecettes
    Regrouper RelancerSondes ReleverRecettes ReleverRecettesSansFenetre RetenirObjet Royaume Signaler Sonder Sondes
    Souscrire Tableau TrierLignes TrouverObjet fournisseurs provenances regroupes types captureDansLesFenetres]]):gmatch("%S+") do
    documentes[nom] = true
  end
  for k in pairs(lib) do assert(documentes[k], "sur le global, ni public ni documenté : " .. tostring(k)) end
end
print("Azeroth Commune : le global ne porte que l'API publique OK")

---------------------------------------------------------------------------------------------------
-- La base (l'ex-GameData : Base.lua, Commerce.lua, Souscriptions.lua), chargée avec le reste du socle dans un espace de
-- noms neuf. Simule juste ce qu'il faut de l'API WoW pour le filtre des conteneurs, le scan des objets, le commerce.
do
AzerothCommune = nil
Auctionator, TSM_API, AuctionDBForeverSaved, C_TradeSkillUI, Settings = nil, nil, nil, nil, nil
hooksecurefunc = function() error("crochet posé : le socle n'en pose aucun (#41)") end
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

-- Le socle dans l'ordre de sa TOC, jusqu'à Base.lua ; Commerce.lua et Souscriptions.lua plus bas.
local function charger(f, gns) assert(loadfile("AzerothCommune/" .. f .. ".lua"))("AzerothCommune", gns or ns) end
for _, f in ipairs({ "AzerothCommune", "Interface", "Capture", "Regroupement", "Fournisseurs", "Base" }) do charger(f) end
-- Un export du socle (AzerothCommune.Exports), par sa clé.
local function export(cle)
  for _, e in ipairs(AzerothCommune.Exports()) do if e.cle == cle then return e end end
end

AzerothCommuneItems, AzerothCommuneDB = {}, { lots = {} }
ns.itemsReady()
ns.itemTick()
local items = AzerothCommuneItems.items
assert(items[1] and items[2] and items[5] and not items[3], "catalogue local")
assert(items[1].name == "Casque" and items[1].price == 50, "objet en cache enregistré tout de suite")
assert(items[1].slot == "INVTYPE_HEAD" and items[1].class == 4)
assert(#requested == 2 and requested[1] == 2 and requested[2] == 5, "seuls les objets hors cache sont demandés")
assert(AzerothCommuneItems.next_id == 2001)

ns.itemLoaded(5, false)
assert(items[5].unknown, "inconnu du serveur : marqué pour ne pas redemander")
ns.itemTick() -- rien de neuf à demander
assert(#requested == 2)

-- Borne du balayage (#56) : posée à la connexion (itemsReady), quand le catalogue des objets est chargé ; son plus grand
-- ID et une marge de 5 000, sinon (repo cloné tel quel) 300 000, qui couvre Forever.
do
local avant = AzerothCommuneItems
local function balayerDepuis(id)
  AzerothCommuneItems = {}
  ns.itemsReady()
  AzerothCommuneItems.next_id = id
  ns.itemTick(); ns.itemTick()
  return AzerothCommuneItems.next_id
end
assert(balayerDepuis(299001) == 300001, "sans catalogue : jusqu'à 300 000, pas plus loin")
ns.catalogueObjets = { [7] = {}, [291005] = {} }
assert(balayerDepuis(295001) == 296006, "avec le catalogue : son plus grand ID (291 005) et 5 000 de marge")
ns.catalogueObjets = {}
assert(balayerDepuis(299001) == 300001, "catalogue vide : comme sans catalogue")
ns.catalogueObjets = nil
balayerDepuis(1)
AzerothCommuneItems = avant
end

-- Commerce : clés de recettes, et agrégation des enchères en prix unitaires et paliers.
charger("Commerce")
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
AzerothCommuneDB = { recipes = {}, errors = {}, chars = {}, lots = {} }
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
charger("Commerce")
local commerce = frames[#frames]
-- Rien n'est relevé sans souscription (Souscriptions.lua, testé plus bas) : ici, souscription à tous les types.
time = os.time
charger("Souscriptions")
for nom in pairs(ns.rangement) do ns.souscrire(nom) end
commerce.fn(commerce, "TRADE_SKILL_LIST_UPDATE")
local r = AzerothCommuneDB.recipes[3307]
assert(r and r.output == 3575 and r.reagents[1].id == 2772 and r.reagents[1].qty == 1, "recette lue")
assert(AzerothCommuneDB.recipes[3308] and AzerothCommuneDB.recipes[3308].output == 3577, "recette pas encore apprise : lue aussi")
assert(c.recipes.Minage.rank == 140 and c.recipes.Minage.known[3307] == "optimal" and not c.recipes.Minage.known[3308])
-- Ce que lit LibCommune (type « recettes connues ») : les recettes vues et, par perso, ses métiers.
AzerothCommuneDB.chars["Belegard-Test"], AzerothCommuneDB.chars["Sans-Metier"] = c, { errors = {} }
local rc = ns.lire["recettes connues"]()
assert(rc.recettes[3307].output == 3575 and rc.persos["Belegard-Test"].Minage.known[3307], "recettes connues pour la lib")
assert(rc.persos["Sans-Metier"] == nil, "un perso sans métier relevé n'apparaît pas")
assert(AzerothCommune:Lire("recettes connues", "Belegard-Test").persos["Belegard-Test"].Minage, "lu par la lib")
-- Base des recettes (#48, #54) : les recettes vues d'abord (3307 et 3308, relevé direct), la réserve extraite du client
-- (RecettesClassic.lua, générée, privée au socle : ns.recettesClassic, nom historique) pour les objets qu'aucune recette vue
-- ne fabrique, chaque ligne de la réserve marquée « extrait du client », avec les seuils jaune et gris du client. La
-- compétence requise, que la fenêtre ne donne pas, vient de la réserve.
ns.recettesClassic = {
  [3307] = { 3575, 1, 1, "Minage", "Fondre le fer", { 2772, 1 }, 125, 130, 140 },        -- vue aussi : la vue gagne
  [9003] = { 3577, 1, 1, "Minage", "Barre d'or (réserve)", { 2776, 1 }, 155, 160, 170 }, -- même objet que la vue 3308 : écartée
  [9002] = { 4255, 1, 2, "Travail du cuir", "Armure verte en cuir", { 4234, 9, 2321, 2 }, 175, 180, 200 },
}
ns.recettesClassicLot = { provenance = "extrait du client", build = 64000, version = "1.16.1.64000", date = "2026-11-21" }
local br, lotBr = AzerothCommune:Lire("base des recettes")
assert(br[3307].name == "Fondre le fer" and br[3307].provenance == nil and br[3307].level == 125, "recette vue, sa compétence requise de la réserve")
assert(AzerothCommuneDB.recipes[3307].level == nil, "la base des recettes vues n'est pas touchée")
assert(br[3308] and br[9003] == nil, "même objet qu'une recette vue : la réserve ne la double pas")
local cuir = br[9002]
assert(cuir and cuir.provenance == "extrait du client" and cuir.profession == "Travail du cuir" and cuir.output == 4255
  and cuir.made_min == 1 and cuir.made_max == 2 and cuir.level == 175 and cuir.reagents[2].id == 2321
  and cuir.reagents[2].qty == 2 and cuir.reagents[1].qty == 9, "recette de la réserve, dans la forme des recettes vues")
assert(cuir.yellow == 180 and cuir.grey == 200 and br[3307].yellow == 130 and br[3307].grey == 140,
  "seuils jaune et gris de la réserve, aussi pour une recette vue (Maîtrise en a besoin)")
assert(lotBr.provenance == "relevé direct", "lot mixte : la provenance la plus fiable")
-- #64 : chaque recette de la réserve porte sa source, la provenance de cette source, le prix du patron (nil sans) et son
-- temps de recharge (secondes) ; une recette vue que la réserve connaît les prend aussi. Un enchantement (sans objet
-- produit) entre dans la base sans casser l'index par objet.
assert(cuir.source == nil and cuir.cooldown == nil, "réserve d'avant #64 : pas de source")
ns.recettesClassic = {
  [3307] = { 3575, 1, 1, "Minage", "Fondre le fer", { 2772, 1 }, 125, 130, 140, "maître", "source externe", 0, 0 },
  [9002] = { 4255, 1, 2, "Travail du cuir", "Armure verte en cuir", { 4234, 9 }, 175, 180, 200, "patron vendu", "source externe", 12000, 0 },
  [18560] = { 14342, 1, 1, "Couture", "Etoffe lunaire", { 14256, 2 }, 250, 270, 300, "patron vendu", "source externe", 20000, 342000 },
  [13501] = { nil, 1, 1, "Enchantement", "Ench. de bracelets (Endurance inférieure)", { 11083, 1 }, 130, 155, 195, "maître", "source externe", 0, 0 },
  [9005] = { nil, 1, 1, "Enchantement", "Ench. de cape (réserve)", { 11083, 2 }, 70, 90, 130, "inconnue", "source externe", 0, 0 },
}
br = AzerothCommune:Lire("base des recettes")
assert(br[9002].source == "patron vendu" and br[9002].source_provenance == "source externe" and br[9002].pattern_price == 12000
  and br[9002].cooldown == 0, "patron vendu, son prix, sans recharge")
assert(br[18560].cooldown == 342000, "recharge de l'étoffe lunaire : 95 h")
assert(br[3307].source == "maître" and br[3307].pattern_price == nil and br[3307].level == 125 and br[3307].provenance == nil,
  "recette vue : la source de la réserve, sans prix de patron")
local ench = br[13501]
assert(ench and ench.output == nil and ench.reagents[1].id == 11083 and ench.level == 130 and ench.yellow == 155
  and ench.source == "maître", "enchantement : sans objet produit, avec composants, seuils et source")
assert(br[9005], "deux enchantements : l'un ne cache pas l'autre")
assert(AzerothCommune.TrouverObjet("Ench. de bracelets (Endurance inférieure)", {}, br) == nil
  and AzerothCommune.TrouverObjet("Etoffe lunaire", {}, br) == 14342, "un enchantement n'est pas un objet")
-- #67 : la condition d'accès de la réserve (14e champ : spécialisation, réputation, plus enseignée) est exposée, sur une recette
-- de la réserve et sur une recette vue ; absente (nil) sinon.
ns.recettesClassic = {
  [3307] = { 3575, 1, 1, "Minage", "Fondre le fer", { 2772, 1 }, 125, 130, 140, "maître", "source externe", 0, 0 },
  [19053] = { 15074, 1, 1, "Travail du cuir", "Gants chimériques", { 8170, 6 }, 260, 260, 280, "patron vendu", "source externe", 12000, 0,
    "spécialisation : travail du cuir tribal" },
  [18560] = { 14342, 1, 1, "Couture", "Etoffe lunaire", { 14256, 2 }, 250, 270, 300, "patron vendu", "source externe", 20000, 342000, "réputation : Aube d'argent" },
}
AzerothCommuneDB.recipes[3307].condition = nil
br = AzerothCommune:Lire("base des recettes")
assert(br[19053].condition == "spécialisation : travail du cuir tribal" and br[18560].condition == "réputation : Aube d'argent"
  and br[3307].condition == nil, "condition de la réserve exposée, nil sans")
ns.recettesClassic = { [3307] = { 3575, 1, 1, "Minage", "Fondre le fer", { 2772, 1 }, 125, 130, 140, "retirée", "extrait du client", 0, 0, "plus enseignée" } }
br = AzerothCommune:Lire("base des recettes")
assert(br[3307].condition == "plus enseignée" and br[3307].name == "Fondre le fer" and AzerothCommuneDB.recipes[3307].condition == nil,
  "une recette vue en prend la condition, sur une copie")
-- Maitrise#15 : l'objet patron de la réserve (15e champ, nil entre condition et patron quand la recette n'a pas de condition) est
-- exposé sur une recette de la réserve et, sur une copie, sur une recette vue ; nil sans.
ns.recettesClassic = {
  [3307] = { 3575, 1, 1, "Minage", "Fondre le fer", { 2772, 1 }, 125, 130, 140, "maître", "source externe", 0, 0 },
  [2158] = { 2307, 1, 1, "Travail du cuir", "Bottes élégantes en cuir", { 2318, 7, 2320, 2 }, 90, 95, 125, "inconnue", "source externe", 0, 0, nil, 2406 },
  [19053] = { 15074, 1, 1, "Travail du cuir", "Gants chimériques", { 8170, 6 }, 260, 260, 280, "patron vendu", "source externe", 12000, 0,
    "spécialisation : travail du cuir tribal", 15750 },
}
local vue3307 = AzerothCommuneDB.recipes[3307] -- la recette vue des tests suivants : rendue telle quelle à la fin
AzerothCommuneDB.recipes[3307].patron = nil
br = AzerothCommune:Lire("base des recettes")
assert(br[2158].patron == 2406 and br[2158].condition == nil and br[19053].patron == 15750 and br[19053].condition ~= nil
  and br[3307].patron == nil, "patron de la réserve exposé, nil sans")
AzerothCommuneDB.recipes[3307] = nil
AzerothCommuneDB.recipes[2158] = { profession = "Travail du cuir", name = "Bottes élégantes en cuir", output = 2307, reagents = {} }
br = AzerothCommune:Lire("base des recettes")
assert(br[2158].patron == 2406 and AzerothCommuneDB.recipes[2158].patron == nil, "une recette vue en prend le patron, sur une copie")
AzerothCommuneDB.recipes[2158] = nil
AzerothCommuneDB.recipes[3307] = vue3307
-- #80 : les marchands du patron (16e champ, liste plate { PNJ, prix, … } ; nil à la place de la condition et du patron absents),
-- joints à la table des PNJ de la réserve (ns.recettesPNJ : nom, carte, x, y, faction) ; prix 0 : inconnu (nil) ; un PNJ hors de
-- la table garde son ID. Nil sans marchand, et copiés sur une recette vue. Les maîtres d'un métier : AC.MaitresDuMetier.
do
ns.recettesPNJ = { [254151] = { "Vayn Moongaze", 2521, 63.8, 36 }, [5] = { "Marchand", 1429, 41.8, 67, "Alliance" },
  [7] = { "Maître", nil, nil, nil, "Horde" } }
ns.recettesMaitres = { Forge = { 7, 5 } }
ns.recettesClassic = {
  [3307] = { 3575, 1, 1, "Minage", "Fondre le fer", { 2772, 1 }, 125, 130, 140, "maître", "source externe", 0, 0 },
  [1301421] = { 276992, 1, 1, "Forge", "Cotte de mailles forge-ciel nuageuse", { 2840, 8 }, 60, 65, 70, "patron vendu", "source externe",
    1250, 0, nil, nil, { 254151, 0 } },
  [2158] = { 2307, 1, 1, "Travail du cuir", "Bottes élégantes en cuir", { 2318, 7 }, 90, 95, 125, "patron vendu", "source externe", 500, 0,
    nil, 2406, { 5, 450, 6, 0 } },
}
br = AzerothCommune:Lire("base des recettes")
local vayn = br[1301421].marchands
assert(#vayn == 1 and vayn[1].pnj == 254151 and vayn[1].nom == "Vayn Moongaze" and vayn[1].prix == nil and vayn[1].carte == 2521
  and vayn[1].x == 63.8 and vayn[1].y == 36 and vayn[1].faction == nil and br[1301421].source == "patron vendu"
  and br[1301421].source_provenance == "source externe" and br[1301421].patron == nil and br[1301421].pattern_price == 1250,
  "patron de Forever lié à la prise : son marchand, sa position, prix inconnu, provenance source externe")
local bottes = br[2158].marchands
assert(#bottes == 2 and bottes[1].prix == 450 and bottes[1].faction == "Alliance" and bottes[1].carte == 1429 and br[2158].patron == 2406
  and bottes[2].pnj == 6 and bottes[2].nom == nil and bottes[2].carte == nil and bottes[2].prix == nil, "deux marchands, un hors de la table des PNJ")
assert(br[3307].marchands == nil, "aucun marchand connu : nil")
AzerothCommuneDB.recipes[3307] = nil
AzerothCommuneDB.recipes[2158] = { profession = "Travail du cuir", name = "Bottes élégantes en cuir", output = 2307, reagents = {} }
br = AzerothCommune:Lire("base des recettes")
assert(br[2158].marchands[1].pnj == 5 and AzerothCommuneDB.recipes[2158].marchands == nil, "une recette vue en prend les marchands, sur une copie")
AzerothCommuneDB.recipes[2158] = nil
AzerothCommuneDB.recipes[3307] = vue3307
local forge = AzerothCommune.MaitresDuMetier("Forge")
assert(#forge == 2 and forge[1].pnj == 7 and forge[1].nom == "Maître" and forge[1].faction == "Horde" and forge[1].carte == nil
  and forge[2].pnj == 5 and forge[2].carte == 1429 and forge[2].x == 41.8 and forge[2].y == 67, "maîtres de la Forge, dans l'ordre, avec position")
forge[1].nom = "touché"
assert(AzerothCommune.MaitresDuMetier("Forge")[1].nom == "Maître" and AzerothCommune.MaitresDuMetier("Pêche") == nil, "copies ; métier inconnu : nil")
ns.recettesPNJ, ns.recettesMaitres = nil, nil
assert(AzerothCommune.MaitresDuMetier("Forge") == nil, "sans réserve : nil")
end
-- #72 : le relevé des maîtres de métier passe devant la réserve et la copie d'une recette vue. Bouchon : trois recettes de
-- la réserve (patron vendu, ajout de Forever « inconnue », jamais vue chez un maître) et une recette vue (3307).
ns.recettesClassic = {
  [3307] = { 3575, 1, 1, "Minage", "Fondre le fer", { 2772, 1 }, 125, 130, 140, "retirée", "extrait du client", 0, 0, "plus enseignée" },
  [9002] = { 4255, 1, 2, "Travail du cuir", "Armure verte en cuir", { 4234, 9 }, 175, 180, 200, "patron vendu", "source externe", 12000, 0 },
  [461708] = { 4300, 1, 1, "Forge", "Bottes brillantes en cuivre", { 2840, 4 }, 40, 40, 40, "inconnue", "extrait du client", 0, 0 },
  [13501] = { nil, 1, 1, "Enchantement", "Ench. de bracelets (Endurance inférieure)", { 11083, 1 }, 130, 155, 195, "patron vendu", "source externe", 500, 0 },
  [9009] = { 4301, 1, 1, "Forge", "Jamais vue chez un maître", { 2840, 1 }, 60, 70, 80, "maître", "source externe", 0, 0 },
  -- deux enchantements de même nom (époques différentes) : un service par ce nom est ambigu
  [9101] = { nil, 1, 1, "Enchantement", "Ench. en double", { 11083, 1 }, 200, 225, 245, "maître", "source externe", 0, 0 },
  [9102] = { nil, 1, 1, "Enchantement", "Ench. en double", { 11137, 4 }, 300, 320, 360, "inconnue", "source externe", 0, 0 },
}
AzerothCommuneDB.trainers = {
  [1] = { services = {
    { name = "Minage d'apprenti", cost = 9, skill_rank = 0 },                                      -- compétence, pas une recette : ignorée
    { name = "Barre de fer", item = 3575, skill = "Minage", skill_rank = 100, cost = 450 },        -- par l'objet enseigné (le nom diffère)
    { name = "Armure verte en cuir", skill = "Travail du cuir", skill_rank = 150, cost = 800 },    -- par le nom, sans objet
    { name = "Bottes brillantes en cuivre", item = 4300, skill = "Forge", skill_rank = 35, cost = 60 },
    { name = "Ench. de bracelets (Endurance inférieure)", skill = "Enchantement", skill_rank = 120, cost = 300 }, -- enchantement : par le nom
    { name = "Recette inconnue de la base", item = 99999, skill = "Forge", skill_rank = 10, cost = 1 },
    { name = "Fondre le fer", item = 4300, skill = "Minage", skill_rank = 1, cost = 1 },           -- l'objet est celui d'un autre métier : le nom décide
    { name = "Ench. en double", skill = "Enchantement", skill_rank = 210, cost = 5 },              -- deux recettes de ce nom : ignoré
  } },
  [2] = { services = { { name = "Armure verte en cuir", skill = "Travail du cuir", skill_rank = 140, cost = 900 } } }, -- un autre maître, plus bas
}
br, lotBr = AzerothCommune:Lire("base des recettes")
assert(br[3307].level == 1 and br[3307].source == "maître" and br[3307].prix_maitre == 1 and br[3307].condition == nil,
  "nom exact quand l'objet ne rapproche rien dans le métier ; enseignée par un maître : plus « plus enseignée »")
assert(br[9002].level == 140 and br[9002].prix_maitre == 900 and br[9002].source == "maître" and br[9002].source_provenance == "relevé direct"
  and br[9002].pattern_price == 12000 and br[9002].yellow == 180, "vue chez un maître : sa compétence et son prix, les autres champs de la réserve gardés ; plusieurs maîtres : le plus bas")
assert(br[461708].level == 35 and br[461708].source == "maître" and br[461708].source_provenance == "relevé direct"
  and br[461708].prix_maitre == 60, "recette Forever « inconnue » vendue par un maître : maître")
assert(br[13501].level == 120 and br[13501].source == "maître" and br[13501].prix_maitre == 300, "enchantement rapproché par son nom")
assert(br[9009].level == 60 and br[9009].source == "maître" and br[9009].source_provenance == "source externe" and br[9009].prix_maitre == nil,
  "jamais vue chez un maître : valeurs de la réserve")
assert(br[9101].level == 200 and br[9101].prix_maitre == nil and br[9102].level == 300 and br[9102].source == "inconnue",
  "service ambigu (deux recettes de ce nom) : ignoré, rien n'est deviné")
assert(lotBr.provenance == "relevé direct", "un maître relevé : lot en relevé direct")
local avant = AzerothCommuneDB.trainers
AzerothCommuneDB.trainers = nil
br, lotBr = AzerothCommune:Lire("base des recettes")
assert(br[9002].level == 175 and br[9002].source == "patron vendu" and br[9002].prix_maitre == nil and br[461708].source == "inconnue"
  and AzerothCommuneDB.recipes[3307].level == nil and lotBr.provenance == "relevé direct", "tables relevées et réserve intactes")
AzerothCommuneDB.trainers = avant
assert(avant[1].services[2].skill_rank == 100 and avant[2].services[1].cost == 900, "relevé des maîtres intact")
AzerothCommuneDB.trainers = nil
-- Sans fichier de réserve (repo cloné tel quel) : les seules recettes vues, sans erreur.
ns.recettesClassic = nil
br, lotBr = AzerothCommune:Lire("base des recettes")
assert(br[3307] and br[3307].level == nil and br[9002] == nil and lotBr.provenance == "relevé direct", "sans réserve : les recettes vues")
-- La réserve seule (aucune recette vue) : son lot, extrait du client, au build du client (64000 ici) ; périmé sous un
-- autre build, ou sans lot (une réserve d'avant #54) ; ni l'une ni l'autre : pas encore relevé.
local vuesAvant = AzerothCommuneDB.recipes
AzerothCommuneDB.recipes = {}
ns.recettesClassic = { [9002] = { 4255, 1, 1, "Travail du cuir", "Armure verte en cuir", { 4234, 9 }, 175, 180, 200 } }
br, lotBr = AzerothCommune:Lire("base des recettes")
assert(br[9002] and lotBr.provenance == "extrait du client" and lotBr.build == 64000 and lotBr.version == "1.16.1.64000"
  and lotBr.date == "2026-11-21" and not lotBr.perime, "la réserve seule, au build du client")
assert(ns.recettesClassicLot.perime == nil, "le lot de la réserve n'est pas touché")
ns.recettesClassicLot = { provenance = "extrait du client", build = 63000 }
assert(select(2, AzerothCommune:Lire("base des recettes")).perime, "réserve extraite sous un autre build : peut-être périmée")
ns.recettesClassicLot = nil
lotBr = select(2, AzerothCommune:Lire("base des recettes"))
assert(lotBr.provenance == "extrait du client" and lotBr.perime, "réserve sans lot : peut-être périmée")
ns.recettesClassic = nil
assert(select(2, AzerothCommune:Lire("base des recettes")) == "pas encore relevé", "ni recette vue ni réserve")
AzerothCommuneDB.recipes = vuesAvant
-- Objets (#52) : les objets relevés (1 nommé, 2 vu sans nom, 5 inconnu du serveur : scan plus haut), puis le catalogue des
-- objets extrait du client (CatalogueObjets.lua, généré, privé au socle : ns.catalogueObjets) pour les autres, chaque
-- ligne marquée « extrait du client ». La fusion est gardée 5 s.
do
local horloge, vus = 100, AzerothCommuneItems.items
GetTime = function() return horloge end
AzerothCommuneDB.lots.objets = { provenance = "relevé direct", build = 64000 }
local ob, lotOb = AzerothCommune:Lire("objets")
assert(ob == vus and lotOb == AzerothCommuneDB.lots.objets, "sans catalogue (repo cloné tel quel) : les objets relevés, comme avant")
local function ligne(nom, q) return { name = nom, quality = q, provenance = "extrait du client" } end
ns.catalogueObjets = { [1] = ligne("Casque (client)", 1), [2] = ligne("Gants", 2), [5] = ligne("Objet fantôme", 1),
  [7] = ligne("Épée", 3) }
ns.catalogueObjetsLot = { provenance = "extrait du client", build = 64000, version = "1.16.1.64000", date = "2026-11-21" }
ob, lotOb = AzerothCommune:Lire("objets")
assert(ob[1] == vus[1] and ob[1].name == "Casque", "un objet relevé l'emporte")
assert(ob[2].name == "Gants" and ob[2].provenance == "extrait du client", "vu, nom pas encore demandé au serveur : le catalogue")
assert(ob[5] == vus[5], "inconnu du serveur : le relevé l'emporte")
assert(ob[7].name == "Épée" and ob[7].quality == 3 and ob[7].provenance == "extrait du client", "jamais vu : le catalogue")
assert(lotOb == AzerothCommuneDB.lots.objets and vus[7] == nil, "lot du relevé ; les objets relevés ne sont pas touchés")
vus[8] = { name = "Neuf" }
assert(AzerothCommune:Lire("objets")[8] == nil, "fusion gardée moins de 5 s")
horloge = 105
assert(AzerothCommune:Lire("objets")[8] == vus[8], "puis refaite")
-- Le catalogue seul (rien de relevé, ou relevé sans nom) : son lot, extrait du client, peut-être périmé sous un autre build.
AzerothCommuneItems.items = { [2] = { class = 4 } }
ob, lotOb = AzerothCommune:Lire("objets")
assert(ob[2].name == "Gants" and ob[7] and lotOb.provenance == "extrait du client" and lotOb.build == 64000
  and not lotOb.perime, "le catalogue seul, sous le build du client")
ns.catalogueObjetsLot.build = 63000
assert(select(2, AzerothCommune:Lire("objets")).perime, "extrait sous un autre build : peut-être périmé")
ns.catalogueObjets, AzerothCommuneItems.items = {}, {}
assert(select(2, AzerothCommune:Lire("objets")) == "pas encore relevé", "ni objet relevé ni catalogue : pas encore relevé")
ns.catalogueObjets, ns.catalogueObjetsLot, AzerothCommuneItems.items = nil, nil, vus
GetTime = function() return 100 end
end
-- Connexion : recettes connues relevées sans fenêtre (IsPlayerSpell, recettes déjà vues), pour un perso jamais passé par
-- sa fenêtre de métier, et sauvegardées dans son perso. Puis la fenêtre s'ouvre : elle prime, sans rien perdre.
local neuf, char0, run0 = { errors = {}, lots = {} }, ns.char, ns.run
ns.char, ns.run = function() return neuf end, function(_, fn) fn(neuf) end
AzerothCommuneDB.recipes[3310] = { profession = "Minage", name = "Fondre le thorium" } -- vue chez un autre perso
-- La réserve du socle (#48) est interrogée aussi, même pour un objet qu'une recette vue fabrique déjà (9004 : la
-- barre de fer, comme 3307) : le même relevé que quand Handshake la remettait.
ns.recettesClassic = { [9001] = { 2840, 1, 1, "Minage", "Fondre le cuivre", { 2770, 1 }, 1 },
  [9004] = { 3575, 1, 1, "Minage", "Fondre le fer (autre)", { 2772, 1 }, 125 } }
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Minage", "icône", 150, 225 end
IsPlayerSpell = function(id) return id == 3307 or id == 3310 or id == 9001 or id == 9004 end
commerce.fn(commerce, "PLAYER_LOGIN")
ns.recettesClassic = nil
local mn = neuf.recipes and neuf.recipes.Minage
assert(mn and mn.rank == 150 and mn.known[3307] == true and mn.known[3310] and not mn.known[3308], "relevé sans fenêtre sauvegardé")
assert(mn.known[9001] and mn.known[9004], "relevé sans fenêtre : la réserve du socle interrogée")
commerce.fn(commerce, "TRADE_SKILL_LIST_UPDATE")
mn = neuf.recipes.Minage
assert(mn.known[3307] == "optimal" and mn.rank == 140 and mn.scanned and not mn.known[3308], "la fenêtre prime")
assert(mn.known[3310], "connue mais absente de la liste de la fenêtre : gardée")
ns.char, ns.run = char0, run0
-- Lecture de l'HV : le scan appelle lui-même le signal « type relevé à nouveau » (#41 : plus de crochet).
C_AuctionHouse = { ReplicateItems = noop, GetNumReplicateItems = function() return 1 end,
  GetReplicateItemInfo = function() return nil, nil, 5, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 2772 end }
-- La maison de l'HV vient de la lib (lib.MaisonHV, GameData#24) : « n° de serveur-faction », le numéro tiré du GUID
-- (LibCommune#35 : le jeu ne donne plus le royaume).
local MAISON = "6942-Alliance"
UnitGUID = function(u) if u == "player" then return "Player-6942-014B6DDC" end end
UnitFactionGroup, time, AzerothCommuneMarket = function() return "Alliance" end, os.time, {}
local scanned, realPrint = 0, print
assert(AzerothCommune:QuandReleve("cours de l'HV", function() scanned = scanned + 1 end))
print = noop
commerce.fn(commerce, "AUCTION_HOUSE_SHOW")
commerce.fn(commerce, "REPLICATE_ITEM_LIST_UPDATE")
print = realPrint
assert(AzerothCommuneMarket[MAISON].items[2772].min == 100 and scanned == 1, "HV lu, puis l'abonné prévenu une fois, sans crochet")
-- Sans fournisseur, le scan de l'HV marche comme avant : GameData relève tout (prix, quantité, paliers, historique).
local hvR = AzerothCommuneMarket[MAISON]
assert(hvR.items[2772].qty == 5 and hvR.items[2772].auctions == 1 and hvR.items[2772].tiers[1].price == 100, "tout relevé")
assert(#hvR.hist[2772] == 1 and hvR.hist[2772][1][2] == 100 and hvR.hist[2772][1][3] == 5, "historique relevé")
local hvLib, lotLib = AzerothCommune:Lire("cours de l'HV")
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
local signale = 0 -- un add-on prévenu de chaque scan de l'HV par le signal « type relevé à nouveau »
assert(AzerothCommune:QuandReleve("cours de l'HV", function() signale = signale + 1 end))
scanHV()
assert(signale == 1, "scan de l'HV : signal « type relevé à nouveau » aux abonnés")
hvR = AzerothCommuneMarket[MAISON]
assert(scanned == 2 and hvR.items[2772].min == 100 and hvR.items[2772].qty == 5 and hvR.items[2772].tiers[1].price == 100, "prix, quantité, paliers gardés comme avant")
assert(hvR.hist == nil, "AuctionDB frais : pas de copie de l'historique")
hvLib, lotLib = AzerothCommune:Lire("cours de l'HV")
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
hvR = AzerothCommuneMarket[MAISON]
assert(scanned == 3 and #hvR.hist[2772] == 1 and hvR.hist[2772][1][2] == 100, "historique gardé par GameData")
assert(AzerothCommune:Lire("cours de l'HV").objet(2772).sources.hist == "AuctionDB", "lu : l'historique d'AuctionDB d'abord")
Auctionator, AuctionDBForeverSaved = nil, nil
print("Azeroth Commune : fournisseurs des cours de l'HV OK")
-- Royaume et faction relevés par la lib, qui les sonde (GameData#24) : plus d'appel direct dans le code chargé.
for _, f in ipairs({ "Base.lua", "Commerce.lua", "Souscriptions.lua" }) do
  local code = io.open("AzerothCommune/" .. f):read("*a")
  for _, appel in ipairs({ "GetRealmName", "GetNormalizedRealmName", "UnitFactionGroup" }) do
    local n = select(2, code:gsub(appel .. "%(", ""))
    assert(n == 0, f .. " : appel direct à " .. appel)
  end
end
print("Azeroth Commune : royaume et faction par AzerothCommune.lua OK")
-- Le socle ne se regroupe pas lui-même (pas de ligne dans son menu) ; /ac remplace /gdata, sans « cout » (le socle
-- n'appelle aucun add-on) ; ses exports sont rendus par AzerothCommune.Exports(), sous son nom.
assert(#AzerothCommune.regroupes == 0, "le socle n'est pas dans le menu de son bouton")
assert(SlashCmdList.GAMEDATA == nil and SLASH_GAMEDATA1 == nil and SLASH_AZEROTHCOMMUNE1 == "/ac", "/ac, plus de /gdata")
AzerothCommuneDB = AzerothCommuneDB or {}
local dits, exporte = {}, nil
local garde, exporter = print, AzerothCommune.Exporter
print = function(m) dits[#dits + 1] = m end
AzerothCommune.Exporter = function(v, nom) exporte = nom end
SlashCmdList.AZEROTHCOMMUNE("export")
SlashCmdList.AZEROTHCOMMUNE("export addons")
print, AzerothCommune.Exporter = garde, exporter
assert(dits[1]:find("/ac export addons | erreurs | hv", 1, true), tostring(dits[1]))
assert(exporte == "ac-addons", "/ac export addons : l'image s'appelle ac-addons")
local cles = {}
for _, e in ipairs(AzerothCommune.Exports()) do
  assert(e.addon == "Azeroth Commune" and e.libelle and e.description and type(e.donnees) == "function", e.cle)
  cles[#cles + 1] = e.cle
end
assert(table.concat(cles, ",") == "perso,persos,recettes,marchands,maitres,hv,addons,erreurs", table.concat(cles, ","))
assert(ns.costCommand == nil and ns.openCraftWindow == nil, "plus d'emplacement pour Handshake")
-- La TOC : une seule, « Azeroth Commune », catégorie Données, des SavedVariables neuves.
local toc = io.open("AzerothCommune/AzerothCommune.toc"):read("*a")
assert(toc:find("## Title: Azeroth Commune\n", 1, true) and toc:find("## Category: Data\n", 1, true)
  and toc:find("## Category-frFR: Données\n", 1, true), "titre et catégorie")
assert(toc:find("## SavedVariables: AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket\n", 1, true), "SavedVariables neuves")
assert(not toc:find("LibStub", 1, true) and not toc:find("Deps", 1, true), "ni LibStub ni dépendance")
print("Azeroth Commune : /ac, exports du socle, TOC OK")

-- Souscriptions (GameData#4), sur plusieurs sessions qui partagent les SavedVariables : une souscription faite sur le
-- personnage A fait relever le type sur le personnage B à sa connexion, même sans l'add-on qui a souscrit ; un type sans
-- souscription n'est pas relevé ; après 30 jours sans souscription il ne l'est plus, ses données restent ;
-- /ac effacer <type> les efface.
AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket = nil, nil, nil
time = os.time
local tickers
C_Timer = { After = function(_, fn) fn() end, NewTicker = function(t) tickers[#tickers + 1] = t return { Cancel = noop } end }
local sortie = {}
local GUID = { Alice = "Player-6942-0000A11C", Bob = "Player-6942-00000B0B", Carl = "Player-6942-0000CA71" }
local NOM_DE_FAMILLE = {} -- 2e retour de UnitName sur Forever
local function session(nom, souscriptions)
  UnitName = function() return nom, NOM_DE_FAMILLE[nom] end
  UnitGUID = function(u) if u == "player" then return GUID[nom] end end
  tickers, sortie = {}, {}
  AzerothCommune = nil -- nouvelle session : le socle repart de zéro, seules les SavedVariables restent
  frames = {} -- [fichier] = son dernier cadre, et dans l'ordre de création
  local gns = {}
  for _, f in ipairs({ "AzerothCommune", "Interface", "Capture", "Regroupement", "Fournisseurs", "Base", "Commerce", "Souscriptions" }) do
    local n = #frames
    charger(f, gns)
    if #frames > n then frames[f] = frames[#frames] end
  end
  frames.Base.fn(frames.Base, "ADDON_LOADED", "AzerothCommune")
  local lib = AzerothCommune
  for _, t in ipairs(souscriptions or {}) do assert(lib:Souscrire(t)) end -- l'add-on qui souscrit, chargé après le socle
  print = function(...) sortie[#sortie + 1] = table.concat({ ... }, " ") end
  for _, fr in ipairs(frames) do if fr.fn then fr.fn(fr, "PLAYER_LOGIN") end end
  print = realPrint
  return gns, lib
end
local function ac(cmd) print = function(...) sortie[#sortie + 1] = table.concat({ ... }, " ") end; SlashCmdList.AZEROTHCOMMUNE(cmd); print = realPrint end
local function objetsScannes() for _, t in ipairs(tickers) do if t == 0.5 then return true end end return false end
local A, B, C = GUID.Alice, GUID.Bob, GUID.Carl -- les fiches sont rangées par GUID (LibCommune#19)

-- Une souscription faite par un add-on (#41) : relevée, visible dans /ac souscriptions, tenue à un seul endroit (la base).
local gns, glib = session("Alice", { "inventaires" })
assert(type(AzerothCommuneDB.souscriptions.inventaires) == "number", "souscription retenue avec sa date")
assert(AzerothCommuneDB.chars[A].bags.Backpack, "A : inventaires relevés")
assert(glib.souscriptions == nil and gns.retenirSouscriptions == nil, "pas d'état en double")
ac("souscriptions")
assert(table.concat(sortie, "\n"):find("inventaires : souscrit le " .. os.date("%Y-%m-%d") .. ", relevé (données gardées)", 1, true),
  table.concat(sortie, "\n"))

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
local bags = AzerothCommuneDB.chars[A].bags
assert(bags.Backpack and bags.Bag_1 and bags.Keyring and bags.ReagentBag, "sacs manquants")
assert(not bags.Bag_2, "un sac de 0 place ne doit pas apparaître")
assert(not bags.Bank and not bags.Reagentbank, "la banque n'est pas un sac")
assert(bags.Backpack.items[1].id == 100 and bags.Backpack.items[1].count == 3 and bags.Backpack.items[1].link == "l")
assert(pareil(bags, avant(isBag)), "sacs : le même relevé qu'avant")
frames.Base.fn(frames.Base, "BANKFRAME_OPENED")
local bank, n = AzerothCommuneDB.chars[A].bank, 0
for _ in pairs(bank) do n = n + 1 end
assert(n == 3, "banque : Bank, Reagentbank et un seul des deux noms de l'onglet 1, trouvé " .. n)
assert(pareil(bank, avant(isBank)), "banque : le même relevé qu'avant")
frames.Base.fn(frames.Base, "BANKFRAME_CLOSED")
print("Azeroth Commune : sacs et banque par lib.Conteneurs, comme avant OK")
assert(not objetsScannes(), "objets sans souscription : pas de scan des objets")
for nom in pairs(glib.types) do assert(type(gns.lire[nom]) == "function", "accesseur de la base : " .. nom) end
for nom in pairs(gns.rangement) do assert(glib.types[nom], "rangé mais pas au catalogue : " .. nom) end

session("Bob") -- l'add-on qui a souscrit n'est pas activé sur B
local b = AzerothCommuneDB.chars[B]
assert(b and b.bags.Backpack.items[1].id == 100, "B : inventaires relevés à sa connexion, souscrits sur A")
assert(b.reputations == nil and b.errors.reputations == nil and b.quests_done == nil, "B : un type sans souscription n'est pas relevé")
assert(glib.types and AzerothCommune:Lire("inventaires", B).persos[B].bags, "lu par la lib")
ac("souscriptions")
local liste = table.concat(sortie, "\n")
assert(liste:find("inventaires : souscrit le", 1, true) and liste:find("objets : aucune souscription", 1, true), liste)

AzerothCommuneDB.souscriptions.inventaires = os.time() - 31 * 24 * 3600
session("Carl")
assert(not (AzerothCommuneDB.chars[C] and AzerothCommuneDB.chars[C].bags), "C : plus de souscription depuis 31 jours, plus relevé")
assert(AzerothCommuneDB.chars[B].bags.Backpack and AzerothCommuneDB.chars[A].bags, "les données relevées restent")
ac("souscriptions")
assert(table.concat(sortie, "\n"):find("plus relevé", 1, true), "la liste dit qu'il n'est plus relevé")

ac("effacer inventaires")
assert(AzerothCommuneDB.chars[A].bags == nil and AzerothCommuneDB.chars[B].bags == nil and AzerothCommuneDB.chars[B].lots.bags == nil, "inventaires effacés")
ac("effacer pas un type")
assert(table.concat(sortie, "\n"):find("inconnu", 1, true), "type inconnu refusé")

-- Types globaux : recettes, maîtres, marchands, HV, objets. Le joueur souscrit lui-même aux objets (/ac souscrire).
ac("souscrire objets")
ac("souscrire cours de l'HV")
assert(gns.souscrit("cours de l'HV"), "/ac souscrire cours de l'HV : le nom tapé tel quel")
session("Bob")
assert(objetsScannes(), "objets souscrits : scan des objets lancé")
AzerothCommuneDB.vendors[42] = { items = {} }
AzerothCommuneItems.items[7] = { name = "x" }
ac("effacer objets")
assert(next(AzerothCommuneItems.items) == nil and AzerothCommuneItems.next_id == 1, "objets effacés, le balayage repart de 1")
gns.itemTick() -- un ID encore en file d'attente, effacé entre-temps : ignoré sans erreur
ac("effacer marchands")
assert(next(AzerothCommuneDB.vendors) == nil, "marchands effacés")
print("Azeroth Commune : souscriptions OK")

-- Provenance (GameData#5) : chaque lot porte sa provenance, son build et sa date. Une base d'avant les lots est migrée
-- (relevé direct, build inconnu donc peut-être périmé) ; un build différent marque les lots figés peut-être périmés ;
-- dans le lot mixte des marchands, la provenance la plus fiable gagne.
AzerothCommuneDB = { souscriptions = { inventaires = os.time(), marchands = os.time() },
  chars = { [A] = { errors = {}, scanned = { bags = "2026-11-01 12:00:00" }, bags = { Backpack = { size = 16, items = {} } } } },
  vendors = { [42] = { name = "Vu en jeu", items = { { id = 159, price = 30, stack = 5 } } } } }
AzerothCommuneItems, AzerothCommuneMarket = nil, nil
gns, glib = session("Carl")
local la = AzerothCommuneDB.chars[A].lots.bags
assert(la.provenance == "relevé direct" and la.date == "2026-11-01 12:00:00" and la.perime and la.build == nil, "migration d'un champ de perso")
assert(AzerothCommuneDB.chars[A].scanned == nil, "la date du relevé est passée dans le lot")
assert(AzerothCommuneDB.lots.marchands.provenance == "relevé direct" and AzerothCommuneDB.lots.marchands.perime, "migration d'un type du joueur")
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
assert(m[42].items[1].price == 30 and m[42].provenance == nil and lot == AzerothCommuneDB.lots.marchands, "vu en jeu > VendorData")
assert(m7.provenance == "source externe" and m7.items[1].price == 25 and AzerothCommuneDB.vendors[7] == nil, "marchand pas vu : la base, sans rien sauvegarder")
assert(m7.items[1].sell == 1 and m7.items[1].maxStack == 20, "ligne de la base : revente et taille de pile")
assert(m[8] == nil and m[9].items[1].id == 159, "base : pas de PNJ amical pour la seule faction adverse")
ac("effacer marchands")
m, lot = glib:Lire("marchands")
assert(m[42].provenance == nil and m[42].items[1].price == 25 and lot.provenance == "source externe" and lot.perime, "seule la base : lot source externe, build inconnu")

-- Nouveau build du client : les lots figés sous l'ancien sont marqués peut-être périmés, rien n'est effacé.
gns.noterLot("marchands") -- un marchand vu sous le build 64000
assert(AzerothCommuneDB.lots.marchands.build == 64000 and not AzerothCommuneDB.lots.marchands.perime)
BUILD = "64100"
gns, glib = session("Alice")
local lm = AzerothCommuneDB.lots.marchands
assert(lm.perime and lm.build == 64000, "lot du joueur figé sous l'ancien build : peut-être périmé")
assert(AzerothCommuneDB.chars[C].lots.bags.perime and AzerothCommuneDB.chars[C].bags, "lot d'un perso pas connecté : marqué, gardé")
assert(AzerothCommuneDB.chars[A].lots.bags.build == 64100 and not AzerothCommuneDB.chars[A].lots.bags.perime, "perso connecté : relevé à nouveau, plus périmé")
local figeLe = lm.date
lm.date = "2026-11-01 12:00:00"
gns.noterLot("marchands") -- un autre marchand vu : les autres restent d'avant
assert(lm.perime and lm.build == 64000 and AzerothCommuneDB.lots.marchands == lm, "relevé partiel : le lot reste peut-être périmé")
assert(lm.date == "2026-11-01 12:00:00" and figeLe, "relevé partiel d'un lot périmé : sa date reste celle où il a été figé")
gns.noterLot("marchands", true)
assert(AzerothCommuneDB.lots.marchands.build == 64100 and not AzerothCommuneDB.lots.marchands.perime, "relevé entier : plus périmé")
print("Azeroth Commune : provenance, build et date des lots OK")

-- Recettes connues sous un nouveau build (64100) : la fenêtre d'un métier ne relève que ce métier. Une fenêtre qui ne
-- relève rien (liste pas à jour, métier d'un autre) ne touche pas au lot ; le lot n'est plus périmé que quand chaque
-- métier a été relevé sous ce build. Le relevé sans fenêtre note son lot à la fin.
AzerothCommuneDB.souscriptions["recettes connues"] = os.time()
local ca = AzerothCommuneDB.chars[A]
ca.recipes = { Minage = { rank = 100, max = 150, known = {} }, Couture = { rank = 50, max = 75, known = {} } }
ca.lots.recipes = { provenance = "relevé direct", build = 64000, date = "2026-11-01 12:00:00", perime = true }
local lr = ca.lots.recipes
local commerceS = frames.Commerce
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
print("Azeroth Commune : lot des recettes connues, par métier OK")

-- Base des recettes (#48) : sans souscription, la fenêtre de métier n'en relève rien ; souscrite seule (sans « recettes
-- connues »), elle relève les recettes vues, pas les recettes connues du perso. /ac la connaît.
AzerothCommuneDB = { souscriptions = { inventaires = os.time() } }
AzerothCommuneItems, AzerothCommuneMarket = nil, nil
gns, glib = session("Alice")
frames.Commerce.fn(frames.Commerce, "TRADE_SKILL_LIST_UPDATE")
assert(not next(AzerothCommuneDB.recipes or {}), "aucune souscription : aucune recette relevée")
assert(select(2, glib:Lire("base des recettes")) == "pas encore relevé", "rien de relevé pour la base des recettes")
gns, glib = session("Alice", { "base des recettes" })
frames.Commerce.fn(frames.Commerce, "TRADE_SKILL_LIST_UPDATE")
assert(AzerothCommuneDB.recipes[3307] and AzerothCommuneDB.chars[A].recipes == nil, "base des recettes seule : les recettes vues, pas les connues")
assert(glib:Lire("base des recettes")[3307].output == 3575, "lue par Lire")
ac("souscriptions")
assert(table.concat(sortie, "\n"):find("base des recettes : souscrit le", 1, true), table.concat(sortie, "\n"))
print("Azeroth Commune : souscription à la base des recettes OK")

-- Fiches par GUID (LibCommune#19), avec le nom « Prénom Nom » ; un autre perso du joueur se lit par sa fiche.
-- (SavedVariables neuves : plus de reprise des fiches d'avant le GUID.)
NOM_DE_FAMILLE.Alice = "Dupont"
AzerothCommuneDB = { souscriptions = { inventaires = os.time() } }
AzerothCommuneItems, AzerothCommuneMarket = nil, nil
gns, glib = session("Alice")
local fa = AzerothCommuneDB.chars[A]
assert(fa and fa.nom == "Alice Dupont" and fa.adresse == nil and fa.bags, "fiche sous le GUID, avec le nom")
local pa = glib.Personnage(A)
assert(pa.guid == A and pa.adresse == nil and pa.nom == "Alice Dupont", "AzerothCommune.Personnage : le perso connecté")
assert(gns.personnage(A).nom == "Alice Dupont" and gns.personnage("Player-6942-0000DEAD") == nil, "accesseur privé personnage")
gns, glib = session("Bob")
assert(glib.Personnage(A).nom == "Alice Dupont" and glib.Personnage(A).adresse == nil, "un autre perso du joueur : sa fiche dans la base")
for k in pairs(glib:Lire("inventaires", "tous").persos) do assert(k:find("^Player%-"), "lu : seulement des GUID, pas " .. k) end
local exportPerso
for _, e in ipairs(glib.Exports()) do if e.cle == "perso" then exportPerso = e end end
assert(next(exportPerso.donnees()) == B, "export perso : sous le GUID")
NOM_DE_FAMILLE.Alice = nil
print("Azeroth Commune : fiches par GUID OK")
end
