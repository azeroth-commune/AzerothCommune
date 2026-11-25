-- L'état de combat, lu par le socle (ADR 0003 de l'atelier, #98) : un add-on suit une lecture nommée, le socle n'écoute
-- le jeu que pour les lectures suivies, rappelle l'add-on à chaque changement et sonde chaque lecture. Rien n'est gardé
-- au-delà de la session.
--   AC:Suivre(lecture, fn)      : fn(valeur) tout de suite, puis à chaque changement ; true, ou false et la raison
--                                 (« lecture inconnue », « pas une fonction »). La même fn suivie deux fois : inscrite une fois.
--   AC:NePlusSuivre(lecture, fn) : fn n'est plus rappelé ; le dernier suiveur parti, le socle cesse d'écouter le jeu.
-- valeur : nil = inconnu, jamais « non » ; une valeur secrète passe telle quelle, pour l'affichage seulement (la portée
-- et le familier, calculés, n'en rendent jamais : une réponse secrète y donne nil). Une table rendue est partagée entre
-- les suiveurs : la lire, jamais la modifier.
local lib = AzerothCommune

local TIR, MELEE = 2, 0 -- Enum.PlayerSwingType.Ranged, .MainHand
local COUPURE_D_AILES, TIR_AUTOMATIQUE = 2974, 75 -- par leur ID : la langue du client n'y fait rien

-- brut : la première réponse du jeu, nil si absente, en erreur ou secrète ; demander : la même, true ou false, sinon nil (fonction absente, erreur, secret, autre chose) ; puis ce qu'en note la
-- sonde : la réponse elle-même, « absente », « secret » ou « erreur : … » (jamais une valeur secrète, qu'aucun calcul ne
-- doit toucher).
local function brut(fn, ...)
  if not fn then return nil, "absente" end
  local ok, v = pcall(fn, ...)
  if not ok then return nil, "erreur : " .. tostring(v) end
  if issecretvalue and issecretvalue(v) then return nil, "secret" end
  return v, v
end
local function demander(fn, ...)
  local v, note = brut(fn, ...)
  if type(v) ~= "boolean" then return nil, note end
  return v, note
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

-- Le familier : { present, mort, humeur, nourritures }, nil quand le jeu ne dit pas s'il est là. present : UnitExists ;
-- mort (UnitIsDead) seulement s'il est là (absent, il peut être renvoyé ou mort sans corps : le jeu ne le dit pas) ;
-- humeur 1 (mécontent), 2 (content), 3 (heureux) ; nourritures : les types qu'il mange, noms du client (« Viande »…).
-- Chaque champ nil quand sa réponse ne tranche pas (secrète, en erreur, hors de ce qu'on attend). La sonde note les
-- quatre réponses ; les types en { n, … } pour se lire dans Diagnostic.
local function familier()
  local pet = C_PetInfo or {}
  local present, a = demander(UnitExists, "pet")
  local mort, b = demander(UnitIsDead, "pet")
  local humeur, c = brut(pet.GetPetHappiness)
  local types, d = brut(pet.GetPetFoodTypes)
  local nourritures
  if type(types) == "table" then
    nourritures, d = {}, { n = #types }
    for i, t in ipairs(types) do
      if issecretvalue and issecretvalue(t) then t = "secret" end
      d[i] = t
      if type(t) ~= "string" or t == "secret" then nourritures = false end
      if nourritures then nourritures[i] = t end
    end
  end
  lib.Sonder("familier", a, b, c, d)
  if present == nil then return nil end
  if humeur ~= 1 and humeur ~= 2 and humeur ~= 3 then humeur = nil end
  if not present then return { present = false } end
  return { present = true, mort = mort, humeur = humeur, nourritures = nourritures or nil }
end
lib.DeclarerSonde("familier",
  "UnitExists et UnitIsDead sur le familier rendent oui, non ou nil ; C_PetInfo.GetPetHappiness une humeur de 1 à 3 ou "
    .. "rien, et GetPetFoodTypes une liste de noms ou rien : ni absents, ni secrets, ni en erreur",
  function(a, b, c, d)
    if not ouiNonOuNil(a, b) then return false end
    if c ~= nil and c ~= 1 and c ~= 2 and c ~= 3 then return false end
    if d == nil then return true end
    if type(d) ~= "table" then return false end
    for i = 1, d.n do if type(d[i]) ~= "string" or d[i] == "secret" then return false end end
    return true
  end, function() familier() end)

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
  familier = {
    lire = familier,
    evenements = { "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE" },
    -- ponytail: relu toutes les secondes, la mort du familier n'ayant pas d'événement sûr (UNIT_HEALTH et UNIT_FLAGS
    -- arrivent pour toutes les unités et relancent toutes les lectures) ; un événement sûr trouvé en jeu le remplacera.
    periode = 1,
  },
}

-- Deux valeurs pareilles : égales, ou deux tables aux mêmes champs (les lectures rendent une table neuve à chaque fois).
local function pareil(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not pareil(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local suivis = {} -- [lecture] = { fn, …, valeur = la dernière rendue, relecture = son C_Timer }
local cadre = CreateFrame("Frame")

local function rappeler(fn, valeur)
  local ok, err = pcall(fn, valeur)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function relire(lecture)
  local s = suivis[lecture]
  local v = LECTURES[lecture].lire()
  -- ponytail: comparée telle quelle (une table champ à champ) ; une lecture qui rendra une valeur secrète (qu'aucun calcul
  -- ne doit toucher, pas même ==) rappellera à chaque relecture, sans comparer.
  if pareil(v, s.valeur) then return end
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
    -- ponytail: les lectures ne partagent aucun événement ; quand deux en partageront un, ne le retirer que si plus
    -- aucune lecture suivie ne l'écoute.
    for _, ev in ipairs(l.evenements) do pcall(cadre.UnregisterEvent, cadre, ev) end
    if s.relecture then s.relecture:Cancel() end
    suivis[lecture] = nil
  end
  return true
end
