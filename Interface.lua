-- Azeroth Commune : fenêtres, tableaux triables, montants et noms d'objets, pour tous les add-ons.
-- Appel avec un point (AzerothCommune.Argent(c), pas :Argent) : ces fonctions servent aussi telles quelles de fmt à un
-- tableau. Rien n'est sauvegardé ici : ce qui doit durer (tri d'un tableau, base des objets) est une table de l'add-on,
-- passée en paramètre (opts.store, objets, garde).
local lib = AzerothCommune

---------------------------------------------------------------------------------------------------
-- Une fenêtre sombre, bord lavande, déplaçable, fermée par Échap, avec titre, croix et bouton capture.
-- Bouton capture : seulement si un add-on l'a demandé (lib.captureDansLesFenetres, posé par Diagnostic, l'add-on de debug, Diagnostic#7).
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
-- Noms d'objets. objets = { [id] = { name, link } } : la base de l'add-on (HandshakeDB.items…).
-- garde : la table où retenir le nom d'un objet quand le serveur l'envoie (nil : ne rien retenir, un autre s'en charge).
local demandes = {} -- [id] = garde (ou false) : déjà demandé au serveur cette session
local cadreObjets -- écoute ITEM_DATA_LOAD_RESULT, créé à la première demande

-- Sonde : un objet en cache rend son nom. Vérifiée quand le client rend quelque chose de l'objet, ou quand le serveur
-- vient de l'envoyer (charge) ; un objet pas encore en cache n'est pas vérifié. Sans relevé sans contexte : il faut un objet.
lib.DeclarerSonde("nom d'objet", "C_Item.GetItemInfo(id) rend le nom d'un objet en cache, non vide",
  function(nom) return type(nom) == "string" and nom ~= "" end)
local function infoObjet(id, charge)
  local name, link = C_Item.GetItemInfo(id)
  if name ~= nil or link ~= nil or charge then lib.Sonder("nom d'objet", name) end
  return name, link
end

-- Nom et lien d'un objet ; pas encore connu du client : demandé au serveur, retenu dans garde quand il arrive.
function lib.RetenirObjet(id, garde)
  local name, link = infoObjet(id)
  if name then
    if garde then garde[id] = { name = name, link = link } end
    return name, link
  end
  if demandes[id] == nil and C_Item.RequestLoadItemDataByID then
    demandes[id] = garde or false
    if not cadreObjets then
      cadreObjets = CreateFrame("Frame")
      cadreObjets:SetScript("OnEvent", function(_, _, iid, reussi)
        if iid and demandes[iid] ~= nil then
          if reussi then infoObjet(iid, true) end
          lib.RetenirObjet(iid, demandes[iid] or nil)
        end
      end)
      pcall(cadreObjets.RegisterEvent, cadreObjets, "ITEM_DATA_LOAD_RESULT")
    end
    C_Item.RequestLoadItemDataByID(id)
  end
end

function lib.NomObjet(id, objets, garde)
  local it = objets and objets[id]
  local _, link = infoObjet(id)
  if not link and not (it and it.link) then lib.RetenirObjet(id, garde) end -- sans lien (catalogue, #52) : demandé, pour le lien
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

-- Recherche d'objets (#49) : la seule des add-ons. Parmi les objets (type « objets » : les objets vus, et avec le catalogue
-- des objets extrait du client, #52, n'importe quel objet du jeu) et les objets fabriqués de la base des recettes, même
-- jamais vus (trouvés alors par le nom de leur recette). Sans catalogue, le jeu ne donnant aucune liste de ses objets, un
-- objet jamais vu et non fabricable ne se trouve que par son lien (TrouverObjet). Lit les deux types elle-même : l'add-on
-- qui cherche y souscrit.
-- Index en mémoire, refait au plus toutes les 5 s (les objets relevés grossissent pendant le balayage).
-- ponytail: un objet relevé ou effacé (/ac effacer) dans ces 5 s attend l'index suivant ; si ça se voit, refaire
-- l'index sur un rappel QuandReleve (« objets » et « base des recettes » ne signalent pas encore : lib:Signaler)
local index, indexFait
local function indexObjets()
  local maintenant = GetTime()
  if index and maintenant - indexFait < 5 then return index end
  local craft, objets = {}, lib:Lire("objets") or {}
  index, indexFait = {}, maintenant
  for _, r in pairs(lib:Lire("base des recettes") or {}) do
    if r.output then craft[r.output] = r.name or craft[r.output] or true end
  end
  for id, it in pairs(objets) do
    if it.name then index[#index + 1] = { id = id, name = it.name, low = it.name:lower(), fabricable = craft[id] ~= nil } end
  end
  for id, nom in pairs(craft) do
    if type(nom) == "string" and not (objets[id] and objets[id].name) then
      index[#index + 1] = { id = id, name = nom, low = nom:lower(), fabricable = true }
    end
  end
  return index
end

-- Les objets dont le nom contient texte (sans casse, au moins 2 caractères), au plus max (8 par défaut) :
-- { { id, name, fabricable }, … }, fabricables d'abord, puis ceux qui commencent par le texte, puis les noms courts, puis l'ID.
-- ponytail: :lower() ne connaît pas les accents (« É » reste « É ») ; taper en minuscules marche
function lib.ChercherObjets(texte, max)
  local q = (texte or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #q < 2 then return {} end
  local hits = {}
  for _, e in ipairs(indexObjets()) do
    local at = e.low:find(q, 1, true)
    if at then hits[#hits + 1] = { e = e, s = (e.fabricable and 0 or 2) + (at == 1 and 0 or 1) } end
  end
  table.sort(hits, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    if #a.e.name ~= #b.e.name then return #a.e.name < #b.e.name end
    return a.e.id < b.e.id
  end)
  local out = {}
  for i = 1, math.min(max or 8, #hits) do
    local e = hits[i].e
    out[i] = { id = e.id, name = e.name, fabricable = e.fabricable }
  end
  return out
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
