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
    f2:Show()
    assertEquals(520, math.floor(f2:GetWidth() + 0.5))
    assertEquals(380, math.floor(f2:GetHeight() + 0.5))
    assertEquals(100, math.floor(f2:GetLeft() + 0.5))
    assertEquals(700, math.floor(f2:GetTop() + 0.5))
    f2:SetWidth(450) -- l'add-on se règle sur son tableau : la taille retenue, plus grande, l'emporte
    assertEquals(520, math.floor(f2:GetWidth() + 0.5))
    f2:Hide()
    AzerothCommuneDB.fenetres.AzerothCommuneTestPlace = nil
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
