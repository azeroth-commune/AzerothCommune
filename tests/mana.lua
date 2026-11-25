-- Lectures de la mana du druide (BeAGoodPal#30) : mana, mana max, coût des formes, pas assez de mana. Les réponses du jeu
-- (UnitPower, UnitPowerMax, IsPlayerSpell, C_Spell.GetSpellPowerCost, C_Spell.IsSpellUsable, InCombatLockdown,
-- issecretvalue) sont remplacées le temps d'un test.
local OURS, OURS_R, FELIN, VOYAGE, AQUA, SELENIEN, SHIFTING = 5487, 9634, 768, 783, 1066, 24858, 1322605
local RIEN = {} -- remplace par nil

-- La valeur secrète simulée : issecretvalue la reconnaît, et tout calcul sur elle (arithmétique, ordre, concaténation,
-- tostring) lève une erreur. == ne se piège pas en Lua : les tests vérifient qu'elle est rappelée sans être comparée.
local function calcul() error("calcul sur une valeur secrète", 2) end
local SECRET = setmetatable({}, { __add = calcul, __sub = calcul, __mul = calcul, __div = calcul, __mod = calcul,
    __pow = calcul, __unm = calcul, __lt = calcul, __le = calcul, __concat = calcul, __len = calcul, __tostring = calcul })

local function avec(jeu, fn)
    local remettre = {}
    for cle, v in pairs(jeu) do
        local nom, champ = cle:match("^([^.]+)%.?(.*)$")
        local t, k = _G, nom
        if champ ~= "" then t, k = _G[nom], champ end
        local avant = t[k]
        if v == RIEN then v = nil end
        t[k] = v
        remettre[#remettre + 1] = function() t[k] = avant end
    end
    local ok, err = pcall(fn)
    for i = #remettre, 1, -1 do remettre[i]() end
    assert(ok, err)
end

-- Les réponses du jeu, lues dans r à chaque appel. r = { mana, max, connus = { [id] = true }, couts = { [id] = coût ou
-- SECRET ou une liste brute }, manque = { [id] = true / false / SECRET }, combat }.
local function jeu(r)
    return {
        UnitPower = function(u, t) if u == "player" and t == 0 then return r.mana end end,
        UnitPowerMax = function(u, t) if u == "player" and t == 0 then return r.max end end,
        IsPlayerSpell = function(id) return r.connus and r.connus[id] == true end,
        ["C_Spell.GetSpellPowerCost"] = function(id)
            local c = r.couts and r.couts[id]
            if type(c) == "number" then return { { type = 0, cost = c, name = "MANA" } } end
            return c
        end,
        ["C_Spell.IsSpellUsable"] = function(id)
            local m = r.manque and r.manque[id]
            return m ~= true, m or false
        end,
        InCombatLockdown = function() return r.combat == true end,
        issecretvalue = function(v) return v == SECRET end,
    }
end

local function suiveur()
    local recu = {}
    return recu, function(v) recu[#recu + 1] = v == nil and "nil" or v end
end

-- La valeur rendue tout de suite à un nouveau suiveur de lecture, avec ces réponses du jeu.
local function lire(lecture, r)
    local recu, fn = suiveur()
    avec(jeu(r), function()
        assertTrue(AzerothCommune:Suivre(lecture, fn))
        AzerothCommune:NePlusSuivre(lecture, fn)
    end)
    assertEquals(1, #recu, "rappelé une fois, tout de suite")
    if recu[1] ~= "nil" then return recu[1] end
end

local function sonde(nom) return AzerothCommune.Sondes()[nom] end
local function noteParLaSonde(s, x)
    if s.valeur == x then return true end
    for i = 1, (type(s.valeur) == "table" and s.valeur.n or 0) do if s.valeur[i] == x then return true end end
    return false
end

test("mana lisible : la valeur du jeu, rappelée à chaque changement (UNIT_POWER_FREQUENT du joueur) ; sonde verte", function()
    local r = { mana = 1234 }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AzerothCommune:Suivre("mana", fn))
        assertEquals(1234, recu[1])
        r.mana = 1000
        FireEvent("UNIT_POWER_FREQUENT", "player", "MANA")
        assertEquals(1000, recu[2])
        FireEvent("UNIT_POWER_FREQUENT", "player", "MANA")
        assertEquals(2, #recu, "même mana : pas de rappel")
        AzerothCommune:NePlusSuivre("mana", fn)
    end)
    assertEquals("vert", sonde("mana").etat)
    assertEquals(1234, lire("mana max", { max = 1234 }))
    assertEquals("vert", sonde("mana max").etat)
end)

test("mana secrète : passée telle quelle, rappelée à chaque relecture sans être comparée ; la sonde, verte, note « secret »", function()
    local r = { mana = SECRET, max = SECRET }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AzerothCommune:Suivre("mana", fn))
        assertTrue(rawequal(SECRET, recu[1]), "la valeur secrète elle-même")
        FireEvent("UNIT_POWER_FREQUENT", "player", "MANA")
        assertEquals(2, #recu, "secrète : jamais comparée à la précédente, donc rappelée")
        assertTrue(rawequal(SECRET, recu[2]))
        r.mana = 500 -- sortie de combat : de nouveau lisible
        FireEvent("UNIT_POWER_FREQUENT", "player", "MANA")
        assertEquals(500, recu[3])
        AzerothCommune:NePlusSuivre("mana", fn)
    end)
    r.mana = SECRET
    assertTrue(rawequal(SECRET, lire("mana", r)))
    local s = sonde("mana")
    assertEquals("vert", s.etat)
    assertEquals("secret", s.valeur, "la sonde note le secret, pas la valeur")
    assertTrue(rawequal(SECRET, lire("mana max", r)))
    assertEquals("vert", sonde("mana max").etat)
end)

test("mana inconnue (nil) : fonction du jeu absente, en erreur ou autre chose qu'un nombre ; sonde rouge", function()
    local j = jeu({})
    j.UnitPower = RIEN
    local recu, fn = suiveur()
    avec(j, function() assertTrue(AzerothCommune:Suivre("mana", fn)); AzerothCommune:NePlusSuivre("mana", fn) end)
    assertEquals("nil", recu[1])
    assertEquals("rouge", sonde("mana").etat)
    assertTrue(noteParLaSonde(sonde("mana"), "absente"))
    j.UnitPower = function() error("API changée") end
    avec(j, function() assertTrue(AzerothCommune:Suivre("mana", fn)); AzerothCommune:NePlusSuivre("mana", fn) end)
    assertEquals("nil", recu[2])
    assertEquals("rouge", sonde("mana").etat)
    assertNil(lire("mana", { mana = "beaucoup" }))
    assertEquals("rouge", sonde("mana").etat)
    assertEquals(10, lire("mana", { mana = 10 }))
    assertEquals("vert", sonde("mana").etat)
end)

test("coût des formes : { [ID] = coût } des formes connues et de Shifting Power, lu hors combat ; sonde verte", function()
    local r = { connus = { [OURS_R] = true, [FELIN] = true, [SHIFTING] = true }, couts = { [OURS_R] = 580, [FELIN] = 580, [SHIFTING] = 580, [VOYAGE] = 210 } }
    local c = lire("coût des formes", r)
    assertEquals(580, c[OURS_R])
    assertEquals(580, c[FELIN])
    assertEquals(580, c[SHIFTING])
    assertNil(c[VOYAGE], "pas connue : pas de coût")
    assertNil(c[OURS])
    assertEquals("vert", sonde("coût des formes").etat)
    assertTrue(noteParLaSonde(sonde("coût des formes"), 580))
    assertTrue(noteParLaSonde(sonde("coût des formes"), "pas connue"))
end)

test("coût des formes : en combat, le dernier lu hors combat est gardé, sans relire le jeu ; relu à la sortie du combat", function()
    local r = { connus = { [FELIN] = true }, couts = { [FELIN] = 300 } }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AzerothCommune:Suivre("coût des formes", fn))
        assertEquals(300, recu[1][FELIN])
        r.combat, r.couts[FELIN] = true, SECRET
        FireEvent("SPELLS_CHANGED")
        assertEquals(1, #recu, "en combat : rien de relu, rien de rappelé")
        local deuxieme, fn2 = suiveur()
        assertTrue(AzerothCommune:Suivre("coût des formes", fn2))
        assertEquals(300, deuxieme[1][FELIN], "un suiveur arrivé en combat a le coût gardé")
        r.combat, r.couts[FELIN] = false, 250
        FireEvent("PLAYER_REGEN_ENABLED")
        assertEquals(250, recu[2][FELIN], "relu à la sortie du combat")
        FireEvent("SPELLS_CHANGED")
        assertEquals(2, #recu, "même coût : pas de rappel")
        AzerothCommune:NePlusSuivre("coût des formes", fn)
        AzerothCommune:NePlusSuivre("coût des formes", fn2)
    end)
end)

test("coût des formes : un coût secret hors combat, sans mana ou en erreur manque ; la sonde rouge le note", function()
    local c = lire("coût des formes", { connus = { [FELIN] = true, [VOYAGE] = true }, couts = { [FELIN] = SECRET, [VOYAGE] = 210 } })
    assertNil(c[FELIN])
    assertEquals(210, c[VOYAGE])
    assertEquals("rouge", sonde("coût des formes").etat)
    assertTrue(noteParLaSonde(sonde("coût des formes"), "secret"))
    c = lire("coût des formes", { connus = { [FELIN] = true }, couts = { [FELIN] = { { type = 3, cost = 40 } } } })
    assertNil(c[FELIN], "pas de mana dans le coût")
    assertEquals("rouge", sonde("coût des formes").etat)
    assertTrue(noteParLaSonde(sonde("coût des formes"), "sans mana"))
    c = lire("coût des formes", { connus = { [FELIN] = true }, couts = { [FELIN] = 300 } })
    assertEquals(300, c[FELIN])
    assertEquals("vert", sonde("coût des formes").etat)
end)

test("pas assez de mana : { [ID] = oui ou non } d'après l'utilisabilité du sort ; secret ou inconnu : absent, sonde rouge", function()
    local r = { connus = { [FELIN] = true, [AQUA] = true, [SELENIEN] = true }, manque = { [FELIN] = true, [AQUA] = false } }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AzerothCommune:Suivre("pas assez de mana", fn))
        assertEquals(true, recu[1][FELIN])
        assertEquals(false, recu[1][AQUA])
        assertEquals(false, recu[1][SELENIEN], "utilisable sans manque de mana : non")
        assertNil(recu[1][VOYAGE], "pas connue : absente")
        assertEquals("vert", sonde("pas assez de mana").etat)
        r.manque[FELIN] = false
        FireEvent("SPELL_UPDATE_USABLE")
        assertEquals(false, recu[2][FELIN])
        FireEvent("SPELL_UPDATE_USABLE")
        assertEquals(2, #recu, "rien de changé : pas de rappel")
        r.manque[FELIN] = SECRET
        FireEvent("UNIT_POWER_FREQUENT", "player", "MANA")
        assertNil(recu[3][FELIN], "secret : inconnu")
        assertEquals("rouge", sonde("pas assez de mana").etat)
        assertTrue(noteParLaSonde(sonde("pas assez de mana"), "secret"))
        AzerothCommune:NePlusSuivre("pas assez de mana", fn)
    end)
end)

test("un événement partagé reste écouté tant qu'une lecture suivie s'en sert ; les événements du joueur, pour lui seul", function()
    local r = { mana = 100, connus = {} }
    avec(jeu(r), function()
        local _, fnMana = suiveur()
        local _, fnManque = suiveur()
        local cadre
        local methodes = getmetatable(CreateFrame("Frame")).__index
        local reg = methodes.RegisterUnitEvent
        methodes.RegisterUnitEvent = function(self, ev, ...)
            if ev == "UNIT_POWER_FREQUENT" then cadre = self end
            return reg(self, ev, ...)
        end
        local ok, err = pcall(function()
            assertTrue(AzerothCommune:Suivre("mana", fnMana))
            assertTrue(AzerothCommune:Suivre("pas assez de mana", fnManque))
        end)
        methodes.RegisterUnitEvent = reg
        assert(ok, err)
        assertNotNil(cadre, "UNIT_POWER_FREQUENT écouté pour une unité")
        local oui, unite = cadre:IsEventRegistered("UNIT_POWER_FREQUENT")
        assertTrue(oui)
        assertEquals("player", unite)
        AzerothCommune:NePlusSuivre("mana", fnMana)
        assertTrue(cadre:IsEventRegistered("UNIT_POWER_FREQUENT"), "encore suivi par « pas assez de mana »")
        AzerothCommune:NePlusSuivre("pas assez de mana", fnManque)
        assertTrue(not cadre:IsEventRegistered("UNIT_POWER_FREQUENT"), "plus aucune lecture suivie ne l'écoute")
    end)
end)

test("sondes de la mana rangées avec les autres (Sondes(), donc Diagnostic), relançables sans suivi", function()
    avec(jeu({ mana = 50, max = 100, connus = { [FELIN] = true }, couts = { [FELIN] = 30 }, manque = {} }), function()
        local etat = AzerothCommune.RelancerSondes()
        for _, nom in ipairs({ "mana", "mana max", "coût des formes", "pas assez de mana" }) do
            assertNotNil(etat[nom], "sonde déclarée : " .. nom)
            assertType("string", etat[nom].attente)
            assertEquals("vert", etat[nom].etat, nom)
        end
    end)
end)
