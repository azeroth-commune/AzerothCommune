-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test LibCommune) : la lib chargée avec GameData et Handshake dans l'interface Forever simulée.
test("LibCommune-1.0 est enregistrée", function()
    assertNotNil(LibStub and LibStub("LibCommune-1.0", true))
end)

test("type inconnu : indisponible avec raison", function()
    local lib = LibStub("LibCommune-1.0")
    local data, raison = lib:Lire("pas un type")
    assertNil(data)
    assertEquals("type inconnu", raison)
end)

test("recettes connues : données ou raison connue", function()
    local lib = LibStub("LibCommune-1.0")
    assertTrue(lib:Souscrire("recettes connues"))
    local data, raison = lib:Lire("recettes connues", "tous")
    if data then
        assertType("table", data.recettes)
        local n = 0 for _ in pairs(data.persos) do n = n + 1 end
        print("recettes connues : " .. n .. " personnage(s) lus via GameData")
    else
        assertContains({ "pas encore relevé", "pas de GameData" }, raison)
        print("recettes connues indisponibles : " .. raison)
    end
end)

test("GameData expose recettesConnues à la lib", function()
    assertType("function", GameDataAPI and GameDataAPI.recettesConnues)
end)

test("recettes connues sans fenêtre : l'API de Forever est là et le relevé tourne", function()
    assertType("function", IsPlayerSpell)
    assertType("function", GetProfessions)
    assertType("function", GetProfessionInfo)
    local lib = LibStub("LibCommune-1.0")
    local metiers, fini = {}, false
    -- sans recette candidate (réserve de Handshake mise de côté), le relevé finit tout de suite, sans attendre d'image
    local reserve = HandshakeClassicRecipes
    HandshakeClassicRecipes = nil
    local ok = lib:ReleverRecettesSansFenetre(metiers, {}, function() fini = true end)
    HandshakeClassicRecipes = reserve
    assertTrue(ok)
    assertTrue(fini)
end)

test("catalogue : chaque type a son accesseur dans GameData", function()
    local lib = LibStub("LibCommune-1.0")
    for nom, t in pairs(lib.types) do
        assertType("function", GameDataAPI[t.gamedata])
        local data, raison = lib:Lire(nom, "tous")
        if not data then assertEquals("pas encore relevé", raison) end
    end
end)

test("souscription retenue par GameData avec sa date, pour tout le joueur", function()
    local lib = LibStub("LibCommune-1.0")
    -- Handshake a souscrit aux recettes connues pendant le chargement : retenu à la connexion
    assertType("number", GameDataDB.souscriptions and GameDataDB.souscriptions["recettes connues"])
    assertTrue(lib:Souscrire("marchands"))
    assertType("number", GameDataDB.souscriptions.marchands)
    assertTrue(GameDataAPI.souscrit("marchands"))
end)

test("provenance : un lot porte le build du client simulé, et chaque type lu rend son lot", function()
    assertType("function", GetBuildInfo)
    local version, build = GetBuildInfo()
    assertType("string", version)
    assertNotNil(tonumber(build))
    assertType("table", GameDataDB.lots) -- lots vérifiés au chargement de GameData
    local lot = GameDataAPI.lot()
    assertEquals("relevé direct", lot.provenance)
    assertEquals(tonumber(build), lot.build)
    assertType("string", lot.date)
    local lib = LibStub("LibCommune-1.0")
    for nom, t in pairs(lib.types) do
        local data, l = lib:Lire(nom, "tous")
        if data and not t.parPerso then assertType("table", l) end
        if data and t.parPerso then assertType("table", l.persos) end
    end
end)

test("sacs lus à l'instant : l'API des conteneurs de Forever est là (relevé de repli des inventaires)", function()
    local lib = LibStub("LibCommune-1.0")
    assertType("table", Enum.BagIndex)
    assertType("function", lib.Conteneurs)
    local sacs = lib.Conteneurs(lib.EstSac)
    assertType("table", sacs)
    for nom, sac in pairs(sacs) do
        assertTrue(lib.EstSac(nom))
        assertType("number", sac.size)
        assertType("table", sac.items)
    end
end)

test("signal « type relevé à nouveau » : le scan de l'HV de GameData appelle les rappels", function()
    local lib = LibStub("LibCommune-1.0")
    local _, raison = lib:QuandReleve("pas un type", print)
    assertEquals("type inconnu", raison)
    local recus = {}
    local function rappel(t) recus[#recus + 1] = t end
    assertTrue(lib:QuandReleve("cours de l'HV", rappel))
    assertTrue(lib.accrocheGameData)
    GameDataAPI.marketScanned() -- ce que GameData appelle à la fin d'une lecture de l'HV
    local l = lib.rappels["cours de l'HV"]
    for i = #l, 1, -1 do if l[i] == rappel then table.remove(l, i) end end
    assertEquals(1, #recus)
    assertEquals("cours de l'HV", recus[1])
end)

test("personnage connecté : GUID, adresse au royaume normalisé, nom ; lu par son GUID", function()
    local lib = LibStub("LibCommune-1.0")
    local p = lib.Personnage()
    assertType("string", p.guid)
    assertEquals(UnitGUID("player"), p.guid)
    local royaume = GetNormalizedRealmName():gsub("[%s%-]", "")
    assertEquals((UnitName("player")) .. "-" .. royaume, p.adresse)
    assertType("string", p.nom)
    assertEquals((UnitName("player")), lib.Destinataire(p.adresse))
    print("personnage : " .. p.guid .. " / " .. p.adresse .. " / " .. p.nom)
end)

test("lire par GUID : persos rangé par GUID", function()
    local lib = LibStub("LibCommune-1.0")
    local data = lib:Lire("inventaires", "tous")
    if not data then SlashCmdList.GAMEDATA("") data = lib:Lire("inventaires", "tous") end -- /gdata : relevé tout de suite
    assertNotNil(data, "inventaires relevés par GameData")
    local n = 0
    for cle in pairs(data.persos) do n = n + 1; assertTrue(cle:find("^Player%-") ~= nil, "clé " .. cle) end
    assertTrue(n > 0, "au moins le personnage connecté")
    local moi = lib:Lire("inventaires", UnitGUID("player"))
    assertNotNil(moi and moi.persos[UnitGUID("player")], "lu par son GUID")
    assertEquals(lib.Personnage().nom, moi.persos[UnitGUID("player")].character.name)
end)
