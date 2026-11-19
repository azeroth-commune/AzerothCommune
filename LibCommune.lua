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
local MAJOR, MINOR = "LibCommune-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- une copie aussi récente est déjà chargée : c'est elle qui sert

-- Catalogue des types de données. léger : relevable sans GameData (relevé de repli) ; un type lourd (HV, catalogue des
-- objets) attendrait GameData ou un fournisseur. gamedata : la fonction de GameDataAPI qui rend ce type.
local TYPES = {
  -- { recettes = { [clé] = { profession, name, output, reagents, … } },
  --   persos = { [personnage] = { [métier] = { rank, max, known = { [clé] = difficulté } } } } }
  ["recettes connues"] = { leger = true, gamedata = "recettesConnues" },
}

-- Même clé que GameData : sur Forever, UnitName("player") rend prénom et nom de famille.
local function personnageConnecte()
  local first, last = UnitName("player")
  return (last and (first .. " " .. last) or first) .. "-" .. GetRealmName()
end

function lib:Lire(typeDeDonnees, personnage)
  local t = TYPES[typeDeDonnees]
  if not t then return nil, "type inconnu" end
  local fournir = GameDataAPI and GameDataAPI[t.gamedata]
  local d = fournir and fournir() -- lecture seule : ce sont les tables de GameData
  if personnage ~= "tous" then
    local p = personnage or personnageConnecte()
    if not d.persos[p] then return nil, "pas encore relevé" end
    d = { recettes = d.recettes, persos = { [p] = d.persos[p] } }
  end
  if not next(d.persos) then return nil, "pas encore relevé" end
  return d
end
