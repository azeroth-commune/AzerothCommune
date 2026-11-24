-- Outils communs dans wow-ui-sim (tools/sim.sh test AzerothCommune) : une fenêtre et un tableau créés par la lib, sans erreur Lua.
test("fenêtre de la lib : créée cachée, Échap la ferme", function()
    local lib = AzerothCommune
    local f = lib.Fenetre("AzerothCommuneTestFenetre", "Essai", 400, 300)
    assertNotNil(f)
    assertEquals(f, _G.AzerothCommuneTestFenetre)
    assertTrue(not f:IsShown())
    local echap = false
    for _, n in ipairs(UISpecialFrames) do if n == "AzerothCommuneTestFenetre" then echap = true end end
    assertTrue(echap)
    f:Show()
    assertTrue(f:IsShown())
    f:Hide()
end)

test("tableau de la lib : données triées, tri gardé dans le store de l'add-on", function()
    local lib = AzerothCommune
    local f = lib.Fenetre("AzerothCommuneTestTableau", "Tableau", 400, 300)
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
    local lib = AzerothCommune
    assertType("string", lib.Argent(12345))
    assertType("function", lib.Capturer)
    assertType("function", lib.Exporter)
    assertType("function", lib.NomObjet)
end)

-- #60 : la barre de recherche d'objets du socle (montée de Composants et de Handshake) : suggestions de ChercherObjets,
-- flèches et Entrée, clic, Entrée sans suggestion (TrouverObjet : un ID), objet déposé, quantité lue dans le champ qty.
test("barre de recherche du socle : suggestion choisie au clavier ou au clic, un ID, un objet déposé", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("objets"))
    assertTrue(lib:Souscrire("base des recettes"))
    local f = lib.Fenetre("AzerothCommuneTestRecherche", "Recherche", 400, 300)
    f:Show()
    local qty = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    qty:SetText("3")
    local pris = {}
    local box, valider = lib.RechercheObjets(f, qty, function(id, q) pris[#pris + 1] = { id, q } end)
    assertTrue(box.recherche)
    assertType("function", valider)
    local attendus = lib.ChercherObjets("bronze", 8)
    assertTrue(#attendus >= 2, "la recherche du socle trouve du bronze")
    -- Suggestions affichées, la 2e choisie par la flèche du bas puis Entrée ; le champ est vidé.
    box:SetText("bronze")
    box:GetScript("OnTextChanged")(box, true)
    local montres = {}
    for _, c in ipairs({ f:GetChildren() }) do
        for _, b in ipairs({ c:GetChildren() }) do
            if b:GetObjectType() == "Button" and b.text and b:IsShown() then montres[#montres + 1] = b end
        end
    end
    assertEquals(#attendus, #montres)
    box:GetScript("OnArrowPressed")(box, "DOWN")
    box:GetScript("OnEnterPressed")(box)
    assertEquals(attendus[2].id, pris[1][1])
    assertEquals(3, pris[1][2])
    assertEquals("", box:GetText())
    -- Au clic : la 1re.
    box:SetText("bronze")
    box:GetScript("OnTextChanged")(box, true)
    montres[1]:Click()
    assertEquals(attendus[1].id, pris[2][1])
    -- Entrée sans suggestion : un ID (TrouverObjet) ; quantité vide : 1.
    qty:SetText("")
    box:SetText("2589")
    box:GetScript("OnTextChanged")(box, true)
    box:GetScript("OnEnterPressed")(box)
    assertEquals(2589, pris[3][1])
    assertEquals(1, pris[3][2])
    -- Un objet déposé sur le champ : choisi aussitôt, curseur vidé.
    local getCursor, clear, vide = GetCursorInfo, ClearCursor, false
    GetCursorInfo = function() return "item", 2840 end
    ClearCursor = function() vide = true end
    box:GetScript("OnReceiveDrag")(box)
    GetCursorInfo, ClearCursor = getCursor, clear
    assertTrue(vide, "curseur vidé")
    assertEquals(2840, pris[4][1])
    f:Hide()
end)
