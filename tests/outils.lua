-- Outils communs dans wow-ui-sim (tools/sim.sh test LibCommune) : une fenêtre et un tableau créés par la lib, sans erreur Lua.
test("fenêtre de la lib : créée cachée, Échap la ferme", function()
    local lib = LibStub("LibCommune-1.0")
    local f = lib.Fenetre("LibCommuneTestFenetre", "Essai", 400, 300)
    assertNotNil(f)
    assertEquals(f, _G.LibCommuneTestFenetre)
    assertTrue(not f:IsShown())
    local echap = false
    for _, n in ipairs(UISpecialFrames) do if n == "LibCommuneTestFenetre" then echap = true end end
    assertTrue(echap)
    f:Show()
    assertTrue(f:IsShown())
    f:Hide()
end)

test("tableau de la lib : données triées, tri gardé dans le store de l'add-on", function()
    local lib = LibStub("LibCommune-1.0")
    local f = lib.Fenetre("LibCommuneTestTableau", "Tableau", 400, 300)
    local store = {}
    local cols = {
        { key = "nom", title = "Nom", w = 120, asc = true, get = function(r) return r.nom end },
        { key = "prix", title = "Prix", w = 80, align = "RIGHT", get = function(r) return r.prix end, fmt = lib.ArgentCourt },
    }
    local t, largeur = lib.Tableau(f, cols, { name = "essai", sort = "prix", store = store })
    assertType("table", t)
    assertEquals(2 * 6 + 200, largeur)
    f:Show()
    t:SetData({ { nom = "b", prix = 50 }, { nom = "a", prix = 12345 }, { nom = "c" } })
    assertEquals("a", t.data[1].nom)
    assertEquals("c", t.data[3].nom)
    cols[1].head:Click()
    assertEquals("nom", store.essai.key)
    assertEquals("a", t.data[1].nom)
    f:Hide()
end)

test("montants et capture : les fonctions sont là", function()
    local lib = LibStub("LibCommune-1.0")
    assertType("string", lib.Argent(12345))
    assertType("function", lib.Capturer)
    assertType("function", lib.Exporter)
    assertType("function", lib.NomObjet)
end)
