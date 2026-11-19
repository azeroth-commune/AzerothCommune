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
    assertTrue(lib:Demander("recettes connues"))
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
