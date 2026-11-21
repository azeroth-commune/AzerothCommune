-- Regroupement dans wow-ui-sim (tools/sim.sh test LibCommune) : nos add-ons chargés ensemble se regroupent sous un seul
-- bouton de minicarte et une seule entrée des options, une sous-page par add-on présent.
test("un seul bouton de minicarte, avec les add-ons présents", function()
    local lib = LibStub("LibCommune-1.0")
    assertNotNil(_G.AzerothCommuneMinimapButton)
    assertEquals(lib.boutonCommun, _G.AzerothCommuneMinimapButton)
    assertTrue(_G.GameDataMinimapButton == nil) -- l'ancien bouton de GameData a disparu
    local noms = {}
    for _, r in ipairs(lib.regroupes) do
        assertNil(noms[r.nom], "regroupé deux fois : " .. r.nom)
        noms[r.nom] = true
    end
    -- nos quatre add-ons chargés ensemble par tools/sim.sh, chacun une fois ; d'autres add-ons de l'atelier (Diagnostic)
    -- peuvent s'y ajouter selon les racines du simulateur
    for _, nom in ipairs({ "Be a Good Pal", "GameData", "Handshake", "Négoce" }) do assertTrue(noms[nom] or false, nom) end
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

-- Outils déclarés par lib.Regrouper{ outils } (LibCommune#21) : sous la ligne de leur add-on dans le menu du bouton.
test("outils du Négoce sous sa ligne dans le menu du bouton commun", function()
    local lignes, vrai = {}, MenuUtil.CreateContextMenu
    MenuUtil.CreateContextMenu = function(_, gen)
        gen(nil, { CreateTitle = function() end, CreateDivider = function() end,
            CreateButton = function(_, t) lignes[#lignes + 1] = (t:gsub("|T.-|t ", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")) end })
    end
    local ok, err = pcall(AzerothCommuneMinimapButton:GetScript("OnClick"), AzerothCommuneMinimapButton, "LeftButton")
    MenuUtil.CreateContextMenu = vrai
    assertTrue(ok, tostring(err))
    local i
    for k, l in ipairs(lignes) do if l == "Négoce" then i = k end end
    assertNotNil(i)
    assertEquals("Mécréant", lignes[i + 1])
    assertEquals("Journal", lignes[i + 2])
    assertEquals("Alertes HV", lignes[i + 3])
    print("menu : " .. table.concat(lignes, " | "))
end)

test("exports de tous les add-ons regroupés, déclarés à la lib", function()
    local cles = {}
    for _, e in ipairs(LibStub("LibCommune-1.0").Exports()) do cles[e.cle] = e.addon end
    assertEquals("GameData", cles.perso)
    assertEquals("GameData", cles.hv)
    assertEquals("Négoce", cles.journal)
    assertEquals("Négoce", cles.mecreant)
end)
