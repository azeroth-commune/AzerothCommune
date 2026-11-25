-- Azeroth Commune : en jeu, les add-ons présents se regroupent (LibCommune#3) : un seul bouton de minicarte
-- « Azeroth Commune » et une seule entrée dans les options du jeu (Options > Add-ons), une sous-page par add-on.
--   AzerothCommune.Regrouper{ nom = "Handshake", dossier = "Handshake", icone = "Interface\\Icons\\…", ouvrir = fn,
--                  reglages = fn(page, ancre), store = fn() -> les SavedVariables de l'add-on,
--                  outils = { { libelle = "Journal", ouvrir = fn, fenetre = "NegoceLedgerFrame" }, … },
--                  exports = { { cle = "journal", libelle = "Journal", description = "…", donnees = fn() -> table }, … } }
--   dossier : le dossier de l'add-on (ses « Notes » du TOC décrivent sa page) ; reglages : facultatif, l'add-on pose
--   ses réglages sur sa page, sous ancre (le bouton « Ouvrir ») ; store : facultatif, voir l'angle du bouton.
--   outils : facultatif, une ligne par outil sous celle de l'add-on dans le menu du bouton ; fenetre (facultatif) : le
--   nom de sa fenêtre, qui passe devant si elle est déjà ouverte au lieu d'être rouverte.
--   exports : facultatif, ce que l'add-on sait photographier en grilles (export de Capture.lua) ; AzerothCommune.Exports()
--   rend ceux du socle puis ceux de tous les add-ons regroupés, que l'add-on d'atelier Diagnostic liste et lance (#33).
-- Le socle ne se regroupe pas lui-même : pas de ligne à lui dans le menu ; sa page est l'entrée « Azeroth Commune »
-- (les add-ons présents, les souscriptions et l'état des données relevées), ses exports viennent de Base.lua (ns).
-- Bouton : clic = l'add-on s'il est seul, sinon la liste des add-ons et de leurs outils ; clic droit = les réglages ;
-- glisser = le déplacer. Seul, un add-on garde son icône sur le bouton.
-- Rien n'est sauvegardé ici : l'angle du bouton est écrit dans le store de chaque add-on regroupé (minimap_angle), et lu
-- dans le premier qui en a un.
-- Tout se construit à l'entrée en jeu (SavedVariables chargées, add-ons présents connus), une seule fois. Les pages des
-- réglages sont faites une fois pour toutes, sans OnShow, OnRefresh ni OnCommit : aucun code à nous ne tourne quand le
-- joueur ouvre ou ferme les options (fermer revient au menu Échap, où du code d'add-on bloque Déconnexion / Quitter) ;
-- les souscriptions de la page du socle se relisent par son bouton « Actualiser ».
local _, ns = ...
local lib = AzerothCommune

lib.regroupes = {} -- dans l'ordre d'arrivée (l'ordre de chargement des add-ons)
local NOM, ICONE, ANGLE = "Azeroth Commune", "Interface\\Icons\\INV_Misc_Map_01", 200
local boutonCommun, categorie -- le bouton de minicarte et l'entrée des options, faits à l'entrée en jeu

local function stores()
  local t = {}
  for _, r in ipairs(lib.regroupes) do
    local db = r.store and r.store()
    if type(db) == "table" then t[#t + 1] = db end
  end
  return t
end
local function lireAngle()
  for _, db in ipairs(stores()) do if db.minimap_angle then return db.minimap_angle end end
  return ANGLE
end

local function ouvrirReglages()
  if categorie then Settings.OpenToCategory(categorie:GetID()) end
end

local function texte(icone, nom) return ("|T%s:16|t %s"):format(icone or ICONE, nom) end

-- Ouvrir un outil : déjà ouvert, il passe devant (le rouvrir le refermerait).
local function ouvrirOutil(o)
  local w = o.fenetre and _G[o.fenetre]
  if w and w:IsShown() then w:Raise() else o.ouvrir() end
end

-- Les exports du socle (ns.exportsSocle), puis ceux de tous les add-ons regroupés dans l'ordre d'arrivée :
-- { cle, libelle, description, donnees, addon }. Lu à chaque appel : un add-on regroupé après l'entrée en jeu y est aussi.
function lib.Exports()
  local t = {}
  for _, r in ipairs({ { nom = NOM, exports = ns.exportsSocle }, unpack(lib.regroupes) }) do
    for _, e in ipairs(r.exports or {}) do
      t[#t + 1] = { cle = e.cle, libelle = e.libelle, description = e.description, donnees = e.donnees, addon = r.nom }
    end
  end
  return t
end

---------------------------------------------------------------------------------------------------
-- Bouton de la minicarte, posé sur le bord à l'angle gardé.
local function placer(b)
  local a, rayon = math.rad(lireAngle()), Minimap:GetWidth() / 2 + 6
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
end

local function clic(b, bouton)
  local r = lib.regroupes
  if bouton == "RightButton" then return ouvrirReglages() end
  if #r == 1 then return r[1].ouvrir() end
  MenuUtil.CreateContextMenu(b, function(_, menu)
    menu:CreateTitle(NOM)
    for _, a in ipairs(r) do
      menu:CreateButton(texte(a.icone, a.nom), function() a.ouvrir() end)
      for _, o in ipairs(a.outils or {}) do
        menu:CreateButton("        |cffd8d8d8" .. o.libelle .. "|r", function() ouvrirOutil(o) end)
      end
    end
    menu:CreateDivider()
    menu:CreateButton("Réglages", ouvrirReglages)
    menu:CreateButton("Signaler un problème", ns.ouvrirRetour)
  end)
end

local function creerBouton()
  local b = CreateFrame("Button", "AzerothCommuneMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  b.icone = b:CreateTexture(nil, "ARTWORK")
  b.icone:SetSize(18, 18)
  b.icone:SetPoint("CENTER")
  b.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local bord = b:CreateTexture(nil, "OVERLAY")
  bord:SetSize(53, 53)
  bord:SetPoint("TOPLEFT")
  bord:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", clic)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      local a = math.deg(math.atan2(py / s - my, px / s - mx))
      for _, db in ipairs(stores()) do db.minimap_angle = a end
      placer(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    local r = lib.regroupes
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(#r == 1 and r[1].nom or NOM)
    if #r == 1 then
      GameTooltip:AddLine("Clic : ouvrir", 1, 1, 1)
    else
      GameTooltip:AddLine("Clic : choisir un add-on", 1, 1, 1)
      for _, a in ipairs(r) do GameTooltip:AddLine("   " .. texte(a.icone, a.nom), 0.8, 0.8, 0.8) end
    end
    GameTooltip:AddLine("Clic droit : réglages", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

---------------------------------------------------------------------------------------------------
-- Pages des réglages : celle d'un add-on (icône, nom, ses Notes du TOC, « Ouvrir », puis ses réglages s'il en a), et
-- celle du socle, l'entrée « Azeroth Commune » : les add-ons présents, puis les souscriptions et l'état des données
-- relevées (ce que dit /ac souscriptions, ns.lignesSouscriptions de Souscriptions.lua).
local function enTete(p, icone, nom)
  local i = p:CreateTexture(nil, "ARTWORK")
  i:SetSize(40, 40)
  i:SetPoint("TOPLEFT", 16, -16)
  i:SetTexture(icone or ICONE)
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  t:SetPoint("LEFT", i, "RIGHT", 12, 0)
  t:SetText(nom)
end

local function bouton(p, texteBouton, fn)
  local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  b:SetSize(140, 24)
  b:SetText(texteBouton)
  b:SetScript("OnClick", fn)
  return b
end

local function pageAddOn(r)
  local p = CreateFrame("Frame")
  p:Hide()
  enTete(p, r.icone, r.nom)
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local notes = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  notes:SetPoint("TOPLEFT", 16, -72)
  notes:SetWidth(560)
  notes:SetJustifyH("LEFT")
  notes:SetText(r.dossier and meta and meta(r.dossier, "Notes") or "")
  local ouvrir = bouton(p, "Ouvrir", function() r.ouvrir() end)
  ouvrir:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -14)
  if r.reglages then r.reglages(p, ouvrir) end
  return p
end

local function accueil()
  local p = CreateFrame("Frame")
  p:Hide()
  enTete(p, ICONE, NOM)
  local d = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d:SetPoint("TOPLEFT", 16, -72)
  d:SetText("Les add-ons d'Azeroth Commune présents ; la page de chacun est dans la liste, sous Azeroth Commune.")
  -- ponytail: la liste de l'entrée en jeu ; un add-on regroupé plus tard n'a que sa sous-page
  local y = -100
  for _, r in ipairs(lib.regroupes) do
    local b = bouton(p, "Ouvrir", function() r.ouvrir() end)
    b:SetPoint("TOPLEFT", 16, y)
    local n = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    n:SetPoint("LEFT", b, "RIGHT", 12, 0)
    n:SetText(texte(r.icone, r.nom))
    y = y - 30
  end
  local titre = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titre:SetPoint("TOPLEFT", 16, y - 10)
  titre:SetText("Données relevées")
  local liste = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  liste:SetPoint("TOPLEFT", titre, "BOTTOMLEFT", 0, -8)
  liste:SetWidth(600)
  liste:SetJustifyH("LEFT")
  local function lire() liste:SetText(table.concat(ns.lignesSouscriptions and ns.lignesSouscriptions() or {}, "\n")) end
  local actualiser = bouton(p, "Actualiser", lire)
  actualiser:SetPoint("LEFT", titre, "RIGHT", 16, 0)
  lire()
  p.souscriptions = liste -- lu par les tests
  return p
end

---------------------------------------------------------------------------------------------------
-- Le regroupement : un seul bouton (s'il y a au moins un add-on), une seule entrée, la page du socle ; une sous-page par add-on.
local function rassembler()
  local r = lib.regroupes
  if #r > 0 then
    boutonCommun = boutonCommun or creerBouton()
    boutonCommun.icone:SetTexture(#r == 1 and r[1].icone or ICONE)
    placer(boutonCommun)
  end
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  if not categorie then
    categorie = Settings.RegisterCanvasLayoutCategory(accueil(), NOM)
    Settings.RegisterAddOnCategory(categorie)
  end
  for _, a in ipairs(r) do
    if not a.categorie then a.categorie = Settings.RegisterCanvasLayoutSubcategory(categorie, pageAddOn(a), a.nom) end
  end
end

function lib.Regrouper(r)
  assert(type(r) == "table" and r.nom and type(r.ouvrir) == "function", "lib.Regrouper{ nom, ouvrir, … }")
  for _, o in ipairs(r.outils or {}) do
    assert(o.libelle and type(o.ouvrir) == "function", "lib.Regrouper{ outils = { { libelle, ouvrir, fenetre } } }")
  end
  for _, e in ipairs(r.exports or {}) do
    assert(e.cle and e.libelle and type(e.donnees) == "function", "lib.Regrouper{ exports = { { cle, libelle, description, donnees } } }")
  end
  lib.regroupes[#lib.regroupes + 1] = r
  if IsLoggedIn and IsLoggedIn() then rassembler() end -- add-on chargé après l'entrée en jeu
end

local cadre = CreateFrame("Frame")
cadre:RegisterEvent("PLAYER_LOGIN")
cadre:SetScript("OnEvent", rassembler)
