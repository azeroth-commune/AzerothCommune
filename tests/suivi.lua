-- Suivi de l'état de combat (#98, ADR 0003 de l'atelier) : un add-on suit une lecture, le socle lit le jeu pour lui, le
-- rappelle à chaque changement et la sonde. Les réponses du jeu (C_SwingTimer, C_Spell.IsSpellInRange,
-- CheckInteractDistance, UnitExists, UnitCanAttack, issecretvalue) sont remplacées le temps d'un test.
local TIR, MELEE = 2, 0 -- Enum.PlayerSwingType.Ranged, .MainHand
local COUPURE, TIR_AUTO, RAPTOR = 2974, 75, 2973 -- Coupure d'ailes, Tir automatique, Attaque du raptor
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
        if v == RIEN then v = nil end -- false reste false
        t[k] = v
        remettre[#remettre + 1] = function() t[k] = avant end
    end
    local ok, err = pcall(fn)
    for i = #remettre, 1, -1 do remettre[i]() end
    assert(ok, err)
end

-- Les réponses du jeu, lues dans r à chaque appel (un test les change en cours de route).
-- r = { cible, attaquable, natif = { [TIR], [MELEE] } (absent : pas de C_SwingTimer), coupure, tirAuto, raptor, suivre,
--       actives = { [type] = true } (rempli par EnableRangeCheck) }
local function jeu(r)
    r.actives = {}
    return {
        UnitExists = function(u) if u == "target" then return r.cible end return false end,
        UnitCanAttack = function(_, u) if u == "target" then return r.attaquable end return false end,
        C_SwingTimer = r.natif and {
            EnableRangeCheck = function(t, oui) r.actives[t] = oui end,
            IsTargetWithinSwingRange = function(t) return r.natif[t] end,
        } or RIEN,
        ["C_Spell.IsSpellInRange"] = function(id, u)
            if u ~= "target" then return nil end
            if id == COUPURE then return r.coupure elseif id == TIR_AUTO then return r.tirAuto elseif id == RAPTOR then return r.raptor end
        end,
        CheckInteractDistance = function(u, i) if u == "target" and i == 4 then return r.suivre end return false end,
        issecretvalue = function(v) return v == SECRET end,
    }
end

-- Un suiveur qui note ce qu'il reçoit (nil noté « nil »).
local function suiveur()
    local recu = {}
    return recu, function(v) recu[#recu + 1] = v == nil and "nil" or v end
end

-- Les tests du suivi, joués deux fois : d'abord sans autre suiveur, puis avec un suiveur déjà là et jamais parti (un
-- add-on qui suit la portée dès le chargement, BeAGoodPal#25) ; deja le dit aux tests qui en dépendent.
local testerUn = test
local function lesTests(deja)
local function test(nom, fn) testerUn(deja and nom .. " (un suiveur déjà là)" or nom, fn) end

test("portée, natif présent : tir tout de suite, mêlée à l'événement du swing timer ; rien de rappelé sans changement", function()
    local AC = AzerothCommune
    local r = { cible = true, attaquable = true, natif = { [TIR] = true, [MELEE] = false } }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("portée", fn))
        assertEquals(true, r.actives[TIR], "test de portée natif activé pour le tir")
        assertEquals(true, r.actives[MELEE], "test de portée natif activé pour la mêlée")
        assertEquals("tir", recu[1])
        r.actives = {} -- coupé par la barre de swing du jeu ou un autre add-on
        FireEvent("PLAYER_TARGET_CHANGED")
        assertEquals(true, r.actives[TIR], "test natif réarmé au changement de cible (tir)")
        assertEquals(true, r.actives[MELEE], "test natif réarmé au changement de cible (mêlée)")
        assertEquals(1, #recu, "même portée : pas de rappel")
        r.natif = { [TIR] = false, [MELEE] = true }
        FireEvent("PLAYER_SWING_RANGE_UPDATE", MELEE, true, true)
        assertEquals("mêlée", recu[2])
        FireEvent("PLAYER_SWING_RANGE_UPDATE", MELEE, true, true)
        assertEquals(2, #recu, "même portée : pas de rappel")
        assertTrue(AC:NePlusSuivre("portée", fn))
        r.natif = { [TIR] = true, [MELEE] = false }
        FireEvent("PLAYER_SWING_RANGE_UPDATE", TIR, true, true)
        assertEquals(2, #recu, "plus suivi : plus rappelé")
    end)
end)

test("portée, natif présent, ni tir ni mêlée : zone morte à moins de 28 m, trop loin au-delà ; le natif l'emporte sur les replis", function()
    local AC = AzerothCommune
    local r = { cible = true, attaquable = true, natif = { [TIR] = false, [MELEE] = false }, coupure = true, tirAuto = true, suivre = true }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("portée", fn))
        assertEquals("zone morte", recu[1], "le natif dit non : Coupure d'ailes et Tir automatique ne comptent pas")
        r.suivre = false
        FireEvent("PLAYER_SWING_RANGE_UPDATE", TIR, false, true)
        assertEquals("trop loin", recu[2])
        AC:NePlusSuivre("portée", fn)
    end)
end)

-- La portée rendue tout de suite à un nouveau suiveur, avec ces réponses du jeu.
local function porteeAvec(r)
    local recu, fn = suiveur()
    avec(jeu(r), function()
        assertTrue(AzerothCommune:Suivre("portée", fn))
        AzerothCommune:NePlusSuivre("portée", fn)
    end)
    assertEquals(1, #recu, "rappelé une fois, tout de suite, même pour nil")
    if recu[1] ~= "nil" then return recu[1] end
end

test("portée, natif absent : replis Coupure d'ailes (mêlée), Tir automatique (tir), test « suivre » (zone morte, trop loin)", function()
    local function r(t) t.cible, t.attaquable = true, true return t end
    assertEquals("mêlée", porteeAvec(r { coupure = true, tirAuto = false }))
    assertEquals("tir", porteeAvec(r { coupure = false, tirAuto = true }))
    assertEquals("zone morte", porteeAvec(r { coupure = false, tirAuto = false, suivre = true }))
    assertEquals("trop loin", porteeAvec(r { coupure = false, tirAuto = false, suivre = false }))
    -- L'Attaque du raptor répond « à portée » à distance de tir : jamais lue.
    assertEquals("trop loin", porteeAvec(r { raptor = true, coupure = false, tirAuto = false, suivre = false }))
    -- Natif présent mais muet (nil : test pas activé, pas d'arme) : les replis aussi.
    assertEquals("mêlée", porteeAvec(r { natif = {}, coupure = true, tirAuto = false }))
    assertEquals("tir", porteeAvec(r { natif = { [MELEE] = false }, coupure = true, tirAuto = true }))
end)

test("portée en combat : CheckInteractDistance jamais appelé (le jeu le bloque), ni tir ni mêlée donne nil", function()
    local r = { cible = true, attaquable = true, coupure = false, tirAuto = false, suivre = true }
    local appels = 0
    local j = jeu(r)
    j.CheckInteractDistance = function() appels = appels + 1 return true end
    j.InCombatLockdown = function() return true end
    local recu, fn = suiveur()
    avec(j, function()
        assertTrue(AzerothCommune:Suivre("portée", fn))
        AzerothCommune:NePlusSuivre("portée", fn)
    end)
    assertEquals(0, appels, "CheckInteractDistance appelé en combat")
    assertEquals("nil", recu[1], "en combat, ni tir ni mêlée : on ne sait pas")
    j.InCombatLockdown = function() return true end
    r.tirAuto = true
    assertEquals("tir", (function() local rr, f = suiveur(); avec(j, function() AzerothCommune:Suivre("portée", f); AzerothCommune:NePlusSuivre("portée", f) end) return rr[1] end)())
end)

test("la même fonction suivie deux fois : inscrite une fois, rappelée tout de suite à chaque Suivre, une fois par changement", function()
    local AC = AzerothCommune
    local r = { cible = true, attaquable = true, natif = { [TIR] = true, [MELEE] = false } }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("portée", fn))
        assertTrue(AC:Suivre("portée", fn))
        assertEquals(2, #recu)
        r.natif = { [TIR] = false, [MELEE] = true }
        FireEvent("PLAYER_SWING_RANGE_UPDATE", MELEE, true, true)
        assertEquals(3, #recu, "un seul rappel au changement")
        assertTrue(AC:NePlusSuivre("portée", fn))
        r.natif = { [TIR] = true, [MELEE] = false }
        FireEvent("PLAYER_SWING_RANGE_UPDATE", TIR, true, true)
        assertEquals(3, #recu, "un seul NePlusSuivre l'arrête")
    end)
end)

test("portée inconnue (nil, jamais « non ») : sans cible, cible pas attaquable, ou des réponses qui ne tranchent pas", function()
    assertNil(porteeAvec { cible = false, attaquable = true, natif = { [TIR] = true } })
    assertNil(porteeAvec { cible = true, attaquable = false, natif = { [TIR] = true } })
    -- Ni tir, mêlée inconnue : zone morte ou mêlée, on ne sait pas.
    assertNil(porteeAvec { cible = true, attaquable = true, tirAuto = false, suivre = true })
    -- Tir inconnu, pas en mêlée : tir ou zone morte, on ne sait pas.
    assertNil(porteeAvec { cible = true, attaquable = true, coupure = false, suivre = true })
    -- Ni tir ni mêlée, mais le test « suivre » ne répond pas.
    assertNil(porteeAvec { cible = true, attaquable = true, natif = { [TIR] = false, [MELEE] = false } })
end)

-- Les réponses notées par la sonde (valeur { n, … }) contiennent-elles x ?
local function noteParLaSonde(s, x)
    for i = 1, (s.valeur and s.valeur.n or 0) do if s.valeur[i] == x then return true end end
    return false
end

test("sonde de la portée : verte sur des oui, non ou nil ; une réponse secrète ou une erreur donne nil et la rend rouge, sans planter", function()
    local AC = AzerothCommune
    assertEquals("tir", porteeAvec { cible = true, attaquable = true, natif = { [TIR] = true, [MELEE] = false } })
    local s = AC.Sondes()["portée"]
    assertNotNil(s, "sonde déclarée")
    assertType("string", s.attente)
    assertEquals("vert", s.etat)
    -- Secret : la portée native rend la valeur témoin, aucun repli ne répond.
    assertNil(porteeAvec { cible = true, attaquable = true, natif = { [TIR] = SECRET, [MELEE] = SECRET } })
    s = AC.Sondes()["portée"]
    assertEquals("rouge", s.etat)
    assertTrue(noteParLaSonde(s, "secret"), "la sonde note le secret, pas la valeur")
    -- Erreur de l'API : les sorts lèvent une erreur.
    local r = { cible = true, attaquable = true, suivre = true }
    local j = jeu(r)
    j["C_Spell.IsSpellInRange"] = function() error("API changée") end
    local recu, fn = suiveur()
    avec(j, function()
        assertTrue(AC:Suivre("portée", fn))
        AC:NePlusSuivre("portée", fn)
    end)
    assertEquals("nil", recu[1])
    assertEquals("rouge", AC.Sondes()["portée"].etat)
    -- De nouveau des réponses attendues : verte.
    assertEquals("trop loin", porteeAvec { cible = true, attaquable = true, natif = { [TIR] = false, [MELEE] = false }, suivre = false })
    assertEquals("vert", AC.Sondes()["portée"].etat)
    -- Une fonction du jeu disparue (un patch retire C_SwingTimer) : rouge, notée « absente » ; la portée tient par les replis.
    assertEquals("mêlée", porteeAvec { cible = true, attaquable = true, coupure = true, tirAuto = false })
    s = AC.Sondes()["portée"]
    assertEquals("rouge", s.etat)
    assertTrue(noteParLaSonde(s, "absente"), "la sonde note la fonction absente")
end)

test("sondes de combat rangées avec celles du relevé (Sondes(), donc Diagnostic), après elles", function()
    local AC = AzerothCommune
    local etat, build, portee = AC.Sondes(), nil, nil
    for i, s in ipairs(etat) do
        if s.nom == "build" then build = i elseif s.nom == "portée" then portee = i end
    end
    assertNotNil(build, "sonde de relevé « build »")
    assertNotNil(portee, "sonde de combat « portée »")
    assertTrue(portee > build)
end)

-- Espionne RegisterEvent et UnregisterEvent sur la table de méthodes partagée des cadres, le temps de fn(notes) ; chaque
-- note : { cadre, événement, quoi = "+" ou "-", deja = l'événement était-il déjà enregistré sur ce cadre }.
local function espionnerEvenements(fn)
    local methodes = getmetatable(CreateFrame("Frame")).__index
    local reg, unreg, notes = methodes.RegisterEvent, methodes.UnregisterEvent, {}
    methodes.RegisterEvent = function(self, ev, ...)
        notes[#notes + 1] = { cadre = self, ev = ev, quoi = "+", deja = self:IsEventRegistered(ev) }
        return reg(self, ev, ...)
    end
    methodes.UnregisterEvent = function(self, ev, ...)
        notes[#notes + 1] = { cadre = self, ev = ev, quoi = "-" }
        return unreg(self, ev, ...)
    end
    local ok, err = pcall(fn, notes)
    methodes.RegisterEvent, methodes.UnregisterEvent = reg, unreg
    assert(ok, err)
end

test("sans suivi, le socle n'écoute aucun événement de combat ; le premier suiveur l'y met, le dernier parti l'en retire", function()
    local AC = AzerothCommune
    local r = { cible = true, attaquable = true, natif = { [TIR] = true, [MELEE] = false } }
    avec(jeu(r), function()
        espionnerEvenements(function(notes)
            local _, fn1 = suiveur()
            local _, fn2 = suiveur()
            assertTrue(AC:Suivre("portée", fn1))
            if deja then
                -- Le socle écoute déjà pour l'autre suiveur : rien de plus, et nos départs ne retirent rien.
                assertEquals(0, #notes, "déjà écouté : rien de réenregistré")
                assertTrue(AC:NePlusSuivre("portée", fn1))
                assertEquals(0, #notes, "l'autre suiveur reste : rien de retiré")
                return
            end
            local cadre, evenements = nil, {}
            for _, n in ipairs(notes) do
                assertEquals("+", n.quoi)
                assertTrue(not n.deja, n.ev .. " déjà écouté avant le premier suivi")
                cadre = cadre or n.cadre
                assertTrue(n.cadre == cadre, "un seul cadre du socle")
                evenements[#evenements + 1] = n.ev
            end
            local liste = table.concat(evenements, " ")
            assertTrue(liste:find("PLAYER_SWING_RANGE_UPDATE", 1, true) ~= nil, "mise à jour de portée native écoutée : " .. liste)
            assertTrue(liste:find("PLAYER_TARGET_CHANGED", 1, true) ~= nil, "changement de cible écouté : " .. liste)
            local n = #notes
            assertTrue(AC:Suivre("portée", fn2))
            assertTrue(AC:NePlusSuivre("portée", fn1))
            assertEquals(n, #notes, "un deuxième suiveur, puis le départ du premier : rien de changé")
            assertTrue(AC:NePlusSuivre("portée", fn2))
            for _, ev in ipairs(evenements) do assertTrue(not cadre:IsEventRegistered(ev), ev .. " encore écouté sans suivi") end
        end)
    end)
end)

test("portée relue toute seule tant qu'elle est suivie (les replis n'ont pas d'événement) ; arrêtée avec le dernier suiveur", function()
    local AC = AzerothCommune
    local r = { cible = true, attaquable = true, coupure = false, tirAuto = true }
    local j = jeu(r)
    local relectures = {}
    j["C_Timer.NewTicker"] = function(periode, fn)
        local t = { periode = periode, fn = fn, Cancel = function(self) self.arrete = true end }
        relectures[#relectures + 1] = t
        return t
    end
    avec(j, function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("portée", fn))
        assertEquals("tir", recu[1])
        if deja then
            assertEquals(0, #relectures, "la relecture déjà en place sert")
            AC:NePlusSuivre("portée", fn)
            return
        end
        assertEquals(1, #relectures, "une relecture périodique")
        local t = relectures[1]
        assertTrue(t.periode > 0 and t.periode <= 0.5, "période " .. tostring(t.periode))
        r.tirAuto, r.suivre = false, true
        t.fn()
        assertEquals("zone morte", recu[2])
        AC:NePlusSuivre("portée", fn)
        assertTrue(t.arrete, "relecture arrêtée sans suivi")
    end)
end)

test("lecture inconnue ou pas une fonction : false et la raison, rien de suivi ni démarré", function()
    local AC = AzerothCommune
    local relectures = 0
    avec({ ["C_Timer.NewTicker"] = function() relectures = relectures + 1 end }, function()
        local ok, raison = AC:Suivre("mana du familier", function() end)
        assertEquals(false, ok)
        assertEquals("lecture inconnue", raison)
        ok, raison = AC:NePlusSuivre("mana du familier", function() end)
        assertEquals(false, ok)
        assertEquals("lecture inconnue", raison)
        ok, raison = AC:Suivre("portée", nil)
        assertEquals(false, ok)
        assertEquals("pas une fonction", raison)
        ok, raison = AC:Suivre("portée", "rappel")
        assertEquals(false, ok)
        assertEquals("pas une fonction", raison)
    end)
    assertEquals(0, relectures, "aucune relecture démarrée")
end)

test("un rappel qui plante ne prive pas les autres suiveurs (erreur rendue au gestionnaire du jeu)", function()
    local AC = AzerothCommune
    local r = { cible = true, attaquable = true, natif = { [TIR] = true, [MELEE] = false } }
    local j, erreurs = jeu(r), {}
    j.geterrorhandler = function() return function(e) erreurs[#erreurs + 1] = e end end
    avec(j, function()
        local function plante() error("rappel cassé") end
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("portée", plante))
        assertTrue(AC:Suivre("portée", fn))
        r.natif = { [TIR] = false, [MELEE] = true }
        FireEvent("PLAYER_SWING_RANGE_UPDATE", MELEE, true, true)
        AC:NePlusSuivre("portée", plante)
        AC:NePlusSuivre("portée", fn)
        assertEquals("tir", recu[1])
        assertEquals("mêlée", recu[2])
        assertEquals(2, #erreurs, "l'erreur du rappel cassé, au suivi puis au changement")
    end)
end)

end -- lesTests

lesTests(false)
-- Un add-on qui suit la portée dès le chargement (BeAGoodPal#25) : il reste inscrit pour toute la suite des tests.
test("un suiveur déjà là avant les tests (un add-on qui suit la portée dès le chargement)", function()
    assertTrue(AzerothCommune:Suivre("portée", function() end))
end)
lesTests(true)
