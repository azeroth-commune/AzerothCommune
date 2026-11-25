-- La fenêtre du socle au look du jeu (#102) : cadre Blizzard, redimensionnable, place et taille retenues dans
-- AzerothCommuneDB.fenetres[nom] ; colonne extensible d'un tableau.
local lib = AzerothCommune

test("fenêtre : cadre du jeu sans portrait, titre et croix du gabarit, Échap la ferme", function()
    local f = lib.Fenetre("AzerothCommuneTestCadre", "Essai", 400, 300)
    assertNotNil(f.NineSlice, "le cadre de ButtonFrameTemplate")
    assertTrue(not f:GetPortrait():IsShown(), "portrait caché")
    assertEquals("Essai", f.title:GetText())
    assertEquals(f:GetTitleText(), f.title, "f.title est le titre du gabarit")
    assertNotNil(f.CloseButton)
    local echap = false
    for _, n in ipairs(UISpecialFrames) do if n == "AzerothCommuneTestCadre" then echap = true end end
    assertTrue(echap)
    f:Show()
    f.CloseButton:Click()
    assertTrue(not f:IsShown(), "la croix ferme")
end)

-- Le joueur tire la poignée : ce que font les gestes du jeu (OnMouseDown, la nouvelle taille, OnMouseUp).
local function agrandir(f, w, h)
    f.ResizeButton:GetScript("OnMouseDown")(f.ResizeButton, "LeftButton")
    f:SetSize(w, h)
    f.ResizeButton:GetScript("OnMouseUp")(f.ResizeButton, "LeftButton")
end
local function deplacer(f, x, y)
    f:GetScript("OnDragStart")(f, "LeftButton")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    f:GetScript("OnDragStop")(f)
end

test("fenêtre : agrandie et déplacée puis recréée, elle retrouve sa place et sa taille (AzerothCommuneDB.fenetres)", function()
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.AzerothCommuneTestPlace = nil
    local f = lib.Fenetre("AzerothCommuneTestPlace", "Place", 400, 300)
    f:Show()
    assertNotNil(f.ResizeButton, "la poignée de Blizzard")
    deplacer(f, 100, 700)
    agrandir(f, 520, 380)
    f:Hide()
    local g = AzerothCommuneDB.fenetres.AzerothCommuneTestPlace
    assertEquals(520, g.w)
    assertEquals(380, g.h)
    local f2 = lib.Fenetre("AzerothCommuneTestPlace", "Place", 400, 300)
    f2:SetWidth(450) -- à la création, l'add-on se règle sur son tableau : la taille retenue, plus grande, l'emporte
    f2:Show()
    assertEquals(520, math.floor(f2:GetWidth() + 0.5))
    assertEquals(380, math.floor(f2:GetHeight() + 0.5))
    assertEquals(100, math.floor(f2:GetLeft() + 0.5))
    assertEquals(700, math.floor(f2:GetTop() + 0.5))
    f2:SetWidth(460) -- ouverte, la taille retenue n'est plus un plancher
    assertEquals(460, math.floor(f2:GetWidth() + 0.5))
    f2:Hide()
    AzerothCommuneDB.fenetres.AzerothCommuneTestPlace = nil
end)

test("fenêtre : un déplacement retient la place seule ; la taille retenue garde celle de la poignée", function()
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.AzerothCommuneTestDeplace = nil
    local f = lib.Fenetre("AzerothCommuneTestDeplace", "Déplacée", 400, 300)
    f:Show()
    deplacer(f, 120, 650)
    local g = AzerothCommuneDB.fenetres.AzerothCommuneTestDeplace
    assertEquals(120, g.x)
    assertTrue(g.w == nil and g.h == nil, "un déplacement n'écrit pas w/h")
    agrandir(f, 500, 350)
    deplacer(f, 140, 640)
    g = AzerothCommuneDB.fenetres.AzerothCommuneTestDeplace
    assertEquals(140, g.x)
    assertEquals(500, g.w, "la taille de la poignée reste retenue après un déplacement")
    f:Hide()
    AzerothCommuneDB.fenetres.AzerothCommuneTestDeplace = nil
end)

test("fenêtre : une hauteur qui suit le contenu redescend, le minimum reste celui de la création", function()
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.AzerothCommuneTestContenu = nil
    local f = lib.Fenetre("AzerothCommuneTestContenu", "Contenu", 300, 100)
    f:Show()
    f:SetHeight(400)
    f:SetHeight(150)
    assertEquals(150, math.floor(f:GetHeight() + 0.5))
    local _, minH = f:GetResizeBounds()
    assertEquals(100, math.floor(minH + 0.5))
    f:Hide()
end)

test("fenêtre : une taille retenue plus grande que l'écran est ramenée à l'écran", function()
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.AzerothCommuneTestEcran = { x = 0, y = 500, w = 99999, h = 99999 }
    local f = lib.Fenetre("AzerothCommuneTestEcran", "Écran", 400, 300)
    assertTrue(f:GetWidth() <= UIParent:GetWidth() + 0.5, "largeur dans l'écran")
    assertTrue(f:GetHeight() <= UIParent:GetHeight() + 0.5, "hauteur dans l'écran")
    AzerothCommuneDB.fenetres.AzerothCommuneTestEcran = nil
end)

test("fenêtre : la taille de création est le minimum ; une largeur fixée d'après un tableau le relève", function()
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.AzerothCommuneTestMini = nil
    local f = lib.Fenetre("AzerothCommuneTestMini", "Mini", 400, 300)
    f:Show()
    agrandir(f, 200, 150)
    assertEquals(400, math.floor(f:GetWidth() + 0.5), "pas plus étroite que sa création")
    assertEquals(300, math.floor(f:GetHeight() + 0.5), "pas moins haute que sa création")
    local _, largeur = lib.Tableau(f, { { key = "nom", title = "Nom", w = 500, get = function(r) return r end } }, { name = "mini" })
    f:SetWidth(largeur + 50)
    agrandir(f, 450, 300)
    assertEquals(largeur + 50, math.floor(f:GetWidth() + 0.5), "le tableau relève le minimum")
    f:Hide()
    AzerothCommuneDB.fenetres.AzerothCommuneTestMini = nil
end)

test("fenêtre non redimensionnable : pas de poignée, place par défaut, place retenue seulement si déplacée", function()
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.AzerothCommuneTestFixe = nil
    local opts = { redimensionnable = false, place = { "TOPLEFT", UIParent, "BOTTOMLEFT", 50, 600 } }
    local f = lib.Fenetre("AzerothCommuneTestFixe", "Fixe", 290, 80, opts)
    f:Show()
    assertTrue(f.ResizeButton == nil, "pas de poignée")
    assertEquals(50, math.floor(f:GetLeft() + 0.5), "place par défaut")
    f:SetHeight(140) -- la taille suit le contenu, gérée par l'add-on
    f:Hide()
    assertTrue(AzerothCommuneDB.fenetres.AzerothCommuneTestFixe == nil, "pas déplacée : rien de retenu")
    f = lib.Fenetre("AzerothCommuneTestFixe", "Fixe", 290, 80, opts)
    assertEquals(80, math.floor(f:GetHeight() + 0.5))
    f:Show()
    deplacer(f, 300, 500)
    f:SetHeight(140)
    f:Hide()
    local g = AzerothCommuneDB.fenetres.AzerothCommuneTestFixe
    assertEquals(300, g.x)
    assertTrue(g.w == nil and g.h == nil, "seule la place est retenue")
    f = lib.Fenetre("AzerothCommuneTestFixe", "Fixe", 290, 80, opts)
    f:Show()
    assertEquals(300, math.floor(f:GetLeft() + 0.5))
    assertEquals(500, math.floor(f:GetTop() + 0.5))
    assertEquals(80, math.floor(f:GetHeight() + 0.5))
    f:Hide()
    AzerothCommuneDB.fenetres.AzerothCommuneTestFixe = nil
end)

-- Asynchrone : le jeu (et le simulateur) signale un changement de taille (OnSizeChanged) à l'image suivante.
local function ensuite(done, fn)
    C_Timer.After(0.05, function()
        local ok, err = pcall(fn)
        if not ok then done(function() error(err, 0) end) end
    end)
end

async_test("tableau : la colonne extensible prend la largeur gagnée par la fenêtre, les autres non ; plus haute, plus de lignes", function(done)
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    AzerothCommuneDB.fenetres.AzerothCommuneTestExtensible = nil
    local cols = {
        { key = "nom", title = "Nom", w = 120, extensible = true, get = function(r) return r.nom end },
        { key = "prix", title = "Prix", w = 80, align = "RIGHT", get = function(r) return r.prix end },
    }
    local f = lib.Fenetre("AzerothCommuneTestExtensible", "Extensible", 300, 300)
    local t, largeur = lib.Tableau(f, cols, { name = "ext", sort = "prix" })
    f:SetWidth(largeur + 50)
    f:Show()
    local lignes = {}
    for i = 1, 60 do lignes[i] = { nom = "objet " .. i, prix = i } end
    t:SetData(lignes)
    local function visibles()
        local n = 0
        for _, r in ipairs(t.rows) do if r:IsShown() then n = n + 1 end end
        return n
    end
    ensuite(done, function()
        local nomW, prixW, celluleW, avant = cols[1].head:GetWidth(), cols[2].head:GetWidth(), t.rows[1].cells[1]:GetWidth(), visibles()
        agrandir(f, largeur + 50 + 200, 500)
        ensuite(done, function()
            done(function()
                assertEquals(math.floor(nomW + 200 + 0.5), math.floor(cols[1].head:GetWidth() + 0.5), "l'en-tête extensible s'élargit")
                assertEquals(math.floor(prixW + 0.5), math.floor(cols[2].head:GetWidth() + 0.5), "les autres gardent leur largeur")
                assertEquals(math.floor(celluleW + 200 + 0.5), math.floor(t.rows[1].cells[1]:GetWidth() + 0.5), "les lignes déjà créées suivent")
                assertTrue(visibles() > avant, "plus haute : plus de lignes")
                f:Hide()
                AzerothCommuneDB.fenetres.AzerothCommuneTestExtensible = nil
            end)
        end)
    end)
end)

test("recherche d'objets : la liste prend le fond des bulles d'aide du jeu", function()
    local f = lib.Fenetre("AzerothCommuneTestBulle", "Bulle", 400, 300)
    local qty = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    lib.RechercheObjets(f, qty, function() end)
    local liste
    for _, c in ipairs({ f:GetChildren() }) do if c.layoutType == "TooltipDefaultLayout" then liste = c end end
    assertNotNil(liste, "la liste est un TooltipBackdropTemplate")
end)

test("tableau : un onglet caché pendant que la fenêtre s'élargit se remet en place au rafraîchissement", function()
    local cols = {
        { key = "nom", title = "Nom", w = 120, extensible = true, get = function(r) return r.nom end },
        { key = "prix", title = "Prix", w = 80, get = function(r) return r.prix end },
    }
    local f = lib.Fenetre("AzerothCommuneTestOnglet", "Onglet", 300, 300)
    local onglet = CreateFrame("Frame", nil, f)
    onglet:SetAllPoints()
    local t = lib.Tableau(onglet, cols, { name = "onglet", sort = "prix" })
    f:Show()
    t:SetData({ { nom = "a", prix = 1 } })
    local avant = cols[1].head:GetWidth()
    onglet:Hide()
    f:SetSize(500, 300) -- le joueur élargit pendant qu'un autre onglet est affiché
    onglet:Show()
    t:Refresh()
    assertEquals(math.floor(avant + 200 + 0.5), math.floor(cols[1].head:GetWidth() + 0.5))
    f:Hide()
end)
