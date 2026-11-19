-- LibCommune : fournisseurs (GameData#6). Un fournisseur tient un type de données relevées pour le joueur : l'API
-- publique d'un autre add-on d'abord, à défaut ses SavedVariables (fragile, si sa licence le permet), en dernier notre
-- propre relevé (GameData). Quand un fournisseur est là, GameData n'en garde pas de copie : il ne relève que les champs
-- qu'aucun fournisseur présent ne donne (lib:ChampsARelever). Sans GameData, la lib passe directement par un fournisseur ;
-- sans GameData ni fournisseur, le type est indisponible, jamais relevé en repli (type lourd).
--
-- Cours de l'HV, ligne d'un objet de ton HV (royaume-faction du personnage connecté). Pour chaque champ, le premier de la
-- liste qui est présent et qui a l'objet :
--   min      prix unitaire le plus bas : Auctionator (API v1) > TSM (TSM_API) > AuctionDB (SavedVariables) > GameData
--   qty      quantité en vente        : AuctionDB > GameData
--   auctions nombre d'annonces        : GameData
--   tiers    paliers { {price, qty} } : GameData
--   hist     historique { {heure, min, qté}, … } : AuctionDB (ses scans des derniers jours) > GameData (12 derniers scans)
--   age      jours depuis qu'Auctionator a vu l'objet (Auctionator seul)
-- Fraîcheur : un « dernier vu » ne vaut que s'il vient du dernier scan ; sinon l'objet est plus en vente (min nil, qty 0
-- pour AuctionDB), l'historique reste. Auctionator : âge 0 (vu le jour de son dernier scan). AuctionDB : point du dernier
-- scan de la maison (ou plus récent : points de persos de confiance).
-- Présence ≠ données : un fournisseur ne compte pour un champ (lib:ChampsARelever) que s'il a des données pour ton HV :
-- Auctionator et TSM, un prix frais pour un des objets du scan en cours (sondes) ; AuctionDB, un scan de moins de 6 h.
-- À la lecture, un champ que GameData a relevé à son dernier scan (aucun fournisseur n'en avait alors) vient de lui.
-- Fournisseurs lus (rien de leur code n'est repris) : Auctionator (« All Rights Reserved ») et TSM par leur API publique
-- seulement ; AuctionDB (GPL v3 dans son LICENSE, LGPLv3 dans son TOC) n'a pas d'API publique : ses SavedVariables, au
-- format décrit dans son History.lua.
local lib = LibStub("LibCommune-1.0", true) or LibStub:NewLibrary("LibCommune-1.0", 0) -- chargé seul : outils, tests
local VERSION = 1
lib.versions = lib.versions or {}
if (lib.versions.fournisseurs or 0) >= VERSION then return end
lib.versions.fournisseurs = VERSION

local HV = "cours de l'HV"
local CHAMPS = { [HV] = { "min", "qty", "auctions", "tiers", "hist" } }
local APPELANT = "LibCommune" -- l'API d'Auctionator demande le nom de l'add-on qui l'appelle

local AUCTIONDB_RECENT = 6 * 3600 -- un scan d'AuctionDB plus vieux : il n'a plus de données pour ton HV

local function maison() -- même clé que GameDataMarket ; nil si la faction est inconnue
  local faction = UnitFactionGroup("player")
  return faction and (GetRealmName() .. "-" .. faction)
end

-- AuctionDB v2.8.1 : AuctionDBForeverSaved.houses["<région-règles> <Faction>"] = { items = { [itemID] = "heure,min,médiane,
-- qté heure,…" (du plus ancien au plus récent ; min 0 : seulement des enchères sans achat immédiat) }, scans = { {heure, …} } }.
-- Sa maison de la faction du personnage, la plus récemment scannée (la clé dit la région, pas le royaume), et l'heure de
-- ce dernier scan.
local function maisonAuctionDB()
  local sv, faction = AuctionDBForeverSaved, UnitFactionGroup("player")
  if type(sv) ~= "table" or type(sv.houses) ~= "table" or not faction then return nil end
  faction = " " .. faction
  local meilleure, quand = nil, -1
  for nom, h in pairs(sv.houses) do
    if type(nom) == "string" and nom:sub(-#faction) == faction and type(h) == "table" and type(h.items) == "table" then
      local t = 0
      for _, scan in ipairs(type(h.scans) == "table" and h.scans or {}) do
        t = math.max(t, type(scan) == "table" and tonumber(scan[1]) or 0)
      end
      if t > quand then meilleure, quand = h, t end
    end
  end
  return meilleure, quand
end

-- Sonde de présence ≠ données : le fournisseur rend un prix pour un des objets du scan en cours.
local function unPrix(lire, sondes)
  for _, id in ipairs(sondes or {}) do
    local ok, r = pcall(lire, id)
    if ok and type(r) == "table" and r.min then return true end
  end
  return false
end

-- Chaque fournisseur : lecteur() rend une fonction (itemID) -> { champ = valeur } s'il est présent, sinon nil ;
-- donnees(lire, sondes) : il a des données pour ton HV (sondes : quelques objets du scan en cours).
lib.fournisseurs = {
  [HV] = {
    { nom = "Auctionator", provenance = "autre add-on", champs = { "min", "age" }, donnees = unPrix,
      lecteur = function()
        local api = Auctionator and Auctionator.API and Auctionator.API.v1
        if not (api and api.GetAuctionPriceByItemID and api.GetAuctionAgeByItemID) then return nil end
        return function(id)
          local p = api.GetAuctionPriceByItemID(APPELANT, id)
          if not p then return nil end
          local age = api.GetAuctionAgeByItemID(APPELANT, id) -- jours ; nil au-delà de 21
          return { min = age == 0 and p or nil, age = age } -- pas vu à son dernier scan : plus en vente
        end
      end },
    -- ponytail: TSM n'est pas installé ici, écrit d'après son API publique documentée, jamais essayé en jeu.
    { nom = "TSM", provenance = "autre add-on", champs = { "min" }, donnees = unPrix,
      lecteur = function()
        if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
        return function(id)
          local p = TSM_API.GetCustomPriceValue("dbminbuyout", "i:" .. id)
          return p and { min = p }
        end
      end },
    { nom = "AuctionDB", provenance = "autre add-on", fragile = true, champs = { "min", "qty", "hist" },
      donnees = function() local _, quand = maisonAuctionDB() return quand ~= nil and time() - quand < AUCTIONDB_RECENT end,
      lecteur = function()
        local h, quand = maisonAuctionDB()
        if not h then return nil end
        return function(id)
          local s = h.items[id]
          if type(s) ~= "string" then return nil end
          local hist = {}
          for t, min, med, qty in s:gmatch("(%d+),(%d+),(%d+),(%d+)") do
            min = tonumber(min)
            hist[#hist + 1] = { tonumber(t), min > 0 and min or nil, tonumber(qty), tonumber(med) }
          end
          local der = hist[#hist]
          if not der then return nil end
          if der[1] < quand then return { min = nil, qty = 0, hist = hist } end -- plus à l'HV à son dernier scan
          return { min = der[2], qty = der[3], hist = hist }
        end
      end },
  },
}

-- Le relevé de GameData (GameDataAPI.coursHV : { hv = GameDataMarket, depot }), en lecteur du même genre, et les champs
-- qu'il a relevés à son dernier scan (releves ; nil : un relevé d'avant les fournisseurs, tous).
local function lecteurGameData(d)
  local h = maison()
  local m = h and d and d.hv and d.hv[h]
  if not m then return nil end
  return function(id)
    local it, h = m.items and m.items[id], m.hist and m.hist[id]
    if not (it or h) then return nil end
    local r = { hist = h }
    for k, v in pairs(it or {}) do r[k] = v end
    return r
  end, m.releves
end
local function tous(typeDeDonnees)
  local t = {}
  for _, c in ipairs(CHAMPS[typeDeDonnees]) do t[c] = true end
  return t
end

local function presents(typeDeDonnees)
  local out = {}
  for _, f in ipairs(lib.fournisseurs[typeDeDonnees] or {}) do
    local ok, lire = pcall(f.lecteur)
    if ok and lire then
      out[#out + 1] = { nom = f.nom, provenance = f.provenance, fragile = f.fragile, champs = f.champs, donnees = f.donnees, lire = lire }
    end
  end
  return out
end

-- Les champs que GameData doit relever lui-même : { champ = true } pour ceux qu'aucun fournisseur présent et qui a des
-- données pour ton HV ne donne. sondes : quelques itemID du scan en cours (sans elles, aucune preuve de données).
function lib:ChampsARelever(typeDeDonnees, sondes)
  local reste = tous(typeDeDonnees)
  if not maison() then return reste end
  for _, f in ipairs(presents(typeDeDonnees)) do
    local ok, a = pcall(f.donnees, f.lire, sondes)
    if ok and a then for _, c in ipairs(f.champs) do reste[c] = nil end end
  end
  return reste
end

-- Appelé par lib:Lire pour un type qui a des fournisseurs ; d, lotGD : ce que rend GameData (nil sans lui ou sans relevé).
-- Rend { objet = fn(itemID) -> ligne ou nil, hv, depot } et le lot { provenance, fournisseur, champs, releve, fragile }.
-- ligne = { min, qty, auctions, tiers, hist, sources = { champ = nom du fournisseur } }. Lot : la provenance du fournisseur
-- en tête (celui des prix ; « autre add-on » et son nom), champs = { champ = nom du fournisseur qui le donne } ; un autre
-- add-on ne dit pas son build : ni build ni date, sauf pour GameData. releve : le lot du relevé de GameData.
function lib:LireParFournisseurs(typeDeDonnees, d, lotGD, avecGameData)
  local chaine = presents(typeDeDonnees)
  local gd, releves
  if avecGameData then gd, releves = lecteurGameData(d) end
  if gd then
    -- un champ relevé par GameData à son dernier scan est le sien : les fournisseurs n'en avaient pas alors
    releves = releves or tous(typeDeDonnees)
    for _, f in ipairs(chaine) do
      local reste = {}
      for _, c in ipairs(f.champs) do if not releves[c] then reste[#reste + 1] = c end end
      f.champs = reste
    end
    chaine[#chaine + 1] = { nom = "GameData", provenance = "relevé direct", champs = CHAMPS[typeDeDonnees], lire = gd }
  end
  if #chaine == 0 then return nil, avecGameData and "pas encore relevé" or "pas de GameData ni de fournisseur" end
  local champs, lot = {}, {}
  for _, f in ipairs(chaine) do
    for _, c in ipairs(f.champs) do
      if not champs[c] then champs[c], lot.fragile = f.nom, lot.fragile or f.fragile end
    end
  end
  local tete = chaine[1] -- celui des prix (premier champ), sinon le premier présent
  for _, f in ipairs(chaine) do if f.nom == champs[CHAMPS[typeDeDonnees][1]] then tete = f break end end
  if tete.nom == "GameData" then for k, v in pairs(lotGD or {}) do lot[k] = v end
  else lot.provenance, lot.fournisseur = tete.provenance, tete.nom end
  lot.champs, lot.releve = champs, lotGD
  local function objet(id)
    local ligne, sources = {}, {}
    for _, f in ipairs(chaine) do
      local ok, r = pcall(f.lire, id) -- un fournisseur qui plante ne prive pas des autres
      if ok and type(r) == "table" then
        for _, c in ipairs(f.champs) do
          if ligne[c] == nil and r[c] ~= nil then ligne[c], sources[c] = r[c], f.nom end
        end
      end
    end
    if not next(ligne) then return nil end
    ligne.sources = sources
    return ligne
  end
  return { objet = objet, hv = d and d.hv, depot = d and d.depot }, lot
end
