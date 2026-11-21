-- LibCommune : la lib commune embarquée des add-ons Azeroth Commune (modèle LibStub : la mineure la plus récente sert).
-- Du code seulement, jamais de données sauvegardées à elle (ADR 0001 de l'atelier : les données relevées ne sont
-- sauvegardées que dans GameData).
--
-- Accès aux données relevées, deux gestes :
--   lib:Souscrire(type)          : l'add-on souscrit à ce type de données (il en a besoin). Avec GameData, la souscription
--                                  vaut pour tous les personnages du joueur (GameData ne relève que les types souscrits, et
--                                  cesse après ~30 jours sans souscription) ; sans lui, elle vaut le temps de la session.
--   lib:Lire(type, personnage)   : les données et leur lot, ou nil et la raison (« type inconnu », « pas de GameData »,
--                                  « pas encore relevé », « pas de GameData ni de fournisseur »). personnage = son GUID, nil pour le
--                                  personnage connecté, « tous » pour tous les personnages relevés.
-- Lot : { provenance, build, version, date, perime } — d'où viennent les données (lib.provenances, du plus fiable au moins
-- fiable), le build du client (GetBuildInfo) et la date du relevé ; perime = true : figé sous un autre build, peut-être
-- périmé. Pour un type par personnage, le lot va aussi par personnage : { persos = { [GUID] = lot } }. Dans un lot
-- mixte (marchands : vus en jeu et base VendorData), une ligne d'une autre provenance porte la sienne (champ provenance).
-- Avec GameData, la lib lit sa base ; sans lui, relevé de repli : le personnage connecté, en mémoire, le temps de la session
-- (recettes connues ; inventaires : sacs lus à l'instant, banque vue cette session).
-- Un type qui a des fournisseurs (cours de l'HV : Auctionator, TSM, AuctionDB) passe aussi par eux (Fournisseurs.lua).
--   lib:QuandReleve(type, fn)    : fn(type) après chaque nouveau relevé de ce type (ex. scan de l'HV terminé).
-- Le consommateur ne teste jamais lui-même la présence de GameData.
-- Personnage : lib.Personnage(guid) = { guid, adresse, nom } ; lib.Adresse(nom, royaume), lib.Destinataire(nom).
-- Prix d'achat : lib:PrixAchat(id, qty, hv, marchands), lib:PrixMarchands() (en fin de fichier).
-- Identité, chaque relevé sondé : lib.Royaume() (affiché), lib.RoyaumeNormalise() (sans espace ni tiret, celui des
-- adresses), lib.MaisonHV() (« royaume-faction », clé des scans de l'HV), lib.Faction(), lib.Build() (nombre).
-- Sondes : lib.Sondes() = l'état de chacune (vert, rouge, pas encore vue ; valeur reçue, heure, build) ;
-- lib.RelancerSondes() refait les relevés sans contexte (aussi à la connexion). Une sonde rouge prévient dans le chat, ne corrige rien.
local MAJOR, MINOR = "LibCommune-1.0", 10
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- une copie aussi récente est déjà chargée : c'est elle qui sert

-- Catalogue des types de données (ceux que GameData relève). léger : relevable sans GameData, par un relevé de repli ;
-- un type lourd (HV, catalogue des objets) attend GameData ou un fournisseur. parPerso : les données vont par personnage
-- ({ persos = { [GUID] = … } }, filtrées par lib:Lire), sinon une seule table pour le joueur. gamedata : la
-- fonction de GameDataAPI qui rend ce type. repli : le relevé de repli est écrit (recettes connues, inventaires).
local TYPES = {
  -- persos[p] = { character (fiche, or), equipped, bags, bank, mail, currencies }
  -- Repli : le personnage connecté, { bags (lus à l'instant), bank (vue cette session) }.
  inventaires = { leger = true, parPerso = true, gamedata = "inventaires", repli = true },
  ["réputations"] = { leger = true, parPerso = true, gamedata = "reputations" }, -- persos[p] = { { id, name, standing, … } }
  ["métiers et compétences"] = { leger = true, parPerso = true, gamedata = "metiersEtCompetences" }, -- persos[p] = { professions, skills }
  ["quêtes terminées"] = { leger = true, parPerso = true, gamedata = "quetesTerminees" }, -- persos[p] = { questID, … }
  -- { recettes = { [clé] = { profession, name, output, reagents, … } },
  --   persos = { [GUID] = { [métier] = { rank, max, known = { [clé] = difficulté, ou true sans fenêtre } } } } }
  ["recettes connues"] = { leger = true, parPerso = true, gamedata = "recettesConnues", repli = true },
  ["maîtres de métier"] = { leger = true, gamedata = "maitresDeMetier" }, -- { [PNJ] = { services, filters, … } }
  marchands = { leger = true, gamedata = "marchands" }, -- { [PNJ] = { items = { { id, price, stack, limited }, … } } }
  ["prix des vols"] = { leger = true, gamedata = "prixDesVols" }, -- { [départ] = { [arrivée] = prix } }
  ["add-ons installés"] = { leger = true, gamedata = "addonsInstalles" }, -- { [dossier] = { title, version, … } }
  -- { objet = fn(itemID) -> { min, qty, auctions, tiers, hist, sources }, depot = { rate24, min }, hv = le relevé de
  --   GameData ({ [royaume-faction] = { items, hist, … } } ; hist absent quand AuctionDB le tient) } : le scan de
  --   GameData fait foi, les fournisseurs pour l'historique et quand GameData n'a pas scanné l'HV (Fournisseurs.lua)
  ["cours de l'HV"] = { gamedata = "coursHV" },
  objets = { gamedata = "objets" }, -- { [itemID] = { name, class, price, stack, … } }
}
lib.types = TYPES -- lecture seule : GameData y vérifie qu'il rend chaque type

-- Provenance d'un lot, du plus fiable au moins fiable (CONTEXT-MAP de l'atelier) : notre add-on via l'API en jeu, les
-- fichiers du client lus hors jeu, un autre add-on installé, une base tierce hors du jeu.
lib.provenances = { "relevé direct", "extrait du client", "autre add-on", "source externe" }
local RANG = {}
for i, p in ipairs(lib.provenances) do RANG[p] = i end

-- Lot mixte : sources = { { donnees = { [clé] = ligne }, provenance = … }, … }. Pour chaque clé, la ligne de la provenance
-- la plus fiable gagne (une provenance hors de lib.provenances passe en dernier). Rend les lignes et la provenance du lot
-- (la plus fiable qui a des données) ; une ligne d'une autre provenance est copiée avec son champ provenance (ni les
-- sources ni leur tableau ne sont touchés).
function lib.Fusionner(sources)
  local triees = {}
  for i, s in ipairs(sources) do triees[i] = s end
  local function rang(s) return RANG[s.provenance] or #lib.provenances + 1 end
  table.sort(triees, function(a, b) return rang(a) < rang(b) end)
  local out, tete = {}, nil
  for _, s in ipairs(triees) do
    for k, ligne in pairs(s.donnees or {}) do
      tete = tete or s.provenance
      if out[k] == nil then
        if s.provenance ~= tete then
          local copie = { provenance = s.provenance }
          for f, v in pairs(ligne) do copie[f] = copie[f] or v end
          ligne = copie
        end
        out[k] = ligne
      end
    end
  end
  return out, tete
end

---------------------------------------------------------------------------------------------------
-- Sondes (CONTEXT-MAP de l'atelier, LibCommune#30) : chaque relevé déclare la sienne à côté de son appel (un nom, une
-- attente en une phrase, une vérification qui compare seulement la valeur reçue, sans rappeler le jeu) ; elle est
-- vérifiée à chaque relevé. Une sonde rouge prévient dans le chat une fois par session et ne change rien à la valeur
-- rendue (pas de mode dégradé : on débugge). Rien n'est sauvegardé : le dernier résultat de chacune, le temps de la session.
lib.sondes = lib.sondes or {} -- [nom] = { etat, valeur, heure, build, prevenu } ; gardé d'une mineure à l'autre
local SONDES = {} -- { { nom, attente, verifier, relever }, … } dans l'ordre de déclaration, et [nom] = la même

local function montrer(v)
  if type(v) == "string" then return ("%q"):format(v) end
  if type(v) ~= "table" then return tostring(v) end
  local t = {}
  for i = 1, v.n do t[i] = montrer(v[i]) end
  return table.concat(t, ", ")
end

-- Le build noté dans l'état des sondes : il ne change pas pendant une session, lu une seule fois (lib.buildLu, gardé
-- d'une mineure à l'autre ; check.lua le remet à nil pour simuler une mise à jour du jeu).
-- ponytail: GetBuildInfo est toujours là en jeu ; le garde sert aux check.lua des add-ons qui ne le bouchonnent pas.
local function buildDeSession()
  if lib.buildLu == nil and GetBuildInfo then lib.buildLu = select(2, GetBuildInfo()) end
  return lib.buildLu
end

-- Vérifie la sonde nom sur ce que le jeu vient de rendre (...) et rend ... tel quel.
local function sonder(nom, ...)
  local s, r = SONDES[nom], lib.sondes[nom] or {}
  lib.sondes[nom] = r
  r.etat = s.verifier(...) and "vert" or "rouge"
  r.valeur = select("#", ...) > 1 and { n = select("#", ...), ... } or (...) -- plusieurs retours : { n, … }
  r.heure, r.build = date("%H:%M:%S"), buildDeSession()
  if r.etat == "rouge" and not r.prevenu then
    r.prevenu = true
    print(("Azeroth Commune : le jeu ne rend pas ce que nous attendons (%s : %s ; reçu %s), build %s. À signaler."):format(
      nom, s.attente, montrer(r.valeur), tostring(r.build)))
  end
  return ...
end

-- Déclare un relevé sondé sans contexte : appel() lit le jeu ; rend la fonction qui relève et sonde.
-- ponytail: toutes les sondes sont sans contexte pour l'instant ; une sonde qui en demande un (fenêtre ouverte…) se
-- déclarera sans relever, et RelancerSondes la sautera.
local function releve(nom, attente, verifier, appel)
  local relever = function() return sonder(nom, appel()) end
  SONDES[#SONDES + 1] = { nom = nom, attente = attente, verifier = verifier, relever = relever }
  SONDES[nom] = SONDES[#SONDES]
  return relever
end

-- { { nom, attente, etat = "vert" | "rouge" | "pas encore vue", valeur, heure, build }, … } dans l'ordre de déclaration,
-- aussi rangées par nom. valeur : ce que le jeu a rendu ({ n, … } pour plusieurs retours) ; heure « HH:MM:SS ».
function lib.Sondes()
  local out = {}
  for i, s in ipairs(SONDES) do
    local r = lib.sondes[s.nom] or {}
    out[i] = { nom = s.nom, attente = s.attente, etat = r.etat or "pas encore vue", valeur = r.valeur, heure = r.heure, build = r.build }
    out[s.nom] = out[i]
  end
  return out
end

-- Refait le relevé de chaque sonde sans contexte (une qui plante reste à son dernier résultat) ; rend lib.Sondes().
function lib.RelancerSondes()
  for _, s in ipairs(SONDES) do if s.relever then pcall(s.relever) end end
  return lib.Sondes()
end

local function nonVide(v) return type(v) == "string" and v ~= "" end

-- Le build du client, un nombre (2e retour de GetBuildInfo, « 64000 »).
local build = releve("build", "le 2e retour de GetBuildInfo() est un numéro de build",
  function(b) return tonumber(b) ~= nil end, function() return (select(2, GetBuildInfo())) end)
function lib.Build() return tonumber(build()) end

-- Le royaume tel que le jeu l'affiche (« CAMWOW EU4 Realm 8 PvP »), et normalisé, sans espace ni tiret, celui des adresses.
lib.Royaume = releve("royaume", "GetRealmName() rend le nom du royaume, non vide", nonVide, function() return (GetRealmName()) end)
local normalise = releve("royaume normalisé", "GetNormalizedRealmName() rend le royaume normalisé, non vide", nonVide,
  function() return GetNormalizedRealmName and GetNormalizedRealmName() or "" end)
function lib.RoyaumeNormalise() return (normalise():gsub("[%s%-]", "")) end

-- La faction du personnage connecté, « Alliance » ou « Horde ».
lib.Faction = releve("faction", "UnitFactionGroup(\"player\") rend Alliance ou Horde",
  function(f) return f == "Alliance" or f == "Horde" end, function() return (UnitFactionGroup("player")) end)

-- La maison de l'HV du personnage connecté, « royaume-faction » au royaume affiché (« CAMWOW EU4 Realm 8 PvP-Alliance ») :
-- la clé des scans de l'HV de GameData ; nil si la faction est inconnue.
lib.MaisonHV = releve("maison de l'HV", "la maison de l'HV est « royaume-faction », royaume non vide, faction Alliance ou Horde",
  function(m) return type(m) == "string" and (m:match("^.+%-Alliance$") or m:match("^.+%-Horde$")) ~= nil end,
  function() local f = lib.Faction() return f and (lib.Royaume() .. "-" .. f) end)

-- Le GUID du personnage connecté, et son prénom et nom de famille (Forever : le 2e retour de UnitName est le nom de famille).
local monGUID = releve("GUID", "UnitGUID(\"player\") est de la forme Player-…",
  function(g) return type(g) == "string" and g:find("^Player%-") ~= nil end, function() return UnitGUID("player") end)
local monNom = releve("nom", "UnitName(\"player\") rend un prénom puis un nom de famille (Forever)",
  function(prenom, nom) return nonVide(prenom) and nonVide(nom) end, function() return UnitName("player") end)

-- Le lot d'un relevé fait maintenant (même forme que les lots de GameData).
local function lotDuJour()
  return { provenance = "relevé direct", build = lib.Build(), version = (GetBuildInfo()), date = date("%Y-%m-%d %H:%M:%S") }
end

---------------------------------------------------------------------------------------------------
-- Personnage (CONTEXT-MAP de l'atelier) : identifié par son GUID (UnitGUID), qui survit à un renommage. Son adresse,
-- « Prénom-Royaume » au royaume normalisé (sans espace ni tiret), sert à lui envoyer un message ; son nom, « Prénom Nom »
-- sur Forever, à l'afficher.
-- Sur Forever, le 2e retour de UnitName, UnitFullName et GetUnitName(unité, true) est le NOM DE FAMILLE, pas le royaume
-- (/handshake noms en jeu, 20/11/2026) : le royaume vient de GetNormalizedRealmName. Un nom de famille n'a ni tiret ni
-- espace (refusé par le jeu) : dans une adresse, le dernier tiret sépare le prénom du royaume.
local ADRESSE = "^[^%-|,:%s%c]+%-[^%-|,:%s%c]+$"

-- L'adresse d'un nom reçu (« Prénom », « Prénom-Royaume », « Prénom Nom », « Prénom Nom-Royaume ») ou d'un prénom et de
-- son royaume (brut ou normalisé) : « Prénom-Royaume », notre royaume s'il n'y en a pas ; nil pour un nom piégé.
function lib.Adresse(nom, royaume)
  if type(nom) ~= "string" or nom == "" then return nil end
  if not royaume then
    local avant, apres = nom:match("^(.+)%-([^%-]+)$")
    if apres then nom, royaume = avant, apres end
  end
  local prenom = nom:match("^[^%s%-]+")
  if not prenom then return nil end
  royaume = (royaume and royaume ~= "") and royaume:gsub("[%s%-]", "") or lib.RoyaumeNormalise()
  local adresse = prenom .. "-" .. royaume
  return adresse:match(ADRESSE) and adresse or nil
end

-- À qui adresser un chuchotement : le prénom seul sur notre royaume (Forever lit « Prénom-Royaume » comme « Prénom
-- NomDeFamille » : « Aucun joueur nommé 'Testeur CAMWOWEU4Realm8PvP' », 18/11/2026), sinon l'adresse ; un nom illisible
-- est rendu tel quel.
-- ponytail: un autre royaume garde « Prénom-Royaume », à vérifier le jour où on joue entre royaumes
function lib.Destinataire(nom)
  local adresse = lib.Adresse(nom)
  if not adresse then return nom end
  local prenom, royaume = adresse:match("^([^%-]+)%-(.+)$")
  return royaume == lib.RoyaumeNormalise() and prenom or adresse
end

-- { guid, adresse, nom } du personnage connecté (guid nil ou le sien), ou d'un personnage du joueur dont GameData a la
-- fiche (écrite à chaque connexion de ce personnage) ; nil sinon.
-- ponytail: pas de GetPlayerInfoByGUID pour un autre joueur (ni nom de famille, ni royaume vérifié sur Forever) ; à
-- ajouter quand un add-on aura besoin du nom d'un autre joueur par son GUID.
function lib.Personnage(guid)
  local moi = monGUID()
  if guid == nil or guid == moi then
    local prenom, nomDeFamille = monNom()
    return { guid = moi, adresse = lib.Adresse(prenom),
      nom = (nomDeFamille and nomDeFamille ~= "") and (prenom .. " " .. nomDeFamille) or prenom }
  end
  local fiche = GameDataAPI and GameDataAPI.personnage
  return fiche and fiche(guid) or nil
end

---------------------------------------------------------------------------------------------------
-- Relevé des recettes connues, dans la fenêtre de métier ouverte (API moderne C_TradeSkillUI de Forever) : toutes
-- les recettes du métier, apprises ou non, avec produit et composants. Sert au relevé de repli et à GameData, qui
-- sauvegarde ce qu'il rend. Rend { metier, rang, max, connues = { [clé] = difficulté }, recettes = { [clé] = … },
-- total, illisibles, premiereErreur }, ou nil, raison (et le métier pour « liste vide »).
local DIFFICULTE = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" } -- Enum.TradeskillRelativeDifficulty

function lib:ReleverRecettes()
  local T = C_TradeSkillUI
  local p = T and T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  local metier = p and p.professionName
  if not metier or metier == "" then return nil, "pas de métier ouvert" end
  -- Pièges vus dans Mastercraft : une fenêtre liée (le métier d'un autre joueur) ou d'un PNJ n'est pas à nous ; et
  -- juste après l'ouverture, la liste peut encore être celle du métier précédent.
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) then return nil, "métier d'un autre" end
  -- GetAllRecipeIDs (non documentée, utilisée par DataStore sur ce client) ignore filtres et en-têtes repliés.
  local liste = T.GetAllRecipeIDs and T.GetAllRecipeIDs() or T.GetFilteredRecipeIDs()
  if liste and liste[1] and T.GetProfessionInfoByRecipeID then
    local owner = T.GetProfessionInfoByRecipeID(liste[1])
    if owner and owner.professionName ~= metier and owner.parentProfessionName ~= metier then return nil, "liste pas à jour" end
  end
  if not liste or #liste == 0 then return nil, "liste vide", metier end -- TRADE_SKILL_LIST_UPDATE suivra
  local r = { metier = metier, rang = p.skillLevel, max = p.maxSkillLevel, connues = {}, recettes = {}, total = #liste, illisibles = 0 }
  for _, id in ipairs(liste) do
    -- une recette qui fait planter l'API ne doit pas faire perdre tout le métier
    local ok, err = pcall(function()
      local info = T.GetRecipeInfo(id)
      if not info or info.isDummyRecipe then return end
      local s = T.GetRecipeSchematic(id, false)
      local composants = {}
      for _, slot in ipairs(s and s.reagentSlotSchematics or {}) do
        local rg = slot.reagents and slot.reagents[1]
        local base = not Enum.CraftingReagentType or slot.reagentType == nil or slot.reagentType == Enum.CraftingReagentType.Basic
        if rg and base and slot.required ~= false then -- composants de base seulement (pas les optionnels)
          composants[#composants + 1] = { id = rg.itemID, currency = rg.currencyID, qty = slot.quantityRequired }
        end
      end
      r.recettes[id] = {
        profession = metier, name = info.name, output = s and s.outputItemID, reagents = composants,
        made_min = s and s.quantityMin, made_max = s and s.quantityMax ~= s.quantityMin and s.quantityMax or nil,
        enchant = info.isEnchantingRecipe or nil, icon = info.icon,
      }
      if info.learned then r.connues[id] = DIFFICULTE[info.relativeDifficulty] or info.relativeDifficulty or true end
    end)
    if not ok then r.illisibles, r.premiereErreur = r.illisibles + 1, r.premiereErreur or (id .. " : " .. tostring(err)) end
  end
  return r
end

-- Range un relevé de la fenêtre (r) dans metiers = { [métier] = { rank, max, known } } : sa liste prime ; une recette
-- connue qu'elle ne liste pas du tout (trouvée sans fenêtre) reste. Rend l'entrée du métier.
function lib:RangerRecettes(metiers, r)
  for id, v in pairs(metiers[r.metier] and metiers[r.metier].known or {}) do
    if type(id) == "number" and not r.recettes[id] then r.connues[id] = v end -- clé « Métier:Nom » : ancien relevé, pas reprise
  end
  metiers[r.metier] = { rank = r.rang, max = r.max, known = r.connues }
  return metiers[r.metier]
end

---------------------------------------------------------------------------------------------------
-- Relevé des recettes connues sans la fenêtre : sur Forever, IsPlayerSpell(ID du sort de la recette) dit vrai pour une
-- recette connue (idée vue dans Mastercraft, dont le code n'est pas repris). Pour chaque métier du personnage, interroge
-- les recettes candidates : celles déjà relevées (recettes = { [ID] = { profession, … } }) et la réserve Classic de
-- Handshake si elle est chargée. PAR_IMAGE par image, jamais en combat (reprise à PLAYER_REGEN_ENABLED). Fusionne dans
-- metiers = { [métier] = { rank, max, known } } : ajoute les connues qui manquent (true), ne retire rien, garde la
-- difficulté lue en fenêtre. fini() une fois tout interrogé.
local PAR_IMAGE = 60

function lib:ReleverRecettesSansFenetre(metiers, recettes, fini)
  if not (IsPlayerSpell and GetProfessions) then return nil, "API absente" end
  local miens = {}
  for _, index in pairs({ GetProfessions() }) do -- des index, avec des trous
    local nom, _, rang, max = GetProfessionInfo(index)
    if nom then miens[nom] = { rang, max } end
  end
  local file, vu = {}, {}
  local function candidate(id, metier)
    if type(id) == "number" and miens[metier] and not vu[id] then vu[id], file[#file + 1] = true, { id, metier } end
  end
  for id, rec in pairs(recettes or {}) do candidate(id, rec.profession) end
  -- ponytail: la réserve de Handshake nomme les métiers en français ; sur un client d'une autre langue elle ne sert pas.
  for id, c in pairs(HandshakeClassicRecipes or {}) do candidate(id, c[4]) end -- { objet, min, max, métier, … }
  local i = 0
  local function image()
    if InCombatLockdown() then
      self.reprise = image -- ponytail: un seul relevé en pause à la fois (il n'y en a qu'un par session)
      pcall(self.cadre.RegisterEvent, self.cadre, "PLAYER_REGEN_ENABLED")
      return
    end
    for _ = 1, PAR_IMAGE do
      i = i + 1
      local c = file[i]
      if not c then if fini then fini() end return end
      local ok, connue = pcall(IsPlayerSpell, c[1]) -- un ID que ce client ignore n'arrête pas le relevé
      if ok and connue then
        local m = metiers[c[2]] or { known = {} }
        metiers[c[2]], m.rank, m.max = m, miens[c[2]][1], miens[c[2]][2]
        m.known[c[1]] = m.known[c[1]] or true
      end
    end
    C_Timer.After(0, image)
  end
  image()
  return true
end

---------------------------------------------------------------------------------------------------
-- Relevé de repli (sans GameData) : en mémoire, dans la lib, jamais dans les SavedVariables de l'add-on hôte.
-- Gardé d'une mineure à l'autre : une copie plus récente reprend ce que la précédente a relevé.
lib.repli = lib.repli or { recettes = {}, metiers = {} }
lib.cadre = lib.cadre or CreateFrame("Frame")
pcall(lib.cadre.RegisterEvent, lib.cadre, "PLAYER_LOGIN") -- les sondes sont relancées à la connexion
-- Les événements de chaque type de repli (enregistrés à sa souscription).
local EVENEMENTS = {
  ["recettes connues"] = { "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" },
  inventaires = { "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED" },
}

-- Conteneurs d'Enum.BagIndex dont le nom passe le filtre (sacs, banque, onglets : ce que ce client a), lus à l'instant :
-- { [nom] = { size, items = { { id, count, link }, … } } } (même forme que GameData). Seule lecture des sacs : GameData,
-- le Négoce et Handshake passent par elle.
function lib.Conteneurs(garder)
  local out, vus = {}, {}
  for nom, sac in pairs(Enum.BagIndex or {}) do
    if garder(nom) and not vus[sac] then
      vus[sac] = true
      local taille = C_Container.GetContainerNumSlots(sac)
      if taille and taille > 0 then
        local items = {}
        for slot = 1, taille do
          local it = C_Container.GetContainerItemInfo(sac, slot)
          if it then items[#items + 1] = { id = it.itemID, count = it.stackCount, link = it.hyperlink } end
        end
        out[nom] = { size = taille, items = items }
      end
    end
  end
  return out
end
function lib.EstSac(n) return n == "Backpack" or n == "Keyring" or n == "ReagentBag" or n:find("^Bag_") ~= nil end
function lib.EstBanque(n) return n:find("[Bb]ank") ~= nil end

---------------------------------------------------------------------------------------------------
-- Signal « type relevé à nouveau ». Les rappels sont gardés d'une mineure à l'autre (lib.rappels) ; un rappel qui plante
-- ne prive pas les autres ni le relevé (erreur rendue au gestionnaire du jeu).
lib.rappels = lib.rappels or {}

function lib:QuandReleve(typeDeDonnees, fn)
  if not TYPES[typeDeDonnees] then return nil, "type inconnu" end
  self.rappels[typeDeDonnees] = self.rappels[typeDeDonnees] or {}
  table.insert(self.rappels[typeDeDonnees], fn)
  self.AccrocherGameData()
  pcall(self.cadre.RegisterEvent, self.cadre, "PLAYER_LOGIN") -- GameData chargé après l'add-on qui s'enregistre
  return true
end

function lib:Signaler(typeDeDonnees)
  for _, fn in ipairs(self.rappels[typeDeDonnees] or {}) do
    local ok, err = pcall(fn, typeDeDonnees)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

-- Relevés de GameData : il appelle GameDataAPI.marketScanned après chaque scan de l'HV. Une seule fois par session, toutes
-- mineures confondues (le crochet appelle la lib, donc sa mineure la plus récente).
-- ponytail: seul l'HV a un signal côté GameData ; les autres types relevés par lui ne signalent pas encore.
function lib.AccrocherGameData()
  if lib.accrocheGameData or not (GameDataAPI and GameDataAPI.marketScanned) then return end
  lib.accrocheGameData = true
  hooksecurefunc(GameDataAPI, "marketScanned", function() lib:Signaler("cours de l'HV") end)
end

local function releveDeRepli()
  local r = lib:ReleverRecettes()
  if not r then return end -- ponytail: « liste pas à jour » attend le TRADE_SKILL_LIST_UPDATE suivant, sans réessai minuté
  for cle, rec in pairs(r.recettes) do lib.repli.recettes[cle] = rec end
  lib:RangerRecettes(lib.repli.metiers, r)
  lib.repli.lot = lotDuJour()
  lib:Signaler("recettes connues")
end

local jeton, banqueOuverte = 0, false
lib.cadre:SetScript("OnEvent", function(_, evenement)
  if evenement == "PLAYER_LOGIN" then -- tous les add-ons sont chargés : GameData aussi, s'il est là
    lib.RelancerSondes() -- une sonde rouge prévient dès la connexion, même si aucun add-on n'a encore rien relevé
    lib.AccrocherGameData()
    if not lib.souscriptions["recettes connues"] then return end
  end
  if evenement == "PLAYER_REGEN_ENABLED" then -- fin du combat : le relevé sans fenêtre reprend (GameData compris)
    local reprise = lib.reprise
    lib.reprise = nil
    if reprise then reprise() end
    return
  end
  if evenement == "BANKFRAME_CLOSED" then banqueOuverte = false return end
  if evenement == "BANKFRAME_OPENED" or evenement == "PLAYERBANKSLOTS_CHANGED" then
    banqueOuverte = banqueOuverte or evenement == "BANKFRAME_OPENED"
    if banqueOuverte and not (GameDataAPI and GameDataAPI.inventaires) then -- GameData relève la banque pour tout le monde
      lib.repli.banque, lib.repli.lotBanque = lib.Conteneurs(lib.EstBanque), lotDuJour()
      lib:Signaler("inventaires")
    end
    return
  end
  if GameDataAPI and GameDataAPI.recettesConnues then return end -- GameData relève et sauvegarde pour tout le monde
  if evenement == "PLAYER_LOGIN" then
    C_Timer.After(5, function()
      lib:ReleverRecettesSansFenetre(lib.repli.metiers, lib.repli.recettes, function()
        lib.repli.lot = lotDuJour()
        lib:Signaler("recettes connues")
      end)
    end)
    return
  end
  jeton = jeton + 1 -- ces événements arrivent en rafale : un seul relevé, une demi-seconde après
  local mien = jeton
  C_Timer.After(0.5, function() if mien == jeton then pcall(releveDeRepli) end end)
end)

-- Les types souscrits pendant cette session : GameData les retient à la connexion (une souscription faite pendant le
-- chargement arrive avant que ses SavedVariables soient lues). Sans GameData, elle vaut le temps de la session.
lib.souscriptions = lib.souscriptions or {}

function lib:Souscrire(typeDeDonnees)
  local t = TYPES[typeDeDonnees]
  if not t then return nil, "type inconnu" end
  self.souscriptions[typeDeDonnees] = true
  if GameDataAPI and GameDataAPI.souscrire then GameDataAPI.souscrire(typeDeDonnees) end
  for _, e in ipairs(EVENEMENTS[typeDeDonnees] or {}) do pcall(self.cadre.RegisterEvent, self.cadre, e) end
  return true
end
-- ponytail: ancien nom, Handshake sur main appelle encore lib:Demander("recettes connues") ; à retirer après sa fusion.
lib.Demander = lib.Souscrire

function lib:Lire(typeDeDonnees, personnage)
  local t = TYPES[typeDeDonnees]
  if not t then return nil, "type inconnu" end
  local fournir = GameDataAPI and GameDataAPI[t.gamedata]
  local d, lot
  if fournir then d, lot = fournir() end -- lecture seule : ce sont les tables de GameData
  if self.LireParFournisseurs and self.fournisseurs[typeDeDonnees] then
    return self:LireParFournisseurs(typeDeDonnees, d, lot, fournir ~= nil)
  end
  if not fournir then
    local moi = monGUID()
    if not t.repli or (personnage and personnage ~= "tous" and personnage ~= moi) then return nil, "pas de GameData" end
    if typeDeDonnees == "inventaires" then
      d = { persos = { [moi] = { bags = lib.Conteneurs(lib.EstSac), bank = self.repli.banque } } }
      lot = { persos = { [moi] = self.repli.lotBanque or lotDuJour() } } -- ponytail: un lot pour les deux ; le moins frais (la banque)
    else
      if not next(self.repli.metiers) then return nil, "pas encore relevé" end
      d, lot = { recettes = self.repli.recettes, persos = { [moi] = self.repli.metiers } }, { persos = { [moi] = self.repli.lot } }
    end
  end
  if not t.parPerso then -- une seule table pour le joueur : personnage sans objet
    if type(d) ~= "table" or not next(d) then return nil, "pas encore relevé" end
    return d, lot or {} -- un GameData d'avant les lots n'en rend pas : lot vide
  end
  lot = { persos = lot and lot.persos or {} }
  if personnage ~= "tous" then
    local p = personnage or monGUID()
    if not d.persos[p] then return nil, "pas encore relevé" end
    local un = { persos = { [p] = d.persos[p] } }
    for k, v in pairs(d) do if k ~= "persos" then un[k] = v end end
    d, lot = un, { persos = { [p] = lot.persos[p] } }
  end
  if not next(d.persos) and not next(d.recettes or {}) then return nil, "pas encore relevé" end
  return d, lot
end

-- Prix d'achat (langage commun de l'atelier) : ce que coûtent qty objets, au moins cher entre les marchands et l'HV.
--   lib:PrixMarchands()                 : { [itemID] = prix unitaire } du marchand le moins cher, en stock illimité et
--                                         payé en or (lu une fois par calcul : la liste des marchands est refaite à chaque lecture).
--   lib:PrixAchat(id, qty, hv, marchands) : coût, source (« marchand » ou « HV »), partiel (l'HV n'en a pas assez : le
--                                         reste au dernier prix vu) ; nil si ni marchand ni HV. hv : table [itemID] -> ligne
--                                         des cours de l'HV (lue ici s'il manque) ; marchands : lib:PrixMarchands().
-- À l'HV : palier par palier au dernier scan, sinon le prix le plus bas d'un fournisseur sans paliers (Auctionator).
function lib:PrixMarchands()
  local best = {}
  for _, v in pairs((self:Lire("marchands")) or {}) do
    for _, it in ipairs(v.items or {}) do
      if it.id and it.price and it.price > 0 and not it.limited and not it.cost_items then
        local unit = it.price / math.max(1, it.stack or 1)
        if not best[it.id] or unit < best[it.id] then best[it.id] = unit end
      end
    end
  end
  return best
end

function lib:PrixAchat(id, qty, hv, marchands)
  local v = (marchands or self:PrixMarchands())[id]
  local m
  if hv then m = hv[id]
  else local d = self:Lire("cours de l'HV"); m = d and d.objet(id) end
  local ah, partiel
  if m and not m.tiers and m.min then
    ah, partiel = m.min * qty, m.qty ~= nil and m.qty < qty
  elseif m and m.tiers and #m.tiers > 0 then
    ah, partiel = 0, false
    local reste = qty
    for _, t in ipairs(m.tiers) do
      local pris = math.min(reste, t.qty)
      ah, reste = ah + pris * t.price, reste - pris
      if reste <= 0 then break end
    end
    if reste > 0 then -- plus que les paliers gardés : le reste au prix du dernier palier
      ah, partiel = ah + reste * m.tiers[#m.tiers].price, (m.qty or 0) < qty
    end
  end
  if v and (not ah or v * qty <= ah) then return v * qty, "marchand" end
  if ah then return ah, "HV", partiel end
end
