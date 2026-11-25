-- Azeroth Commune : fenêtres, tableaux triables, montants et noms d'objets, pour tous les add-ons.
-- Appel avec un point (AzerothCommune.Argent(c), pas :Argent) : ces fonctions servent aussi telles quelles de fmt à un
-- tableau. Seule la géométrie des fenêtres (place et taille, de l'interface) est sauvegardée ici, dans
-- AzerothCommuneDB.fenetres ; le reste de ce qui doit durer (tri d'un tableau, base des objets) est une table de l'add-on,
-- passée en paramètre (opts.store, objets, garde).
local lib = AzerothCommune

---------------------------------------------------------------------------------------------------
-- Une fenêtre au look du jeu (ButtonFrameTemplate sans portrait : son titre, sa croix), déplaçable, fermée par Échap,
-- avec poignée de redimensionnement et bouton capture. f.title est le titre du gabarit.
-- La taille de création est la taille de départ et le minimum ; une largeur fixée ensuite par l'add-on
-- (f:SetWidth(largeur du tableau + 50)) relève le minimum, et à la création (fenêtre pas encore montrée) la largeur
-- retenue, si elle est plus grande, l'emporte. Une hauteur fixée par l'add-on (d'après son contenu) est prise telle quelle.
-- Place et taille retenues pour le compte dans AzerothCommuneDB.fenetres[name] (la géométrie d'une fenêtre est de
-- l'interface), retrouvées à la création ; pas par le jeu (SetUserPlaced(false)). Base pas encore chargée : rien n'est
-- lu ni retenu cette fois.
-- opts (facultatif) : { redimensionnable = false (pas de poignée, taille gérée par l'add-on, seule la place est retenue,
-- si le joueur l'a déplacée), place = { "TOPRIGHT", Minimap, "TOPLEFT", -12, -20 } (tant que rien n'est retenu ; le
-- centre sinon), cadre = false (un affichage informatif, pas une fenêtre : cadre nu, sans gabarit, titre, croix, poignée
-- ni Échap ; seule la place est retenue, comme redimensionnable = false ; l'add-on dessine son en-tête et le désigne par
-- f:DeplacePar(entete)) }. Une fenêtre qui se place elle-même après coup (ClearAllPoints, SetPoint) garde sa place.
-- f:DeplacePar(enfant) : glisser cet enfant déplace f et retient sa place (une ligne du contenu, l'en-tête d'un cadre nu).
-- Bouton capture : seulement si un add-on l'a demandé (lib.captureDansLesFenetres, posé par Diagnostic, l'add-on de debug, Diagnostic#7).
function lib.Fenetre(name, title, w, h, opts)
  opts = opts or {}
  local nu = opts.cadre == false
  local redim = not nu and opts.redimensionnable ~= false
  local f = CreateFrame("Frame", name, UIParent, not nu and "ButtonFrameTemplate" or nil)
  if not nu then
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideAttic(f)
    ButtonFrameTemplate_HideButtonBar(f)
    f:SetTitle(title)
    f.title = f:GetTitleText()
  end
  local g = AzerothCommuneDB and AzerothCommuneDB.fenetres and AzerothCommuneDB.fenetres[name]
  -- La taille choisie par le joueur (à la poignée), jamais plus grande que l'écran ; ne sert qu'à la création.
  local voulue = redim and g and g.w and g.h and { math.min(g.w, UIParent:GetWidth()), math.min(g.h, UIParent:GetHeight()) }
  f:SetSize(voulue and math.max(w, voulue[1]) or w, voulue and math.max(h, voulue[2]) or h)
  f:ClearAllPoints()
  if g and g.x and g.y then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.x, g.y)
  elseif opts.place then f:SetPoint(unpack(opts.place))
  else f:SetPoint("CENTER") end
  f:SetFrameStrata("HIGH")
  f:EnableMouse(not nu) -- un cadre nu laisse passer les clics entre ses lignes, comme le suivi des quêtes du jeu
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  -- Deux fenêtres au même niveau mélangeaient leurs textes (18/11/2026) : celle qu'on ouvre ou qu'on clique passe devant.
  f:SetToplevel(true)
  f:HookScript("OnShow", function(self) self:Raise() end)
  -- Un déplacement retient la place seule ; la poignée, la place et la taille (une taille retenue avant reste).
  local function retenir(avecTaille)
    f:StopMovingOrSizing()
    f:SetUserPlaced(false) -- c'est nous qui retenons la place, pas le jeu
    if not AzerothCommuneDB then return end
    AzerothCommuneDB.fenetres = AzerothCommuneDB.fenetres or {}
    local r = AzerothCommuneDB.fenetres[name] or {}
    r.x, r.y = math.floor(f:GetLeft() + 0.5), math.floor(f:GetTop() + 0.5)
    if avecTaille then r.w, r.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) end
    AzerothCommuneDB.fenetres[name] = r
  end
  function f:DeplacePar(poignee)
    poignee:EnableMouse(true)
    poignee:RegisterForDrag("LeftButton")
    poignee:SetScript("OnDragStart", function() f:StartMoving() end)
    poignee:SetScript("OnDragStop", function() retenir(false) end)
  end
  if not nu then f:DeplacePar(f) end
  if redim then
    local minW, minH = w, h
    f:SetResizable(true)
    f:SetResizeBounds(minW, minH)
    local poignee = CreateFrame("Button", nil, f, "PanelResizeButtonTemplate")
    poignee:SetPoint("BOTTOMRIGHT", -4, 4)
    poignee:Init(f, minW, minH)
    f.ResizeButton = poignee
    poignee.resizeStoppedCallback = function()
      f:SetSize(math.max(minW, f:GetWidth()), math.max(minH, f:GetHeight())) -- le jeu borne déjà ; au cas où
      retenir(true)
    end
    -- La largeur fixée par l'add-on relève le minimum (pas pendant que le joueur tire la poignée : la borne du gabarit
    -- passe aussi par SetWidth). Pas la hauteur : celle d'un contenu doit pouvoir redescendre.
    f:HookScript("OnShow", function() voulue = nil end) -- la taille retenue ne sert qu'à la création
    hooksecurefunc(f, "SetWidth", function(_, v)
      if poignee:IsActive() then return end
      minW = math.max(minW, v)
      f:SetResizeBounds(minW, minH)
      poignee:SetMinWidth(minW)
      if voulue and not f:IsShown() and voulue[1] > v then f:SetSize(voulue[1], f:GetHeight()) end
    end)
  end
  if not nu then table.insert(UISpecialFrames, name) end -- Échap ferme la fenêtre
  if not nu and lib.captureDansLesFenetres and lib.BoutonCapture then -- dans la barre de titre, au niveau de la croix (sinon sous le cadre)
    lib.BoutonCapture(f, title, -28, -3):SetFrameLevel(f.CloseButton:GetFrameLevel())
  end
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
-- (recettes = { [clé] = { name, output } }) : on rend alors son produit (un enchantement n'en a pas : on cherche plus loin).
function lib.TrouverObjet(text, objets, recettes)
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
  if id then return id end
  local wanted = text:lower()
  for iid, it in pairs(objets or {}) do
    if it.name and it.name:lower() == wanted then return iid end
  end
  for _, r in pairs(recettes or {}) do
    if r.output and r.name and r.name:lower() == wanted then return r.output end
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

-- Un objet pris dans les sacs (au curseur) et déposé sur f : il est rendu à son sac et onObjet(id) le reçoit (#60).
function lib.RecevoirObjet(f, onObjet)
  local function depose()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return end
    ClearCursor()
    onObjet(id)
  end
  f:EnableMouse(true)
  f:SetScript("OnReceiveDrag", depose)
  f:HookScript("OnMouseUp", depose)
end

-- Barre de recherche d'objets avec suggestions (ChercherObjets ; #60, montée de Composants et de Handshake) : flèches
-- haut/bas, Entrée ou Tab pour choisir, ou clic ; Entrée sans suggestion : TrouverObjet (nom exact, lien ou ID) ; un objet
-- déposé sur le champ est choisi aussitôt. onPick(id, quantité), la quantité lue dans l'EditBox qty (1 au moins), dont
-- l'Entrée valide aussi. w = largeur du champ (280 par défaut). Renvoie le champ (marqué .recherche) et la validation.
-- Maj+clic n'est pas pris : dans le jeu, il sépare une pile ou colle le lien dans la discussion.
function lib.RechercheObjets(parent, qty, onPick, w)
  w = w or 280
  local name = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  name:SetSize(w, 22)
  name:SetAutoFocus(false)
  name.recherche = true
  local drop = CreateFrame("Frame", nil, parent, "TooltipBackdropTemplate") -- le fond des bulles d'aide du jeu
  drop:SetPoint("TOPLEFT", name, "BOTTOMLEFT", -6, -2)
  drop:SetSize(w + 40, 10)
  drop:SetFrameStrata("DIALOG")
  drop:Hide()
  local buttons, hits, sel = {}, {}, 1
  local function qtyValue() return math.max(1, tonumber(qty:GetText()) or 1) end
  local function pick(e)
    onPick(e.id, qtyValue())
    name:SetText("")
    name:ClearFocus()
    drop:Hide()
  end
  local function paint()
    for i, b in ipairs(buttons) do b.hl:SetShown(i == sel) end
  end
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, drop)
    b:SetSize(w + 36, 20)
    b:SetPoint("TOPLEFT", 2, -4 - (i - 1) * 20)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight") -- la surbrillance des listes du jeu
    b.hl:SetBlendMode("ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 4, 0)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 24, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function() sel = i; paint() end)
    b:SetScript("OnClick", function() if hits[i] then pick(hits[i]) end end)
    buttons[i] = b
  end
  local function update()
    hits, sel = lib.ChercherObjets(name:GetText(), 8), 1
    for i, b in ipairs(buttons) do
      local e = hits[i]
      b:SetShown(e ~= nil)
      if e then
        b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
        b.text:SetText(e.name .. (e.fabricable and "  |cffe6a640fabricable|r" or ""))
      end
    end
    drop:SetHeight(8 + 20 * #hits)
    drop:SetShown(#hits > 0)
    paint()
  end
  local function submit()
    if drop:IsShown() and hits[sel] then return pick(hits[sel]) end
    local id = lib.TrouverObjet(name:GetText() or "", lib:Lire("objets"), lib:Lire("base des recettes"))
    if not id then return print("Azeroth Commune : objet introuvable (nom exact, lien ou ID).") end
    pick({ id = id })
  end
  name:SetScript("OnTextChanged", function(_, userInput) if userInput then update() end end)
  name:SetScript("OnEditFocusLost", function() C_Timer.After(0.2, function() drop:Hide() end) end) -- laisse passer le clic
  name:SetScript("OnEscapePressed", function(self) drop:Hide(); self:ClearFocus() end)
  name:SetScript("OnEnterPressed", submit)
  name:SetScript("OnTabPressed", function() if hits[sel] then pick(hits[sel]) end end)
  name:SetScript("OnArrowPressed", function(_, key)
    if not drop:IsShown() then return end
    if key == "DOWN" then sel = math.min(#hits, sel + 1) elseif key == "UP" then sel = math.max(1, sel - 1) end
    paint()
  end)
  qty:SetScript("OnEnterPressed", submit)
  lib.RecevoirObjet(name, function(id) onPick(id, qtyValue()) end)
  return name, submit
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
--            button = function(ligne) → libellé, click = function(ligne), tip = "aide de l'en-tête",
--            extensible = true (une colonne au plus : elle prend la largeur libre, et s'élargit avec la fenêtre) }
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
  for _, c in ipairs(cols) do
    if c.get then
      local b = CreateFrame("Button", nil, header)
      b:SetHeight(18)
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
  end
  local line = header:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  line:SetHeight(1)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -32, opts.bottom or 30)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetHeight(1)
  scroll:SetScrollChild(content)
  t.header, t.scroll = header, scroll

  -- La colonne extensible prend la largeur libre du défilement (ancré au bord droit du parent) : elle s'élargit avec la
  -- fenêtre, les autres gardent la leur. c.x, c.lw : place et largeur du moment.
  local total = width
  local function placer(r)
    r:SetWidth(total)
    for k, c in ipairs(cols) do
      local cell = r.cells[k]
      if c.button then
        cell:SetWidth(c.lw)
        cell:SetPoint("LEFT", c.x, 0)
      else
        local left = c.x
        if c.icon then r["icon" .. k]:SetPoint("LEFT", left, 0); left = left + rowH end
        cell:SetPoint("LEFT", left, 0)
        cell:SetWidth(c.lw - (left - c.x))
      end
    end
  end
  local function disposer()
    local libre, x = math.max(0, math.floor(scroll:GetWidth() - width)), 0
    for _, c in ipairs(cols) do
      c.x, c.lw = x, c.w + (c.extensible and libre or 0)
      if c.head then c.head:SetPoint("TOPLEFT", x, 0); c.head:SetWidth(c.lw) end
      x = x + c.lw + GAP
    end
    total = x
    header:SetWidth(total)
    line:SetWidth(total)
    content:SetWidth(total)
    for _, r in ipairs(t.rows) do placer(r) end
  end
  disposer()

  local function makeRow()
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(rowH)
    r:EnableMouse(true)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.08)
    r.cells = {}
    for k, c in ipairs(cols) do
      if c.button then
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetHeight(rowH - 2)
        b:SetScript("OnClick", function() c.click(r.item) end)
        r.cells[k] = b
      else
        if c.icon then
          r["icon" .. k] = r:CreateTexture(nil, "ARTWORK")
          r["icon" .. k]:SetSize(rowH - 4, rowH - 4)
        end
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    placer(r)
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
  scroll:HookScript("OnSizeChanged", function() disposer(); render() end)

  function t:Refresh()
    disposer() -- un onglet caché pendant que la fenêtre changeait de taille se remet en place
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
