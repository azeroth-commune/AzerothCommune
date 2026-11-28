-- Azeroth Commune : l'Arbre (langage commun de la carte des contextes), des cases reliées en étages de gauche à droite,
-- rangées en bandes empilées. L'add-on dit ses cases, ses liens et ses bandes, et dessine chaque case ; le socle les place
-- (AzerothCommune.PlacerArbre, sans aucun cadre : testé hors jeu), trace les liens et fait défiler la toile
-- (AzerothCommune.Arbre). Extrait de l'arbre de fabrication de Composants (#108) ; Compagnie y dessine ses chaînes.
local lib = AzerothCommune

-- Tailles par défaut, en unités du dessin : celles de l'arbre de Composants.
local DIMS = { largeur = 190, hauteur = 42, ecart = 8, relais = 10, entreBandes = 28, marge = 10, haut = 36 }

---------------------------------------------------------------------------------------------------
-- Hauteurs. Chaque case (ou relais) vise le milieu de ses voisins, sans chevauchement (de gauche à droite, puis retour).
-- Un relais ne prend que la hauteur d'un lien. Chaque bande est placée seule (voisins de sa bande seulement), puis les
-- bandes sont empilées, entreBandes entre elles. Une bande tient donc dans un rectangle ; un lien d'une bande à l'autre ne
-- passe qu'entre deux étages.
local function hauteurs(g, bands, d)
  local last, up, down = g.cols - 1, g.up, g.down
  local step = d.hauteur + d.ecart
  local function half(n) return n.kind == "relay" and d.relais / 2 or d.hauteur / 2 end
  local function size(n) return n.kind == "relay" and d.relais or step end
  local function bandOf(n) -- (pas « bands and n.band or 1 » : une bande peut avoir la clé false)
    if bands then return n.band end
    return 1
  end
  local offset, any = 0, false
  for _, key in ipairs(bands or { 1 }) do
    local cols, members = {}, {}
    for c = 0, last do cols[c] = {} end
    for _, n in ipairs(g.all) do
      if bandOf(n) == key then table.insert(cols[n.col], n); members[#members + 1] = n end
    end
    if #members > 0 then
      local function aim(n, around, fallback)
        local s, k = 0, 0
        for _, v in ipairs(around) do
          if bandOf(v) == key then s, k = s + v.y + half(v), k + 1 end
        end
        if k == 0 then return fallback end
        return s / k - half(n)
      end
      local function place(col)
        table.sort(col, function(a, b) if a.w ~= b.w then return a.w < b.w end return a.key < b.key end)
        local prev
        for _, n in ipairs(col) do
          n.y = (prev and n.w < prev.y + size(prev)) and prev.y + size(prev) or n.w
          prev = n
        end
      end
      table.sort(cols[0], function(a, b) return (a.index or 0) < (b.index or 0) end)
      for i, n in ipairs(cols[0]) do n.w = (i - 1) * step end
      place(cols[0])
      for c = 1, last do
        for _, n in ipairs(cols[c]) do n.w = aim(n, up[n], 0) end
        place(cols[c])
      end
      for c = last - 1, 0, -1 do
        for _, n in ipairs(cols[c]) do n.w = aim(n, down[n], n.y) end
        place(cols[c])
      end
      local minY, maxY = math.huge, -math.huge
      for _, n in ipairs(members) do minY, maxY = math.min(minY, n.y), math.max(maxY, n.y + 2 * half(n)) end
      if any then offset = offset + d.entreBandes end
      for _, n in ipairs(members) do n.y = n.y - minY + offset end
      offset, any = offset + maxY - minY, true
    end
  end
  g.height = offset
end

-- AzerothCommune.PlacerArbre(cases, liens, bandes, dims) → g : le placement seul, sans aucun cadre.
--   cases : { { key = clé unique (texte), band = clé de sa bande, index = rang en tête (facultatif : une racine, à l'étage 0,
--           rangée par son rang) }, … } ; les autres champs sont à l'add-on (sa fonction de case les lit).
--   liens : { { from = case, to = case }, … }, du parent vers l'enfant ; facultatifs, pour le dessin (arbre:Dessiner) :
--           text (écrit juste avant la case d'arrivée), color = { r, g, b }, thick (2 par défaut), hidden (placé, pas tracé).
--   bandes (facultatif) : { { key, title, color = { r, g, b } }, … } dans l'ordre, de haut en bas ; sans elles, une seule.
--           Au dessin, une bande avec color a son rectangle (ses cases, à sa couleur), une bande avec title son en-tête.
--   dims (facultatif) : les tailles, en unités du dessin (défauts : DIMS) : largeur et hauteur d'une case (imposées),
--           ecart entre deux cases d'un étage, relais (la place d'un lien qui traverse un étage), entreBandes, marge (à
--           gauche et à droite) et haut (au-dessus de la première bande : la place de son en-tête).
-- Écrit sur chaque case col (son étage : 0 pour une racine ou une case sans parent, sinon juste à droite de son parent le
-- plus à droite) et y (son haut, depuis le haut de la première bande) ; sur chaque lien path (départ, relais…, arrivée :
-- un relais { kind = "relay", col, y, band = celle du départ } dans chaque étage sauté, que les cases de l'étage laissent
-- libre : un lien ne passe jamais sous une case), first et last (le premier et le dernier pas après le départ).
-- g = { nodes = cases, edges = liens, cols = nombre d'étages, height = hauteur de toutes les bandes, bands, dims,
--       all = cases et relais, up / down = [nœud] → voisins de gauche / de droite }.
function lib.PlacerArbre(cases, liens, bandes, dims)
  local d = setmetatable({}, { __index = DIMS })
  for k, v in pairs(dims or {}) do d[k] = v end
  local parents = {}
  for _, n in ipairs(cases) do parents[n] = {} end
  for _, e in ipairs(liens) do table.insert(parents[e.to], e.from) end
  for _, n in ipairs(cases) do n.col = n.index and 0 or 1 end
  for _ = 1, #cases do -- ponytail: relaxation O(n²), assez pour quelques dizaines de cases ; s'arrête sur une boucle
    local changed = false
    for _, n in ipairs(cases) do
      if not n.index then
        local c = #parents[n] == 0 and 0 or 1
        for _, p in ipairs(parents[n]) do c = math.max(c, p.col + 1) end
        if c ~= n.col then n.col, changed = c, true end
      end
    end
    if not changed then break end
  end
  local last = 0
  for _, n in ipairs(cases) do last = math.max(last, n.col) end

  local all, up, down = {}, {}, {}
  for _, n in ipairs(cases) do all[#all + 1], up[n], down[n] = n, {}, {} end
  for _, e in ipairs(liens) do
    e.path = { e.from }
    for c = e.from.col + 1, e.to.col - 1 do
      local r = { key = "R" .. e.from.key .. ">" .. e.to.key .. ":" .. c, kind = "relay", col = c, band = e.from.band }
      all[#all + 1], up[r], down[r] = r, {}, {}
      e.path[#e.path + 1] = r
    end
    e.path[#e.path + 1] = e.to
    for i = 2, #e.path do
      table.insert(down[e.path[i - 1]], e.path[i]); table.insert(up[e.path[i]], e.path[i - 1])
    end
    e.first, e.last = e.path[2], e.path[#e.path - 1]
  end
  local g = { nodes = cases, edges = liens, cols = last + 1, bands = bandes, dims = d, all = all, up = up, down = down }
  local keys
  if bandes then
    keys = {}
    for i, b in ipairs(bandes) do keys[i] = b.key end
  end
  hauteurs(g, keys, d)
  return g
end

---------------------------------------------------------------------------------------------------
-- AzerothCommune.Arbre(parent, opts) → arbre : la toile qui défile, où arbre:Dessiner(g) dessine un placement
-- (g = AzerothCommune.PlacerArbre(…), que l'add-on peut retoucher avant, ex. g.height).
--   opts.case = function(case, cadre) → cadre : la fonction de case de l'add-on, appelée pour chaque case à chaque dessin ;
--     cadre = nil la première fois (elle le crée, sur arbre.toile, et le rend), puis le même cadre d'un dessin à l'autre
--     (un cadre par rang de case : cases[i] reçoit arbre.cadres[i]) ; elle le remplit. L'Arbre lui impose sa taille
--     (dims.largeur × dims.hauteur), le place et l'affiche ; les cadres de trop sont cachés.
--   arbre.zone : le cadre qui découpe la toile, à ancrer par l'add-on ; molette = zoom autour du curseur, glisser le fond =
--     déplacer, clic du milieu = vue ajustée (le dessin rétrécit pour tenir en largeur, jamais ne grandit).
--   arbre.toile : le dessin (l'add-on y pose ses propres éléments : en-têtes d'étage, étiquettes…) ; arbre.vue = { zoom,
--     x, y, fit } : l'échelle de la toile est fit × zoom, son décalage x, y en unités du dessin.
--   arbre.cadres : les cadres des cases (rang de g.nodes) ; arbre.rectangles : un cadre par bande dessinée (ceux de trop
--     cachés), r.band = la bande, r.title = son en-tête (texte de bande.title, au-dessus du rectangle), r.color.
-- Après arbre:Dessiner(g) : n.x (abscisse sur la toile) sur chaque case et relais, n.y + dims.haut son ordonnée (vers le bas),
-- g.ecart la distance entre deux étages (ils s'étalent sur la largeur de la zone, 44 au moins entre deux cases).
local COULEUR_LIEN = { 0.60, 0.60, 0.62 }
function lib.Arbre(parent, opts)
  local zone = CreateFrame("Frame", nil, parent)
  zone:SetClipsChildren(true)
  local toile = CreateFrame("Frame", nil, zone)
  toile:SetSize(1, 1)
  local vue = { zoom = 1, x = 0, y = 0, fit = 1 }
  local arbre = { zone = zone, toile = toile, vue = vue, cadres = {}, rectangles = {} }
  local function appliquer()
    vue.zoom = math.max(0.25, math.min(3, vue.zoom))
    toile:SetScale(vue.fit * vue.zoom)
    toile:ClearAllPoints()
    toile:SetPoint("TOPLEFT", zone, "TOPLEFT", vue.x, vue.y) -- décalage dans l'échelle du dessin
  end
  local function curseur() -- le curseur dans la zone, vers la droite et vers le bas
    local cx, cy = GetCursorPosition()
    local es = zone:GetEffectiveScale()
    return cx / es - zone:GetLeft(), zone:GetTop() - cy / es
  end
  zone:EnableMouseWheel(true)
  zone:SetScript("OnMouseWheel", function(_, d)
    local mx, my = curseur()
    local s = vue.fit * vue.zoom
    local px, py = mx / s - vue.x, my / s + vue.y -- le point du dessin sous le curseur…
    vue.zoom = vue.zoom * (d > 0 and 1.15 or 1 / 1.15)
    appliquer()
    s = vue.fit * vue.zoom
    vue.x, vue.y = mx / s - px, py - my / s -- …reste sous le curseur
    appliquer()
  end)
  zone:EnableMouse(true)
  local drag
  zone:SetScript("OnMouseDown", function(_, button)
    if button == "MiddleButton" then vue.zoom, vue.x, vue.y = 1, 0, 0; return appliquer() end
    local mx, my = curseur()
    drag = { mx = mx, my = my, x = vue.x, y = vue.y }
  end)
  zone:SetScript("OnMouseUp", function() drag = nil end)
  zone:SetScript("OnUpdate", function()
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then drag = nil return end
    local mx, my = curseur()
    local s = vue.fit * vue.zoom
    vue.x, vue.y = drag.x + (mx - drag.mx) / s, drag.y - (my - drag.my) / s -- le dessin suit la souris
    appliquer()
  end)

  local traits, textes = {}, {}
  local nTraits, nTextes = 0, 0
  local function segment(x1, y1, x2, y2, col, thick)
    nTraits = nTraits + 1
    local l = traits[nTraits] or toile:CreateLine(nil, "BACKGROUND")
    traits[nTraits] = l
    l:SetThickness(thick)
    l:SetColorTexture(col[1], col[2], col[3], 0.45)
    l:SetStartPoint("TOPLEFT", toile, x1, -y1)
    l:SetEndPoint("TOPLEFT", toile, x2, -y2)
    l:Show()
  end
  -- Courbe en S entre deux cases (8 traits), le texte du lien juste avant la case d'arrivée.
  local function courbe(x1, y1, x2, y2, col, texte, thick)
    local px, py = x1, y1
    for i = 1, 8 do
      local t = i / 8
      local s = t * t * (3 - 2 * t)
      local x, y = x1 + (x2 - x1) * t, y1 + (y2 - y1) * s
      segment(px, py, x, y, col, thick)
      px, py = x, y
    end
    if not texte then return end -- tronçon avant un relais : le texte n'est écrit qu'à l'arrivée
    nTextes = nTextes + 1
    local f = textes[nTextes] or toile:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    textes[nTextes] = f
    f:ClearAllPoints()
    f:SetPoint("RIGHT", toile, "TOPLEFT", x2 - 3, -y2 + 6)
    f:SetText(texte)
    f:Show()
  end

  function arbre:Dessiner(g)
    local d = g.dims
    -- Les étages s'étalent sur la largeur ; trop nombreux, le dessin rétrécit pour tenir (puis molette pour zoomer).
    local avail = zone:GetWidth()
    if avail < 100 then avail = parent:GetWidth() end -- ponytail: zone pas encore mise en page ; redessiner une fois affichée
    local ecart = g.cols > 1 and math.max(d.largeur + 44, (avail - d.largeur - 2 * d.marge) / (g.cols - 1)) or 0
    local width = d.largeur + ecart * (g.cols - 1) + 2 * d.marge
    vue.fit = math.min(1, avail / width)
    toile:SetSize(width, math.max(1, (g.height + d.haut + 10)))
    appliquer()
    g.ecart = ecart
    for _, n in ipairs(g.all) do n.x = d.marge + n.col * ecart end

    local cadres = self.cadres
    for i, n in ipairs(g.nodes) do
      local c = opts.case(n, cadres[i])
      cadres[i] = c
      if c:GetParent() ~= toile then c:SetParent(toile) end
      c:SetSize(d.largeur, d.hauteur)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", toile, "TOPLEFT", n.x, -(n.y + d.haut))
      c:Show()
    end
    for i = #g.nodes + 1, #cadres do cadres[i]:Hide() end

    -- Un rectangle par bande qui a une couleur : toutes ses cases, à sa couleur ; son en-tête au-dessus.
    local nRect = 0
    for _, band in ipairs(g.bands or {}) do
      local top, bottom, left, right = math.huge, -math.huge, math.huge, -math.huge
      for _, n in ipairs(g.nodes) do
        if n.band == band.key then
          top, bottom = math.min(top, n.y), math.max(bottom, n.y + d.hauteur)
          left, right = math.min(left, n.x), math.max(right, n.x + d.largeur)
        end
      end
      if (band.color or band.title) and top < math.huge then
        nRect = nRect + 1
        local b = self.rectangles[nRect]
        if not b then
          b = CreateFrame("Frame", nil, toile, "BackdropTemplate")
          b:SetFrameLevel(toile:GetFrameLevel() + 1)
          b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
          b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          b.title:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 4, 2)
          self.rectangles[nRect] = b
        end
        local k = band.color or { 1, 0.82, 0 }
        b.band, b.color = band, band.color
        b:SetBackdropColor(k[1], k[2], k[3], band.color and 0.06 or 0)
        b:SetBackdropBorderColor(k[1], k[2], k[3], band.color and 0.7 or 0)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", toile, "TOPLEFT", left - 6, -(top + d.haut) + 6)
        b:SetSize(right - left + 12, bottom - top + 12)
        b.title:SetTextColor(k[1], k[2], k[3])
        b.title:SetText(band.title or "")
        b:Show()
      end
    end
    for i = nRect + 1, #self.rectangles do self.rectangles[i]:Hide() end

    -- Chaque courbe part et arrive à sa propre hauteur sur le bord de la case, dans l'ordre des cases d'en face :
    -- pas de croisement au départ, et les textes ne se marchent pas dessus.
    -- ponytail: au-delà de 3 courbes sur un même bord, les textes se rapprochent trop ; agrandir dims.hauteur si ça arrive
    local outs, ins, drawn = {}, {}, {}
    for _, e in ipairs(g.edges) do
      if not e.hidden then
        drawn[#drawn + 1] = e
        outs[e.from] = outs[e.from] or {}
        ins[e.to] = ins[e.to] or {}
        table.insert(outs[e.from], e)
        table.insert(ins[e.to], e)
      end
    end
    local function spread(map, field, other)
      for _, es in pairs(map) do
        table.sort(es, function(a, b)
          if a[other].y ~= b[other].y then return a[other].y < b[other].y end
          return a[other].key < b[other].key
        end)
        for i, e in ipairs(es) do e[field] = d.hauteur * i / (#es + 1) end
      end
    end
    spread(outs, "dy1", "first")
    spread(ins, "dy2", "last")
    nTraits, nTextes = 0, 0
    for _, e in ipairs(drawn) do
      local k, thick = e.color or COULEUR_LIEN, e.thick or 2
      local px, py = e.from.x + d.largeur, e.from.y + d.haut + e.dy1
      for i = 2, #e.path - 1 do -- relais : on y entre, on traverse l'étage tout droit, on en ressort
        local r = e.path[i]
        local ry = r.y + d.haut + d.relais / 2
        courbe(px, py, r.x, ry, k, nil, thick)
        segment(r.x, ry, r.x + d.largeur, ry, k, thick)
        px, py = r.x + d.largeur, ry
      end
      courbe(px, py, e.to.x, e.to.y + d.haut + e.dy2, k, e.text, thick)
    end
    for i = nTraits + 1, #traits do traits[i]:Hide() end
    for i = nTextes + 1, #textes do textes[i]:Hide() end
  end
  return arbre
end
