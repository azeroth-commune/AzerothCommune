-- Lecture « familier » du cœur de combat (BeAGoodPal#28) : existence, mort, humeur et types de nourriture du familier.
-- Les réponses du jeu (UnitExists, UnitIsDead, C_PetInfo, issecretvalue) sont remplacées le temps d'un test.
local SECRET = {} -- la valeur témoin que l'issecretvalue remplacé reconnaît
local RIEN = {} -- remplace par nil

-- Pose les remplacements (« nom » ou « table.champ » → valeur) le temps de fn, puis remet tout, même si fn échoue.
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

-- Les réponses du jeu, lues dans r à chaque appel. r = { la, mort, humeur, nourritures } ; une valeur fonction est
-- appelée (pour lever une erreur).
local function jeu(r)
    local function rendre(v) if type(v) == "function" then return v() end return v end
    return {
        UnitExists = function(u) if u == "pet" then return rendre(r.la) end return false end,
        UnitIsDead = function(u) if u == "pet" then return rendre(r.mort) end return false end,
        C_PetInfo = {
            GetPetHappiness = function() return rendre(r.humeur), 0, 0 end,
            GetPetFoodTypes = function() return rendre(r.nourritures) end,
        },
        issecretvalue = function(v) return v == SECRET end,
    }
end

-- Le familier rendu tout de suite à un nouveau suiveur, avec ces réponses du jeu ("nil" pour nil).
local function familierAvec(r)
    local recu = {}
    local function fn(v) recu[#recu + 1] = v == nil and "nil" or v end
    avec(jeu(r), function()
        assertTrue(AzerothCommune:Suivre("familier", fn))
        AzerothCommune:NePlusSuivre("familier", fn)
    end)
    assertEquals(1, #recu, "rappelé une fois, tout de suite, même pour nil")
    return recu[1]
end

test("familier : là, vivant, humeur et types de nourriture tels que le jeu les dit", function()
    local f = familierAvec { la = true, mort = false, humeur = 3, nourritures = { "Viande", "Poisson" } }
    assertEquals(true, f.present)
    assertEquals(false, f.mort)
    assertEquals(3, f.humeur)
    assertEquals("Viande, Poisson", table.concat(f.nourritures, ", "))
    f = familierAvec { la = true, mort = true, humeur = 1, nourritures = {} }
    assertEquals(true, f.mort)
    assertEquals(1, f.humeur)
    assertEquals(0, #f.nourritures)
end)

test("familier absent : present faux, et rien d'autre (mort inconnue : renvoyé ou mort sans corps)", function()
    local f = familierAvec { la = false, mort = false }
    assertEquals(false, f.present)
    assertNil(f.mort)
    assertNil(f.humeur)
    assertNil(f.nourritures)
end)

test("familier : nil quand le jeu ne dit rien, et nil pour chaque réponse qui ne tranche pas", function()
    assertEquals("nil", familierAvec { la = SECRET })
    assertEquals("nil", familierAvec { la = function() error("API changée") end })
    assertEquals("nil", familierAvec { la = "oui" })
    local f = familierAvec { la = true, mort = SECRET, humeur = SECRET, nourritures = SECRET }
    assertEquals(true, f.present)
    assertNil(f.mort); assertNil(f.humeur); assertNil(f.nourritures)
    f = familierAvec { la = true, mort = false, humeur = 7, nourritures = "Viande" } -- hors de ce qu'on attend
    assertNil(f.humeur); assertNil(f.nourritures)
    f = familierAvec { la = true, mort = false, humeur = 2, nourritures = { "Viande", SECRET } }
    assertNil(f.nourritures, "un type secret : la liste est inconnue")
    avec({ C_PetInfo = RIEN, UnitExists = function() return true end, UnitIsDead = function() return false end }, function()
        local recu
        local function fn(v) recu = v end
        assertTrue(AzerothCommune:Suivre("familier", fn))
        AzerothCommune:NePlusSuivre("familier", fn)
        assertEquals(true, recu.present)
        assertNil(recu.humeur, "C_PetInfo absent : humeur inconnue")
    end)
end)

test("familier : rappelé au changement (événements du familier), pas sans changement ; plus rien sans suivi", function()
    local AC = AzerothCommune
    local r = { la = true, mort = false, humeur = 2, nourritures = { "Viande" } }
    avec(jeu(r), function()
        local recu = {}
        local function fn(v) recu[#recu + 1] = v end
        assertTrue(AC:Suivre("familier", fn))
        assertEquals(2, recu[1].humeur)
        FireEvent("UNIT_HAPPINESS", "pet")
        assertEquals(1, #recu, "même familier (nouvelle table, mêmes valeurs) : pas de rappel")
        r.humeur = 3
        FireEvent("UNIT_HAPPINESS", "pet")
        assertEquals(3, recu[2].humeur)
        r.la = false
        FireEvent("UNIT_PET", "player")
        assertEquals(false, recu[3].present)
        r.la, r.nourritures = true, { "Viande", "Pain" }
        FireEvent("PET_UI_UPDATE")
        assertEquals("Viande, Pain", table.concat(recu[4].nourritures, ", "))
        assertTrue(AC:NePlusSuivre("familier", fn))
        r.humeur = 1
        FireEvent("UNIT_HAPPINESS", "pet")
        assertEquals(4, #recu, "plus suivi : plus rappelé")
    end)
end)

test("familier relu tout seul tant qu'il est suivi (la mort n'a pas d'événement sûr) ; arrêté avec le dernier suiveur", function()
    local AC = AzerothCommune
    local r = { la = true, mort = false, humeur = 3, nourritures = {} }
    local j, relectures = jeu(r), {}
    j["C_Timer.NewTicker"] = function(periode, fn)
        local t = { periode = periode, fn = fn, Cancel = function(self) self.arrete = true end }
        relectures[#relectures + 1] = t
        return t
    end
    avec(j, function()
        local recu = {}
        local function fn(v) recu[#recu + 1] = v end
        assertTrue(AC:Suivre("familier", fn))
        assertEquals(1, #relectures, "une relecture périodique")
        r.mort = true
        relectures[1].fn()
        assertEquals(true, recu[2].mort)
        AC:NePlusSuivre("familier", fn)
        assertTrue(relectures[1].arrete, "relecture arrêtée sans suivi")
    end)
end)

test("sans suivi du familier, le socle n'écoute pas ses événements", function()
    local cadres = {}
    local methodes = getmetatable(CreateFrame("Frame")).__index
    local reg = methodes.RegisterEvent
    methodes.RegisterEvent = function(self, ev, ...) cadres[#cadres + 1] = { self, ev }; return reg(self, ev, ...) end
    local ok, err = pcall(function()
        avec(jeu { la = true, mort = false }, function()
            local fn = function() end
            assertTrue(AzerothCommune:Suivre("familier", fn))
            AzerothCommune:NePlusSuivre("familier", fn)
        end)
    end)
    methodes.RegisterEvent = reg
    assert(ok, err)
    assertTrue(#cadres > 0, "des événements écoutés pendant le suivi")
    for _, c in ipairs(cadres) do assertTrue(not c[1]:IsEventRegistered(c[2]), c[2] .. " encore écouté sans suivi") end
end)

-- Les réponses notées par la sonde contiennent-elles x ?
local function note(s, x)
    for i = 1, (s.valeur and s.valeur.n or 0) do if s.valeur[i] == x then return true end end
    return false
end

test("sonde du familier : verte sur des réponses attendues, rouge sur un secret, une erreur ou une humeur hors 1-3, sans planter", function()
    local AC = AzerothCommune
    familierAvec { la = true, mort = false, humeur = 2, nourritures = { "Viande" } }
    local s = AC.Sondes()["familier"]
    assertNotNil(s, "sonde déclarée")
    assertType("string", s.attente)
    assertEquals("vert", s.etat)
    familierAvec { la = false, mort = false } -- pas de familier : humeur et nourritures nil, attendu
    assertEquals("vert", AC.Sondes()["familier"].etat)
    familierAvec { la = true, mort = false, humeur = SECRET, nourritures = {} }
    s = AC.Sondes()["familier"]
    assertEquals("rouge", s.etat)
    assertTrue(note(s, "secret"), "la sonde note le secret, pas la valeur")
    familierAvec { la = true, mort = false, humeur = 3, nourritures = {} }
    assertEquals("vert", AC.Sondes()["familier"].etat)
    familierAvec { la = true, mort = function() error("API changée") end, humeur = 3, nourritures = {} }
    assertEquals("rouge", AC.Sondes()["familier"].etat)
    familierAvec { la = true, mort = false, humeur = 7, nourritures = {} }
    assertEquals("rouge", AC.Sondes()["familier"].etat)
    familierAvec { la = true, mort = false, humeur = 3, nourritures = 12 }
    assertEquals("rouge", AC.Sondes()["familier"].etat)
end)

test("sonde du familier rangée avec les autres (Sondes(), donc Diagnostic), et relançable sans suivi", function()
    local AC = AzerothCommune
    local trouve
    for _, s in ipairs(AC.Sondes()) do if s.nom == "familier" then trouve = true end end
    assertTrue(trouve)
    avec(jeu { la = true, mort = false, humeur = 1, nourritures = { "Fruit" } }, function() AC.RelancerSondes() end)
    local s = AC.Sondes()["familier"]
    assertEquals("vert", s.etat)
    assertTrue(note(s, 1), "l'humeur notée")
end)
