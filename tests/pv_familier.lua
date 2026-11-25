-- Lecture « pv du familier » du cœur de combat (BeAGoodPal#29) et AC:PVDuFamilier(courbe) : les PV du familier sont
-- secrets, en combat comme hors combat ; le socle ne fait que les passer tels quels (pourcentage et courbe évalués par le
-- jeu). Les réponses du jeu (UnitExists, UnitHealthPercent, C_CurveUtil, issecretvalue) sont remplacées le temps d'un test.
local RIEN = {} -- remplace par nil

-- La valeur secrète simulée : issecretvalue la reconnaît, et toute opération sur elle (arithmétique, ordre, concaténation,
-- tostring, longueur, index, appel) lève une erreur. == et le test de vérité ne se piègent pas en Lua : les tests
-- vérifient qu'elle est rappelée à chaque relecture (donc jamais comparée à la précédente).
local function operation() error("opération sur une valeur secrète", 2) end
local SECRET = setmetatable({}, { __add = operation, __sub = operation, __mul = operation, __div = operation,
    __mod = operation, __pow = operation, __unm = operation, __lt = operation, __le = operation, __eq = operation,
    __concat = operation, __len = operation, __tostring = operation, __index = operation, __newindex = operation,
    __call = operation })

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

-- Les réponses du jeu, lues dans r à chaque appel. r = { la, pv } : pv, la vie du familier de 0 à 1, que la courbe donnée
-- à UnitHealthPercent transforme (comme le jeu) ; SECRET : UnitHealthPercent rend la valeur secrète ; une fonction : appelée.
local function jeu(r)
    local function rendre(v) if type(v) == "function" then return v() end return v end
    return {
        UnitExists = function(u) if u == "pet" then return rendre(r.la) end return false end,
        UnitHealthPercent = function(u, predit, courbe)
            r.courbes = r.courbes or {}
            r.courbes[#r.courbes + 1] = courbe
            if u ~= "pet" then return 0 end
            local pv = rendre(r.pv)
            if rawequal(pv, SECRET) or not courbe then return pv end
            return courbe:Evaluate(pv)
        end,
        issecretvalue = function(v) return rawequal(v, SECRET) end,
    }
end

local function suiveur()
    local recu = {}
    return recu, function(v) recu[#recu + 1] = v == nil and "nil" or v end
end

local function lire(r)
    local recu, fn = suiveur()
    avec(jeu(r), function()
        assertTrue(AzerothCommune:Suivre("pv du familier", fn))
        AzerothCommune:NePlusSuivre("pv du familier", fn)
    end)
    assertEquals(1, #recu, "rappelé une fois, tout de suite")
    return recu[1]
end

local function sonde() return AzerothCommune.Sondes()["pv du familier"] end
local function note(s, x)
    for i = 1, (type(s.valeur) == "table" and s.valeur.n or 0) do if s.valeur[i] == x then return true end end
    return false
end

test("pv du familier lisible : le pourcentage (0 à 100) que le jeu calcule par une courbe ; sonde verte", function()
    assertEquals(73, math.floor(lire({ la = true, pv = 0.73 }) + 0.5))
    assertEquals(0, lire({ la = true, pv = 0 }))
    assertEquals("vert", sonde().etat)
end)

test("pv du familier secrets : passés tels quels, rappelés à chaque événement sans être comparés ; sonde verte, « secret » noté", function()
    local r = { la = true, pv = SECRET }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AzerothCommune:Suivre("pv du familier", fn))
        assertTrue(rawequal(SECRET, recu[1]), "la valeur secrète elle-même")
        FireEvent("UNIT_HEALTH", "pet")
        assertEquals(2, #recu, "secrets : jamais comparés au précédent, donc rappelés")
        assertTrue(rawequal(SECRET, recu[2]))
        FireEvent("UNIT_MAXHEALTH", "pet")
        assertEquals(3, #recu)
        r.pv = 0.5 -- lisible de nouveau : comparé, rappelé seulement s'il change
        FireEvent("UNIT_HEALTH", "pet")
        assertEquals(50, recu[4])
        FireEvent("UNIT_HEALTH", "pet")
        assertEquals(4, #recu, "même pourcentage lisible : pas de rappel")
        AzerothCommune:NePlusSuivre("pv du familier", fn)
    end)
    assertTrue(rawequal(SECRET, lire({ la = true, pv = SECRET })))
    local s = sonde()
    assertEquals("vert", s.etat)
    assertTrue(note(s, "secret"), "la sonde note le secret, pas la valeur")
end)

test("pv du familier inconnus (nil) : pas de familier, présence secrète ; fonction du jeu absente ou en erreur : sonde rouge", function()
    assertEquals("nil", lire({ la = false, pv = 0.5 }))
    assertEquals("vert", sonde().etat, "pas de familier : rien d'anormal")
    assertEquals("nil", lire({ la = SECRET, pv = 0.5 }))
    assertEquals("rouge", sonde().etat)
    assertEquals("nil", lire({ la = true, pv = function() error("API changée") end }))
    assertEquals("rouge", sonde().etat)
    assertEquals("nil", lire({ la = true, pv = "beaucoup" }))
    assertEquals("rouge", sonde().etat)
    local recu, fn = suiveur()
    local j = jeu({ la = true, pv = 0.5 })
    j.UnitHealthPercent = RIEN
    avec(j, function() assertTrue(AzerothCommune:Suivre("pv du familier", fn)); AzerothCommune:NePlusSuivre("pv du familier", fn) end)
    assertEquals("nil", recu[1])
    assertEquals("rouge", sonde().etat)
    assertTrue(note(sonde(), "absente"))
    assertEquals(50, lire({ la = true, pv = 0.5 }))
    assertEquals("vert", sonde().etat)
end)

test("AC:PVDuFamilier(courbe) : la courbe du module, évaluée par le jeu sur les PV du familier, rendue telle quelle", function()
    local AC = AzerothCommune
    local courbe = C_CurveUtil.CreateCurve()
    courbe:SetType(Enum.LuaCurveType.Linear)
    courbe:AddPoint(0, 1); courbe:AddPoint(0.3, 1); courbe:AddPoint(0.33, 0); courbe:AddPoint(1, 0)
    local r = { la = true, pv = 0.2 }
    avec(jeu(r), function()
        assertEquals(1, AC:PVDuFamilier(courbe))
        assertTrue(rawequal(courbe, r.courbes[#r.courbes]), "la courbe du module, passée au jeu")
        r.pv = 0.8
        assertEquals(0, AC:PVDuFamilier(courbe))
        r.pv = SECRET
        assertTrue(rawequal(SECRET, AC:PVDuFamilier(courbe)), "secret : rendu tel quel")
        r.la = false
        assertNil(AC:PVDuFamilier(courbe), "pas de familier : nil")
    end)
    assertEquals("vert", sonde().etat)
end)

test("pv du familier : écoutés pour le familier seul, relus tant qu'ils sont suivis, plus rien sans suivi", function()
    local AC = AzerothCommune
    local r = { la = true, pv = 0.9 }
    local j, relectures, unites = jeu(r), {}, {}
    j["C_Timer.NewTicker"] = function(periode, fn)
        local t = { periode = periode, fn = fn, Cancel = function(self) self.arrete = true end }
        relectures[#relectures + 1] = t
        return t
    end
    local cadre
    local methodes = getmetatable(CreateFrame("Frame")).__index
    local reg = methodes.RegisterUnitEvent
    methodes.RegisterUnitEvent = function(self, ev, unite, ...)
        if ev == "UNIT_HEALTH" then cadre = self end
        unites[ev] = unite
        return reg(self, ev, unite, ...)
    end
    local ok, err = pcall(avec, j, function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("pv du familier", fn))
        assertEquals("pet", unites.UNIT_HEALTH)
        assertEquals("pet", unites.UNIT_MAXHEALTH)
        assertEquals(1, #relectures, "relu tout seul : le familier appelé ou renvoyé n'a pas d'événement de vie")
        r.la = false
        relectures[1].fn()
        assertEquals("nil", recu[2], "renvoyé : inconnus")
        AC:NePlusSuivre("pv du familier", fn)
        assertTrue(relectures[1].arrete, "relecture arrêtée sans suivi")
        assertTrue(not cadre:IsEventRegistered("UNIT_HEALTH"), "UNIT_HEALTH plus écouté sans suivi")
        assertTrue(not cadre:IsEventRegistered("UNIT_MAXHEALTH"))
    end)
    methodes.RegisterUnitEvent = reg
    assert(ok, err)
end)

test("sonde des PV du familier rangée avec les autres (Sondes(), donc Diagnostic), relançable sans suivi", function()
    avec(jeu({ la = true, pv = SECRET }), function() AzerothCommune.RelancerSondes() end)
    local s = sonde()
    assertNotNil(s, "sonde déclarée")
    assertType("string", s.attente)
    assertEquals("vert", s.etat)
end)
