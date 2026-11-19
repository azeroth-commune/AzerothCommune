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
print("LibCommune : GameData présent OK")

-- Type absent du catalogue : indisponible, avec sa raison.
d, raison = lib:Lire("cours de la bourse")
assert(d == nil and raison == "type inconnu", tostring(raison))
d, raison = lib:Demander("cours de la bourse")
assert(d == nil and raison == "type inconnu", tostring(raison))
print("LibCommune : type inconnu OK")

-- GameData absent : relevé de repli du personnage connecté, en mémoire ; rien n'est écrit chez l'hôte.
GameDataAPI = nil
HoteDB = { reglages = { x = 1 } } -- les SavedVariables de l'add-on hôte
local avant = {}
for k in pairs(_G) do avant[k] = true end
d, raison = lib:Lire("recettes connues")
assert(d == nil and raison == "pas encore relevé", "rien de relevé : " .. tostring(raison))
assert(lib:Demander("recettes connues"))
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
