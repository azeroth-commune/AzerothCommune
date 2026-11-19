-- GameData : cadre de fenêtre commun, bouton de la minicarte et fenêtre d'export.
--   Minicarte : clic gauche = fenêtre GameData : outils (acheter ou fabriquer, Mécréant) et exports (ouvre / replie), clic droit = « Acheter ou fabriquer »,
--               glisser = le déplacer autour de la carte (position gardée).
--   Export : un bouton par partie de la base ; chaque export est photographié en grilles de couleurs
--            (BeAGoodPal.Export), puis relu hors du jeu par tools/crop_captures.py. Sans /reload.
local _, ns = ...

-- Une fenêtre sombre, bord lavande, déplaçable, fermée par Échap, avec titre, croix et bouton capture.
function ns.newWindow(name, title, w, h)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
  f:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.35)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  -- Deux fenêtres au même niveau mélangeaient leurs textes (18/11/2026) : celle qu'on ouvre ou qu'on clique passe devant.
  f:SetToplevel(true)
  f:HookScript("OnShow", function(self) self:Raise() end)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  table.insert(UISpecialFrames, name) -- Échap ferme la fenêtre
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 14, -12)
  f.title:SetText(title)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  if BeAGoodPal and BeAGoodPal.AddCaptureButton then BeAGoodPal.AddCaptureButton(f, title, -30, -8) end
  f:Hide()
  return f
end

---------------------------------------------------------------------------------------------------
-- Montant, nom d'objet, objet d'après un nom/lien/ID (servent aussi à BeAGoodPal_Commandes)
function ns.money(c)
  local fmt = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  return c and fmt(math.floor(c + 0.5)) or "?"
end
function ns.itemLabel(id)
  local it = GameDataItems.items and GameDataItems.items[id]
  return (it and it.link) or select(2, C_Item.GetItemInfo(id)) or (it and it.name) or ("objet " .. id)
end

function ns.findItem(text)
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
  if id then return id end
  local wanted = text:lower()
  for iid, it in pairs(GameDataItems.items or {}) do
    if it.name and it.name:lower() == wanted then return iid end
  end
  for _, r in pairs(GameDataDB.recipes or {}) do
    if r.name and r.name:lower() == wanted then return r.output end
  end
end

---------------------------------------------------------------------------------------------------
-- Montant court pour une case de tableau : au-delà d'1 po on oublie les pc, au-delà de 100 po les pa.
function ns.moneyShort(c)
  if not c then return "–" end
  c = math.floor(math.abs(c) + 0.5)
  if c >= 1000000 then c = math.floor(c / 10000 + 0.5) * 10000 elseif c >= 10000 then c = math.floor(c / 100 + 0.5) * 100 end
  if c == 0 then return "0" end
  return ((C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString)(c, 10)
end
function ns.moneySigned(c)
  if not c then return "–" end
  return (c >= 0 and "|cff59cc73+" or "|cffe64d4d-") .. ns.moneyShort(c) .. "|r"
end

-- Tri d'un tableau : colonne sort.key, sens sort.desc ; les cases vides vont toujours en bas, l'ordre d'arrivée
-- départage les égalités (table.sort n'est pas stable).
function ns.sortRows(list, cols, sort)
  local get
  for _, c in ipairs(cols) do if c.key == sort.key then get = c.get end end
  if not get then return list end
  local v, pos = {}, {}
  for i, r in ipairs(list) do v[r], pos[r] = get(r), i end
  table.sort(list, function(a, b)
    local x, y = v[a], v[b]
    if (x == nil) ~= (y == nil) then return x ~= nil end
    if x == nil or x == y then return pos[a] < pos[b] end
    if sort.desc then return x > y end
    return x < y
  end)
  return list
end

-- Un vrai tableau : en-têtes cliquables (clic = trier sur cette colonne, re-clic = sens inverse), tri gardé dans
-- GameDataDB.sort[name], lignes alternées, défilement.
--   cols : { key, title, w, get = function(ligne) → valeur de tri, fmt = function(valeur, ligne) → texte,
--            align = "LEFT"/"RIGHT", asc = true (premier clic croissant), icon = function(ligne) → texture,
--            button = function(ligne) → libellé, click = function(ligne), tip = "aide de l'en-tête" }
--   opts : { name, sort = clé par défaut, desc, top, bottom, rowH, tooltip = function(ligne, GameTooltip),
--            onClick = function(ligne, bouton) }
-- Renvoie le tableau (t:SetData(liste)) et sa largeur, pour dimensionner la fenêtre.
local GAP = 6
function ns.newTable(parent, cols, opts)
  GameDataDB.sort = GameDataDB.sort or {}
  local t = { data = {}, rows = {} }
  t.sort = GameDataDB.sort[opts.name] or { key = opts.sort, desc = opts.desc ~= false }
  local rowH, width = opts.rowH or 20, 0
  for _, c in ipairs(cols) do width = width + c.w + GAP end
  local header = CreateFrame("Frame", nil, parent)
  header:SetPoint("TOPLEFT", 14, -(opts.top or 40))
  header:SetSize(width, 18)
  local function arrows()
    for _, c in ipairs(cols) do
      if c.head then
        local on = t.sort.key == c.key
        c.head.text:SetTextColor(on and 1 or 0.85, on and 0.82 or 0.78, on and 0.2 or 0.6)
        c.head.arrow:SetShown(on)
        if t.sort.desc then c.head.arrow:SetTexCoord(0, 0.5625, 0, 1) else c.head.arrow:SetTexCoord(0, 0.5625, 1, 0) end
      end
    end
  end
  local x = 0
  for _, c in ipairs(cols) do
    c.x = x
    if c.get then
      local b = CreateFrame("Button", nil, header)
      b:SetPoint("TOPLEFT", x, 0)
      b:SetSize(c.w, 18)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.text:SetAllPoints()
      b.text:SetJustifyH(c.align or "LEFT")
      b.text:SetWordWrap(false)
      b.text:SetText(c.title)
      -- La flèche du tri : la texture des colonnes du jeu (les ▲▼ ne sont pas dans toutes les polices).
      b.arrow = b:CreateTexture(nil, "OVERLAY")
      b.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
      b.arrow:SetSize(9, 8)
      if c.align == "RIGHT" then b.arrow:SetPoint("RIGHT", b.text, "RIGHT", -(b.text:GetStringWidth() + 3), 0)
      else b.arrow:SetPoint("LEFT", b.text, "LEFT", b.text:GetStringWidth() + 3, 0) end
      b.arrow:Hide()
      b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
      b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
      b:SetScript("OnClick", function()
        if t.sort.key == c.key then t.sort.desc = not t.sort.desc else t.sort = { key = c.key, desc = not c.asc } end
        GameDataDB.sort[opts.name] = t.sort
        t:Refresh()
      end)
      if c.tip then
        b:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_TOP")
          GameTooltip:SetText(c.title)
          GameTooltip:AddLine(c.tip, 1, 1, 1, true)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      c.head = b
    end
    x = x + c.w + GAP
  end
  local line = header:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.66, 0.56, 1, 0.3)
  line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  line:SetSize(width, 1)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -32, opts.bottom or 30)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(width, 1)
  scroll:SetScrollChild(content)
  t.header, t.scroll = header, scroll

  local function makeRow()
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(width, rowH)
    r:EnableMouse(true)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(0.66, 0.56, 1, 0.12)
    r.cells = {}
    for k, c in ipairs(cols) do
      if c.button then
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetSize(c.w, rowH - 2)
        b:SetPoint("LEFT", c.x, 0)
        b:SetScript("OnClick", function() c.click(r.item) end)
        r.cells[k] = b
      else
        local left = c.x
        if c.icon then
          r["icon" .. k] = r:CreateTexture(nil, "ARTWORK")
          r["icon" .. k]:SetSize(rowH - 4, rowH - 4)
          r["icon" .. k]:SetPoint("LEFT", left, 0)
          left = left + rowH
        end
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", left, 0)
        fs:SetWidth(c.w - (left - c.x))
        fs:SetJustifyH(c.align or "LEFT")
        fs:SetWordWrap(false)
        r.cells[k] = fs
      end
    end
    if opts.onClick then r:SetScript("OnMouseUp", function(self, button) opts.onClick(self.item, button) end) end
    if opts.tooltip then
      r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        opts.tooltip(self.item, GameTooltip)
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return r
  end

  -- Seules les lignes visibles existent (une vingtaine), réutilisées au défilement : le journal entier (5 000
  -- opérations) en créait une par opération et figeait le jeu (18/11/2026).
  local function render()
    local first = math.floor(scroll:GetVerticalScroll() / rowH) + 1
    local shown = math.ceil(scroll:GetHeight() / rowH) + 1
    for slot = 1, shown do
      local i, r = first + slot - 1, t.rows[slot]
      local item = t.data[i]
      if item then
        if not r then r = makeRow(); t.rows[slot] = r end
        r.item = item
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
        for k, c in ipairs(cols) do
          if c.button then
            local label = c.button(item)
            r.cells[k]:SetShown(label ~= nil)
            if label then r.cells[k]:SetText(label) end
          else
            local v = c.get and c.get(item)
            r.cells[k]:SetText(c.fmt and c.fmt(v, item) or (v == nil and "–" or tostring(v)))
            if c.icon then r["icon" .. k]:SetTexture(c.icon(item)) end
          end
        end
        r:Show()
      elseif r then
        r:Hide()
      end
    end
    for slot = shown + 1, #t.rows do t.rows[slot]:Hide() end
  end
  scroll:HookScript("OnVerticalScroll", render)
  scroll:HookScript("OnSizeChanged", render)

  function t:Refresh()
    arrows()
    ns.sortRows(self.data, cols, self.sort)
    content:SetHeight(math.max(1, #self.data * rowH))
    if scroll:GetVerticalScroll() > math.max(0, #self.data * rowH - scroll:GetHeight()) then scroll:SetVerticalScroll(0) end
    render()
  end
  function t:SetData(list) self.data = list; self:Refresh() end
  function t:SetShown(on) header:SetShown(on); scroll:SetShown(on) end
  return t, width
end

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
  { "mecreant", "Mécréant", "les affaires proposées, avec PNJ, faction et trajet (diagnostic)" },
  { "journal", "Journal", "tes achats, ventes, mises en vente et retours, avec le bilan par objet" },
}

local exportFrame
local function buildExport()
  local f = ns.newWindow("GameDataExportFrame", "GameData", 500, 160 + #EXPORTS * 34) -- 4 outils de 118 px
  -- Ouvrir un outil referme ce menu : les deux fenêtres ne se superposent pas.
  local function show(name, toggle)
    return function()
      f:Hide()
      local w = _G[name]
      if w and w:IsShown() then w:Raise() else toggle() end
    end
  end
  local tools = { { "Acheter ou fabriquer", function() f:Hide(); if ns.openCraftWindow then ns.openCraftWindow() end end },
    { "Mécréant", show("GameDataFlipFrame", function() ns.toggleFlipWindow() end) },
    { "Journal", show("GameDataLedgerFrame", function() ns.toggleLedgerWindow() end) },
    { "Alertes HV", show("GameDataAlertFrame", function() ns.toggleAlertWindow() end) } }
  for i, t in ipairs(tools) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(114, 24)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 118, -40)
    b:SetText(t[1])
    b:SetScript("OnClick", t[2])
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
