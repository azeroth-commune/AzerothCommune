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
