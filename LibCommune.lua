-- LibCommune : la lib commune embarquée des add-ons Azeroth Commune (modèle LibStub : la mineure la plus récente sert).
-- Du code seulement, jamais de données sauvegardées à elle (ADR 0001 de l'atelier : les données relevées ne sont
-- sauvegardées que dans GameData).
--
-- Accès aux données relevées, deux gestes :
--   lib:Demander(type)           : l'add-on déclare qu'il a besoin de ce type de données.
--   lib:Lire(type, personnage)   : les données, ou nil et la raison (« type inconnu », « pas de GameData »,
--                                  « pas encore relevé »). personnage = « Nom-Royaume » (sur Forever « Prénom Nom-Royaume »),
--                                  nil pour le personnage connecté, « tous » pour tous les personnages relevés.
-- Avec GameData, la lib lit sa base ; sans lui, relevé de repli : le personnage connecté, en mémoire, le temps de la session.
-- Le consommateur ne teste jamais lui-même la présence de GameData.
local MAJOR, MINOR = "LibCommune-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- une copie aussi récente est déjà chargée : c'est elle qui sert

-- Catalogue des types de données. léger : relevable sans GameData (relevé de repli) ; un type lourd (HV, catalogue des
-- objets) attendrait GameData ou un fournisseur. gamedata : la fonction de GameDataAPI qui rend ce type.
local TYPES = {
  -- { recettes = { [clé] = { profession, name, output, reagents, … } },
  --   persos = { [personnage] = { [métier] = { rank, max, known = { [clé] = difficulté, ou true sans fenêtre } } } } }
  ["recettes connues"] = { leger = true, gamedata = "recettesConnues" },
}

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
      if IsPlayerSpell(c[1]) then
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
    C_Timer.After(5, function() lib:ReleverRecettesSansFenetre(lib.repli.metiers, lib.repli.recettes) end)
    return
  end
  jeton = jeton + 1 -- ces événements arrivent en rafale : un seul relevé, une demi-seconde après
  local mien = jeton
  C_Timer.After(0.5, function() if mien == jeton then pcall(releveDeRepli) end end)
end)

-- ponytail: une demande vaut jusqu'à la fin de la session ; « plus personne ne demande ce type » viendra avec un 2e type.
function lib:Demander(typeDeDonnees)
  if not TYPES[typeDeDonnees] then return nil, "type inconnu" end
  for _, e in ipairs(EVENEMENTS) do pcall(self.cadre.RegisterEvent, self.cadre, e) end
  return true
end

function lib:Lire(typeDeDonnees, personnage)
  local t = TYPES[typeDeDonnees]
  if not t then return nil, "type inconnu" end
  local fournir = GameDataAPI and GameDataAPI[t.gamedata]
  local d
  if fournir then
    d = fournir() -- lecture seule : ce sont les tables de GameData
  else
    local moi = personnageConnecte()
    if not t.leger or (personnage and personnage ~= "tous" and personnage ~= moi) then return nil, "pas de GameData" end
    if not next(self.repli.metiers) then return nil, "pas encore relevé" end
    d = { recettes = self.repli.recettes, persos = { [moi] = self.repli.metiers } }
  end
  if personnage ~= "tous" then
    local p = personnage or personnageConnecte()
    if not d.persos[p] then return nil, "pas encore relevé" end
    d = { recettes = d.recettes, persos = { [p] = d.persos[p] } }
  end
  if not next(d.persos) and not next(d.recettes) then return nil, "pas encore relevé" end
  return d
end
