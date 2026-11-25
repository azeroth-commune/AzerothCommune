-- L'état de combat, lu par le socle (ADR 0003 de l'atelier, #98) : un add-on suit une lecture nommée, le socle n'écoute
-- le jeu que pour les lectures suivies, rappelle l'add-on à chaque changement et sonde chaque lecture. Rien n'est gardé
-- au-delà de la session.
--   AC:Suivre(lecture, fn)      : fn(valeur) tout de suite, puis à chaque changement ; true, ou false et la raison
--                                 (« lecture inconnue », « pas une fonction »). La même fn suivie deux fois : inscrite une fois.
--   AC:NePlusSuivre(lecture, fn) : fn n'est plus rappelé ; le dernier suiveur parti, le socle cesse d'écouter le jeu.
--   AC:PVDuFamilier(courbe)     : les PV du familier passés par une courbe (C_CurveUtil) que le jeu évalue, tels quels.
-- valeur : nil = inconnu, jamais « non » ; une valeur secrète passe telle quelle, pour l'affichage seulement (la portée,
-- le familier, les munitions et l'aspect, calculés, n'en rendent jamais : une réponse secrète y donne nil). Une table
-- rendue est partagée entre les suiveurs : la lire, jamais la modifier.
-- Lectures : « portée » (une chaîne, voir portee), « familier » (une table, voir familier), « swing » (une table,
-- voir surSwing), « munitions » (un nombre ou false, voir munitions), « aspect » (une chaîne, voir aspect), « pv du
-- familier » (un nombre ou une valeur secrète, voir pvDuFamilier) et « déplacement » (true ou false, voir deplacement).
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
  -- En combat, le jeu bloque CheckInteractDistance sur une cible qu'on ne peut pas attaquer (taint.log du 25/11 :
  -- « An action was blocked in combat because of taint from AzerothCommune », au moment où le mob fuyait ou mourait) ;
  -- sur une cible attaquable vivante, il répond (sonde en combat du 25/11). Comme OutplayedCombat pour IsItemInRange.
  local proche, g -- nil : on ne sait pas, la sonde reste verte
  if not InCombatLockdown() or (cible and attaquable and UnitIsDead("target") == false) then
    proche, g = demander(CheckInteractDistance, "target", 4)
  end
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

-- Grondement en lancement automatique : le 6e retour de GetPetActionInfo sur la case de la barre du familier qui porte
-- son nom (celui du rang 1, le même pour tous les rangs, dans la langue du client) ; nil s'il n'y est pas.
local GRONDEMENT = 2649
local function grondementAuto()
  local nom, info = brut(C_Spell and C_Spell.GetSpellName, GRONDEMENT), GetPetActionInfo
  return demander(info and type(nom) == "string" and function()
    for i = 1, NUM_PET_ACTION_SLOTS or 10 do
      local n, _, _, _, _, auto = info(i)
      if not (issecretvalue and issecretvalue(n)) and n == nom then return auto end
    end
  end)
end

-- Le familier : { present, mort, humeur, nourritures, grondement }, nil quand le jeu ne dit pas s'il est là. present : UnitExists ;
-- mort (UnitIsDead) seulement s'il est là (absent, il peut être renvoyé ou mort sans corps : le jeu ne le dit pas) ;
-- humeur 1 (mécontent), 2 (content), 3 (heureux) ; nourritures : les types qu'il mange, noms du client (« Viande »…) ;
-- grondement : son lancement automatique (BeAGoodPal#29), vrai ou faux.
-- Chaque champ nil quand sa réponse ne tranche pas (secrète, en erreur, hors de ce qu'on attend). La sonde note les
-- cinq réponses ; les types en { n, … } pour se lire dans Diagnostic.
local function familier()
  local pet = C_PetInfo or {}
  local present, a = demander(UnitExists, "pet")
  local mort, b = demander(UnitIsDead, "pet")
  local humeur, c = brut(pet.GetPetHappiness)
  local types, d = brut(pet.GetPetFoodTypes)
  local grondement, e = grondementAuto()
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
  lib.Sonder("familier", a, b, c, d, e)
  if present == nil then return nil end
  if humeur ~= 1 and humeur ~= 2 and humeur ~= 3 then humeur = nil end
  if not present then return { present = false } end
  return { present = true, mort = mort, humeur = humeur, nourritures = nourritures or nil, grondement = grondement }
end
lib.DeclarerSonde("familier",
  "UnitExists et UnitIsDead sur le familier rendent oui, non ou nil ; C_PetInfo.GetPetHappiness une humeur de 1 à 3 ou "
    .. "rien, GetPetFoodTypes une liste de noms ou rien, et le lancement automatique du Grondement dans la barre du "
    .. "familier (GetPetActionInfo) oui, non ou rien : ni absents, ni secrets, ni en erreur",
  function(a, b, c, d, e)
    if not ouiNonOuNil(a, b, e) then return false end
    if c ~= nil and c ~= 1 and c ~= 2 and c ~= 3 then return false end
    if d == nil then return true end
    if type(d) ~= "table" then return false end
    for i = 1, d.n do if type(d[i]) ~= "string" or d[i] == "secret" then return false end end
    return true
  end, function() familier() end)

-- Le Tir auto (BeAGoodPal#26) : l'événement de swing natif de Forever (PLAYER_SWING, seulement le type Tir), l'envoi du
-- Tir automatique (UNIT_SPELLCAST_SENT : Forever n'envoie pas de début de sort pour lui) et le début et la fin du tir
-- répété. Valeur : nil tant que rien n'est venu, puis une table neuve à chaque changement (jamais modifiée ensuite) :
--   actif       true après START_AUTOREPEAT_SPELL, false après STOP_AUTOREPEAT_SPELL (Tab, cible morte…), nil avant
--   tir         GetTime() du dernier tir parti
--   duree       secondes de ce tir au suivant, déjà corrigées de la hâte par le jeu ; secrète : passée telle quelle
--   immobile    secondes, à la fin de duree, où il faut rester immobile : 0,5 s à la vitesse de base de l'arme, réduite
--               par la hâte (0,5 × duree / vitesse de base) ; nil si la vitesse de base est illisible ou la durée secrète
--   preparation GetTime() du dernier envoi du Tir auto (le premier tir se prépare dès l'envoi ; un envoi pendant le
--               rechargement, une touche martelée, ne change rien au tir)
-- ponytail: pas d'auto-calibrage de la latence (YaHT) ni des nouvelles tentatives quand on bouge (UNIT_SPELLCAST_FAILED_QUIET).
local EMPLACEMENT_DISTANCE = INVSLOT_RANGED or 18
local function secret(v) return issecretvalue and issecretvalue(v) end
local function est(v, x) return not secret(v) and v == x end -- pas même == sur une valeur secrète
local function noter(v) if secret(v) then return "secret" end return v end

-- La vitesse de base de l'arme à distance, sans hâte : le nombre au bout du texte de droite d'une ligne de son infobulle
-- (« Vitesse 2,80 », « Speed 2.80 » : quelle que soit la langue). Rend la vitesse ou nil, puis ce qu'en note la sonde.
-- ponytail: relue à chaque tir (une infobulle toutes les 2 à 3 s) ; un cache par objet si ça pèse un jour.
local function vitesseDeBase()
  if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil, "absente" end
  local ok, v = pcall(function()
    local donnees = C_TooltipInfo.GetInventoryItem("player", EMPLACEMENT_DISTANCE)
    for _, ligne in ipairs(donnees and donnees.lines or {}) do
      local texte = ligne.rightText
      if secret(texte) then return "secret" end
      local n = type(texte) == "string" and texte:match("(%d+[.,]%d+)%s*$")
      if n then return tonumber((n:gsub(",", "."))) end
    end
  end)
  if not ok then return nil, "erreur : " .. tostring(v) end
  if type(v) == "number" and v > 0 then return v, v end
  return nil, v == "secret" and "secret" or "illisible"
end

local swing
local function changerSwing() -- une copie de la valeur, à remplir : l'ancienne, déjà rendue, ne bouge plus
  local t = {}
  for k, v in pairs(swing or {}) do t[k] = v end
  swing = t
  return t
end

local function surSwing(ev, ...)
  if ev == "PLAYER_SWING" then
    local duree, genre = ...
    local tir = est(genre, TIR)
    local base, noteBase
    if tir then base, noteBase = vitesseDeBase() end
    lib.Sonder("swing", noter(duree), noter(genre), noteBase)
    if not tir then return end
    local lisible = not secret(duree) and type(duree) == "number" and duree > 0
    local t = changerSwing()
    t.tir = GetTime()
    -- Pas de « x and duree or nil » : le « or » ferait un test booléen sur la valeur secrète, refusé par le jeu.
    if lisible or secret(duree) then t.duree = duree else t.duree = nil end
    t.immobile = lisible and base and 0.5 * duree / base or nil
  elseif ev == "UNIT_SPELLCAST_SENT" then
    local unite, _, _, sort = ...
    if est(unite, "player") and est(sort, TIR_AUTOMATIQUE) then changerSwing().preparation = GetTime() end
  elseif ev == "START_AUTOREPEAT_SPELL" then changerSwing().actif = true
  elseif ev == "STOP_AUTOREPEAT_SPELL" then changerSwing().actif = false
  end
end
lib.DeclarerSonde("swing",
  "à chaque coup, PLAYER_SWING rend une durée positive et un type de swing (0, 1 ou 2), ni secrets ; pour un tir, "
    .. "l'infobulle de l'arme à distance donne sa vitesse de base",
  function(duree, genre, base)
    return type(duree) == "number" and duree > 0 and (genre == 0 or genre == 1 or genre == 2)
      and (base == nil or type(base) == "number" and base > 0)
  end) -- pas de relevé sans contexte : il faut un coup (« pas encore vue » d'ici là)

-- La mana (BeAGoodPal#30) : une valeur affichable, un nombre ou une valeur secrète (en combat) passée telle quelle, pour
-- l'affichage seulement ; nil sinon. La sonde note le nombre, ou « secret » (attendu en combat : verte).
local MANA = 0 -- Enum.PowerType.Mana
local function affichable(fn, ...)
  if not fn then return nil, "absente" end
  local ok, v = pcall(fn, ...)
  if not ok then return nil, "erreur : " .. tostring(v) end
  if secret(v) then return v, "secret" end
  if type(v) ~= "number" then return nil, v end
  return v, v
end
local function nombreOuSecret(note) return type(note) == "number" or note == "secret" end

-- Les PV du familier (BeAGoodPal#29), secrets en combat comme hors combat : jamais comparés ni calculés, ici comme
-- chez qui les suit. UnitHealthPercent("pet", true, courbe) : le jeu évalue lui-même la courbe sur la part de vie (0 à 1)
-- et rend le résultat, un nombre ou une valeur secrète, passé tel quel (affichable) ; nil sans familier, ou quand le jeu
-- ne répond pas. Sans courbe : le pourcentage, de 0 à 100 (CurveConstants.ScaleTo100 n'existe pas sur Forever). La
-- sonde note l'existence du familier puis la réponse (« secret », attendu : verte).
local centPourCent
local function pvDuFamilier(courbe)
  if not courbe then
    if not centPourCent and C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType then
      centPourCent = C_CurveUtil.CreateCurve()
      centPourCent:SetType(Enum.LuaCurveType.Linear)
      centPourCent:AddPoint(0, 0); centPourCent:AddPoint(1, 100)
    end
    courbe = centPourCent
  end
  local present, a = demander(UnitExists, "pet")
  local v, b
  if present and not courbe then b = "courbe absente"
  elseif present then v, b = affichable(UnitHealthPercent, "pet", true, courbe) end
  lib.Sonder("pv du familier", a, b)
  return v
end
lib.DeclarerSonde("pv du familier",
  "UnitExists(\"pet\") rend oui, non ou nil ; familier là, UnitHealthPercent(\"pet\", true, courbe) rend un nombre ou une "
    .. "valeur secrète : ni absente, ni en erreur",
  function(a, b) return ouiNonOuNil(a) and (b == nil or nombreOuSecret(b)) end,
  function() pvDuFamilier() end)
function lib:PVDuFamilier(courbe) return pvDuFamilier(courbe) end
local function mana()
  local v, note = affichable(UnitPower, "player", MANA)
  lib.Sonder("mana", note)
  return v
end
local function manaMax()
  local v, note = affichable(UnitPowerMax, "player", MANA)
  lib.Sonder("mana max", note)
  return v
end
lib.DeclarerSonde("mana", "UnitPower(\"player\", 0) rend un nombre, ou une valeur secrète (en combat)", nombreOuSecret,
  function() mana() end)
lib.DeclarerSonde("mana max", "UnitPowerMax(\"player\", 0) rend un nombre, ou une valeur secrète (en combat)", nombreOuSecret,
  function() manaMax() end)

-- Les formes du druide et Shifting Power, par leur ID, dans l'ordre des notes de leurs sondes : Ours, Ours redoutable,
-- Félin, Voyage, Aquatique, Sélénien, Shifting Power.
local FORMES = { 5487, 9634, 768, 783, 1066, 24858, 1322605 }
-- Pour chaque forme, sa réponse (fn(id) : valeur, note), ou nil et « pas connue » si le joueur ne la connaît pas ; rend
-- { [id] = valeur } (les réponses nil manquent) et les notes { n, … } de la sonde.
local function parForme(fn)
  local t, notes = {}, { n = #FORMES }
  for i, id in ipairs(FORMES) do
    local connu, note = demander(IsPlayerSpell, id)
    if connu then t[id], note = fn(id) elseif connu == false then note = "pas connue" end
    notes[i] = note
  end
  return t, notes
end
local function notesAttendues(estAttendue)
  return function(notes)
    for i = 1, notes.n do if notes[i] ~= "pas connue" and not estAttendue(notes[i]) then return false end end
    return true
  end
end

-- Coût des formes : { [id] = coût en mana }, lu hors combat seulement (le jeu peut le rendre secret en combat) et gardé
-- pour le combat, la session seulement. Une forme manque : pas connue, ou coût illisible (secret, sans mana, erreur).
local coutsGardes
local function coutDe(id)
  local liste, note = brut(C_Spell and C_Spell.GetSpellPowerCost, id)
  if type(liste) ~= "table" then return nil, liste == nil and note or "sans mana" end
  for _, c in ipairs(liste) do
    if not secret(c) and type(c) == "table" and not secret(c.type) and c.type == MANA then
      if secret(c.cost) then return nil, "secret" end
      if type(c.cost) == "number" then return c.cost, c.cost end
    end
  end
  return nil, "sans mana"
end
local function coutsDesFormes()
  if InCombatLockdown() then return coutsGardes or {} end
  local t, notes = parForme(coutDe)
  lib.Sonder("coût des formes", notes)
  coutsGardes = t
  return t
end
lib.DeclarerSonde("coût des formes",
  "hors combat, C_Spell.GetSpellPowerCost rend un coût en mana numérique pour chaque forme connue (et Shifting Power) : "
    .. "ni absent, ni secret, ni en erreur",
  notesAttendues(function(n) return type(n) == "number" end), function() coutsDesFormes() end)

-- Pas assez de mana : { [id] = oui ou non }, le 2e retour de C_Spell.IsSpellUsable pour chaque forme connue (et Shifting
-- Power). Une forme manque : pas connue, ou réponse qui ne tranche pas (secrète, absente, en erreur).
local function manqueDe(id)
  local utilisable = C_Spell and C_Spell.IsSpellUsable
  return demander(utilisable and function(x) return select(2, utilisable(x)) end, id)
end
local function pasAssezDeMana()
  local t, notes = parForme(manqueDe)
  lib.Sonder("pas assez de mana", notes)
  return t
end
lib.DeclarerSonde("pas assez de mana",
  "C_Spell.IsSpellUsable rend en 2e retour oui ou non (« pas assez de mana ») pour chaque forme connue (et Shifting Power) : "
    .. "ni absent, ni secret, ni en erreur",
  notesAttendues(function(n) return type(n) == "boolean" end), function() pasAssezDeMana() end)

-- Munitions : le compte des munitions placées, 0 sans munitions placées, false si l'arme n'en utilise pas
-- (UnitUsesAmmo), nil quand le jeu ne le dit pas. Le compte de l'emplacement de munitions d'abord ; s'il ne répond
-- pas ou répond 1 (certains clients y rendent la pile, pas le total), celui de cet objet dans les sacs. La sonde note
-- les quatre réponses.
local AMMO = INVSLOT_AMMO or 0
local function munitions()
  local utilise, a = demander(UnitUsesAmmo, "player")
  local id, b = brut(GetInventoryItemID, "player", AMMO)
  local compte, c = brut(GetInventoryItemCount, "player", AMMO)
  local sacs, d
  if type(id) == "number" then sacs, d = brut((C_Item or {}).GetItemCount, id) end
  lib.Sonder("munitions", a, b, c, d)
  if utilise == false then return false end
  if utilise == nil then return nil end
  if b == nil then return 0 end -- l'emplacement répond vide : rien à tirer
  if type(id) ~= "number" then return nil end
  if type(compte) == "number" and compte > 1 then return compte end
  if type(sacs) == "number" then return sacs end
  if type(compte) == "number" then return compte end
end
local function typesOuNil(...)
  local types = { ... }
  return function(...)
    for i, t in ipairs(types) do
      local v = select(i, ...)
      if v ~= nil and type(v) ~= t then return false end
    end
    return true
  end
end
lib.DeclarerSonde("munitions",
  "UnitUsesAmmo rend oui, non ou nil ; GetInventoryItemID et GetInventoryItemCount sur l'emplacement de munitions, et "
    .. "C_Item.GetItemCount de cet objet, un nombre ou rien : ni absents, ni secrets, ni en erreur",
  typesOuNil("boolean", "number", "number", "number"), function() munitions() end)

-- Aspect du chasseur : « faucon », « singe », « guépard », « meute », « bête », « nature », « aucun », ou nil. Chaque
-- aspect cherché par son nom (celui du client, lu par l'ID de son premier rang : tous les rangs le portent) parmi tes
-- auras (filtre PLAYER : la Meute d'un autre chasseur ne compte pas). Rien trouvé ne vaut « aucun » qu'hors combat, ou
-- en combat quand le jeu dit que ces auras ne sont pas secrètes (en combat, une aura secrète peut ne pas être rendue
-- du tout). Le Faucon du dragon et la Vipère ne sont pas confirmés sur Forever (PRD BeAGoodPal#22) : pas lus. La sonde
-- note le combat, puis pour chaque aspect la réponse des auras (true : trouvé) et celle de ShouldSpellAuraBeSecret.
local ASPECTS = { { "faucon", 13165 }, { "singe", 13163 }, { "guépard", 5118 }, { "meute", 13159 }, { "bête", 13161 },
                  { "nature", 20043 } }
local function aspect()
  local auras, secrets, sorts = C_UnitAuras or {}, C_Secrets or {}, C_Spell or {}
  local combat, a = demander(InCombatLockdown)
  local notes, actif, inconnu = { a }, nil, false
  for i, asp in ipairs(ASPECTS) do
    local nom = brut(sorts.GetSpellName, asp[2])
    local aura, n
    if type(nom) == "string" then aura, n = brut(auras.GetAuraDataBySpellName, "player", nom, "HELPFUL|PLAYER")
    else n = "pas de nom (" .. asp[2] .. ")" end
    if type(aura) == "table" then n, actif = true, actif or asp[1]
    elseif n ~= nil then inconnu = true end
    local _, m = demander(secrets.ShouldSpellAuraBeSecret, asp[2])
    notes[2 * i], notes[2 * i + 1] = n, m -- des nil parmi les notes : pas de #notes
  end
  lib.Sonder("aspect", unpack(notes, 1, 1 + 2 * #ASPECTS))
  if actif then return actif end
  if inconnu or combat == nil then return nil end
  if not combat then return "aucun" end
  for i = 3, 1 + 2 * #ASPECTS, 2 do if notes[i] ~= false then return nil end end -- en combat : lisibles seulement si le jeu le dit
  return "aucun"
end
lib.DeclarerSonde("aspect",
  "InCombatLockdown rend oui ou non ; pour chaque aspect, C_Spell.GetSpellName un nom, C_UnitAuras.GetAuraDataBySpellName "
    .. "ton aura ou rien, C_Secrets.ShouldSpellAuraBeSecret oui ou non : ni absents, ni secrets, ni en erreur",
  function(combat, ...)
    if type(combat) ~= "boolean" then return false end
    for i = 1, select("#", ...), 2 do
      local n, m = select(i, ...)
      if (n ~= nil and n ~= true) or type(m) ~= "boolean" then return false end
    end
    return true
  end, function() aspect() end)

-- Déplacement du joueur (BeAGoodPal#32) : IsPlayerMoving, true ou false (lisible en combat, sans drapeau secret dans la
-- doc Forever), nil quand la réponse ne tranche pas. La sonde note la réponse. Après PLAYER_STARTED_MOVING ou
-- PLAYER_STOPPED_MOVING, l'événement fait foi : rien ne garantit qu'IsPlayerMoving y réponde déjà la nouvelle valeur
-- (les add-ons de chasseur d'addons-src prennent tous le nom de l'événement).
local mouvement -- le dernier événement de déplacement depuis le suivi : true (commencé), false (fini), nil (aucun)
local function deplacement()
  local v, note = demander(IsPlayerMoving)
  lib.Sonder("déplacement", note)
  if mouvement ~= nil then return mouvement end
  return v
end
lib.DeclarerSonde("déplacement", "IsPlayerMoving() rend oui ou non : ni absente, ni secrète, ni en erreur",
  function(note) return type(note) == "boolean" end, function() deplacement() end)

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
    evenements = { "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE", "PET_BAR_UPDATE" },
    -- ponytail: relu toutes les secondes, la mort du familier n'ayant pas d'événement sûr ; un événement trouvé en jeu
    -- (UNIT_HEALTH ou UNIT_FLAGS, avec unite = "pet") le remplacera.
    periode = 1,
  },
  ["swing"] = {
    lire = function() return swing end,
    oublier = function() swing = nil end, -- plus suivie, plus écoutée : la valeur gardée deviendrait fausse
    evenements = { "PLAYER_SWING", "UNIT_SPELLCAST_SENT", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL" },
    evenement = surSwing, -- reçoit chaque événement écouté (et ses données) avant la relecture
  },
  -- unite : ses événements UNIT_* écoutés pour cette unité seulement (le joueur, pas le groupe ni la cible).
  -- ponytail: une unité par événement (RegisterUnitEvent remplace la précédente) ; deux lectures qui voudront le même
  -- événement UNIT_* pour deux unités : l'enregistrer pour les deux, et trier par unité dans OnEvent.
  mana = { lire = mana, evenements = { "UNIT_POWER_FREQUENT" }, unite = "player" },
  ["mana max"] = { lire = manaMax, evenements = { "UNIT_MAXPOWER" }, unite = "player" },
  ["coût des formes"] = { lire = coutsDesFormes, evenements = { "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" } },
  ["pas assez de mana"] = {
    lire = pasAssezDeMana,
    evenements = { "SPELL_UPDATE_USABLE", "SPELLS_CHANGED", "UNIT_POWER_FREQUENT" },
    unite = "player",
  },
  munitions = { lire = munitions, evenements = { "BAG_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" },
    unite = "player" },
  aspect = { lire = aspect, evenements = { "UNIT_AURA", "PLAYER_REGEN_ENABLED" }, unite = "player" },
  ["déplacement"] = { lire = deplacement, evenements = { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" },
    evenement = function(ev) mouvement = ev == "PLAYER_STARTED_MOVING" end, oublier = function() mouvement = nil end },
  ["pv du familier"] = {
    lire = function() return pvDuFamilier() end,
    evenements = { "UNIT_HEALTH", "UNIT_MAXHEALTH" },
    unite = "pet",
    -- ponytail: relu toutes les secondes, le familier appelé ou renvoyé n'ayant pas d'événement de vie (UNIT_PET vient du
    -- joueur, pas du familier) ; secrets, ils sont rappelés à chaque relecture (jamais comparés).
    periode = 1,
  },
}

-- Deux valeurs pareilles : égales, ou deux tables aux mêmes champs (les lectures rendent une table neuve à chaque fois).
-- Une valeur secrète n'est jamais comparée (pas même ==) : pas pareille, on rappelle.
local function pareil(a, b)
  if secret(a) or secret(b) then return false end
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not pareil(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function ecoute(l, ev)
  for _, e in ipairs(l.evenements) do if e == ev then return true end end
  return false
end

local suivis = {} -- [lecture] = { fn, …, valeur = la dernière rendue, relecture = son C_Timer }
local cadre = CreateFrame("Frame")

local function rappeler(fn, valeur)
  local ok, err = pcall(fn, valeur)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function relire(lecture)
  local s = suivis[lecture]
  if not s then return end -- plus suivie : un rappel l'a arrêtée
  local v = LECTURES[lecture].lire()
  -- Une valeur secrète (la nouvelle ou la précédente) n'est jamais comparée (pareil) : rappelée à chaque relecture.
  if pareil(v, s.valeur) then return end
  s.valeur = v
  -- Sur une copie : un suiveur qui part (ou arrive) pendant un rappel ne fait sauter (ni rappeler deux fois) personne.
  for _, fn in ipairs({ unpack(s) }) do rappeler(fn, v) end
end

-- Un événement relit les lectures suivies qui l'écoutent (une relecture sans changement ne rappelle personne).
cadre:SetScript("OnEvent", function(_, ev, ...)
  local aRelire = {} -- d'abord la liste : un rappel peut suivre ou arrêter une lecture
  for lecture in pairs(suivis) do if ecoute(LECTURES[lecture], ev) then aRelire[#aRelire + 1] = lecture end end
  for _, lecture in ipairs(aRelire) do
    local l = LECTURES[lecture]
    if ev == "PLAYER_TARGET_CHANGED" and l.demarrer then l.demarrer() end
    if l.evenement then l.evenement(ev, ...) end
    relire(lecture)
  end
end)

function lib:Suivre(lecture, fn)
  local l = LECTURES[lecture]
  if not l then return false, "lecture inconnue" end
  if type(fn) ~= "function" then return false, "pas une fonction" end
  local s = suivis[lecture]
  if not s then
    for _, ev in ipairs(l.evenements) do -- un événement que ce client n'a pas : sauté
      if l.unite and ev:find("^UNIT_") then pcall(cadre.RegisterUnitEvent, cadre, ev, l.unite)
      else pcall(cadre.RegisterEvent, cadre, ev) end
    end
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
    if s.relecture then s.relecture:Cancel() end
    suivis[lecture] = nil
    if l.oublier then l.oublier() end
    -- Un événement qu'une autre lecture suivie écoute aussi reste écouté.
    local garde = {}
    for autre in pairs(suivis) do for _, ev in ipairs(LECTURES[autre].evenements) do garde[ev] = true end end
    for _, ev in ipairs(l.evenements) do
      if not garde[ev] then pcall(cadre.UnregisterEvent, cadre, ev) end
    end
  end
  return true
end
