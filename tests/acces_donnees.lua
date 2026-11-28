-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test AzerothCommune) : le socle chargé dans l'interface Forever
-- simulée, son API publique par le global AzerothCommune.
-- L'API publique, sous les noms de l'ancienne lib ; ni LibStub("LibCommune-1.0") ni GameDataAPI (ADR 0002).
local API = { "Lire", "Souscrire", "QuandReleve", "Signaler", "Personnage", "Destinataire", "Royaume", "MaisonHV", "Faction",
    "Build", "Sondes", "RelancerSondes", "DeclarerSonde", "Sonder", "Conteneurs", "EstSac", "EstBanque", "Fusionner",
    "PrixAchat", "PrixMarchands", "Fenetre", "Tableau", "TrierLignes", "Argent", "ArgentCourt", "ArgentSigne", "NomObjet",
    "RetenirObjet", "TrouverObjet", "ChercherObjets", "Capturer", "BoutonCapture", "Exporter", "JsonSur", "Regrouper", "Exports",
    "MaitresDuMetier", "Ecarts", "RechercheObjets", "RecevoirObjet", "QuandAchatHV" }

test("le global AzerothCommune porte l'API publique ; plus de LibCommune ni de GameDataAPI", function()
    assertType("table", AzerothCommune)
    for _, nom in ipairs(API) do assertType("function", AzerothCommune[nom]) end
    assertNil(GameDataAPI)
    assertNil(LibStub and LibStub("LibCommune-1.0", true))
    assertNil(AzerothCommune.versions)
    assertNil(AzerothCommune.listeSondes)
end)

test("type inconnu : indisponible avec raison", function()
    local lib = AzerothCommune
    local data, raison = lib:Lire("pas un type")
    assertNil(data)
    assertEquals("type inconnu", raison)
end)

test("recettes connues : données ou raison connue", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("recettes connues"))
    local data, raison = lib:Lire("recettes connues", "tous")
    if data then
        assertType("table", data.recettes)
        local n = 0 for _ in pairs(data.persos) do n = n + 1 end
        print("recettes connues : " .. n .. " personnage(s) lus dans la base")
    else
        assertEquals("pas encore relevé", raison)
        print("recettes connues indisponibles : " .. raison)
    end
end)

test("recettes connues sans fenêtre : l'API de Forever est là et le relevé tourne", function()
    assertType("function", IsPlayerSpell)
    assertType("function", GetProfessions)
    assertType("function", GetProfessionInfo)
    local lib = AzerothCommune
    local metiers, fini = {}, false
    -- sans métier, aucune recette candidate : le relevé finit tout de suite
    local ok = lib:ReleverRecettesSansFenetre(metiers, {}, function() fini = true end)
    assertTrue(ok)
    if next({ GetProfessions() }) == nil then assertTrue(fini) end
    assertNil(lib.RemettreRecettes) -- plus de remise par un add-on (#48)
end)

-- #48, #54 : la réserve extraite du client (RecettesReserve.lua, générée, hors du repo : à copier dans un worktree) est
-- chargée par la TOC du socle, privée ; elle se lit par la base des recettes, chaque recette avec sa provenance, sa
-- compétence requise et ses seuils jaune et gris.
local SOURCES = { ["d'emblée"] = true, ["maître"] = true, ["patron vendu"] = true, ["retirée"] = true, inconnue = true }
local COMPETENCES = { ["règle"] = true, incertaine = true, patron = true, ["extrait du client"] = true, ["relevé direct"] = true }
test("base des recettes : la réserve du socle chargée, chaque recette avec sa provenance", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    assertNil(HandshakeClassicRecipes)
    local data, lot = lib:Lire("base des recettes")
    assertNotNil(data, "base des recettes vide (RecettesReserve.lua présent ?)")
    assertType("table", lot)
    local reserve, vues = 0, 0
    for _, r in pairs(data) do
        if r.provenance == "extrait du client" then
            reserve = reserve + 1
            if r.output ~= nil then assertType("number", r.output) end -- nil : un enchantement (#64)
            assertType("string", r.profession)
            assertType("table", r.reagents)
            assertType("number", r.level) -- 0 : inconnue (Bottes d'hiver 44953 : absente de Classic, sans seuils dans le client)
            assertTrue(r.grey >= r.yellow, "seuils : " .. tostring(r.name))
            assertTrue(SOURCES[r.source], "source : " .. tostring(r.name) .. " " .. tostring(r.source))
            assertTrue(r.source_provenance == "extrait du client" or r.source_provenance == "source externe"
                or r.source_provenance == "relevé direct" and r.source == "maître") -- #83 : un maître de l'atelier
            if r.level_provenance == "relevé direct" then assertType("string", r.level_date) else assertNil(r.level_date) end
            assertType("number", r.cooldown)
            -- #81 : la provenance de la compétence ; la règle du décalage ne dépasse jamais le jaune (Boulettes fumées du désert :
            -- 305, jaune 325) ; un patron, seulement pour une recette « inconnue » ou « patron vendu », jamais au-dessus de 300
            assertTrue(COMPETENCES[r.level_provenance], "provenance de la compétence : " .. tostring(r.name) .. " " .. tostring(r.level_provenance))
            if r.level_provenance == "règle" then assertTrue(r.level >= 1 and r.level <= r.yellow, "règle au-dessus du jaune : " .. tostring(r.name)) end
            if r.level_provenance == "patron" then assertTrue((r.source == "inconnue" or r.source == "patron vendu") and r.level <= 300) end
            -- un patron vendu que Fabrikao seul connaît (#80) peut n'avoir pas de prix de base dans le client, mais il a ses marchands
            if r.pattern_price ~= nil then assertEquals("patron vendu", r.source) end
            if r.source == "patron vendu" then
                assertTrue(r.pattern_price ~= nil or r.marchands ~= nil, "patron vendu sans prix ni marchand : " .. tostring(r.name))
            end
        else
            vues = vues + 1
        end
    end
    assertTrue(reserve > 1000, "réserve chargée : " .. reserve .. " recettes")
    -- Une recette propre à Forever (potion de soins inférieure, passée au secourisme), absente de Classic.
    local potion = data[1244432]
    assertTrue(potion ~= nil and potion.profession == "Secourisme" and potion.output == 858, "recette de Forever")
    print("base des recettes : " .. vues .. " vue(s), " .. reserve .. " de la réserve")
end)

-- #64 : source, compétence pour l'apprendre, prix du patron et temps de recharge, sur les exemples vérifiés de l'issue ;
-- les enchantements d'objet entrent dans la réserve, sans objet produit.
test("base des recettes : source, compétence, patron et recharge de chaque recette", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    local data = lib:Lire("base des recettes")
    local rouleau, robe, lunaire = data[18401], data[18406], data[18560]
    assertEquals("maître", rouleau.source) -- Rouleau d'étoffe runique
    assertTrue(rouleau.level <= 210, "compétence du rouleau : " .. rouleau.level)
    assertEquals("patron vendu", robe.source) -- Robe en étoffe runique
    assertTrue(robe.pattern_price > 0)
    assertTrue(math.abs(lunaire.cooldown - 95 * 3600) < 3600, "recharge de l'étoffe lunaire : " .. lunaire.cooldown)
    assertEquals("inconnue", data[19435].source) -- Bottes en étoffe lunaire (recette de quête)
    assertEquals("d'emblée", data[2149].source) -- Bottes en cuir cousu main
    assertEquals("extrait du client", data[2149].source_provenance)
    local ench = data[13501] -- Ench. de bracelets (Endurance inférieure)
    assertNotNil(ench, "enchantement dans la réserve")
    assertNil(ench.output)
    assertEquals("Enchantement", ench.profession)
    assertTrue(#ench.reagents > 0 and ench.yellow > 0 and ench.grey >= ench.yellow)
    assertEquals("maître", ench.source)
end)

-- #81 : la compétence pour l'apprendre par la règle du décalage, rang Classic − (jaune Classic − jaune Forever) ; Fabrikao
-- « incertaine » pour une recette ajoutée par Forever ; le patron du client pour une recette de patron (Maitrise#15).
test("base des recettes : la compétence pour l'apprendre et sa provenance", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    local data = lib:Lire("base des recettes")
    local ceinture = data[2666] -- Ceinture runique en cuivre : 70 − (110 − 85), confirmé par le relevé de l'atelier (#83)
    assertEquals(45, ceinture.level)
    assertEquals("règle", data[2331].level_provenance) -- Potion de mana mineure : jamais vue chez un maître de l'atelier
    assertEquals("incertaine", data[1249630].level_provenance) -- Teinture céruléenne, ajoutée par Forever
    assertEquals("extrait du client", data[2149].level_provenance) -- d'emblée
    assertEquals("patron", data[1301421].level_provenance) -- Cotte forge-ciel nuageuse : le patron de Vayn Moongaze
end)

-- #83 : les relevés directs de l'atelier dans la réserve. Pantalon en anneaux de cuivre : la règle dit 1, Bengus Deepforge
-- enseigne à 15 ; Ardeur de palourde géante : Kelsey Yance (2664), dont Fabrikao ignore le prix, le vend 50 pa.
test("base des recettes : les relevés directs de l'atelier (maîtres et marchands visités)", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    local data, lot = lib:Lire("base des recettes")
    local pantalon = data[2662]
    assertEquals(15, pantalon.level)
    assertEquals("relevé direct", pantalon.level_provenance)
    assertEquals("maître", pantalon.source)
    assertType("string", pantalon.level_date)
    assertTrue(pantalon.level_date:match("^%d%d%d%d%-%d%d%-%d%d") ~= nil, "date du relevé : " .. pantalon.level_date)
    assertEquals("règle", data[2331].level_provenance) -- Potion de mana mineure : jamais vue chez un maître de l'atelier
    assertNil(data[2331].level_date)
    local yance
    for _, m in ipairs(data[7213].marchands) do if m.pnj == 2664 then yance = m end end
    assertNotNil(yance, "Kelsey Yance parmi les marchands du patron")
    assertEquals(5000, yance.prix)
    assertType("string", lot.marchands.releves)
end)

-- #80 : les marchands des patrons (Fabrikao, source externe), avec leur position et leur prix, et la position des maîtres.
test("base des recettes : le marchand de chaque patron vendu, sa position ; les maîtres d'un métier", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    local data, lot = lib:Lire("base des recettes")
    assertEquals("source externe", lot.marchands.provenance)
    assertEquals("Fabrikao", lot.marchands.source)
    assertType("string", lot.marchands.date)
    local n = 0
    for _, r in pairs(data) do
        if r.marchands then
            n = n + 1
            assertTrue(#r.marchands > 0, "liste vide : " .. tostring(r.name))
            for _, m in ipairs(r.marchands) do
                assertType("number", m.pnj)
                if m.carte then assertType("number", m.x) assertType("number", m.y) end
                if m.prix then assertTrue(m.prix > 0) end
                assertTrue(m.faction == nil or m.faction == "Alliance" or m.faction == "Horde")
            end
        end
    end
    assertTrue(n > 700, "recettes avec un marchand : " .. n)
    -- Patron propre à Forever : la série forge-ciel nuageuse de Vayn Moongaze (PNJ 254151), carte 2521.
    local cotte = data[1301421]
    assertEquals("patron vendu", cotte.source)
    assertEquals("source externe", cotte.source_provenance)
    assertEquals(254151, cotte.marchands[1].pnj)
    assertEquals("Vayn Moongaze", cotte.marchands[1].nom)
    assertEquals(2521, cotte.marchands[1].carte)
    assertNil(data[2149].marchands) -- Bottes en cuir cousu main : d'emblée, aucun marchand
    -- Patron de butin (Robe du Vide, patron 14514 lâché par Darkmaster Gandling) : pas de marchand, toujours « inconnue ».
    assertNil(data[18458].marchands)
    assertEquals("inconnue", data[18458].source)
    local forge, lotF = lib.MaitresDuMetier("Forge")
    assertEquals("source externe", lotF.provenance)
    assertTrue(#forge > 10, "maîtres de la Forge : " .. #forge)
    local places = 0
    for _, m in ipairs(forge) do
        assertType("number", m.pnj)
        assertType("string", m.nom)
        if m.carte then places = places + 1 end
    end
    assertTrue(places >= #forge - 1, "maîtres placés : " .. places .. "/" .. #forge)
    assertNil(lib.MaitresDuMetier("pas un métier"))
    print("base des recettes : " .. n .. " recettes avec un marchand ; " .. #forge .. " maîtres de la Forge")
end)

-- #49 : la recherche d'objets de la suite, parmi les objets vus et les objets fabriqués de la base des recettes.
test("recherche d'objets : objets fabriqués de la base des recettes, sans doublon, en nombre limité", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("objets"))
    assertTrue(lib:Souscrire("base des recettes"))
    local trouves = lib.ChercherObjets("bronze")
    assertEquals(8, #trouves)
    local vus = {}
    for _, e in ipairs(trouves) do
        assertType("number", e.id)
        assertType("string", e.name)
        assertNil(vus[e.id], "doublon : " .. e.id)
        vus[e.id] = true
    end
    assertTrue(trouves[1].fabricable, "fabricables d'abord")
    local pantalon = false
    for _, e in ipairs(lib.ChercherObjets("cuir cousu main", 30)) do pantalon = pantalon or e.id == 2303 end
    assertTrue(pantalon, "objet de la réserve trouvé par le nom de sa recette")
    assertEquals(0, #lib.ChercherObjets("b"))
end)

test("catalogue : chaque type se lit dans la base, ou pas encore relevé", function()
    local lib = AzerothCommune
    for nom, t in pairs(lib.types) do
        local data, raison = lib:Lire(nom, "tous")
        if not data then assertEquals("pas encore relevé", raison) end
    end
end)

test("souscription retenue par la base avec sa date, pour tout le joueur", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("marchands"))
    assertType("number", AzerothCommuneDB.souscriptions.marchands)
end)

test("provenance : chaque type lu rend son lot, au build du client simulé", function()
    assertType("function", GetBuildInfo)
    local version, build = GetBuildInfo()
    assertType("string", version)
    assertNotNil(tonumber(build))
    assertType("table", AzerothCommuneDB.lots) -- lots vérifiés au chargement de la base
    local lib = AzerothCommune
    for nom, t in pairs(lib.types) do
        local data, l = lib:Lire(nom, "tous")
        if data and not t.parPerso then assertType("table", l) end
        if data and t.parPerso then assertType("table", l.persos) end
    end
end)

test("sacs lus à l'instant : l'API des conteneurs de Forever est là", function()
    local lib = AzerothCommune
    assertType("table", Enum.BagIndex)
    assertType("function", lib.Conteneurs)
    local sacs = lib.Conteneurs(lib.EstSac)
    assertType("table", sacs)
    for nom, sac in pairs(sacs) do
        assertTrue(lib.EstSac(nom))
        assertType("number", sac.size)
        assertType("table", sac.items)
        for _, it in ipairs(sac.items) do -- chaque objet : son ID, sa quantité et son lien (LibCommune#20)
            assertType("number", it.id)
            assertType("number", it.count)
            assertType("string", it.link)
        end
    end
end)

test("signal « type relevé à nouveau » : les rappels appelés, sans crochet (le scan de l'HV lui-même : check.lua)", function()
    local lib = AzerothCommune
    local _, raison = lib:QuandReleve("pas un type", print)
    assertEquals("type inconnu", raison)
    local recus, actif = {}, true
    local function rappel(t) if actif then recus[#recus + 1] = t end end -- les rappels sont privés (#45) : il se tait
    assertTrue(lib:QuandReleve("cours de l'HV", rappel))
    assertNil(lib.AccrocherGameData)
    assertNil(lib.rappels)
    lib:Signaler("cours de l'HV")
    actif = false
    assertEquals(1, #recus)
    assertEquals("cours de l'HV", recus[1])
end)

test("personnage connecté : GUID et nom, plus d'adresse ; chuchoté par son nom complet", function()
    local lib = AzerothCommune
    local p = lib.Personnage()
    assertType("string", p.guid)
    assertEquals(UnitGUID("player"), p.guid)
    assertType("string", p.nom)
    assertNil(p.adresse)
    assertEquals(p.nom, lib.Destinataire(p.nom))
    print("personnage : " .. p.guid .. " / " .. p.nom)
end)

test("lire par GUID : persos rangé par GUID", function()
    local lib = AzerothCommune
    local data = lib:Lire("inventaires", "tous")
    if not data then lib:Souscrire("inventaires"); SlashCmdList.AZEROTHCOMMUNE("") data = lib:Lire("inventaires", "tous") end -- /ac : relevé tout de suite
    assertNotNil(data, "inventaires relevés par la base")
    local n = 0
    for cle in pairs(data.persos) do n = n + 1; assertTrue(cle:find("^Player%-") ~= nil, "clé " .. cle) end
    assertTrue(n > 0, "au moins le personnage connecté")
    local moi = lib:Lire("inventaires", UnitGUID("player"))
    assertNotNil(moi and moi.persos[UnitGUID("player")], "lu par son GUID")
    assertEquals(lib.Personnage().nom, moi.persos[UnitGUID("player")].character.name)
end)

test("prix d'achat exposé par la lib : un coût ou rien, sans erreur", function()
    local lib = AzerothCommune
    assertType("function", lib.PrixAchat)
    assertType("table", lib:PrixMarchands())
    local c, src = lib:PrixAchat(2772, 5)
    if c then assertType("number", c); assertTrue(src == "marchand" or src == "HV") end
    assertEquals(300, (lib:PrixAchat(1, 3, { [1] = { min = 100 } }, {})))
end)

-- #69 : un gain de compétence (SKILL_LINES_CHANGED) relit tout de suite les métiers et le signale (QuandReleve).
test("gain de compétence : les métiers relus aussitôt et signalés", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("métiers et compétences"))
    local recus = 0
    assertTrue(lib:QuandReleve("métiers et compétences", function() recus = recus + 1 end))
    local gp, gpi = GetProfessions, GetProfessionInfo
    GetProfessions = function() return 1 end
    GetProfessionInfo = function() return "Forge", "icône", 42, 75 end
    local ok, err = pcall(function()
        FireEvent("SKILL_LINES_CHANGED")
        assertEquals(1, recus)
        local d = lib:Lire("métiers et compétences", UnitGUID("player"))
        local _, fiche = next(d and d.persos or {})
        assertNotNil(fiche, "fiche du perso")
        assertEquals("Forge", fiche.professions[1].name)
        assertEquals(42, fiche.professions[1].rank)
        -- En combat aussi (un bandage, un dépeçage, une récolte font monter un métier).
        local icl = InCombatLockdown
        InCombatLockdown = function() return true end
        GetProfessionInfo = function() return "Forge", "icône", 43, 75 end
        local ok2, err2 = pcall(FireEvent, "SKILL_LINES_CHANGED")
        InCombatLockdown = icl
        assert(ok2, err2)
        assertEquals(2, recus, "signalé en combat")
        -- Liste vide (écran de chargement) : rien d'écrasé, rien de signalé.
        GetProfessions = function() return nil, nil, nil, nil, nil end
        FireEvent("SKILL_LINES_CHANGED")
        assertEquals(2, recus, "liste vide : pas de signal")
        _, fiche = next(lib:Lire("métiers et compétences", UnitGUID("player")).persos)
        assertEquals(43, fiche.professions[1].rank, "liste vide : la fiche reste")
    end)
    GetProfessions, GetProfessionInfo = gp, gpi
    assert(ok, err)
end)

-- #70, #71 : la réserve porte le temps d'incantation et les outils demandés, extraits du client.
test("base des recettes : temps d'incantation et outils demandés (Ceinture runique en cuivre : 8 s, marteau de forgeron)", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    local r = lib:Lire("base des recettes")[2666]
    assertNotNil(r, "Ceinture runique en cuivre")
    assertEquals(8, r.cast)
    assertNotNil(r.outils, "outils")
    assertEquals("Marteau de forgeron", r.outils[1].nom)
    local marteau = false
    for _, o in ipairs(r.outils[1].objets) do marteau = marteau or o == 5956 end
    assertTrue(marteau, "le marteau de forgeron (5956) convient")
end)
