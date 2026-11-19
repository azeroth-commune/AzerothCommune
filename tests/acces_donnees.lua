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
