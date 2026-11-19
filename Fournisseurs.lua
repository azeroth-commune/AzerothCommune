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
-- Fournisseurs lus (rien de leur code n'est repris) : Auctionator (« All Rights Reserved ») et TSM par leur API publique
-- seulement ; AuctionDB (GPL v3) n'a pas d'API publique : ses SavedVariables, au format décrit dans son History.lua.
local lib = LibStub("LibCommune-1.0", true) or LibStub:NewLibrary("LibCommune-1.0", 0) -- chargé seul : outils, tests
local VERSION = 1
lib.versions = lib.versions or {}
if (lib.versions.fournisseurs or 0) >= VERSION then return end
lib.versions.fournisseurs = VERSION

local HV = "cours de l'HV"
local CHAMPS = { [HV] = { "min", "qty", "auctions", "tiers", "hist" } }
local APPELANT = "LibCommune" -- l'API d'Auctionator demande le nom de l'add-on qui l'appelle

local function maison() return GetRealmName() .. "-" .. UnitFactionGroup("player") end -- même clé que GameDataMarket

-- AuctionDB v2.8.1 : AuctionDBForeverSaved.houses["<région-règles> <Faction>"] = { items = { [itemID] = "heure,min,médiane,
-- qté heure,…" (du plus ancien au plus récent ; min 0 : seulement des enchères sans achat immédiat) }, scans = { {heure, …} } }.
-- Sa maison de la faction du personnage, la plus récemment scannée (la clé dit la région, pas le royaume).
local function maisonAuctionDB()
  local sv = AuctionDBForeverSaved
  if type(sv) ~= "table" or type(sv.houses) ~= "table" then return nil end
  local faction, meilleure, quand = " " .. (UnitFactionGroup("player") or ""), nil, -1
  for nom, h in pairs(sv.houses) do
    if type(nom) == "string" and nom:sub(-#faction) == faction and type(h) == "table" and type(h.items) == "table" then
      local dernier = type(h.scans) == "table" and h.scans[#h.scans]
      local t = type(dernier) == "table" and tonumber(dernier[1]) or 0
      if t > quand then meilleure, quand = h, t end
    end
  end
  return meilleure
end

-- Chaque fournisseur : lecteur() rend une fonction (itemID) -> { champ = valeur } s'il est présent, sinon nil.
lib.fournisseurs = {
  [HV] = {
    { nom = "Auctionator", provenance = "autre add-on", champs = { "min" },
      lecteur = function()
        local api = Auctionator and Auctionator.API and Auctionator.API.v1
        if not (api and api.GetAuctionPriceByItemID) then return nil end
        return function(id)
          local p = api.GetAuctionPriceByItemID(APPELANT, id)
          return p and { min = p }
        end
      end },
    -- ponytail: TSM n'est pas installé ici, écrit d'après son API publique documentée, jamais essayé en jeu.
    { nom = "TSM", provenance = "autre add-on", champs = { "min" },
      lecteur = function()
        if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
        return function(id)
          local p = TSM_API.GetCustomPriceValue("dbminbuyout", "i:" .. id)
          return p and { min = p }
        end
      end },
    { nom = "AuctionDB", provenance = "autre add-on", fragile = true, champs = { "min", "qty", "hist" },
      lecteur = function()
        local h = maisonAuctionDB()
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
          return der and { min = der[2], qty = der[3], hist = hist }
        end
      end },
  },
}

-- Le relevé de GameData (GameDataAPI.coursHV : { hv = GameDataMarket, depot }), en lecteur du même genre : les champs
-- qu'il a relevés pour ton HV (tous, ou seulement ceux qu'aucun fournisseur ne donnait au moment du scan).
local function lecteurGameData(d)
  local m = d and d.hv and d.hv[maison()]
  if not m then return nil end
  return function(id)
    local it, h = m.items and m.items[id], m.hist and m.hist[id]
    if not (it or h) then return nil end
    local r = { hist = h }
    for k, v in pairs(it or {}) do r[k] = v end
    return r
  end
end

local function presents(typeDeDonnees)
  local out = {}
  for _, f in ipairs(lib.fournisseurs[typeDeDonnees] or {}) do
    local ok, lire = pcall(f.lecteur)
    if ok and lire then out[#out + 1] = { nom = f.nom, provenance = f.provenance, fragile = f.fragile, champs = f.champs, lire = lire } end
  end
  return out
end

-- Les champs que GameData doit relever lui-même : { champ = true } pour ceux qu'aucun fournisseur présent ne donne.
function lib:ChampsARelever(typeDeDonnees)
  local reste = {}
  for _, c in ipairs(CHAMPS[typeDeDonnees] or {}) do reste[c] = true end
  for _, f in ipairs(presents(typeDeDonnees)) do for _, c in ipairs(f.champs) do reste[c] = nil end end
  return reste
end

-- Appelé par lib:Lire pour un type qui a des fournisseurs ; d, lotGD : ce que rend GameData (nil sans lui ou sans relevé).
-- Rend { objet = fn(itemID) -> ligne ou nil, hv, depot } et le lot { provenance, fournisseur, champs, releve, fragile }.
-- ligne = { min, qty, auctions, tiers, hist, sources = { champ = nom du fournisseur } }. Lot : la provenance du fournisseur
-- en tête (celui des prix ; « autre add-on » et son nom), champs = { champ = nom du fournisseur qui le donne } ; un autre
-- add-on ne dit pas son build : ni build ni date, sauf pour GameData. releve : le lot du relevé de GameData.
function lib:LireParFournisseurs(typeDeDonnees, d, lotGD, avecGameData)
  local chaine = presents(typeDeDonnees)
  local gd = avecGameData and lecteurGameData(d)
  if gd then chaine[#chaine + 1] = { nom = "GameData", provenance = "relevé direct", champs = CHAMPS[typeDeDonnees], lire = gd } end
  if #chaine == 0 then return nil, avecGameData and "pas encore relevé" or "pas de GameData ni de fournisseur" end
  local champs, lot = {}, {}
  for _, f in ipairs(chaine) do
    for _, c in ipairs(f.champs) do
      if not champs[c] then champs[c], lot.fragile = f.nom, lot.fragile or f.fragile end
    end
  end
  local tete = chaine[1]
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
