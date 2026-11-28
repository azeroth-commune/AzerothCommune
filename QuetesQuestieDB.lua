-- Azeroth Commune : la base des quêtes en direct depuis QuestieDB (#111, PRD #109), un fournisseur de la base des quêtes.
-- QuestieDB (GPL-3.0, https://github.com/Questie/QuestieDB) est lu par son API publique seulement (globale LibQuestieDB,
-- contrat 4 : Quest/Npc/Object/Item.Get, GetAllIds, Exists, Enum ; Support.Get("ZoneDB"), documenté dans son
-- src/support/data.lua) ; dépendance optionnelle du socle (## OptionalDeps: QuestieDB : chargé avant lui s'il est là).
-- Deux blocs, jamais mélangés par quête ni par champ (Souscriptions.lua, « Base des quêtes ») : QuestieDB présent, contrat 4
-- accepté et faction du perso connue → ce bloc ; sinon la réserve QuetesReserve.lua. QuestieDB absent : la réserve, sans
-- message ; QuestieDB incompatible (contrat refusé) ou qui plante à la lecture : la réserve, et la sonde « QuestieDB »
-- prévient une fois par session. La base est construite d'un coup, à la première lecture (une souscription : rien sans),
-- et gardée pour la session (#110 : ~110 ms en jeu, ~160 ms à froid).
-- Lot : { provenance = « autre add-on », source = « QuestieDB », version = sa version (sa TOC) } ; un autre add-on ne dit
-- ni build ni date (Fournisseurs.lua).
-- Même forme et même sémantique que la réserve (en-tête de QuetesReserve.lua ; prototype : research/questiedb/ de
-- l'atelier, identique au Python sur 4237 quêtes de QuestieDB 1.1.6 sauf 2 corrections de faction, où il a raison),
-- avec ces différences de nature :
--   - les noms sont ceux de la langue du client (QuestieDB traduit seul selon GetLocale), l'anglais à défaut ;
--   - la base est celle de la faction du perso connecté : QuestieDB applique à son chargement ses corrections de faction
--     (zone, donneurs…) selon UnitFactionGroup("player"), toutes, pas seulement les zones de l'Alliance ; les races filtrent
--     les quêtes, friendlyToFaction le donneur ;
--   - un bit de race ou de classe inconnu est ignoré (le Python échoue).
-- Lua 5.1, ni bit.band : les masques de races vont jusqu'au bit 2^33 (Skyborne).
local _, ns = ...
local lib = AzerothCommune

local CONTRAT = 4 -- la version du contrat de QuestieDB contre laquelle ce fichier est écrit

-- La sonde n'a de contexte qu'une lecture de la base avec QuestieDB présent : « pas encore vue » sans lui.
lib.DeclarerSonde("QuestieDB", "LibQuestieDB.RequireContract(" .. CONTRAT .. ") accepte le contrat et sa base se lit sans erreur",
  function(ok) return ok == true end)

-- { [questID] = { nom, zone, niveau, niveau_requis, races, classes, prerequis, prerequis_un, suites, amorces, objet,
--   origine = { nom, pnjs, objets }, donneur = { pnj | objet, nom, carte, x, y } } } pour faction ("Alliance", "Horde").
local function construireBase(libQ, faction)
  local Q, N, O, I = libQ.Quest, libQ.Npc, libQ.Object, libQ.Item
  local lettre = faction:sub(1, 1) -- friendlyToFaction : "A", "H", "AH"

  local function a(masque, b) return masque % (b * 2) >= b end -- le bit b (puissance de 2) est-il dans masque ?
  local function arrondi(v) return math.floor(v * 100 + 0.5) / 100 end
  local function ouNil(t) if t and #t > 0 then return t end end
  local function nonNul(v) if v ~= 0 then return v end end -- QuestieDB rend 0 pour un nombre absent

  -- Races : raceID -> bit (Enum.raceMaskById) ; celles de la faction, d'après factionRaceMasks.
  local bitsRaces, racesFaction = {}, {}
  for race, b in pairs(libQ.Enum.raceMaskById) do
    bitsRaces[#bitsRaces + 1] = { race, b }
    if a(libQ.Enum.factionRaceMasks[faction], b) then racesFaction[race] = true end
  end
  table.sort(bitsRaces, function(x, y) return x[1] < y[1] end)
  local function races(masque) -- liste triée des raceID, nil : toutes
    if masque == 0 then return nil end
    local l = {}
    for _, rb in ipairs(bitsRaces) do if a(masque, rb[2]) then l[#l + 1] = rb[1] end end
    return l
  end
  local function classes(masque) -- classID c au bit 2^(c-1) (classKeys Classic, que Forever reprend)
    if masque == 0 then return nil end
    local l = {}
    for c = 1, 32 do if a(masque, 2 ^ (c - 1)) then l[#l + 1] = c end end
    return l
  end
  local function pourFaction(rs)
    if not rs then return true end
    for _, r in ipairs(rs) do if racesFaction[r] then return true end end
    return false
  end

  -- Cartes : areaID -> uiMapID, la table de QuestieDB (du texte « return {…} ») ; ses exceptions l'emportent, 0 (masquée) :
  -- absente.
  local cartes = {}
  -- Sans ZoneDB, une erreur (la réserve, et la sonde le dit) plutôt qu'une base sans cartes.
  local zdb = libQ.Support and libQ.Support.Get("ZoneDB")
  assert(type(zdb) == "table" and type(zdb.private) == "table", "ZoneDB introuvable (Support.Get)")
  for _, src in ipairs({ zdb.private.areaIdToUiMapId, zdb.private.areaIdToUiMapIdOverride }) do
    local t = src
    if type(src) == "string" then t = loadstring(src)() end
    for aire, carte in pairs(type(t) == "table" and t or {}) do cartes[aire] = carte end
  end
  for aire, carte in pairs(cartes) do if carte == 0 then cartes[aire] = nil end end

  -- carte, x, y : la première apparition dans la zone de la quête, sinon dans la plus petite zone listée ; x, y nil
  -- hors carte (-1 : instance). nil sans apparition.
  -- ponytail: « la plus petite zone » remplace « la première listée » du Python (ordre CBOR, perdu par pairs) ; 0 donneur
  -- différent sur QuestieDB 1.1.6 (#110).
  local function position(apparitions, zone)
    if type(apparitions) ~= "table" then return nil end
    local z = apparitions[zone] and zone
    if not z then for k in pairs(apparitions) do if not z or k < z then z = k end end end
    if not z then return nil end
    local c = (apparitions[z] or {})[1]
    if not c or c[1] < 0 then return cartes[z] end
    return cartes[z], arrondi(c[1]), arrondi(c[2])
  end

  -- Le premier donneur : un PNJ amical pour la faction, sinon un objet du monde.
  local function donneur(startedBy, zone)
    for _, n in ipairs(startedBy[1] or {}) do
      local f = N.Exists(n) and (N.Get(n, "friendlyToFaction") or "")
      if f and (f == "" or f:find(lettre, 1, true)) then
        local carte, x, y = position(N.Get(n, "spawns"), zone)
        return { pnj = n, nom = N.Get(n, "name"), carte = carte, x = x, y = y }
      end
    end
    for _, o in ipairs(startedBy[2] or {}) do
      if O.Exists(o) then
        local carte, x, y = position(O.Get(o, "spawns"), zone)
        return { objet = o, nom = O.Get(o, "name"), carte = carte, x = x, y = y }
      end
    end
  end

  local MAX_ORIGINE = 3 -- noms par origine : « lâché par les kobolds », pas la liste entière
  local function premiers(ids, ent)
    local l, vus = {}, {}
    for _, i in ipairs(ids or {}) do
      local nom = ent.Get(i, "name")
      if nom and not vus[nom] then vus[nom] = true; l[#l + 1] = nom end
      if #l == MAX_ORIGINE then break end
    end
    return ouNil(l)
  end
  local function origine(item)
    if not I.Exists(item) then return nil end
    return { nom = I.Get(item, "name"), pnjs = premiers(I.Get(item, "npcDrops"), N),
             objets = premiers(I.Get(item, "objectDrops"), O) }
  end

  -- 1er passage : les quêtes de la faction, leurs champs propres ; suites et amorces inversées au passage.
  local base, brut, suites, amorces = {}, {}, {}, {}
  local function ajoute(t, cle, v) t[cle] = t[cle] or {}; t[cle][v] = true end
  for _, id in ipairs(Q.GetAllIds()) do
    local rs = races(Q.Get(id, "requiredRaces") or 0)
    if pourFaction(rs) then
      local pg, ps = ouNil(Q.Get(id, "preQuestGroup")), ouNil(Q.Get(id, "preQuestSingle"))
      base[id] = { nom = Q.Get(id, "name"), zone = nonNul(Q.Get(id, "zoneOrSort")), niveau = nonNul(Q.Get(id, "questLevel")),
        niveau_requis = nonNul(Q.Get(id, "requiredLevel")), races = rs, classes = classes(Q.Get(id, "requiredClasses") or 0),
        prerequis = pg, prerequis_un = ps }
      brut[id] = Q.Get(id, "startedBy") or {}
      for _, l in ipairs({ pg or {}, ps or {} }) do for _, p in ipairs(l) do ajoute(suites, p, id) end end
      local suite = nonNul(Q.Get(id, "nextQuestInChain") or 0)
      if suite then ajoute(suites, id, suite) end
      for _, b in ipairs(Q.Get(id, "breadcrumbs") or {}) do ajoute(amorces, id, b) end
      local pour = nonNul(Q.Get(id, "breadcrumbForQuestId") or 0)
      if pour then ajoute(amorces, pour, id) end
    end
  end

  -- 2e passage : suites et amorces gardées dans la base, donneur, objet de départ et son origine.
  local function liste(ensemble)
    local l = {}
    for i in pairs(ensemble or {}) do if base[i] then l[#l + 1] = i end end
    table.sort(l)
    return ouNil(l)
  end
  for id, q in pairs(base) do
    q.suites, q.amorces = liste(suites[id]), liste(amorces[id])
    q.donneur = donneur(brut[id], q.zone)
    q.objet = (brut[id][3] or {})[1]
    q.origine = q.objet and origine(q.objet) or nil
  end
  return base
end

-- La base en direct et une copie de son lot, ou nil : la réserve. Choisie à la première lecture pour la LibQuestieDB
-- présente (en jeu : une fois par session ; une autre LibQuestieDB, celle d'un test, refait le choix). Faction encore
-- inconnue : la réserve pour cette lecture, le choix est retenté à la suivante (la sonde « faction » prévient).
local vue, base, lot = {}, nil, nil -- vue : la LibQuestieDB du dernier choix ({} : aucun encore)
function ns.quetesQuestieDB()
  local q = LibQuestieDB
  local faction = lib.Faction()
  if q ~= vue and not (type(q) == "table" and not faction) then
    vue, base, lot = q, nil, nil
    if type(q) == "table" then -- absent : la réserve, sans message
      local ok, accepte, raison = false, nil, "LibQuestieDB sans RequireContract" -- trop ancien : incompatible
      if type(q.RequireContract) == "function" then
        ok, accepte, raison = pcall(q.RequireContract, CONTRAT) -- refusé : false et son message
        if not ok then raison = accepte end
        ok = ok and accepte == true
      end
      local construite
      if ok then
        ok, construite = pcall(construireBase, q, faction)
        if not ok then raison = construite end
      end
      lib.Sonder("QuestieDB", ok, not ok and raison or nil)
      if ok then
        local meta = C_AddOns and C_AddOns.GetAddOnMetadata
        base, lot = construite, { provenance = "autre add-on", source = "QuestieDB",
          version = meta and meta(q.addonName or "QuestieDB", "Version") }
      end
    end
  end
  if not base then return nil end
  local copie = {}
  for f, v in pairs(lot) do copie[f] = v end
  return base, copie
end
