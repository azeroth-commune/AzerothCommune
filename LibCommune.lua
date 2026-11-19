-- LibCommune : la lib commune embarquée des add-ons Azeroth Commune (modèle LibStub : la mineure la plus récente sert).
-- Du code seulement, jamais de données sauvegardées à elle (ADR 0001 de l'atelier : les données relevées ne sont
-- sauvegardées que dans GameData).
--
-- Accès aux données relevées, deux gestes :
--   lib:Souscrire(type)          : l'add-on souscrit à ce type de données (il en a besoin). Avec GameData, la souscription
--                                  vaut pour tous les personnages du joueur (GameData ne relève que les types souscrits, et
--                                  cesse après ~30 jours sans souscription) ; sans lui, elle vaut le temps de la session.
--   lib:Lire(type, personnage)   : les données et leur lot, ou nil et la raison (« type inconnu », « pas de GameData »,
--                                  « pas encore relevé », « pas de GameData ni de fournisseur »). personnage = « Nom-Royaume » (sur Forever « Prénom Nom-Royaume »),
--                                  nil pour le personnage connecté, « tous » pour tous les personnages relevés.
-- Lot : { provenance, build, version, date, perime } — d'où viennent les données (lib.provenances, du plus fiable au moins
-- fiable), le build du client (GetBuildInfo) et la date du relevé ; perime = true : figé sous un autre build, peut-être
-- périmé. Pour un type par personnage, le lot va aussi par personnage : { persos = { [personnage] = lot } }. Dans un lot
-- mixte (marchands : vus en jeu et base VendorData), une ligne d'une autre provenance porte la sienne (champ provenance).
-- Avec GameData, la lib lit sa base ; sans lui, relevé de repli : le personnage connecté, en mémoire, le temps de la session.
-- Un type qui a des fournisseurs (cours de l'HV : Auctionator, TSM, AuctionDB) passe aussi par eux (Fournisseurs.lua).
-- Le consommateur ne teste jamais lui-même la présence de GameData.
local MAJOR, MINOR = "LibCommune-1.0", 5
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- une copie aussi récente est déjà chargée : c'est elle qui sert

-- Catalogue des types de données (ceux que GameData relève). léger : relevable sans GameData, par un relevé de repli ;
-- un type lourd (HV, catalogue des objets) attend GameData ou un fournisseur. parPerso : les données vont par personnage
-- ({ persos = { [personnage] = … } }, filtrées par lib:Lire), sinon une seule table pour le joueur. gamedata : la
-- fonction de GameDataAPI qui rend ce type. repli : le relevé de repli est écrit (seulement les recettes connues).
local TYPES = {
  -- persos[p] = { character (fiche, or), equipped, bags, bank, mail, currencies }
  inventaires = { leger = true, parPerso = true, gamedata = "inventaires" },
  ["réputations"] = { leger = true, parPerso = true, gamedata = "reputations" }, -- persos[p] = { { id, name, standing, … } }
  ["métiers et compétences"] = { leger = true, parPerso = true, gamedata = "metiersEtCompetences" }, -- persos[p] = { professions, skills }
  ["quêtes terminées"] = { leger = true, parPerso = true, gamedata = "quetesTerminees" }, -- persos[p] = { questID, … }
  -- { recettes = { [clé] = { profession, name, output, reagents, … } },
  --   persos = { [personnage] = { [métier] = { rank, max, known = { [clé] = difficulté, ou true sans fenêtre } } } } }
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

-- Le lot d'un relevé fait maintenant (même forme que les lots de GameData).
local function lotDuJour()
  local version, build = GetBuildInfo()
  return { provenance = "relevé direct", build = tonumber(build), version = version, date = date("%Y-%m-%d %H:%M:%S") }
end

-- Même clé que GameData : sur Forever, UnitName("player") rend prénom et nom de famille.
local function personnageConnecte()
  local first, last = UnitName("player")
  return (last and (first .. " " .. last) or first) .. "-" .. GetRealmName()
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
local EVENEMENTS = { "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }

local function releveDeRepli()
  local r = lib:ReleverRecettes()
  if not r then return end -- ponytail: « liste pas à jour » attend le TRADE_SKILL_LIST_UPDATE suivant, sans réessai minuté
  for cle, rec in pairs(r.recettes) do lib.repli.recettes[cle] = rec end
  lib:RangerRecettes(lib.repli.metiers, r)
  lib.repli.lot = lotDuJour()
end

local jeton = 0
lib.cadre:SetScript("OnEvent", function(_, evenement)
  if evenement == "PLAYER_REGEN_ENABLED" then -- fin du combat : le relevé sans fenêtre reprend (GameData compris)
    local reprise = lib.reprise
    lib.reprise = nil
    if reprise then reprise() end
    return
  end
  if GameDataAPI and GameDataAPI.recettesConnues then return end -- GameData relève et sauvegarde pour tout le monde
  if evenement == "PLAYER_LOGIN" then
    C_Timer.After(5, function()
      lib:ReleverRecettesSansFenetre(lib.repli.metiers, lib.repli.recettes, function() lib.repli.lot = lotDuJour() end)
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
  if t.repli then for _, e in ipairs(EVENEMENTS) do pcall(self.cadre.RegisterEvent, self.cadre, e) end end
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
    local moi = personnageConnecte()
    if not t.repli or (personnage and personnage ~= "tous" and personnage ~= moi) then return nil, "pas de GameData" end
    if not next(self.repli.metiers) then return nil, "pas encore relevé" end
    d, lot = { recettes = self.repli.recettes, persos = { [moi] = self.repli.metiers } }, { persos = { [moi] = self.repli.lot } }
  end
  if not t.parPerso then -- une seule table pour le joueur : personnage sans objet
    if type(d) ~= "table" or not next(d) then return nil, "pas encore relevé" end
    return d, lot or {} -- un GameData d'avant les lots n'en rend pas : lot vide
  end
  lot = { persos = lot and lot.persos or {} }
  if personnage ~= "tous" then
    local p = personnage or personnageConnecte()
    if not d.persos[p] then return nil, "pas encore relevé" end
    local un = { persos = { [p] = d.persos[p] } }
    for k, v in pairs(d) do if k ~= "persos" then un[k] = v end end
    d, lot = un, { persos = { [p] = lot.persos[p] } }
  end
  if not next(d.persos) and not next(d.recettes or {}) then return nil, "pas encore relevé" end
  return d, lot
end
