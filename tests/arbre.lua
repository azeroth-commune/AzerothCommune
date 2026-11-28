-- L'Arbre du socle (#108) dessiné : la fonction de case de l'add-on appelée pour chaque case, cadres réutilisés d'un dessin à
-- l'autre, cases placées (à droite de leurs parents, sans chevauchement), liens tracés (relais compris), rectangles et
-- en-têtes des bandes, toile qui défile. Le placement seul est vérifié hors jeu (check.lua).
local lib = AzerothCommune

-- Deux bandes : x (racine A ; A → B → C, A → C qui saute l'étage 1, A → D, B → D caché), y (racine E ; E → F ; F → C, de
-- bande à bande). Données neuves à chaque appel : le placement écrit sur les cases.
local function donnees()
    local function case(key, band, index) return { key = key, band = band, index = index } end
    local A, B, C, D, E, F = case("A", "x", 1), case("B", "x"), case("C", "x"), case("D", "x"), case("E", "y", 2), case("F", "y")
    local liens = {
        { from = A, to = B, text = "×2" }, { from = B, to = C }, { from = A, to = C, color = { 1, 0, 0 }, thick = 4 },
        { from = A, to = D }, { from = B, to = D, hidden = true }, { from = E, to = F }, { from = F, to = C },
    }
    local bandes = { { key = "x", title = "Bande X", color = { 0.3, 0.8, 0.85 } }, { key = "y", title = "Bande Y", color = { 1, 0.82, 0 } } }
    return { A, B, C, D, E, F }, liens, bandes
end

local function nouvelArbre(nom)
    local f = lib.Fenetre(nom, "Arbre", 500, 300)
    local appels, crees = {}, 0
    local arbre = lib.Arbre(f, { case = function(case, cadre)
        appels[#appels + 1] = { case = case, cadre = cadre }
        if not cadre then
            crees = crees + 1
            cadre = CreateFrame("Button", nil, f) -- l'Arbre le rattache à sa toile
            cadre.texte = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cadre.texte:SetPoint("CENTER")
        end
        cadre.texte:SetText(case.key)
        return cadre
    end })
    arbre.zone:SetPoint("TOPLEFT", 10, -30)
    arbre.zone:SetPoint("BOTTOMRIGHT", -10, 10)
    f:Show()
    return f, arbre, appels, function() return crees end
end

-- Les lignes tracées visibles sur la toile.
local function lignes(toile)
    local n = 0
    for _, r in ipairs({ toile:GetRegions() }) do if r:GetObjectType() == "Line" and r:IsShown() then n = n + 1 end end
    return n
end
local function textes(toile)
    local t = {}
    for _, r in ipairs({ toile:GetRegions() }) do
        if r:GetObjectType() == "FontString" and r:IsShown() then t[r:GetText() or ""] = true end
    end
    return t
end

test("arbre : la fonction de case pour chaque case, à la taille imposée, placée à droite de ses parents, sans chevauchement", function()
    local f, arbre, appels = nouvelArbre("AzerothCommuneTestArbre")
    local cases, liens, bandes = donnees()
    local g = lib.PlacerArbre(cases, liens, bandes)
    arbre:Dessiner(g)
    assertEquals(#cases, #appels, "un appel par case")
    for i, a in ipairs(appels) do
        assertEquals(cases[i], a.case)
        assertNil(a.cadre, "premier dessin : l'add-on crée le cadre")
    end
    local cadre = {}
    for i, n in ipairs(cases) do
        local c = arbre.cadres[i]
        cadre[n] = c
        assertTrue(c:IsShown(), n.key .. " affichée")
        assertEquals(arbre.toile, c:GetParent(), "sur la toile")
        assertEquals(190, math.floor(c:GetWidth() + 0.5), "largeur imposée")
        assertEquals(42, math.floor(c:GetHeight() + 0.5), "hauteur imposée")
    end
    for _, e in ipairs(liens) do
        assertTrue(cadre[e.to]:GetLeft() > cadre[e.from]:GetRight(), e.from.key .. " à gauche de " .. e.to.key)
    end
    for _, n in ipairs(cases) do
        for _, m in ipairs(cases) do
            local a, b = cadre[n], cadre[m]
            local separees = a:GetRight() <= b:GetLeft() + 0.5 or b:GetRight() <= a:GetLeft() + 0.5
                or a:GetTop() <= b:GetBottom() + 0.5 or b:GetTop() <= a:GetBottom() + 0.5
            assertTrue(n == m or separees, n.key .. " chevauche " .. m.key)
        end
    end
    f:Hide()
end)

test("arbre : liens tracés en courbes (8 traits), un trait par relais, lien caché non tracé, texte du lien", function()
    local f, arbre = nouvelArbre("AzerothCommuneTestArbreLiens")
    local cases, liens, bandes = donnees()
    local g = lib.PlacerArbre(cases, liens, bandes)
    arbre:Dessiner(g)
    local attendu = 0
    for _, e in ipairs(liens) do
        local relais = #e.path - 2
        if not e.hidden then attendu = attendu + 8 * (relais + 1) + relais end
    end
    assertEquals(3, #liens[3].path, "A → C passe par un relais")
    assertEquals(attendu, lignes(arbre.toile))
    assertTrue(textes(arbre.toile)["×2"], "le texte du lien A → B")
    f:Hide()
end)

test("arbre : rectangles et en-têtes des bandes, empilées dans l'ordre, chacune autour de ses cases", function()
    local f, arbre = nouvelArbre("AzerothCommuneTestArbreBandes")
    local cases, liens, bandes = donnees()
    arbre:Dessiner(lib.PlacerArbre(cases, liens, bandes))
    local rect = {}
    for _, r in ipairs(arbre.rectangles) do if r:IsShown() then rect[r.band.key] = r end end
    assertEquals("Bande X", rect.x.title:GetText())
    assertEquals("Bande Y", rect.y.title:GetText())
    assertTrue(rect.x:GetBottom() > rect.y:GetTop(), "x au-dessus de y, sans se mêler")
    for i, n in ipairs(cases) do
        local c, r = arbre.cadres[i], rect[n.band]
        assertTrue(c:GetLeft() >= r:GetLeft() and c:GetRight() <= r:GetRight() and c:GetTop() <= r:GetTop()
            and c:GetBottom() >= r:GetBottom(), n.key .. " dans le rectangle de sa bande")
    end
    -- Une bande sans couleur ni titre (le reste) : ni rectangle ni en-tête.
    bandes[2].color, bandes[2].title = nil, nil
    cases, liens = donnees()
    arbre:Dessiner(lib.PlacerArbre(cases, liens, bandes))
    local n = 0
    for _, r in ipairs(arbre.rectangles) do if r:IsShown() then n = n + 1 end end
    assertEquals(1, n, "seule la bande x a son rectangle")
    assertNil(textes(arbre.toile)["Bande Y"])
    f:Hide()
end)

test("arbre : redessiné, les mêmes cadres sont rendus à la fonction de case ; une case de moins, son cadre caché", function()
    local f, arbre, appels, crees = nouvelArbre("AzerothCommuneTestArbreReutilise")
    local cases, liens, bandes = donnees()
    arbre:Dessiner(lib.PlacerArbre(cases, liens, bandes))
    local avant = {}
    for i, c in ipairs(arbre.cadres) do avant[i] = c end
    for i = #appels, 1, -1 do appels[i] = nil end
    cases, liens, bandes = donnees()
    arbre:Dessiner(lib.PlacerArbre(cases, liens, bandes))
    assertEquals(#cases, crees(), "aucun cadre de plus")
    for i, a in ipairs(appels) do assertEquals(avant[i], a.cadre, "le cadre " .. i .. " rendu à l'add-on") end
    cases, liens, bandes = donnees()
    table.remove(cases) -- F, et ses liens
    liens = { liens[1], liens[2], liens[3] }
    arbre:Dessiner(lib.PlacerArbre(cases, liens, bandes))
    assertTrue(not avant[6]:IsShown(), "le cadre de trop caché")
    f:Hide()
end)

test("arbre : la toile tient tout l'arbre (hauteur rendue) ; plus grande que la zone, molette = zoom, clic du milieu = vue ajustée", function()
    local f, arbre = nouvelArbre("AzerothCommuneTestArbreToile")
    arbre.zone:ClearAllPoints()
    arbre.zone:SetPoint("TOPLEFT", 10, -30)
    arbre.zone:SetSize(300, 50)
    local cases, liens, bandes = donnees()
    local g = lib.PlacerArbre(cases, liens, bandes)
    arbre:Dessiner(g)
    assertEquals(math.floor(g.height + g.dims.haut + 10 + 0.5), math.floor(arbre.toile:GetHeight() + 0.5), "hauteur rendue")
    assertTrue(arbre.zone:DoesClipChildren(), "la zone découpe la toile")
    assertTrue(arbre.toile:GetHeight() * arbre.toile:GetScale() > arbre.zone:GetHeight(), "l'arbre dépasse la zone : " .. arbre.toile:GetHeight() .. " × " .. arbre.toile:GetScale())
    local echelle = arbre.toile:GetScale()
    arbre.zone:GetScript("OnMouseWheel")(arbre.zone, 1)
    assertTrue(arbre.toile:GetScale() > echelle, "molette : zoom")
    arbre.zone:GetScript("OnMouseDown")(arbre.zone, "MiddleButton")
    assertEquals(echelle, arbre.toile:GetScale(), "clic du milieu : vue ajustée")
    assertNotNil(arbre.zone:GetScript("OnUpdate"), "glisser le fond déplace la toile")
    f:Hide()
end)
