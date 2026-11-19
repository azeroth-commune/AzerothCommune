-- GameData : fenêtre d'export (la fenêtre, les tableaux, les montants, le bouton de la minicarte : LibCommune).
--   Fenêtre GameData : outils (acheter ou fabriquer, ceux du Négoce s'il est là) et exports (ouvre / replie), par le
--   bouton de minicarte commun d'Azeroth Commune.
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
  if not lib then return print("GameData : la fenêtre demande LibCommune.") end
  exportFrame = exportFrame or buildExport()
  exportFrame:SetShown(not exportFrame:IsShown())
end

---------------------------------------------------------------------------------------------------
-- Bouton de la minicarte et entrée des options : ceux d'Azeroth Commune, communs aux add-ons présents (LibCommune#3).
-- Clic (GameData seul) ou sa ligne du menu = cette fenêtre ; « Acheter ou fabriquer » (l'ancien clic droit) = la ligne
-- Handshake du menu, et le premier outil de cette fenêtre. L'angle reste dans GameDataDB.minimap_angle.
if lib and lib.Regrouper then
  lib.Regrouper({ nom = "GameData", dossier = "GameData", icone = "Interface\\Icons\\INV_Scroll_03",
    ouvrir = ns.toggleExportWindow, store = function() return GameDataDB end })
end
