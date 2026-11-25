-- Lecture « déplacement » du cœur de combat (BeAGoodPal#32) : IsPlayerMoving, relue à PLAYER_STARTED_MOVING et
-- PLAYER_STOPPED_MOVING. Les réponses du jeu (IsPlayerMoving, issecretvalue) sont remplacées le temps d'un test.
local SECRET = {} -- la valeur témoin que l'issecretvalue remplacé reconnaît
local RIEN = {} -- remplace par nil

-- Pose les remplacements (nom → valeur) le temps de fn, puis remet tout, même si fn échoue.
local function avec(jeu, fn)
    local avant = {}
    for nom, v in pairs(jeu) do
        avant[nom] = _G[nom]
        if v == RIEN then v = nil end
        _G[nom] = v
    end
    local ok, err = pcall(fn)
    for nom in pairs(jeu) do _G[nom] = avant[nom] end
    assert(ok, err)
end

local function suiveur()
    local recu = {}
    return recu, function(v) recu[#recu + 1] = v == nil and "nil" or v end
end

-- r.bouge : ce que rend IsPlayerMoving (RIEN : la fonction est absente ; « erreur » : elle lève une erreur).
local function jeu(r)
    local f = function() if r.bouge == "erreur" then error("API changée") end return r.bouge end
    return { IsPlayerMoving = r.bouge == RIEN and RIEN or f, issecretvalue = function(v) return v == SECRET end }
end

-- La valeur rendue tout de suite à un nouveau suiveur, avec ces réponses du jeu.
local function lire(r)
    local recu, fn = suiveur()
    avec(jeu(r), function()
        assertTrue(AzerothCommune:Suivre("déplacement", fn))
        AzerothCommune:NePlusSuivre("déplacement", fn)
    end)
    assertEquals(1, #recu, "rappelé une fois, tout de suite")
    if recu[1] ~= "nil" then return recu[1] end
end

test("déplacement : true quand le joueur bouge, false à l'arrêt ; nil (inconnu) sur un secret, une erreur, autre chose ou une fonction absente", function()
    assertEquals(true, lire { bouge = true })
    assertEquals(false, lire { bouge = false })
    assertNil(lire { bouge = SECRET })
    assertNil(lire { bouge = "erreur" })
    assertNil(lire { bouge = 1 })
    assertNil(lire { bouge = RIEN })
end)

-- Espionne RegisterEvent et UnregisterEvent des cadres le temps de fn(notes) ; note « +EV » ou « -EV ».
local function espionner(fn)
    local m = getmetatable(CreateFrame("Frame")).__index
    local reg, unreg, notes = m.RegisterEvent, m.UnregisterEvent, {}
    m.RegisterEvent = function(self, ev, ...) notes[#notes + 1] = "+" .. ev; return reg(self, ev, ...) end
    m.UnregisterEvent = function(self, ev, ...) notes[#notes + 1] = "-" .. ev; return unreg(self, ev, ...) end
    local ok, err = pcall(fn, notes)
    m.RegisterEvent, m.UnregisterEvent = reg, unreg
    assert(ok, err)
end

local function contient(notes, x)
    for _, n in ipairs(notes) do if n == x then return true end end
    return false
end

test("déplacement : relu au début et à la fin d'un déplacement, écoutés seulement pendant le suivi", function()
    local AC = AzerothCommune
    local r = { bouge = false }
    avec(jeu(r), function()
        espionner(function(notes)
            local recu, fn = suiveur()
            assertTrue(AC:Suivre("déplacement", fn))
            assertTrue(contient(notes, "+PLAYER_STARTED_MOVING"), table.concat(notes, " "))
            assertTrue(contient(notes, "+PLAYER_STOPPED_MOVING"), table.concat(notes, " "))
            assertEquals(false, recu[1])
            r.bouge = true
            FireEvent("PLAYER_STARTED_MOVING")
            assertEquals(true, recu[2])
            FireEvent("PLAYER_STARTED_MOVING")
            assertEquals(2, #recu, "pas de changement : pas de rappel")
            r.bouge = false
            FireEvent("PLAYER_STOPPED_MOVING")
            assertEquals(false, recu[3])
            assertTrue(AC:NePlusSuivre("déplacement", fn))
            assertTrue(contient(notes, "-PLAYER_STARTED_MOVING") and contient(notes, "-PLAYER_STOPPED_MOVING"),
                table.concat(notes, " "))
            r.bouge = true
            FireEvent("PLAYER_STARTED_MOVING")
            assertEquals(3, #recu, "plus suivi : plus rappelé")
        end)
    end)
end)

test("déplacement : l'événement fait foi, même si IsPlayerMoving répond encore l'ancienne valeur ; oublié à la fin du suivi", function()
    local AC = AzerothCommune
    local r = { bouge = false }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("déplacement", fn))
        assertEquals(false, recu[1])
        FireEvent("PLAYER_STARTED_MOVING") -- IsPlayerMoving dit encore non
        assertEquals(true, recu[2])
        r.bouge = true
        FireEvent("PLAYER_STOPPED_MOVING") -- IsPlayerMoving dit encore oui
        assertEquals(false, recu[3])
        assertTrue(AC:NePlusSuivre("déplacement", fn))
    end)
    assertEquals(true, lire { bouge = true }, "un nouveau suivi relit IsPlayerMoving")
end)

test("sonde déplacement : verte sur oui ou non ; rouge sur un secret, une erreur ou une fonction disparue ; relançable sans suivi", function()
    local AC = AzerothCommune
    local function etat(r) lire(r); return AC.Sondes()["déplacement"] end
    local s = etat { bouge = true }
    assertNotNil(s, "sonde déclarée")
    assertType("string", s.attente)
    assertEquals("vert", s.etat)
    assertEquals("vert", etat({ bouge = false }).etat)
    s = etat { bouge = SECRET }
    assertEquals("rouge", s.etat)
    assertEquals("secret", s.valeur, "la sonde note le secret, pas la valeur")
    assertEquals("rouge", etat({ bouge = "erreur" }).etat)
    s = etat { bouge = RIEN }
    assertEquals("rouge", s.etat)
    assertEquals("absente", s.valeur)
    avec(jeu { bouge = false }, function() AC.RelancerSondes() end)
    assertEquals("vert", AC.Sondes()["déplacement"].etat, "relancée sans suivi")
end)
