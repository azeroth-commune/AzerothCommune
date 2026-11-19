-- GameData : bouton de la minicarte et fenêtre d'export (la fenêtre, les tableaux, les montants : LibCommune).
--   Minicarte : clic gauche = fenêtre GameData : outils (acheter ou fabriquer, ceux du Négoce s'il est là) et exports (ouvre / replie), clic droit = « Acheter ou fabriquer »,
--               glisser = le déplacer autour de la carte (position gardée).
--   Export : un bouton par partie de la base ; chaque export est photographié en grilles de couleurs
--            (export de LibCommune), puis relu hors du jeu par tools/crop_captures.py. Sans /reload.
local _, ns = ...
local lib = LibStub and LibStub("LibCommune-1.0", true)

---------------------------------------------------------------------------------------------------
-- Fenêtre d'export
local EXPORTS = {
  { "perso", "Mon perso", "fiche, sacs, banque, courrier, équipement, monnaies, réputations, métiers, quêtes" },
  { "persos", "Tous mes persos", "la même chose pour chaque perso déjà connecté" },
  { "recettes", "Recettes", "toutes les recettes vues, avec produit et composants" },
  { "marchands", "Marchands", "ce que chaque marchand visité vend, et à quel prix" },
  { "maitres", "Maîtres", "ce que chaque maître enseigne, prix et niveau requis" },
  { "hv", "Hôtel des ventes", "le dernier scan : prix le plus bas, quantité, 3 premiers paliers" },
  { "addons", "Add-ons", "les add-ons installés : version, auteur, dépendances" },
  { "erreurs", "Diagnostic", "erreurs de scan et derniers événements vus" },
}
ns.exportList = EXPORTS

-- Les outils du hub : { libellé, ouvrir, nom de sa fenêtre }. Un add-on consommateur (le Négoce) y ajoute les siens
-- avant la première ouverture du hub.
-- ponytail: une rangée de 4 boutons de 118 px ; passer à deux rangées si un 5e outil arrive.
ns.hubTools = { { "Acheter ou fabriquer", function() if ns.openCraftWindow then ns.openCraftWindow() end end } }

local exportFrame
local function buildExport()
  local f = lib.Fenetre("GameDataExportFrame", "GameData", 500, 160 + #EXPORTS * 34) -- 4 outils de 118 px
  for i, t in ipairs(ns.hubTools) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(114, 24)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 118, -40)
    b:SetText(t[1])
    -- Ouvrir un outil referme ce menu : les deux fenêtres ne se superposent pas ; déjà ouvert, il passe devant.
    b:SetScript("OnClick", function()
      f:Hide()
      local w = t[3] and _G[t[3]]
      if w and w:IsShown() then w:Raise() else t[2]() end
    end)
  end
  local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  head:SetPoint("TOPLEFT", 14, -78)
  head:SetText("Exports")
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -96)
  hint:SetWidth(352)
  hint:SetJustifyH("LEFT")
  hint:SetText("Chaque export s'affiche en grille de couleurs une demi-seconde par page et se photographie tout seul.")
  for i, e in ipairs(EXPORTS) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(130, 24)
    b:SetPoint("TOPLEFT", 14, -122 - (i - 1) * 34)
    b:SetText(e[2])
    b:SetScript("OnClick", function() ns.exportCommand(e[1]) end)
    local d = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("LEFT", b, "RIGHT", 10, 0)
    d:SetWidth(212)
    d:SetJustifyH("LEFT")
    d:SetText(e[3])
  end
  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.status:SetPoint("BOTTOMLEFT", 14, 12)
  f.status:SetWidth(352)
  f.status:SetJustifyH("LEFT")
  f:SetScript("OnShow", function(self)
    self.status:SetText(ns.commerceStatus and ns.commerceStatus() or "")
  end)
  return f
end

function ns.toggleExportWindow()
  exportFrame = exportFrame or buildExport()
  exportFrame:SetShown(not exportFrame:IsShown())
end

---------------------------------------------------------------------------------------------------
-- Bouton de la minicarte, posé sur le bord à l'angle gardé dans GameDataDB.minimap_angle.
local function placeButton(b)
  local a = math.rad(GameDataDB.minimap_angle or 200)
  local r = Minimap:GetWidth() / 2 + 6
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function makeMinimapButton()
  local b = CreateFrame("Button", "GameDataMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER")
  icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then if ns.openCraftWindow then ns.openCraftWindow() end else ns.toggleExportWindow() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      GameDataDB.minimap_angle = math.deg(math.atan2(py / s - my, px / s - mx))
      placeButton(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("GameData")
    GameTooltip:AddLine("Clic : outils et exports", 1, 1, 1)
    GameTooltip:AddLine("Clic droit : acheter ou fabriquer", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  placeButton(b)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() pcall(makeMinimapButton) end)
