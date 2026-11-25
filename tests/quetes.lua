-- Base des quêtes (#43) dans wow-ui-sim (tools/sim.sh test AzerothCommune) : la réserve QuetesReserve.lua, générée par
-- tools/build_quest_data.py de l'atelier depuis QuestieDB Forever et commitée, chargée par le TOC. Rien sans souscription.
local BASE = "base des quêtes"

-- La souscription du type le temps d'un test (une autre a pu souscrire avant : remise après).
local function avec(souscrit, fn)
    local avant = AzerothCommuneDB.souscriptions and AzerothCommuneDB.souscriptions[BASE]
    AzerothCommuneDB.souscriptions = AzerothCommuneDB.souscriptions or {}
    AzerothCommuneDB.souscriptions[BASE] = nil
    if souscrit then assertTrue(AzerothCommune:Souscrire(BASE)) end
    local ok, err = pcall(fn)
    AzerothCommuneDB.souscriptions[BASE] = avant
    assertTrue(ok, err)
end

test("sans souscription, la base des quêtes ne rend rien", function()
    avec(false, function()
        local d, raison = AzerothCommune:Lire(BASE)
        assertNil(d)
        assertEquals("pas encore relevé", raison)
    end)
end)

test("après souscription : la réserve et sa provenance (QuestieDB Forever, version, date)", function()
    avec(true, function()
        local d, lot = AzerothCommune:Lire(BASE)
        assertType("table", d)
        assertEquals("source externe", lot.provenance)
        assertEquals("QuestieDB Forever", lot.source)
        assertType("string", lot.version)
        assertTrue(lot.date:find("^%d%d%d%d%-%d%d%-%d%d$") ~= nil, lot.date)
        lot.source = "modifié" -- le lot rendu est une copie
        assertEquals("QuestieDB Forever", (select(2, AzerothCommune:Lire(BASE))).source)
    end)
end)

-- Tous les prérequis d'une quête, de proche en proche (« tous » et « un seul suffit »).
local function ascendance(d, id, vu)
    vu = vu or {}
    local q = d[id] or {}
    for _, liste in ipairs({ q.prerequis or {}, q.prerequis_un or {} }) do
        for _, p in ipairs(liste) do
            if d[p] and not vu[p] then vu[p] = true; ascendance(d, p, vu) end
        end
    end
    return vu
end

test("vrai cas : Bosquet des Anciens (952) est à Sombrivage, ses prérequis à Teldrassil", function()
    avec(true, function()
        local d = AzerothCommune:Lire(BASE)
        local q = d[952]
        assertEquals("Bosquet des Anciens", q.nom) -- nom français de QuestieDB
        assertEquals(148, q.zone) -- Sombrivage (areaID)
        assertEquals(17, q.niveau)
        assertEquals(6, q.niveau_requis)
        assertEquals(3516, q.donneur.pnj) -- Fandral Forteramure, à Darnassus
        assertEquals(1457, q.donneur.carte)
        assertType("number", q.donneur.x)
        local anc, n = ascendance(d, 952), 0
        assertTrue(anc[940], "Teldrassil (940)")
        assertTrue(anc[98398], "L'arbre de l'Oracle (98398)")
        for p in pairs(anc) do n = n + 1; assertEquals(141, d[p].zone, "prérequis " .. p .. " à Teldrassil") end
        assertTrue(n >= 3, "au moins trois prérequis : " .. n)
    end)
end)

test("vrai cas : Des problèmes à Sombrivage ? (730) est une amorce, pas un prérequis", function()
    avec(true, function()
        local d = AzerothCommune:Lire(BASE)
        local q = d[729] -- Les absences du Prospecteur
        local amorce = false
        for _, a in ipairs(q.amorces or {}) do amorce = amorce or a == 730 end
        assertTrue(amorce, "730 dans les amorces de 729")
        assertNil(ascendance(d, 729)[730], "730 n'est pas un prérequis de 729")
        assertEquals("Des problèmes à Sombrivage ?", d[730].nom)
    end)
end)

-- races : liste des raceID (UnitRace), nil : toutes ; les bits 2^32 / 2^33 de QuestieDB sont les races Skyborne (95, 96).
local function contient(liste, v)
    for _, x in ipairs(liste or {}) do if x == v then return true end end
    return false
end

test("races : À la découverte de l'Alliance (93963) est pour les Skyborne de l'Alliance seuls", function()
    avec(true, function()
        local q = AzerothCommune:Lire(BASE)[93963]
        assertType("table", q.races)
        assertTrue(contient(q.races, 95), "Skyborne de l'Alliance (95)")
        assertTrue(not contient(q.races, 1), "pas les Humains")
    end)
end)

test("races : toute l'Alliance (952) est la liste explicite, Humain et Skyborne compris", function()
    avec(true, function()
        local q = AzerothCommune:Lire(BASE)[952]
        assertTrue(contient(q.races, 1), "Humain (1)")
        assertTrue(contient(q.races, 95), "Skyborne de l'Alliance (95)")
        assertTrue(not contient(q.races, 96), "pas les Skyborne de la Horde")
        assertNil(q.classes) -- toutes
    end)
end)

test("zone corrigée pour l'Alliance : Almanach de Nar'thalas (78124) est à Hurlevent", function()
    avec(true, function()
        assertEquals(1519, AzerothCommune:Lire(BASE)[78124].zone)
    end)
end)

test("/ac souscriptions montre la souscription à la base des quêtes", function()
    avec(true, function()
        local dits, garde = {}, print
        print = function(...) dits[#dits + 1] = table.concat({ ... }, " ") end
        local ok, err = pcall(SlashCmdList.AZEROTHCOMMUNE, "souscriptions")
        print = garde
        assertTrue(ok, err)
        local dit = table.concat(dits, "\n")
        assertTrue(dit:find(BASE .. " : souscrit le " .. date("%Y-%m-%d"), 1, true) ~= nil, dit)
    end)
end)
