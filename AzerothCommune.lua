-- Azeroth Commune, le socle (ADR 0002 de l'atelier) : GameData et la lib commune fondus en un seul add-on, requis par
-- tous les autres. Son API publique est le global AzerothCommune (ce fichier le crée, les autres fichiers du socle le
-- complètent) ; l'intérieur de l'ex-GameData (scans, rangement en base) reste dans l'espace de noms privé, ns.
--
-- Accès aux données relevées, deux gestes :
--   AC:Souscrire(type)           : l'add-on souscrit à ce type de données (il en a besoin). La souscription vaut pour tous
--                                  les personnages du joueur (le socle ne relève que les types souscrits, et cesse après
--                                  ~30 jours sans souscription).
--   AC:Lire(type, personnage)    : les données et leur lot, ou nil et la raison (« type inconnu », « pas encore relevé »).
--                                  personnage = son GUID, nil pour le personnage connecté, « tous » pour tous les
--                                  personnages relevés.
-- Lot : { provenance, build, version, date, perime } — d'où viennent les données (AC.provenances, du plus fiable au moins
-- fiable), le build du client (GetBuildInfo) et la date du relevé ; perime = true : figé sous un autre build, peut-être
-- périmé. Pour un type par personnage, le lot va aussi par personnage : { persos = { [GUID] = lot } }. Dans un lot
-- mixte (marchands : vus en jeu et base VendorData), une ligne d'une autre provenance porte la sienne (champ provenance).
-- Un seul chemin par type : la lecture passe par l'accesseur privé de la base (ns.lire[type] : Souscriptions.lua,
-- Commerce.lua).
-- Un type qui a des fournisseurs (cours de l'HV : Auctionator, TSM, AuctionDB) passe aussi par eux (Fournisseurs.lua).
--   AC:QuandReleve(type, fn)     : fn(type) après chaque nouveau relevé de ce type (ex. scan de l'HV terminé).
-- Personnage : AC.Personnage(guid) = { guid, nom } ; AC.Destinataire(nom) (« Prénom Nom », pour un chuchotement).
-- Prix d'achat : AC:PrixAchat(id, qty, hv, marchands), AC:PrixMarchands() (en fin de fichier).
-- Recherche d'objets : AC.ChercherObjets(texte, max) parmi les objets (relevés, puis le catalogue extrait du client) et les
-- objets fabriqués de la base des recettes (Interface.lua) ; l'add-on qui cherche souscrit à « objets » et à « base des recettes ».
-- Identité, chaque relevé sondé : AC.Royaume() (le numéro de serveur du GUID, « 6942 »), AC.MaisonHV() (« 6942-Alliance »,
-- clé des scans de l'HV), AC.Faction(), AC.Build() (nombre).
-- Sondes : AC.Sondes() = l'état de chacune (vert, rouge, pas encore vue ; valeur reçue, heure, build) ;
-- AC.RelancerSondes() refait les relevés sans contexte (aussi à la connexion). Une sonde rouge prévient dans le chat, ne corrige rien.
-- Sondés aussi : sacs (AC.Conteneurs), recettes (fenêtre ouverte), noms d'objets (Interface.lua), fournisseurs de prix
-- (Fournisseurs.lua) ; ceux qui demandent un contexte restent « pas encore vue » tant qu'il ne s'est pas présenté.
-- Pour les autres fichiers du socle : AC.DeclarerSonde(nom, attente, verifier, relever), AC.Sonder(nom, ...).
-- Le global ne porte rien d'autre que l'API publique et des champs documentés à côté de leur code : les relevés de
-- recettes (AC:ReleverRecettes, AC:RangerRecettes, AC:ReleverRecettesSansFenetre, ci-dessous), AC:Signaler, les
-- fournisseurs (AC.fournisseurs, AC:LireParFournisseurs, AC:ChampsARelever : Fournisseurs.lua), AC.regroupes
-- (Regroupement.lua), AC.captureDansLesFenetres (posé par un add-on : Interface.lua). Cadres et états de session (état des
-- sondes, rappels, bouton de minicarte, entrée des options) sont privés : ns ou locaux (#45).
local _, ns = ...
AzerothCommune = {}
local lib = AzerothCommune

-- Catalogue des types de données (ceux que la base relève). parPerso : les données vont par personnage
-- ({ persos = { [GUID] = … } }, filtrées par lib:Lire), sinon une seule table pour le joueur.
local TYPES = {
  inventaires = { parPerso = true }, -- persos[p] = { character (fiche, or), equipped, bags, bank, mail, currencies }
  ["réputations"] = { parPerso = true }, -- persos[p] = { { id, name, standing, … } }
  ["métiers et compétences"] = { parPerso = true }, -- persos[p] = { professions, skills }
  ["quêtes terminées"] = { parPerso = true }, -- persos[p] = { questID, … }
  -- { recettes = { [clé] = { profession, name, output, reagents, … } },
  --   persos = { [GUID] = { [métier] = { rank, max, known = { [clé] = difficulté, ou true sans fenêtre } } } } }
  ["recettes connues"] = { parPerso = true },
  -- Tout ce que fabrique une recette, connue ou non : { [clé] = { profession, name, output (nil : enchantement), reagents,
  --   made_min, made_max, level (compétence pour l'apprendre, de la réserve), yellow, grey (seuils du client, de la
  --   réserve), source, source_provenance, pattern_price, cooldown (de la réserve, #64), condition (de la réserve, #67 :
  --   « spécialisation : travail du cuir tribal », « réputation : Aube d'argent » ou « plus enseignée » ; nil quand la
  --   recette n'en demande aucune : une recette à condition n'est pas apprenable par qui ne l'a pas), provenance } }. Les recettes vues
  --   sur tous les persos (relevé direct), la réserve extraite du client (champ provenance) pour les objets qu'aucune
  --   recette vue ne fabrique (Commerce.lua). Les maîtres de métier relevés passent devant les deux (#72) : une recette
  --   qu'un maître enseigne (rapprochée par l'objet enseigné, sinon par le nom, dans le métier du service) prend sa
  --   compétence demandée en level, source « maître », source_provenance « relevé direct » et prix_maitre (cuivre) ;
  --   les autres gardent les valeurs de la réserve.
  ["base des recettes"] = {},
  ["maîtres de métier"] = {}, -- { [PNJ] = { services, filters, … } }
  marchands = {}, -- { [PNJ] = { items = { { id, price, stack, limited }, … } } }
  ["prix des vols"] = {}, -- { [départ] = { [arrivée] = prix } }
  ["add-ons installés"] = {}, -- { [dossier] = { title, version, … } }
  -- { objet = fn(itemID) -> { min, qty, auctions, tiers, hist, sources }, depot = { rate24, min }, hv = le relevé de
  --   la base ({ [royaume-faction] = { items, hist, … } } ; hist absent quand AuctionDB le tient) } : le scan du
  --   socle fait foi, les fournisseurs pour l'historique et quand le socle n'a pas scanné l'HV (Fournisseurs.lua)
  ["cours de l'HV"] = {},
  -- { [itemID] = { name, class, price, stack, quality, … } } : les objets relevés, puis le catalogue des objets extrait du
  --   client (CatalogueObjets.lua : name, quality, champ provenance) pour les autres (Souscriptions.lua).
  objets = {},
}
lib.types = TYPES -- lecture seule
-- Les accesseurs privés de la base, un par type : ns.lire[type]() rend les données et leur lot (Souscriptions.lua,
-- Commerce.lua). Lecture seule : ce sont les tables de la base.
ns.lire = {}

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
ns.sondes = {} -- [nom] = { etat, valeur, heure, build, prevenu } ; privé (lu par lib.Sondes)
local SONDES = {} -- { { nom, attente, verifier, relever }, … } dans l'ordre de déclaration, et [nom] = la même

local function montrer(v)
  if type(v) == "string" then return ("%q"):format(v) end
  if type(v) ~= "table" or not v.n then return tostring(v) end -- une table rendue par le jeu : pas plusieurs retours
  local t = {}
  for i = 1, v.n do t[i] = montrer(v[i]) end
  return table.concat(t, ", ")
end

-- Le build noté dans l'état des sondes : il ne change pas pendant une session, lu une seule fois (ns.buildLu ;
-- check.lua le remet à nil pour simuler une mise à jour du jeu).
-- ponytail: GetBuildInfo est toujours là en jeu ; le garde sert aux check.lua des add-ons qui ne le bouchonnent pas.
local function buildDeSession()
  if ns.buildLu == nil and GetBuildInfo then ns.buildLu = select(2, GetBuildInfo()) end
  return ns.buildLu
end

-- Vérifie la sonde nom sur ce que le jeu vient de rendre (...) et rend ... tel quel.
local function sonder(nom, ...)
  local s = SONDES[nom]
  if not s then return ... end -- pas déclarée : jamais d'erreur dans un relevé
  local r = ns.sondes[nom] or {}
  ns.sondes[nom] = r
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
lib.Sonder = sonder

-- Déclare une sonde. relever() refait son relevé (qui la sonde) pour RelancerSondes ; nil pour une sonde qui demande un
-- contexte (fenêtre de métier ouverte, fournisseur présent…) : elle reste « pas encore vue » tant qu'il ne s'est pas présenté.
function lib.DeclarerSonde(nom, attente, verifier, relever)
  local s = SONDES[nom]
  if not s then s = {}; SONDES[#SONDES + 1], SONDES[nom] = s, s end
  s.nom, s.attente, s.verifier, s.relever = nom, attente, verifier, relever
end

-- Déclare un relevé sondé sans contexte : appel() lit le jeu ; rend la fonction qui relève et sonde.
local function releve(nom, attente, verifier, appel)
  local relever = function() return sonder(nom, appel()) end
  lib.DeclarerSonde(nom, attente, verifier, relever)
  return relever
end

-- { { nom, attente, etat = "vert" | "rouge" | "pas encore vue", valeur, heure, build }, … } dans l'ordre de déclaration,
-- aussi rangées par nom. valeur : ce que le jeu a rendu ({ n, … } pour plusieurs retours) ; heure « HH:MM:SS ».
function lib.Sondes()
  local out = {}
  for i, s in ipairs(SONDES) do
    local r = ns.sondes[s.nom] or {}
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

-- Le royaume : le numéro de serveur du GUID du personnage connecté (« Player-6942-… » -> « 6942 », LibCommune#35). Depuis
-- le build 71037, GetRealmName et GetNormalizedRealmName rendent "" ; le GUID, fourni par le serveur, reste. Un numéro 0
-- (ou pas de GUID : nil) est rendu tel quel, la sonde le dit.
lib.Royaume = releve("royaume", "UnitGUID(\"player\") porte un numéro de serveur différent de 0 (Player-<n°>-…)",
  function(n) return tonumber(n) ~= nil and tonumber(n) ~= 0 end,
  function() return (tostring(UnitGUID("player")):match("^Player%-(%d+)%-")) end)

-- La faction du personnage connecté, « Alliance » ou « Horde ».
lib.Faction = releve("faction", "UnitFactionGroup(\"player\") rend Alliance ou Horde",
  function(f) return f == "Alliance" or f == "Horde" end, function() return (UnitFactionGroup("player")) end)

-- La maison de l'HV du personnage connecté, « royaume-faction » (« 6942-Alliance ») : la clé des scans de l'HV de
-- la base ; nil si la faction ou le royaume est inconnu. Les scans rangés sous l'ancienne clé (royaume affiché) ne sont
-- plus lus : ils se refont.
lib.MaisonHV = releve("maison de l'HV", "la maison de l'HV est « n° de serveur-faction », n° différent de 0, faction Alliance ou Horde",
  function(m) return type(m) == "string" and (m:match("^[1-9]%d*%-Alliance$") or m:match("^[1-9]%d*%-Horde$")) ~= nil end,
  function() local f, r = lib.Faction(), lib.Royaume() return f and r and (r .. "-" .. f) end)

-- Le GUID du personnage connecté, et son prénom et nom de famille (Forever : le 2e retour de UnitName est le nom de famille).
local monGUID = releve("GUID", "UnitGUID(\"player\") est de la forme Player-…",
  function(g) return type(g) == "string" and g:find("^Player%-") ~= nil end, function() return UnitGUID("player") end)
local monNom = releve("nom", "UnitName(\"player\") rend un prénom puis un nom de famille (Forever)",
  function(prenom, nom) return nonVide(prenom) and nonVide(nom) end, function() return UnitName("player") end)

---------------------------------------------------------------------------------------------------
-- Personnage (CONTEXT-MAP de l'atelier) : identifié par son GUID (UnitGUID), unique, fourni par le serveur, qui survit à
-- un renommage ; son nom, « Prénom Nom » sur Forever, sert à l'afficher et à lui chuchoter (LibCommune#35).
-- Sur Forever, le 2e retour de UnitName, UnitFullName et GetUnitName(unité, true) est le NOM DE FAMILLE, pas le royaume
-- (/handshake noms en jeu, 20/11/2026).

-- À qui adresser un chuchotement : « Prénom Nom », la forme que le serveur accepte et qu'il donne comme expéditeur d'un
-- message d'add-on (au prénom seul : « Aucun joueur nommé 'Belegard' », 21/11/2026). Un « -Royaume » est retiré : Forever
-- le lit comme un nom de famille (« Aucun joueur nommé 'Testeur CAMWOWEU4Realm8PvP' », 18/11/2026). Un nom illisible est
-- rendu tel quel.
function lib.Destinataire(nom)
  if type(nom) ~= "string" then return nom end
  return nom:match("^([^%-]+)%-[^%-]+$") or nom
end

-- { guid, nom } du personnage connecté (guid nil ou le sien), ou d'un personnage du joueur dont la base a la fiche
-- (écrite à chaque connexion de ce personnage) ; nil sinon.
-- ponytail: pas de GetPlayerInfoByGUID pour un autre joueur (forme de ses retours pas relevée sur Forever) ; à ajouter
-- quand un add-on aura besoin du nom d'un autre joueur par son GUID.
function lib.Personnage(guid)
  local moi = monGUID()
  if guid == nil or guid == moi then
    local prenom, nomDeFamille = monNom()
    return { guid = moi, nom = (nomDeFamille and nomDeFamille ~= "") and (prenom .. " " .. nomDeFamille) or prenom }
  end
  return ns.personnage(guid)
end

---------------------------------------------------------------------------------------------------
-- Relevé des recettes connues, dans la fenêtre de métier ouverte (API moderne C_TradeSkillUI de Forever) : toutes
-- les recettes du métier, apprises ou non, avec produit et composants. La base sauvegarde ce qu'il rend. Rend { metier,
-- rang, max, connues = { [clé] = difficulté }, recettes = { [clé] = … }, total, illisibles, premiereErreur }, ou nil,
-- raison (et le métier pour « liste vide »).
local DIFFICULTE = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" } -- Enum.TradeskillRelativeDifficulty

-- Sonde : la fiche de la première recette lisible (relevé en masse) a un nom, un produit (sauf un enchantement) et des
-- composants. Fenêtre de métier ouverte : pas de relevé sans contexte, RelancerSondes la saute.
-- ponytail: une liste vide n'est pas rouge : c'est l'état passager juste après l'ouverture (TRADE_SKILL_LIST_UPDATE
-- suit) ; une liste toujours vide ne se verrait qu'à « pas encore vue ». La sonder si ce cas arrive.
lib.DeclarerSonde("recettes", "la fiche d'une recette (GetRecipeInfo, GetRecipeSchematic) porte un nom, un produit (sauf un enchantement) et ses composants",
  function(nom, produit, composants, enchant)
    return nonVide(nom) and (type(produit) == "number" or enchant == true) and type(composants) == "number" and composants > 0
  end)

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
  local sondee = false
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
      if not sondee then
        sondee = true
        sonder("recettes", info.name, s and s.outputItemID, #composants, info.isEnchantingRecipe)
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
-- les recettes candidates (recettes = { [ID] = { profession, … } } : la base passe les recettes vues et la réserve,
-- Commerce.lua). PAR_IMAGE par image, jamais en combat (reprise à la fin du combat). Fusionne dans
-- metiers = { [métier] = { rank, max, known } } : ajoute les connues qui manquent (true), ne retire rien, garde la
-- difficulté lue en fenêtre. fini() une fois tout interrogé.
local PAR_IMAGE = 60
-- Le cadre du socle : à la connexion (tous les add-ons chargés), les sondes sont relancées, une sonde rouge prévient
-- tout de suite ; à la fin d'un combat, le relevé sans fenêtre en pause reprend.
local cadre, reprise = CreateFrame("Frame"), nil
pcall(cadre.RegisterEvent, cadre, "PLAYER_LOGIN")
cadre:SetScript("OnEvent", function(_, evenement)
  if evenement == "PLAYER_LOGIN" then lib.RelancerSondes() return end
  local r = reprise -- PLAYER_REGEN_ENABLED
  reprise = nil
  if r then r() end
end)

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
  -- ponytail: un métier se reconnaît à son nom ; une recette sous un nom d'une autre langue que le client ne sert pas.
  for id, rec in pairs(recettes or {}) do candidate(id, type(rec) == "table" and rec.profession) end
  local i = 0
  local function image()
    if InCombatLockdown() then
      reprise = image -- ponytail: un seul relevé en pause à la fois (il n'y en a qu'un par session)
      pcall(cadre.RegisterEvent, cadre, "PLAYER_REGEN_ENABLED")
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
-- Conteneurs d'Enum.BagIndex dont le nom passe le filtre (sacs, banque, onglets : ce que ce client a), lus à l'instant :
-- { [nom] = { size, items = { { id, count, link }, … } } }. Seule lecture des sacs : la base, le Négoce et Handshake
-- passent par elle. Sondes : le premier conteneur lu et le premier objet vu (relevé en masse).
lib.DeclarerSonde("emplacements d'un conteneur", "C_Container.GetContainerNumSlots(sac) rend un nombre d'emplacements",
  function(n) return type(n) == "number" end, function() lib.Conteneurs(lib.EstSac) end)
lib.DeclarerSonde("objet d'un conteneur", "C_Container.GetContainerItemInfo rend, pour un objet présent, son itemID et son lien",
  function(id, lien) return type(id) == "number" and type(lien) == "string" and lien:match("item:(%d+)") == tostring(id) end,
  function() lib.Conteneurs(lib.EstSac) end)

function lib.Conteneurs(garder)
  local out, vus, sondeTaille, sondeObjet = {}, {}, true, true
  for nom, sac in pairs(Enum.BagIndex or {}) do
    if garder(nom) and not vus[sac] then
      vus[sac] = true
      local taille = C_Container.GetContainerNumSlots(sac)
      if sondeTaille then sondeTaille = false; sonder("emplacements d'un conteneur", taille) end
      if taille and taille > 0 then
        local items = {}
        for slot = 1, taille do
          local it = C_Container.GetContainerItemInfo(sac, slot)
          if it then
            if sondeObjet then sondeObjet = false; sonder("objet d'un conteneur", it.itemID, it.hyperlink) end
            items[#items + 1] = { id = it.itemID, count = it.stackCount, link = it.hyperlink }
          end
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
-- Signal « type relevé à nouveau », appelé par le relevé lui-même (Commerce.lua, après chaque scan de l'HV). Un rappel
-- qui plante ne prive pas les autres ni le relevé (erreur rendue au gestionnaire du jeu).
-- ponytail: seul l'HV signale ; un autre type appellera lib:Signaler au bout de son relevé quand un add-on en aura besoin.
ns.rappels = {} -- [type] = { fn, … }

function lib:QuandReleve(typeDeDonnees, fn)
  if not TYPES[typeDeDonnees] then return nil, "type inconnu" end
  ns.rappels[typeDeDonnees] = ns.rappels[typeDeDonnees] or {}
  table.insert(ns.rappels[typeDeDonnees], fn)
  return true
end

function lib:Signaler(typeDeDonnees)
  for _, fn in ipairs(ns.rappels[typeDeDonnees] or {}) do
    local ok, err = pcall(fn, typeDeDonnees)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

-- La souscription est tenue par la base seule (Souscriptions.lua : AzerothCommuneDB.souscriptions, avec sa date). Avant
-- que la base soit chargée (un add-on sans « ## Dependencies: AzerothCommune ») : refusée, un avertissement par session.
local prevenuTropTot = false
function lib:Souscrire(typeDeDonnees)
  if not TYPES[typeDeDonnees] then return nil, "type inconnu" end
  if not AzerothCommuneDB then
    if not prevenuTropTot then
      prevenuTropTot = true
      local pile = debugstack and debugstack(2, 1, 0) -- la ligne de l'appelant ; jamais d'erreur si elle manque
      local addon = type(pile) == "string" and pile:match("[Aa]dd[Oo]ns[/\\]([^/\\]+)[/\\]")
      print(("Azeroth Commune : %s a souscrit à « %s » avant le chargement du socle ; souscription perdue. Son TOC doit déclarer « ## Dependencies: AzerothCommune »."):format(
        addon and ("l'add-on " .. addon) or "un add-on", typeDeDonnees))
    end
    return nil, "socle pas chargé"
  end
  ns.souscrire(typeDeDonnees)
  return true
end

function lib:Lire(typeDeDonnees, personnage)
  local t = TYPES[typeDeDonnees]
  if not t then return nil, "type inconnu" end
  local d, lot = ns.lire[typeDeDonnees]()
  if self.fournisseurs[typeDeDonnees] then return self:LireParFournisseurs(typeDeDonnees, d, lot) end
  if type(d) ~= "table" then return nil, "pas encore relevé" end
  if not t.parPerso then -- une seule table pour le joueur : personnage sans objet
    if not next(d) then return nil, "pas encore relevé" end
    return d, lot or {} -- une base sans lot pour ce type : lot vide
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
