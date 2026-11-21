-- Regroupement dans wow-ui-sim (tools/sim.sh test AzerothCommune) : les add-ons présents se regroupent sous un seul
-- bouton de minicarte et une seule entrée des options, la page du socle, une sous-page par add-on. Le socle n'a pas de
-- ligne à lui. Indépendant des autres add-ons chargés : un add-on d'essai se regroupe après l'entrée en jeu.
local ouverts = {}
local function essai()
    for _, r in ipairs(AzerothCommune.regroupes) do if r.nom == "Essai" then return r end end
    local r = { nom = "Essai", ouvrir = function() ouverts[#ouverts + 1] = "essai" end,
        outils = { { libelle = "Outil d'essai", ouvrir = function() ouverts[#ouverts + 1] = "outil" end } },
        exports = { { cle = "essai", libelle = "Essai", donnees = function() return {} end } } }
    AzerothCommune.Regrouper(r)
    return r
end

test("une seule entrée Azeroth Commune, la page du socle, une sous-page par add-on", function()
    local lib = AzerothCommune
    essai()
    local n, categorie = 0, nil -- l'entrée du socle est privée : trouvée par son nom
    for _, g in ipairs(SettingsPanel:GetCategoryList().groups) do
        for _, c in ipairs(g.categories) do if c:GetName() == "Azeroth Commune" then n, categorie = n + 1, c end end
    end
    assertEquals(1, n)
    assertEquals(categorie, Settings.GetCategory(categorie:GetID()))
    local sous = categorie:GetSubcategories()
    assertEquals(#lib.regroupes, #sous)
    for i, r in ipairs(lib.regroupes) do assertEquals(r.nom, sous[i]:GetName()) end
end)

test("un seul bouton de minicarte ; le socle n'a pas de ligne dans son menu", function()
    local lib = AzerothCommune
    essai()
    assertNotNil(_G.AzerothCommuneMinimapButton)
    assertNil(lib.boutonCommun) -- privé (#45) : le bouton n'est connu que par son nom de cadre
    assertTrue(_G.GameDataMinimapButton == nil)
    local noms = {}
    for _, r in ipairs(lib.regroupes) do
        assertNil(noms[r.nom], "regroupé deux fois : " .. r.nom)
        noms[r.nom] = true
    end
    assertNil(noms["Azeroth Commune"])
    assertNil(noms["GameData"])
end)

test("clic sur le bouton : seul, l'add-on s'ouvre ; à plusieurs, ses outils sous sa ligne", function()
    essai()
    local lignes, vrai = {}, MenuUtil.CreateContextMenu
    MenuUtil.CreateContextMenu = function(_, gen)
        gen(nil, { CreateTitle = function() end, CreateDivider = function() end,
            CreateButton = function(_, t) lignes[#lignes + 1] = (t:gsub("|T.-|t ", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")) end })
    end
    ouverts = {}
    local ok, err = pcall(AzerothCommuneMinimapButton:GetScript("OnClick"), AzerothCommuneMinimapButton, "LeftButton")
    MenuUtil.CreateContextMenu = vrai
    assertTrue(ok, tostring(err))
    if #AzerothCommune.regroupes == 1 then
        assertEquals("essai", ouverts[1])
        assertEquals(0, #lignes)
    else
        local i
        for k, l in ipairs(lignes) do if l == "Essai" then i = k end end
        assertNotNil(i)
        assertEquals("Outil d'essai", lignes[i + 1])
        for _, l in ipairs(lignes) do assertTrue(l ~= "Azeroth Commune", "pas de ligne du socle") end
    end
    print("menu : " .. table.concat(lignes, " | "))
end)

test("exports : ceux du socle d'abord, puis ceux des add-ons regroupés", function()
    essai()
    local cles = {}
    for _, e in ipairs(AzerothCommune.Exports()) do cles[e.cle] = e.addon end
    assertEquals("Azeroth Commune", cles.perso)
    assertEquals("Azeroth Commune", cles.hv)
    assertEquals("Essai", cles.essai)
    assertEquals("perso", AzerothCommune.Exports()[1].cle)
end)
