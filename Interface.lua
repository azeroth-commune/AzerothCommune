-- LibCommune : fenêtres, tableaux triables, montants et noms d'objets, une seule copie pour tous les add-ons.
-- Appel avec un point (lib.Argent(c), pas lib:Argent) : ces fonctions servent aussi telles quelles de fmt à un tableau.
-- Rien n'est sauvegardé ici : ce qui doit durer (tri d'un tableau, base des objets) est une table de l'add-on, passée
-- en paramètre (opts.store, objets, garde).
local lib = LibStub("LibCommune-1.0", true) or LibStub:NewLibrary("LibCommune-1.0", 0) -- chargé seul : outils, tests
-- Ce fichier a sa propre version : de deux copies de la lib (deux add-ons qui l'embarquent), la plus récente sert.
local VERSION = 1
lib.versions = lib.versions or {}
if (lib.versions.interface or 0) >= VERSION then return end
lib.versions.interface = VERSION

---------------------------------------------------------------------------------------------------
-- Une fenêtre sombre, bord lavande, déplaçable, fermée par Échap, avec titre, croix et bouton capture.
-- Bouton capture : seulement si un add-on l'a demandé (lib.captureDansLesFenetres, posé par Be a Good Pal).
function lib.Fenetre(name, title, w, h)
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
  if lib.captureDansLesFenetres and lib.BoutonCapture then lib.BoutonCapture(f, title, -30, -8) end
  f:Hide()
  return f
end

---------------------------------------------------------------------------------------------------
-- Montants
local function pieces() return (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString end
function lib.Argent(c)
  return c and pieces()(math.floor(c + 0.5)) or "?"
end
-- Montant court pour une case de tableau : au-delà d'1 po on oublie les pc, au-delà de 100 po les pa.
function lib.ArgentCourt(c)
  if not c then return "–" end
  c = math.floor(math.abs(c) + 0.5)
  if c >= 1000000 then c = math.floor(c / 10000 + 0.5) * 10000 elseif c >= 10000 then c = math.floor(c / 100 + 0.5) * 100 end
  if c == 0 then return "0" end
  return pieces()(c, 10)
end
function lib.ArgentSigne(c)
  if not c then return "–" end
  return (c >= 0 and "|cff59cc73+" or "|cffe64d4d-") .. lib.ArgentCourt(c) .. "|r"
end

---------------------------------------------------------------------------------------------------
-- Noms d'objets. objets = { [id] = { name, link } } : la base de l'add-on (GameDataItems.items, HandshakeDB.items…).
-- garde : la table où retenir le nom d'un objet quand le serveur l'envoie (nil : ne rien retenir, un autre s'en charge).
local demandes = {} -- [id] = garde (ou false) : déjà demandé au serveur cette session

-- Nom et lien d'un objet ; pas encore connu du client : demandé au serveur, retenu dans garde quand il arrive.
function lib.RetenirObjet(id, garde)
  local name, link = C_Item.GetItemInfo(id)
  if name then
    if garde then garde[id] = { name = name, link = link } end
    return name, link
  end
  if demandes[id] == nil and C_Item.RequestLoadItemDataByID then
    demandes[id] = garde or false
    if not lib.cadreObjets then
      lib.cadreObjets = CreateFrame("Frame")
      lib.cadreObjets:SetScript("OnEvent", function(_, _, iid)
        if iid and demandes[iid] ~= nil then lib.RetenirObjet(iid, demandes[iid] or nil) end
      end)
      pcall(lib.cadreObjets.RegisterEvent, lib.cadreObjets, "ITEM_DATA_LOAD_RESULT")
    end
    C_Item.RequestLoadItemDataByID(id)
  end
end

function lib.NomObjet(id, objets, garde)
  local it = objets and objets[id]
  local _, link = C_Item.GetItemInfo(id)
  if not link and not it then lib.RetenirObjet(id, garde) end
  return (it and it.link) or link or (it and it.name) or ("objet " .. id)
end

-- Un objet d'après un lien, un ID, ou son nom exact (sans casse) dans objets, à défaut le nom d'une recette
-- (recettes = { [clé] = { name, output } }) : on rend alors son produit.
function lib.TrouverObjet(text, objets, recettes)
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
  if id then return id end
  local wanted = text:lower()
  for iid, it in pairs(objets or {}) do
    if it.name and it.name:lower() == wanted then return iid end
  end
  for _, r in pairs(recettes or {}) do
    if r.name and r.name:lower() == wanted then return r.output end
  end
end

---------------------------------------------------------------------------------------------------
-- Tri d'un tableau : colonne sort.key, sens sort.desc ; les cases vides vont toujours en bas, l'ordre d'arrivée
-- départage les égalités (table.sort n'est pas stable).
function lib.TrierLignes(list, cols, sort)
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
-- opts.store[opts.name] (une table des SavedVariables de l'add-on ; sans store, le tri dure la session), lignes
-- alternées, défilement.
--   cols : { key, title, w, get = function(ligne) → valeur de tri, fmt = function(valeur, ligne) → texte,
--            align = "LEFT"/"RIGHT", asc = true (premier clic croissant), icon = function(ligne) → texture,
--            button = function(ligne) → libellé, click = function(ligne), tip = "aide de l'en-tête" }
--   opts : { name, sort = clé par défaut, desc, store, top, bottom, rowH, tooltip = function(ligne, GameTooltip),
--            onClick = function(ligne, bouton) }
-- Renvoie le tableau (t:SetData(liste)) et sa largeur, pour dimensionner la fenêtre.
local GAP = 6
function lib.Tableau(parent, cols, opts)
  local store = opts.store or {}
  local t = { data = {}, rows = {} }
  t.sort = store[opts.name] or { key = opts.sort, desc = opts.desc ~= false }
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
        store[opts.name] = t.sort
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
    lib.TrierLignes(self.data, cols, self.sort)
    content:SetHeight(math.max(1, #self.data * rowH))
    if scroll:GetVerticalScroll() > math.max(0, #self.data * rowH - scroll:GetHeight()) then scroll:SetVerticalScroll(0) end
    render()
  end
  function t:SetData(list) self.data = list; self:Refresh() end
  function t:SetShown(on) header:SetShown(on); scroll:SetShown(on) end
  return t, width
end
