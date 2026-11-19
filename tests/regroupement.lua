-- Regroupement dans wow-ui-sim (tools/sim.sh test LibCommune) : nos add-ons chargés ensemble se regroupent sous un seul
-- bouton de minicarte et une seule entrée des options, une sous-page par add-on présent.
test("un seul bouton de minicarte, avec les add-ons présents", function()
    local lib = LibStub("LibCommune-1.0")
    assertNotNil(_G.AzerothCommuneMinimapButton)
    assertEquals(lib.boutonCommun, _G.AzerothCommuneMinimapButton)
    assertTrue(_G.GameDataMinimapButton == nil) -- l'ancien bouton de GameData a disparu
    local noms = {}
    for _, r in ipairs(lib.regroupes) do noms[r.nom] = true end
    -- nos quatre add-ons chargés ensemble par tools/sim.sh, chacun une fois
    for _, nom in ipairs({ "Be a Good Pal", "GameData", "Handshake", "Négoce" }) do assertTrue(noms[nom] or false) end
    assertEquals(4, #lib.regroupes)
end)

test("une seule entrée Azeroth Commune, une sous-page par add-on", function()
    local lib = LibStub("LibCommune-1.0")
    local n = 0
    for _, g in ipairs(SettingsPanel:GetCategoryList().groups) do
        for _, c in ipairs(g.categories) do if c:GetName() == "Azeroth Commune" then n = n + 1 end end
    end
    assertEquals(1, n)
    assertEquals(lib.categorie, Settings.GetCategory(lib.categorie:GetID()))
    local sous = lib.categorie:GetSubcategories()
    assertEquals(#lib.regroupes, #sous)
    for i, r in ipairs(lib.regroupes) do assertEquals(r.nom, sous[i]:GetName()) end
end)
