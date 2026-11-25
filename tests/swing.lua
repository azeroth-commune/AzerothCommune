-- La lecture « swing » du suivi (BeAGoodPal#26) : le Tir auto, lu par le socle. Les réponses du jeu (PLAYER_SWING,
-- UNIT_SPELLCAST_SENT, START/STOP_AUTOREPEAT_SPELL, l'infobulle de l'arme, GetTime, issecretvalue) sont remplacées le
-- temps d'un test.
local TIR, MELEE = 2, 0 -- Enum.PlayerSwingType.Ranged, .MainHand
local TIR_AUTO, RAPTOR = 75, 2973
local RIEN = {} -- remplace par nil
-- Une valeur secrète témoin : le moindre calcul ou comparaison d'ordre dessus est noté (et lève une erreur).
local touchee = false
local function interdit() touchee = true; error("calcul sur une valeur secrète") end
local SECRET = setmetatable({}, { __add = interdit, __sub = interdit, __mul = interdit, __div = interdit,
    __unm = interdit, __lt = interdit, __le = interdit, __concat = interdit })

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

-- Le jeu : l'heure r.heure, l'infobulle de l'arme à distance (r.vitesse : le texte de droite de sa ligne de dégâts).
local function jeu(r)
    return {
        GetTime = function() return r.heure end,
        C_TooltipInfo = { GetInventoryItem = function(u, slot)
            if u ~= "player" or slot ~= 18 then return nil end
            return { lines = { { leftText = "Arc long" }, { leftText = "Arc", rightText = "Arc" },
                               { leftText = "41 - 77 points de dégâts", rightText = r.vitesse } } }
        end },
        issecretvalue = function(v) return v == SECRET end,
    }
end

local function suiveur()
    local recu = {}
    return recu, function(v) recu[#recu + 1] = v == nil and "nil" or v end
end

test("swing : chaque tir avec sa durée et sa part immobile, l'envoi du Tir auto, le début et la fin du tir répété", function()
    local AC = AzerothCommune
    local r = { heure = 100, vitesse = "Vitesse 3,00" }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("swing", fn))
        local n = #recu
        assertEquals(1, n, "rappelé tout de suite")
        FireEvent("START_AUTOREPEAT_SPELL")
        assertEquals(n + 1, #recu)
        assertEquals(true, recu[#recu].actif, "tir répété commencé")
        r.heure = 101
        FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-1", TIR_AUTO)
        assertEquals(101, recu[#recu].preparation, "préparation à l'envoi du Tir auto")
        local avant = #recu
        FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-2", RAPTOR)
        FireEvent("UNIT_SPELLCAST_SENT", "pet", "", "Cast-3", TIR_AUTO)
        assertEquals(avant, #recu, "un autre sort, ou pas le joueur : rien")
        r.heure = 101.5
        FireEvent("PLAYER_SWING", 2.4, TIR)
        local v = recu[#recu]
        assertEquals(101.5, v.tir, "heure du tir")
        assertEquals(2.4, v.duree, "durée jusqu'au tir suivant, corrigée de la hâte par le jeu")
        assertTrue(math.abs(v.immobile - 0.4) < 1e-9, "0,5 s à la vitesse de base (3,00), réduite par la hâte : " .. tostring(v.immobile))
        assertEquals(true, v.actif, "le reste est gardé")
        assertEquals(101, v.preparation)
        avant = #recu
        FireEvent("PLAYER_SWING", 1.8, MELEE)
        assertEquals(avant, #recu, "un coup de mêlée : pas un tir")
        r.heure = 102
        FireEvent("STOP_AUTOREPEAT_SPELL")
        assertEquals(false, recu[#recu].actif, "tir répété arrêté")
        assertEquals(101.5, recu[#recu].tir)
        assertTrue(AC:NePlusSuivre("swing", fn))
        avant = #recu
        FireEvent("PLAYER_SWING", 2.4, TIR)
        FireEvent("START_AUTOREPEAT_SPELL")
        assertEquals(avant, #recu, "plus suivi : plus rappelé")
    end)
end)

test("swing : un autre événement du suivi ne rappelle pas (même valeur) ; la valeur rendue n'est pas modifiée ensuite", function()
    local AC = AzerothCommune
    local r = { heure = 200, vitesse = "Speed 2.00" }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("swing", fn))
        FireEvent("PLAYER_SWING", 2.0, TIR)
        local v, n = recu[#recu], #recu
        assertTrue(math.abs(v.immobile - 0.5) < 1e-9, "infobulle anglaise lue aussi")
        FireEvent("PLAYER_TARGET_CHANGED")
        assertEquals(n, #recu, "pas de changement : pas de rappel")
        FireEvent("START_AUTOREPEAT_SPELL")
        assertEquals(200, v.tir)
        assertTrue(v ~= recu[#recu], "une nouvelle valeur à chaque changement")
        AC:NePlusSuivre("swing", fn)
    end)
end)

-- Les réponses notées par la sonde (valeur { n, … }) contiennent-elles x ?
local function noteParLaSonde(s, x)
    for i = 1, (s.valeur and s.valeur.n or 0) do if s.valeur[i] == x then return true end end
    return false
end

test("sonde swing : verte sur un tir normal ; vitesse de base illisible : part immobile inconnue (nil), rouge", function()
    local AC = AzerothCommune
    local r = { heure = 300, vitesse = "Vitesse 2,80" }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("swing", fn))
        FireEvent("PLAYER_SWING", 2.8, TIR)
        local s = AC.Sondes()["swing"]
        assertNotNil(s, "sonde déclarée")
        assertType("string", s.attente)
        assertEquals("vert", s.etat)
        FireEvent("PLAYER_SWING", 2.0, MELEE)
        assertEquals("vert", AC.Sondes()["swing"].etat, "un coup de mêlée normal : vert aussi")
        r.vitesse = nil -- pas d'arme, ou infobulle changée
        FireEvent("PLAYER_SWING", 2.8, TIR)
        assertEquals(2.8, recu[#recu].duree)
        assertNil(recu[#recu].immobile, "part immobile inconnue")
        s = AC.Sondes()["swing"]
        assertEquals("rouge", s.etat)
        assertTrue(noteParLaSonde(s, "illisible"), "la sonde note la vitesse illisible")
        r.vitesse = "Vitesse 2,80"
        FireEvent("PLAYER_SWING", 2.8, TIR)
        assertEquals("vert", AC.Sondes()["swing"].etat)
        AC:NePlusSuivre("swing", fn)
    end)
end)

test("swing : une durée secrète passe telle quelle, sans calcul (part immobile nil) ; un type secret n'est pas un tir ; sonde rouge", function()
    local AC = AzerothCommune
    local r = { heure = 400, vitesse = "Vitesse 3,00" }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("swing", fn))
        touchee = false
        FireEvent("PLAYER_SWING", SECRET, TIR)
        assertTrue(not touchee, "aucun calcul sur la valeur secrète")
        local v = recu[#recu]
        assertTrue(v.duree == SECRET, "durée secrète passée telle quelle")
        assertNil(v.immobile)
        assertEquals(400, v.tir)
        local s = AC.Sondes()["swing"]
        assertEquals("rouge", s.etat)
        assertTrue(noteParLaSonde(s, "secret"), "la sonde note le secret, pas la valeur")
        local n = #recu
        r.heure = 401
        FireEvent("PLAYER_SWING", 2.4, SECRET)
        assertEquals(n, #recu, "type secret : on ne sait pas si c'est un tir")
        FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-1", SECRET)
        assertEquals(n, #recu, "sort secret : on ne sait pas si c'est le Tir auto")
        assertTrue(not touchee)
        AC:NePlusSuivre("swing", fn)
    end)
end)

test("swing : rien d'écouté sans suivi ; le premier suiveur y met le socle, le dernier parti l'en retire", function()
    local AC = AzerothCommune
    local methodes = getmetatable(CreateFrame("Frame")).__index
    local reg, notes = methodes.RegisterEvent, {}
    methodes.RegisterEvent = function(self, ev, ...) notes[#notes + 1] = { cadre = self, ev = ev }; return reg(self, ev, ...) end
    local _, fn = suiveur()
    local ok, err = pcall(AC.Suivre, AC, "swing", fn)
    methodes.RegisterEvent = reg
    assert(ok, err)
    local cadre, liste = nil, {}
    for _, n in ipairs(notes) do cadre = cadre or n.cadre; liste[#liste + 1] = n.ev end
    local tout = table.concat(liste, " ")
    for _, ev in ipairs({ "PLAYER_SWING", "UNIT_SPELLCAST_SENT", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL" }) do
        assertTrue((" " .. tout .. " "):find(" " .. ev .. " ", 1, true) ~= nil, ev .. " écouté : " .. tout)
    end
    assertTrue(AC:NePlusSuivre("swing", fn))
    for _, ev in ipairs(liste) do assertTrue(not cadre:IsEventRegistered(ev), ev .. " encore écouté sans suivi") end
end)

test("sonde swing rangée avec les autres, après la portée", function()
    local etat, portee, swing = AzerothCommune.Sondes(), nil, nil
    for i, s in ipairs(etat) do
        if s.nom == "portée" then portee = i elseif s.nom == "swing" then swing = i end
    end
    assertNotNil(swing, "sonde de combat « swing »")
    assertTrue(swing > portee)
end)

test("swing : le dernier suiveur parti, rien n'est gardé ; une valeur secrète n'est pas comparée (rappel à chaque relecture)", function()
    local AC = AzerothCommune
    local r = { heure = 500, vitesse = "Vitesse 3,00" }
    avec(jeu(r), function()
        local recu, fn = suiveur()
        assertTrue(AC:Suivre("swing", fn))
        FireEvent("START_AUTOREPEAT_SPELL")
        FireEvent("PLAYER_SWING", 3.0, TIR)
        AC:NePlusSuivre("swing", fn)
        -- STOP_AUTOREPEAT_SPELL, s'il vient maintenant, n'est plus écouté : « actif » gardé serait faux.
        recu, fn = suiveur()
        assertTrue(AC:Suivre("swing", fn))
        assertEquals("nil", recu[1], "suivi repris : inconnu, pas l'ancien tir répété")
        FireEvent("START_AUTOREPEAT_SPELL")
        FireEvent("PLAYER_SWING", SECRET, TIR)
        local n = #recu
        FireEvent("START_AUTOREPEAT_SPELL") -- rien ne change, mais la durée secrète ne se compare pas
        assertEquals(n + 1, #recu, "valeur secrète : rappelée sans comparaison")
        assertTrue(recu[#recu].duree == SECRET)
        AC:NePlusSuivre("swing", fn)
    end)
end)
