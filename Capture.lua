-- LibCommune : capture d'une fenêtre et export de données par image, sans /reload. Relus hors du jeu par
-- tools/crop_captures.py (atelier). Appel avec un point, comme Interface.lua.
--   lib.Capturer(cadre, libellé, fini, discret)   photo de l'écran, repères magenta autour du cadre
--   lib.BoutonCapture(cadre, libellé, x, y)        petit bouton loupe qui fait cette photo
--   lib.Exporter(valeur, "nom")                    une table Lua photographiée en grilles de couleurs
--
-- Export : la valeur est mise en JSON puis compressée (fonctions natives C_EncodingUtil), découpée en pages, et chaque
-- page est dessinée en grille de 96 × 96 cases de 8 couleurs (3 bits par case) au centre de l'écran, puis photographiée.
-- Environ 3,3 Ko compressés par page ; les pages s'enchaînent toutes seules.
-- Grille : ligne 0 et colonne 0 en damier noir/blanc (repères), dernière colonne noire (marge), dernière ligne =
-- palette (case c = couleur c % 8) : le décodeur y apprend comment la photo rend chaque couleur (le HDR les délave et
-- les mélange : magenta pur -> (143, 91, 152) le 18/11/2026) et classe chaque case par la couleur la plus proche.
-- Données dans les 94 × 94 cases restantes, ligne par ligne. Couleur d'une case : rouge, vert, bleu = ses 3 bits.
-- Chaque page commence par un en-tête de 16 octets : « BGP1 », n° d'export (4), page (2), pages (2),
-- longueur (2), somme de contrôle (2) - tout en gros-boutiste.
-- Aucun cadre n'est créé au chargement : le fichier se charge aussi hors du jeu (LibStub.lua puis ce fichier), pour
-- PagesExport et GrilleExport.
local lib = LibStub("LibCommune-1.0", true) or LibStub:NewLibrary("LibCommune-1.0", 0) -- chargé seul : outils, tests
local VERSION = 2
lib.versions = lib.versions or {}
if (lib.versions.capture or 0) >= VERSION then return end
lib.versions.capture = VERSION

local floor = math.floor
local function dire(msg) print("Azeroth Commune : " .. msg) end

---------------------------------------------------------------------------------------------------
-- Capture d'une fenêtre. Le jeu ne sait photographier que tout l'écran (Screenshot(), comme Impr. écran) : pendant la
-- photo, deux carrés magenta s'affichent juste à l'extérieur des coins haut-gauche et bas-droite de la fenêtre ;
-- tools/crop_captures.py les repère sur l'image (_forever_/Screenshots) et découpe entre les deux.
-- Le temps de la photo, le format passe en PNG (couleurs exactes, texte net), puis revient.
local shot
local function cadrePhoto()
  if shot then return shot end
  shot = CreateFrame("Frame", nil, UIParent)
  shot:SetFrameStrata("TOOLTIP")
  shot:SetAllPoints()
  shot:Hide()
  shot.tl, shot.br = shot:CreateTexture(nil, "OVERLAY"), shot:CreateTexture(nil, "OVERLAY")
  for _, t in ipairs({ shot.tl, shot.br }) do t:SetColorTexture(1, 0, 1, 1); t:SetSize(10, 10) end
  shot:RegisterEvent("SCREENSHOT_SUCCEEDED")
  shot:RegisterEvent("SCREENSHOT_FAILED")
  shot:SetScript("OnEvent", function(self, event)
    self:Hide()
    self.token = (self.token or 0) + 1 -- la réponse est arrivée : le délai de 10 s ne sert plus
    local onDone, quiet = self.onDone, self.quiet
    self.onDone, self.quiet = nil, nil
    if self.format then C_CVar.SetCVar("screenshotFormat", self.format); self.format = nil end
    if event == "SCREENSHOT_SUCCEEDED" and self.label and not quiet then dire("capture de « " .. self.label .. " » prise.") end
    self.label = nil
    if onDone then onDone(event == "SCREENSHOT_SUCCEEDED") end -- la suite (page suivante d'un export…)
  end)
  return shot
end

-- onDone(ok) : appelé une fois la photo écrite ; quiet : pas de message dans le chat.
function lib.Capturer(frame, label, onDone, quiet)
  if not frame:GetRect() then return end
  local s = cadrePhoto()
  s.label, s.onDone, s.quiet = label or frame:GetName() or "fenêtre", onDone, quiet
  s.tl:ClearAllPoints(); s.tl:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT")
  s.br:ClearAllPoints(); s.br:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT")
  s:Show()
  s.format = s.format or C_CVar.GetCVar("screenshotFormat")
  C_CVar.SetCVar("screenshotFormat", "png")
  s.token = (s.token or 0) + 1
  local mine = s.token
  C_Timer.After(0, function() -- une image plus tard : les repères sont dessinés
    local ok, err = pcall(Screenshot)
    if not ok then dire("Screenshot() a échoué : " .. tostring(err)) end
  end)
  C_Timer.After(10, function() -- pas de réponse du jeu : on n'attend pas indéfiniment (une page 4K de grille peut dépasser 3 s)
    if s.token == mine and s:IsShown() then
      dire("capture sans réponse du jeu au bout de 10 s (SCREENSHOT_SUCCEEDED jamais reçu).")
      s:GetScript("OnEvent")(s, "SCREENSHOT_FAILED")
    end
  end)
end

-- Petit bouton « capture » en haut à droite d'une fenêtre (à gauche de sa croix, s'il y en a une).
function lib.BoutonCapture(frame, label, x, y)
  local b = CreateFrame("Button", nil, frame)
  b:SetSize(16, 16)
  b:SetPoint("TOPRIGHT", x or -30, y or -8)
  b:SetNormalTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
  b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnClick", function() lib.Capturer(frame, label) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Capture de cette fenêtre")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

---------------------------------------------------------------------------------------------------
-- Export par image.
-- 96 × 96 et pas 128 × 128 : 16 384 textures (65 536 sommets, 2^16) faisaient disparaître toute l'interface au
-- moment de la photo (18/11/2026). Les cases voisines de même couleur sont en plus fusionnées en une texture.
local N, CELL, HEADER, BAND = 96, 5, 16, 24
local PAGE_BYTES = floor((N - 2) * (N - 2) * 3 / 8) - HEADER
local MAX_PAGES = 100
lib.EXPORT_N, lib.EXPORT_PAGE_BYTES = N, PAGE_BYTES

local function u16(n) return string.char(floor(n / 256) % 256, n % 256) end
local function u32(n) return u16(floor(n / 65536) % 65536) .. u16(n % 65536) end
local function checksum(s)
  local sum = 0
  for i = 1, #s do sum = (sum + s:byte(i)) % 65536 end
  return sum
end

-- Les pages d'un export : en-tête + morceau de la donnée compressée.
function lib.PagesExport(data, id)
  local pages = {}
  local count = math.max(1, math.ceil(#data / PAGE_BYTES))
  for i = 1, count do
    local chunk = data:sub((i - 1) * PAGE_BYTES + 1, i * PAGE_BYTES)
    pages[i] = "BGP1" .. u32(id) .. u16(i) .. u16(count) .. u16(#chunk) .. u16(checksum(chunk)) .. chunk
  end
  return pages
end

-- Valeur (0-7) de chaque case de la grille pour une page, ligne par ligne : grid[r * N + c + 1].
function lib.GrilleExport(bytes)
  local syms, acc, n = {}, 0, 0
  for i = 1, #bytes do
    acc, n = acc * 256 + bytes:byte(i), n + 8
    while n >= 3 do
      n = n - 3
      local d = 2 ^ n
      syms[#syms + 1] = floor(acc / d)
      acc = acc % d
    end
  end
  if n > 0 then syms[#syms + 1] = acc * 2 ^ (3 - n) end
  local grid, k = {}, 0
  for r = 0, N - 1 do
    for c = 0, N - 1 do
      local v
      if r == 0 then v = (c % 2 == 0) and 0 or 7
      elseif c == 0 then v = (r % 2 == 0) and 0 or 7
      elseif r == N - 1 and c < N - 1 then v = c % 8 -- palette : les 8 couleurs telles que la photo les rend
      elseif r == N - 1 or c == N - 1 then v = 0
      else k = k + 1; v = syms[k] or 0 end
      grid[r * N + c + 1] = v
    end
  end
  return grid
end

local frame, bands, pools

-- 4 sous-cadres de 24 lignes ; dans chaque ligne, une texture par suite de cases de même couleur.
local function build()
  frame = CreateFrame("Frame", "LibCommuneExportCode", UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetSize(N * CELL, N * CELL)
  bands, pools = {}, {}
  for i = 0, N / BAND - 1 do
    local band = CreateFrame("Frame", nil, frame)
    band:SetPoint("TOPLEFT", 0, -i * BAND * CELL)
    band:SetSize(N * CELL, BAND * CELL)
    bands[i] = band
  end
  for r = 0, N - 1 do pools[r] = {} end
  frame:Hide()
end

-- Une unité de la grille = un pixel de l'écran (à l'échelle 1, l'écran fait 768 unités de haut), posée sur des
-- pixels entiers : chaque case fait exactement CELL pixels.
local function place()
  local pw, ph = GetPhysicalScreenSize()
  frame:SetScale(768 / ph / UIParent:GetEffectiveScale())
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", floor((pw - N * CELL) / 2), -floor((ph - N * CELL) / 2))
end

local function paint(bytes)
  local grid = lib.GrilleExport(bytes)
  for r = 0, N - 1 do
    local pool, used, c = pools[r], 0, 0
    while c < N do
      local v, run = grid[r * N + c + 1], 1
      while c + run < N and grid[r * N + c + run + 1] == v do run = run + 1 end
      used = used + 1
      local t = pool[used]
      if not t then
        t = bands[floor(r / BAND)]:CreateTexture(nil, "ARTWORK")
        pool[used] = t
      end
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", c * CELL, -(r % BAND) * CELL)
      t:SetSize(run * CELL, CELL)
      t:SetColorTexture(floor(v / 4) % 2, floor(v / 2) % 2, v % 2, 1)
      t:Show()
      c = c + run
    end
    for i = used + 1, #pool do pool[i]:Hide() end
  end
end

-- C_EncodingUtil.SerializeJSON jette les tables à clés numériques non consécutives (recettes par ID de sort,
-- équipement par emplacement 0-19 : reçues vides le 18/11/2026). On les recopie avec des clés en texte ;
-- les vraies listes (1, 2, 3…) restent des listes.
local function jsonSafe(v, seen)
  if type(v) ~= "table" then return v end
  if seen[v] then return nil end -- boucle : coupée
  seen[v] = true
  local n, count = #v, 0
  for _ in pairs(v) do count = count + 1 end
  local out = {}
  if count == n then
    for i = 1, n do out[i] = jsonSafe(v[i], seen) end
  else
    for k, x in pairs(v) do out[tostring(k)] = jsonSafe(x, seen) end
  end
  seen[v] = nil
  return out
end
function lib.JsonSur(v) return jsonSafe(v, {}) end

local busy = false
function lib.Exporter(value, label)
  if busy then return dire("un export est déjà en cours.") end
  if InCombatLockdown() then return dire("pas d'export en combat.") end
  label = label or "export"
  local json = C_EncodingUtil.SerializeJSON({ label = label, time = date("%Y-%m-%d %H:%M:%S"), data = jsonSafe(value, {}) },
    { ignoreSerializationErrors = true })
  local z = C_EncodingUtil.CompressString(json, Enum.CompressionMethod.Zlib, Enum.CompressionLevel.OptimizeForSize)
  local pages = lib.PagesExport(z, time() % 4294967296)
  if #pages > MAX_PAGES then
    return dire(("« %s » ferait %d pages (max %d), trop gros."):format(label, #pages, MAX_PAGES))
  end
  if not frame then build() end
  place()
  frame:Show()
  busy = true
  local function shoot(i, ok)
    if i > #pages or ok == false then
      frame:Hide()
      busy = false
      return dire(("export « %s » %s (%d page%s, %d Ko de JSON)."):format(label,
        ok == false and "interrompu" or "photographié", #pages, #pages > 1 and "s" or "", floor(#json / 1024)))
    end
    paint(pages[i])
    lib.Capturer(frame, label, function(success) shoot(i + 1, success) end, true)
  end
  shoot(1)
end
