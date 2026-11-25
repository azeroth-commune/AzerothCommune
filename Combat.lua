-- L'état de combat, lu par le socle (ADR 0003 de l'atelier, #98) : un add-on suit une lecture nommée, le socle n'écoute
-- le jeu que pour les lectures suivies, rappelle l'add-on à chaque changement et sonde chaque lecture. Rien n'est gardé
-- au-delà de la session.
--   AC:Suivre(lecture, fn)      : fn(valeur) tout de suite, puis à chaque changement ; true, ou false et la raison
--                                 (« lecture inconnue », « pas une fonction »). La même fn suivie deux fois : inscrite une fois.
--   AC:NePlusSuivre(lecture, fn) : fn n'est plus rappelé ; le dernier suiveur parti, le socle cesse d'écouter le jeu.
-- valeur : nil = inconnu, jamais « non » ; une valeur secrète passe telle quelle, pour l'affichage seulement (la portée,
-- calculée, n'en rend jamais : une réponse secrète y donne nil).
local lib = AzerothCommune

local TIR, MELEE = 2, 0 -- Enum.PlayerSwingType.Ranged, .MainHand
local COUPURE_D_AILES, TIR_AUTOMATIQUE = 2974, 75 -- par leur ID : la langue du client n'y fait rien

-- Une réponse du jeu : true ou false, sinon nil (fonction absente, erreur, secret, autre chose) ; puis ce qu'en note la
-- sonde : la réponse elle-même, « absente », « secret » ou « erreur : … » (jamais une valeur secrète, qu'aucun calcul ne
-- doit toucher).
local function demander(fn, ...)
  if not fn then return nil, "absente" end
  local ok, v = pcall(fn, ...)
  if not ok then return nil, "erreur : " .. tostring(v) end
  if issecretvalue and issecretvalue(v) then return nil, "secret" end
  if type(v) ~= "boolean" then return nil, v end
  return v, v
end

local function ouiNonOuNil(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v ~= nil and type(v) ~= "boolean" then return false end
  end
  return true
end

-- Portée de la cible : « tir », « zone morte », « mêlée », « trop loin » ou nil. Le test de portée natif du swing timer
-- d'abord, pour la mêlée et pour le tir ; replis quand il ne dit rien : Coupure d'ailes pour la mêlée (jamais l'Attaque du
-- raptor, qui répond « à portée » à distance de tir), le Tir automatique pour le tir. Ni mêlée ni tir : à moins de 28 m
-- (test « suivre »), c'est la zone morte ; au-delà, la cible est trop loin pour le tir aussi. Tout est lu à chaque fois
-- pour la sonde, qui note les sept réponses dans l'ordre de son attente.
local function portee()
  local natif, sorts = C_SwingTimer or {}, C_Spell or {}
  local cible, a = demander(UnitExists, "target")
  local attaquable, b = demander(UnitCanAttack, "player", "target")
  local melee, c = demander(natif.IsTargetWithinSwingRange, MELEE)
  local tir, d = demander(natif.IsTargetWithinSwingRange, TIR)
  local coupure, e = demander(sorts.IsSpellInRange, COUPURE_D_AILES, "target")
  local tirAuto, f = demander(sorts.IsSpellInRange, TIR_AUTOMATIQUE, "target")
  local proche, g = demander(CheckInteractDistance, "target", 4)
  lib.Sonder("portée", a, b, c, d, e, f, g)
  if not (cible and attaquable) then return nil end
  if melee == nil then melee = coupure end
  if tir == nil then tir = tirAuto end
  if melee then return "mêlée" end
  if tir then return "tir" end
  if melee == false and tir == false and proche ~= nil then return proche and "zone morte" or "trop loin" end
end
lib.DeclarerSonde("portée",
  "sur la cible, UnitExists, UnitCanAttack, la portée native de la mêlée puis du tir (C_SwingTimer), celles de Coupure d'ailes "
    .. "puis du Tir automatique, et le test « suivre » (28 m) rendent oui, non ou nil : ni absents, ni secrets, ni en erreur",
  ouiNonOuNil, function() portee() end)

local LECTURES = {
  ["portée"] = {
    lire = portee,
    evenements = { "PLAYER_SWING_RANGE_UPDATE", "PLAYER_TARGET_CHANGED" },
    periode = 0.2, -- secondes : les replis et le test « suivre » n'ont pas d'événement, relus tant que la portée est suivie
    -- Le test de portée natif ne répond qu'une fois activé : à chaque Suivre et à chaque changement de cible (la barre de
    -- swing du jeu ou un autre add-on a pu le couper). Jamais désactivé : la barre de swing du jeu s'en sert aussi.
    demarrer = function()
      local natif = C_SwingTimer
      if not (natif and natif.EnableRangeCheck) then return end
      pcall(natif.EnableRangeCheck, TIR, true)
      pcall(natif.EnableRangeCheck, MELEE, true)
    end,
  },
}

local suivis = {} -- [lecture] = { fn, …, valeur = la dernière rendue, relecture = son C_Timer }
local cadre = CreateFrame("Frame")

local function rappeler(fn, valeur)
  local ok, err = pcall(fn, valeur)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function relire(lecture)
  local s = suivis[lecture]
  local v = LECTURES[lecture].lire()
  -- ponytail: comparée telle quelle ; une lecture qui rendra une valeur secrète (qu'aucun calcul ne doit toucher, pas même
  -- ==) rappellera à chaque relecture, sans comparer.
  if v == s.valeur then return end
  s.valeur = v
  -- Sur une copie : un suiveur qui part (ou arrive) pendant un rappel ne fait sauter (ni rappeler deux fois) personne.
  for _, fn in ipairs({ unpack(s) }) do rappeler(fn, v) end
end

-- ponytail: tout événement relit toutes les lectures suivies (une relecture sans changement ne rappelle personne).
cadre:SetScript("OnEvent", function(_, ev)
  for lecture in pairs(suivis) do
    local l = LECTURES[lecture]
    if ev == "PLAYER_TARGET_CHANGED" and l.demarrer then l.demarrer() end
    relire(lecture)
  end
end)

function lib:Suivre(lecture, fn)
  local l = LECTURES[lecture]
  if not l then return false, "lecture inconnue" end
  if type(fn) ~= "function" then return false, "pas une fonction" end
  local s = suivis[lecture]
  if not s then
    for _, ev in ipairs(l.evenements) do pcall(cadre.RegisterEvent, cadre, ev) end -- un événement que ce client n'a pas : sauté
    s = {}
    suivis[lecture] = s
    if l.periode then s.relecture = C_Timer.NewTicker(l.periode, function() relire(lecture) end) end
  end
  if l.demarrer then l.demarrer() end
  -- Relue à chaque Suivre, pas rendue du cache : le nouveau suiveur a la valeur du moment (et les autres, si elle a changé).
  relire(lecture)
  local deja = false
  for _, f in ipairs(s) do if f == fn then deja = true end end
  if not deja then s[#s + 1] = fn end
  rappeler(fn, s.valeur)
  return true
end

function lib:NePlusSuivre(lecture, fn)
  local l = LECTURES[lecture]
  if not l then return false, "lecture inconnue" end
  local s = suivis[lecture]
  if not s then return true end
  for i = #s, 1, -1 do if s[i] == fn then table.remove(s, i) break end end
  if #s == 0 then
    -- ponytail: une seule lecture ; quand deux écouteront le même événement, ne le retirer que si plus aucune lecture
    -- suivie ne l'écoute.
    for _, ev in ipairs(l.evenements) do pcall(cadre.UnregisterEvent, cadre, ev) end
    if s.relecture then s.relecture:Cancel() end
    suivis[lecture] = nil
  end
  return true
end
