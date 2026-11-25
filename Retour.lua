-- Azeroth Commune : signaler un problème (/ac retour, ou le menu du bouton de minicarte). Un add-on ne peut rien
-- envoyer ni ouvrir de navigateur : le socle prépare un rapport à copier (versions de nos add-ons, client, sondes
-- rouges, erreurs de relevé, dernières erreurs Lua de nos add-ons), que le joueur colle sur la page CurseForge de
-- l'add-on (Issues → GitHub, ou un commentaire). Rien de nominatif n'est ajouté : ni nom de perso ni royaume.
local _, ns = ...
local lib = AzerothCommune

-- Erreurs Lua : le gestionnaire du jeu est chaîné (il s'affiche toujours) ; on garde les erreurs qui touchent un
-- dossier d'add-on, et le rapport ne montre que celles des nôtres (le socle et les regroupés, connus à ce moment-là).
-- Gardées dans AzerothCommuneDB.erreursLua (même table dès l'entrée en jeu) : elles passent un /reload.
-- ponytail: BugGrabber (s'il est chargé avant nous) verrouille seterrorhandler, on ne voit alors rien ; lire sa base si ça gêne.
local MAX = 30
local erreurs = {}

function ns.noterErreurLua(msg, pile)
  local texte = tostring(msg)
  if not (texte .. (pile or "")):find("AddOns[/\\]") then return end
  for _, e in ipairs(erreurs) do
    if e.msg == texte then e.n, e.heure = e.n + 1, date("%d/%m %H:%M") return end
  end
  erreurs[#erreurs + 1] = { msg = texte, pile = pile, n = 1, heure = date("%d/%m %H:%M") }
  if #erreurs > MAX then table.remove(erreurs, 1) end
end

if seterrorhandler and geterrorhandler then
  local avant = geterrorhandler()
  seterrorhandler(function(msg, ...)
    pcall(ns.noterErreurLua, msg, debugstack and debugstack(3, 12, 0))
    if avant then return avant(msg, ...) end
  end)
end

local cadre = CreateFrame("Frame")
cadre:RegisterEvent("PLAYER_LOGIN")
cadre:SetScript("OnEvent", function()
  local gardees = AzerothCommuneDB.erreursLua or {}
  for _, e in ipairs(erreurs) do gardees[#gardees + 1] = e end
  while #gardees > MAX do table.remove(gardees, 1) end
  erreurs = gardees
  AzerothCommuneDB.erreursLua = gardees
end)

local function nos_dossiers()
  local d = { "AzerothCommune" }
  for _, r in ipairs(lib.regroupes) do d[#d + 1] = r.dossier or r.nom end
  return d
end

-- La ligne de l'erreur qui nomme l'un de nos dossiers (le message, sinon la première de la pile), ou nil.
local function chez_nous(e, dossiers)
  for _, d in ipairs(dossiers) do
    local motif = "AddOns[/\\]" .. d:gsub("%p", "%%%0") .. "[/\\]"
    if e.msg:find(motif) then return e.msg end
    for ligne in (e.pile or ""):gmatch("[^\n]+") do
      if ligne:find(motif) then return e.msg .. "\n    (depuis " .. ligne:gsub("^%s+", "") .. ")" end
    end
  end
end

local function montrer(v)
  if type(v) ~= "table" then return tostring(v) end
  local t = {}
  for i = 1, v.n or #v do t[i] = tostring(v[i]) end
  return table.concat(t, ", ")
end

-- Sondes dont la valeur reçue dirait qui joue : le rapport finit en public (GitHub, CurseForge).
local NOMINATIVES = { nom = true, GUID = true }

function ns.rapportRetour()
  local l = {}
  local function dire(s) l[#l + 1] = s end
  local version, build = GetBuildInfo()
  local _, classe = UnitClass("player")
  dire(("Azeroth Commune — rapport du %s"):format(date("%d/%m/%Y %H:%M")))
  dire(("Client %s (%s), %s ; perso niveau %s %s"):format(tostring(version), tostring(build), GetLocale(),
    tostring(UnitLevel("player")), tostring(classe)))
  local dossiers = nos_dossiers()
  local v = {}
  for _, d in ipairs(dossiers) do v[#v + 1] = d .. " " .. tostring(C_AddOns.GetAddOnMetadata(d, "Version")) end
  dire("Add-ons : " .. table.concat(v, ", "))

  local rouges = {}
  for _, s in ipairs(lib.Sondes()) do
    if s.etat == "rouge" then
      local recu = NOMINATIVES[s.nom] and "(masqué)" or montrer(s.valeur)
      rouges[#rouges + 1] = ("  %s : reçu %s"):format(s.nom, recu) -- l'attente est dans le code (DeclarerSonde)
    end
  end
  dire("Sondes rouges : " .. (#rouges == 0 and "aucune" or ""))
  for _, r in ipairs(rouges) do dire(r) end

  local releves = {}
  for _, t in ipairs({ AzerothCommuneDB and AzerothCommuneDB.errors or {}, AzerothCommuneDB and ns.char().errors or {} }) do
    for nom, err in pairs(t) do releves[#releves + 1] = ("  %s : %s"):format(nom, tostring(err)) end
  end
  table.sort(releves)
  dire("Erreurs de relevé : " .. (#releves == 0 and "aucune" or ""))
  for _, r in ipairs(releves) do dire(r) end

  local lua = {}
  for i = #erreurs, 1, -1 do -- les plus récentes d'abord
    local ligne = chez_nous(erreurs[i], dossiers)
    if ligne and #lua < 10 then lua[#lua + 1] = ("  [%s, %d×] %s"):format(erreurs[i].heure, erreurs[i].n, ligne) end
  end
  dire("Erreurs Lua : " .. (#lua == 0 and "aucune" or ""))
  for _, r in ipairs(lua) do dire(r) end
  return table.concat(l, "\n")
end

-- La fenêtre : une seule chose à y faire, copier le rapport. Le texte est sélectionné à l'ouverture ; une frappe le
-- remet tel quel (lecture seule) ; Échap ferme.
local fenetre, zone, texte

local function construire()
  fenetre = lib.Fenetre("AzerothCommuneRetour", "Signaler un problème", 460, 300)
  local aide = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  aide:SetPoint("TOPLEFT", 16, -36)
  aide:SetPoint("RIGHT", -16, 0)
  aide:SetJustifyH("LEFT")
  aide:SetText("Copie ce rapport (Ctrl+C) et colle-le sur la page CurseForge de l'add-on («\194\160Issues\194\160» ou un commentaire), "
    .. "avec ce qui s'est passé.")
  local defile = CreateFrame("ScrollFrame", nil, fenetre, "UIPanelScrollFrameTemplate")
  defile:SetPoint("TOPLEFT", aide, "BOTTOMLEFT", 0, -8)
  defile:SetPoint("BOTTOMRIGHT", -34, 26)
  zone = CreateFrame("EditBox", "AzerothCommuneRetourTexte", defile)
  zone:SetMultiLine(true)
  zone:SetAutoFocus(false)
  zone:SetFontObject(ChatFontNormal)
  zone:SetJustifyH("LEFT")
  zone:SetWidth(400)
  zone:SetHeight(200)
  defile:HookScript("OnSizeChanged", function() zone:SetWidth(defile:GetWidth()) end)
  defile:SetScript("OnMouseDown", function() zone:SetFocus() zone:HighlightText() end)
  defile:SetScrollChild(zone)
  zone:SetScript("OnTextChanged", function(self, parJoueur)
    if parJoueur then self:SetText(texte) self:HighlightText() end
  end)
  zone:SetScript("OnEscapePressed", function() fenetre:Hide() end)
end

function ns.ouvrirRetour()
  if not fenetre then construire() end
  lib.RelancerSondes()
  texte = ns.rapportRetour()
  fenetre:Show()
  zone:SetText(texte)
  zone:SetFocus()
  zone:HighlightText()
end
