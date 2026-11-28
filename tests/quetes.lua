-- Base des quêtes dans wow-ui-sim (tools/sim.sh test AzerothCommune). Deux blocs, jamais mélangés : QuestieDB en direct
-- (#111, QuetesQuestieDB.lua : LibQuestieDB présent et contrat accepté), sinon la réserve QuetesReserve.lua (#43, #112),
-- la sortie du même convertisseur, un texte par faction (tools/reserve_quetes.sh de l'atelier), commitée, chargée par le
-- TOC ; seule la faction du perso est servie. Rien sans souscription.
-- Le simulateur ne charge pas QuestieDB de lui-même (suffixe _Forever de sa TOC, research/questiedb/NOTES.md de l'atelier) :
-- la réserve est testée sans LibQuestieDB, le direct avec une fausse LibQuestieDB posée le temps d'un test (le vrai est remis
-- après) ; les tests « vrai QuestieDB » ne tournent que s'il a été ajouté aux racines.
local BASE = "base des quêtes"

-- La souscription du type et LibQuestieDB le temps d'un test (une autre a pu souscrire avant : remise après).
-- qdb : la LibQuestieDB du test, nil : QuestieDB absent. faction (facultative) : celle du perso le temps du test.
local function avec(souscrit, fn, qdb, faction)
    local avant, vrai, uf = AzerothCommuneDB.souscriptions and AzerothCommuneDB.souscriptions[BASE], LibQuestieDB, UnitFactionGroup
    AzerothCommuneDB.souscriptions = AzerothCommuneDB.souscriptions or {}
    AzerothCommuneDB.souscriptions[BASE] = nil
    if souscrit then assertTrue(AzerothCommune:Souscrire(BASE)) end
    LibQuestieDB = qdb
    if faction then UnitFactionGroup = function(u) if u == "player" then return faction, faction end return uf(u) end end
    local ok, err = pcall(fn)
    AzerothCommuneDB.souscriptions[BASE], LibQuestieDB, UnitFactionGroup = avant, vrai, uf
    if not ok then error(err, 0) end -- assertTrue tairait la raison
end

-- Une ligne au journal du simulateur (print va au chat simulé, invisible) : grep 'QUETES|'.
local function dire(...) io.stdout:write("QUETES|", string.format(...), "\n") end

local function taille(d)
    local n = 0
    for _ in pairs(d) do n = n + 1 end
    return n
end

-- En premier : rien n'a encore lu la réserve dans ce lancement (Compagnie, s'il est chargé, lit la base en direct).
test("vrai QuestieDB chargé : la réserve n'a construit aucune table (la construire, maintenant, prend de la mémoire)", function()
    if not LibQuestieDB then dire("QuestieDB pas chargé au simulateur : sauté") return end
    avec(true, function()
        local direct = AzerothCommune:Lire(BASE) -- gardée : relire sans QuestieDB lâche la base en direct
        collectgarbage("collect")
        local avant = collectgarbage("count")
        LibQuestieDB = nil
        local r, lot = AzerothCommune:Lire(BASE)
        collectgarbage("collect")
        local pris = collectgarbage("count") - avant
        dire("réserve (%s, %d quêtes) construite à la demande : %.0f Ko ; jusque-là rien (base en direct : %d quêtes)",
            tostring(AzerothCommune.Faction()), taille(r), pris, taille(direct))
        assertEquals("source externe", lot.provenance)
        assertTrue(pris > 300, ("%.0f Ko : la réserve était déjà construite"):format(pris))
    end, LibQuestieDB)
end)

local function contient(liste, v)
    for _, x in ipairs(liste or {}) do if x == v then return true end end
    return false
end

-- Les print le temps de fn : la liste de ce qui a été dit.
local function dits(fn)
    local l, garde = {}, print
    print = function(...) l[#l + 1] = table.concat({ ... }, " ") end
    local ok, err = pcall(fn)
    print = garde
    if not ok then error(err, 0) end -- assertTrue tairait la raison
    return l
end

test("sans souscription, la base des quêtes ne rend rien", function()
    avec(false, function()
        local d, raison = AzerothCommune:Lire(BASE)
        assertNil(d)
        assertEquals("pas encore relevé", raison)
    end)
end)

test("après souscription : la réserve et sa provenance (QuestieDB, version, date)", function()
    avec(true, function()
        local d, lot = AzerothCommune:Lire(BASE)
        assertType("table", d)
        assertEquals("source externe", lot.provenance)
        assertEquals("QuestieDB", lot.source)
        assertTrue(lot.version:find("^%d+%.%d+%.%d+") ~= nil, lot.version)
        assertTrue(lot.date:find("^%d%d%d%d%-%d%d%-%d%d$") ~= nil, lot.date)
        lot.source = "modifié" -- le lot rendu est une copie
        assertEquals("QuestieDB", (select(2, AzerothCommune:Lire(BASE))).source)
    end)
end)

-- QuestieDB absent : la réserve de la faction du perso, les quêtes des deux factions dans chacune (#112).
test("QuestieDB absent, perso de l'Alliance : ses quêtes et celles des deux factions, pas celles de la Horde", function()
    avec(true, function()
        local d, lot = AzerothCommune:Lire(BASE)
        assertEquals("source externe", lot.provenance)
        assertEquals("Bosquet des Anciens", d[952].nom) -- Alliance
        assertEquals("Brawl at the Maul", d[99233].nom) -- les deux factions
        assertNil(d[4641], "Votre place en ce monde : la Horde")
        assertEquals(653, d[687].prerequis_un[1]) -- correction de faction de QuestieDB, côté Alliance
        assertTrue(taille(d) > 3000, taille(d))
    end, nil, "Alliance")
end)

test("QuestieDB absent, perso de la Horde : ses quêtes et celles des deux factions, pas celles de l'Alliance", function()
    avec(true, function()
        local d, lot = AzerothCommune:Lire(BASE)
        assertEquals("source externe", lot.provenance)
        assertEquals("QuestieDB", lot.source)
        local q = d[4641] -- Votre place en ce monde, chez les orcs
        assertEquals("Votre place en ce monde", q.nom)
        assertTrue(contient(q.races, 2) and contient(q.races, 96) and not contient(q.races, 1), "races de la Horde")
        assertEquals(10176, q.donneur.pnj) -- Kaltunk
        assertEquals("Brawl at the Maul", d[99233].nom) -- les deux factions
        assertNil(d[952], "Bosquet des Anciens : l'Alliance")
        -- Corrections de faction de QuestieDB, côté Horde : prérequis et donneur de 687, zone de 78124 (Fossoyeuse).
        assertEquals(688, d[687].prerequis_un[1])
        assertEquals(2787, d[687].donneur.pnj)
        assertEquals(1497, d[78124].zone)
        assertTrue(taille(d) > 3000, taille(d))
    end, nil, "Horde")
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

test("objet de départ : Le collecteur (123) part du Plan de route du Collecteur, lâché par les gnolls Rivepatte", function()
    avec(true, function()
        local q = AzerothCommune:Lire(BASE)[123]
        assertEquals(1307, q.objet)
        assertEquals("Plan de route du Collecteur", q.origine.nom)
        assertTrue(contient(q.origine.pnjs, "Rivepatte chétif"), "lâché par les Rivepatte chétifs")
        assertTrue(#q.origine.pnjs <= 3, "3 noms au plus")
        assertNil(AzerothCommune:Lire(BASE)[952].origine) -- sans objet de départ
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

---------------------------------------------------------------------------------------------------
-- QuestieDB en direct (#111). Une fausse LibQuestieDB, de la forme de QuestieDB 1.1.6 (contrat 4) : Entité.Get(id, champ)
-- (un nombre absent se lit 0, startedBy absent {}), GetAllIds, Exists, Enum (bits des races, Skyborne aux bits 2^32 / 2^33),
-- Support.Get("ZoneDB") (areaID -> uiMapID, du texte « return {…} »). Faction du perso du simulateur : F ; l'autre : O.
local F = AzerothCommune.Faction() or "Alliance"
local O = F == "Alliance" and "Horde" or "Alliance"
local MASQUES = { Alliance = 1 + 4 + 8 + 64 + 2 ^ 32, Horde = 2 + 16 + 32 + 128 + 2 ^ 33 }
local RACES_F = F == "Alliance" and { 1, 3, 4, 7, 95 } or { 2, 5, 6, 8, 96 }

local function entite(donnees)
    local NOMBRES = { zoneOrSort = true, questLevel = true, requiredLevel = true, requiredRaces = true,
        requiredClasses = true, nextQuestInChain = true, breadcrumbForQuestId = true }
    local ids = {}
    for id in pairs(donnees) do ids[#ids + 1] = id end
    table.sort(ids)
    return {
        Get = function(id, champ)
            local v = donnees[id] and donnees[id][champ]
            if v == nil and NOMBRES[champ] then return 0 end
            if v == nil and champ == "startedBy" then return {} end
            return v
        end,
        GetAllIds = function() return ids end,
        Exists = function(id) return donnees[id] ~= nil end,
    }
end

-- contrat : ce que rend RequireContract(4) (défaut : accepté). addonName : un add-on chargé au simulateur, pour lire une
-- version par GetAddOnMetadata comme le socle le fait pour QuestieDB.
local function fausseQuestieDB(contrat)
    return {
        addonName = "AzerothCommune",
        RequireContract = function(v) if contrat ~= nil then return contrat, "contract mismatch" end return v == 4 end,
        Enum = { raceMaskById = { [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128, [95] = 2 ^ 32, [96] = 2 ^ 33 },
            factionRaceMasks = MASQUES },
        Support = { Get = function(n) if n == "ZoneDB" then
            return { private = { areaIdToUiMapId = "return {[12]=1429,[5]=1411,[7]=1}", areaIdToUiMapIdOverride = "return {[7]=0}" } }
        end end },
        Quest = entite({
            [101] = { name = "Première", zoneOrSort = 12, questLevel = 5, requiredLevel = 3, requiredRaces = MASQUES[F],
                startedBy = { { 1001 } }, nextQuestInChain = 102 },
            [102] = { name = "Deuxième", zoneOrSort = 12, questLevel = 6, preQuestSingle = { 101 }, startedBy = { { 1002, 1001 } } },
            [103] = { name = "Amorce", zoneOrSort = 12, breadcrumbForQuestId = 102, startedBy = { {}, { 2001 } } },
            [104] = { name = "Lettre trouvée", zoneOrSort = 7, startedBy = { {}, {}, { 3001 } } },
            [105] = { name = "Autre faction", zoneOrSort = 12, requiredRaces = MASQUES[O], preQuestSingle = { 101 },
                startedBy = { { 1001 } } },
            [106] = { name = "Quête de classe", zoneOrSort = -101, requiredClasses = 1 + 8, preQuestGroup = {} },
        }),
        Npc = entite({
            [1001] = { name = "Ami", friendlyToFaction = "AH", spawns = { [5] = { { 1, 1 } }, [12] = { { 40.123, 50.456 } } } },
            [1002] = { name = "Ennemi", friendlyToFaction = O:sub(1, 1), spawns = { [12] = { { 10, 10 } } } },
            [1003] = { name = "Kobold" }, [1004] = { name = "Kobold" }, [1005] = { name = "Chef kobold" },
            [1006] = { name = "Mineur" }, [1007] = { name = "Contremaître" },
        }),
        Object = entite({ [2001] = { name = "Coffre", spawns = { [12] = { { -1, -1 } } } } }),
        Item = entite({ [3001] = { name = "Lettre", npcDrops = { 1003, 1004, 1005, 1006, 1007 } } }),
    }
end

test("QuestieDB absent : la réserve, lot « source externe », sans message", function()
    local l = dits(function()
        avec(true, function()
            local d, lot = AzerothCommune:Lire(BASE)
            assertEquals("source externe", lot.provenance)
            assertType("table", d[952])
        end, nil)
    end)
    assertEquals(0, #l, table.concat(l, " | "))
end)

test("rien sans souscription, même avec QuestieDB", function()
    avec(false, function()
        local d, raison = AzerothCommune:Lire(BASE)
        assertNil(d)
        assertEquals("pas encore relevé", raison)
    end, fausseQuestieDB())
end)

test("QuestieDB en direct : la base de la faction du perso, lot « autre add-on » et sa version", function()
    avec(true, function()
        local d, lot = AzerothCommune:Lire(BASE)
        assertEquals("autre add-on", lot.provenance)
        assertEquals("QuestieDB", lot.source)
        assertEquals(C_AddOns.GetAddOnMetadata("AzerothCommune", "Version"), lot.version)
        assertNil(d[952], "pas de mélange avec la réserve")
        assertNil(d[105], "une quête de l'autre faction seulement : absente")
        local n = 0
        for _ in pairs(d) do n = n + 1 end
        assertEquals(5, n)
        lot.source = "modifié" -- le lot rendu est une copie
        assertEquals("QuestieDB", (select(2, AzerothCommune:Lire(BASE))).source)
    end, fausseQuestieDB())
end)

-- Même forme que la réserve : champs nommés, listes triées de questID, nil quand vides, donneur { pnj | objet, nom, carte,
-- x, y }, origine { nom, pnjs, objets } (3 noms au plus, sans doublon).
local function memes(attendu, vu, ou)
    if type(attendu) ~= "table" then return assertEquals(attendu, vu, ou) end
    assertType("table", vu, ou)
    for k, v in pairs(attendu) do memes(v, vu[k], ou .. "." .. k) end
    for k in pairs(vu) do assertNotNil(attendu[k], ou .. "." .. k .. " en trop") end
end

test("QuestieDB en direct : suites inversées, amorces, donneur, objet de départ et origine, comme la réserve", function()
    avec(true, function()
        local d = AzerothCommune:Lire(BASE)
        memes({ nom = "Première", zone = 12, niveau = 5, niveau_requis = 3, races = RACES_F, suites = { 102 },
            donneur = { pnj = 1001, nom = "Ami", carte = 1429, x = 40.12, y = 50.46 } }, d[101], "101")
        memes({ nom = "Deuxième", zone = 12, niveau = 6, prerequis_un = { 101 }, amorces = { 103 },
            donneur = { pnj = 1001, nom = "Ami", carte = 1429, x = 40.12, y = 50.46 } }, d[102], "102 (1002 : ennemi)")
        memes({ nom = "Amorce", zone = 12, donneur = { objet = 2001, nom = "Coffre", carte = 1429 } }, d[103], "103 (hors carte)")
        memes({ nom = "Lettre trouvée", zone = 7, objet = 3001,
            origine = { nom = "Lettre", pnjs = { "Kobold", "Chef kobold", "Mineur" } } }, d[104], "104 (carte masquée)")
        memes({ nom = "Quête de classe", zone = -101, classes = { 1, 4 } }, d[106], "106")
        -- La réserve a la même forme (un vrai cas de chaque) : donneur PNJ, objet du monde, objet de départ.
        LibQuestieDB = nil
        local r = AzerothCommune:Lire(BASE)
        for _, q in ipairs({ r[952], d[101] }) do assertType("number", q.donneur.pnj); assertNil(q.donneur.objet) end
        for _, q in ipairs({ r[940], d[103] }) do assertType("number", q.donneur.objet); assertNil(q.donneur.pnj) end
        for _, q in ipairs({ r[123], d[104] }) do assertType("string", q.origine.nom); assertType("table", q.origine.pnjs) end
    end, fausseQuestieDB())
end)

test("QuestieDB incompatible (contrat refusé) : la réserve, et la sonde prévient une seule fois", function()
    local l = dits(function()
        avec(true, function()
            for _ = 1, 2 do assertEquals("source externe", (select(2, AzerothCommune:Lire(BASE))).provenance) end
        end, fausseQuestieDB(false))
        avec(true, function() AzerothCommune:Lire(BASE) end, fausseQuestieDB(false)) -- une autre LibQuestieDB refusée
    end)
    assertEquals(1, #l, table.concat(l, " | "))
    assertTrue(l[1]:find("QuestieDB", 1, true) ~= nil, l[1])
    assertEquals("rouge", AzerothCommune.Sondes().QuestieDB.etat)
end)

test("vrai QuestieDB chargé au simulateur (lien QuestieDB.toc, NOTES.md de l'atelier) : toute sa base, en direct", function()
    if not LibQuestieDB then dire("QuestieDB pas chargé au simulateur : sauté") return end
    avec(true, function()
        local d, lot = AzerothCommune:Lire(BASE)
        local n = 0
        for _ in pairs(d) do n = n + 1 end
        dire("QuestieDB %s en direct : %d quêtes (%s)", tostring(lot.version), n, tostring(F))
        assertEquals("autre add-on", lot.provenance)
        assertEquals(C_AddOns.GetAddOnMetadata("QuestieDB", "Version"), lot.version)
        assertTrue(n > 4000, n)
    end, LibQuestieDB)
end)

-- La réserve est la sortie du même convertisseur (#112) : sur le vrai QuestieDB de la même version, en français comme elle,
-- la base en direct de la faction du perso et sa réserve rendent exactement la même chose, quête par quête.
test("vrai QuestieDB de la version de la réserve : la réserve et la base en direct rendent la même chose", function()
    if not LibQuestieDB then dire("QuestieDB pas chargé au simulateur : sauté") return end
    local vrai = LibQuestieDB
    avec(true, function()
        LibQuestieDB = nil
        local r, lotR = AzerothCommune:Lire(BASE)
        if lotR.version ~= C_AddOns.GetAddOnMetadata("QuestieDB", "Version") then
            dire("réserve de QuestieDB %s, QuestieDB %s chargé : comparaison sautée", lotR.version,
                tostring(C_AddOns.GetAddOnMetadata("QuestieDB", "Version")))
            return
        end
        vrai.l10n.SetLocale("frFR")
        LibQuestieDB = setmetatable({}, { __index = vrai }) -- une autre table : le socle refait sa base, en français
        local ok, d, lotD = pcall(AzerothCommune.Lire, AzerothCommune, BASE)
        vrai.l10n.SetLocale(GetLocale())
        assert(ok, d)
        assertEquals("autre add-on", lotD.provenance)
        assertEquals(taille(r), taille(d))
        for id, q in pairs(d) do memes(q, r[id], tostring(id)) end
        dire("réserve et base en direct (%s, QuestieDB %s) : %d quêtes identiques", tostring(F), lotR.version, taille(d))
    end, vrai)
end)
