-- GameData : fenêtre des exports (la fenêtre, l'export par image, le bouton de la minicarte : LibCommune).
--   La fenêtre GameData liste les exports que les add-ons regroupés déclarent à LibCommune (lib.Regrouper{ exports },
--   ceux de GameData compris : GameData.lua) ; elle s'ouvre par sa ligne du bouton de minicarte commun d'Azeroth Commune
--   ou par /gdata export. Chaque export est photographié en grilles de couleurs (export de LibCommune), puis relu hors
--   du jeu par tools/crop_captures.py. Sans /reload.
-- ponytail: affichage provisoire ; la liste vit dans la lib, un futur module de debug de la lib la reprendra (TODO).
local _, ns = ...
local lib = LibStub and LibStub("LibCommune-1.0", true)

-- Les lignes des exports, groupées par add-on ; refaites à l'ouverture si la liste a changé (add-on regroupé plus tard).
local function poserExports(f)
  local liste = lib.Exports()
  if f.contenu and f.n == #liste then return end
  if f.contenu then f.contenu:Hide() end -- ponytail: l'ancien contenu reste en mémoire ; la liste change rarement
  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints()
  local y, addon = -70, nil
  for _, e in ipairs(liste) do
    if e.addon ~= addon then
      addon = e.addon
      local h = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      h:SetPoint("TOPLEFT", 14, y - 4)
      h:SetText(addon)
      y = y - 26
    end
    local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    b:SetSize(130, 24)
    b:SetPoint("TOPLEFT", 14, y)
    b:SetText(e.libelle)
    b:SetScript("OnClick", function() ns.exportCommand(e.cle) end)
    local d = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("LEFT", b, "RIGHT", 10, 0)
    d:SetWidth(330)
    d:SetJustifyH("LEFT")
    d:SetText(e.description or "")
    y = y - 34
  end
  f.contenu, f.n = c, #liste
  f:SetHeight(-y + 30)
end

local exportFrame
local function buildExport()
  local f = lib.Fenetre("GameDataExportFrame", "GameData", 500, 200)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -40)
  hint:SetWidth(472)
  hint:SetJustifyH("LEFT")
  hint:SetText("Chaque export s'affiche en grille de couleurs une demi-seconde par page et se photographie tout seul.")
  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.status:SetPoint("BOTTOMLEFT", 14, 12)
  f.status:SetWidth(472)
  f.status:SetJustifyH("LEFT")
  f:HookScript("OnShow", function(self)
    poserExports(self)
    self.status:SetText(ns.commerceStatus and ns.commerceStatus() or "")
  end)
  return f
end

function ns.toggleExportWindow()
  if not (lib and lib.Exports) then return print("GameData : la fenêtre demande LibCommune.") end
  exportFrame = exportFrame or buildExport()
  exportFrame:SetShown(not exportFrame:IsShown())
end
