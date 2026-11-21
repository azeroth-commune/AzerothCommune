-- Azeroth Commune : fournisseurs (GameData#6). Un fournisseur tient un type de données relevées pour le joueur : l'API
-- publique d'un autre add-on d'abord, à défaut ses SavedVariables (fragile, si sa licence le permet), en dernier notre
-- propre relevé (la base du socle, nommée « GameData » dans les sources d'une ligne). On ne copie pas ce qui est lourd et
-- qu'un fournisseur tient déjà (l'historique de l'HV) ; ce que le scan du socle vient de voir est gardé et fait foi : un
-- « dernier vu » d'un autre add-on ne dit pas si l'objet est encore en vente. Sans scan ni fournisseur, le type est
-- indisponible, jamais relevé en repli.
-- ponytail: « GameData » reste le nom de notre scan dans sources et champs (lu par le Négoce) ; à renommer avec lui.
--
-- Cours de l'HV, ligne d'un objet de ton HV (royaume-faction du personnage connecté) :
--   Avec un scan de GameData pour cet HV : min (prix unitaire le plus bas), qty (quantité en vente), auctions (annonces),
--     tiers (paliers { {price, qty} }) de son dernier scan, relevé direct ; un objet absent de ce scan est plus en vente
--     (min nil, qty 0). hist ({ {heure, min, qté}, … }) : AuctionDB dès qu'il en a un, même ancien (un historique reste juste) ;
--     sinon celui de GameData. GameData n'en garde pas de copie quand AuctionDB a scanné l'HV il y a moins de 6 h.
--   Sans : les fournisseurs seuls. min : Auctionator (API v1 ; seulement si son âge est 0, « vu aujourd'hui » : le mieux
--     qu'il dise, pas « vu au dernier scan ») > TSM (TSM_API, non essayé) > AuctionDB ; qty et hist : AuctionDB. age :
--     jours depuis qu'Auctionator a vu l'objet. AuctionDB : un point qui n'est pas du dernier scan de la maison (ou plus
--     récent : persos de confiance) veut dire plus en vente (min nil, qty 0), l'historique reste.
-- Fournisseurs lus (rien de leur code n'est repris) : Auctionator (« All Rights Reserved ») et TSM par leur API publique
-- seulement ; AuctionDB (GPL v3 dans son LICENSE, LGPLv3 dans son TOC) n'a pas d'API publique : ses SavedVariables, au
-- format décrit dans son History.lua. Sa qty compte aussi les enchères sans achat immédiat.
-- Chargé après AzerothCommune.lua : la maison de l'HV et la faction viennent de ses relevés sondés.
local lib = AzerothCommune

local HV = "cours de l'HV"
local CHAMPS = { [HV] = { "min", "qty", "auctions", "tiers", "hist" } }
local APPELANT = "AzerothCommune" -- l'API d'Auctionator demande le nom de l'add-on qui l'appelle
local AUCTIONDB_RECENT = 6 * 3600 -- un scan d'AuctionDB plus vieux : son historique n'est plus frais pour ton HV

local function maison() return lib.MaisonHV() end -- même clé que AzerothCommuneMarket, sondée ; nil si la faction est inconnue

-- Sondes des fournisseurs : un prix numérique, ou rien, pour un objet. Vérifiées sur la première ligne de chaque lecture
-- (relevé en masse) ; un fournisseur absent n'est jamais lu : sa sonde reste « pas encore vue », sans relevé sans contexte.
local function prixOuRien(p) return p == nil or type(p) == "number" end
lib.DeclarerSonde("prix Auctionator", "Auctionator.API.v1 rend un prix et un âge numériques, ou rien",
  function(p, age) return prixOuRien(p) and prixOuRien(age) end)
lib.DeclarerSonde("prix TSM", "TSM_API.GetCustomPriceValue rend un prix numérique, ou rien", prixOuRien)
lib.DeclarerSonde("prix AuctionDB", "AuctionDBForeverSaved : la ligne d'un objet est « heure,min,médiane,qté … », ou rien",
  function(l) return l == nil or (type(l) == "string" and l:find("^%d+,%d+,%d+,%d+") ~= nil) end)
-- Une fonction qui sonde nom sur sa première ligne seulement (une par lecteur, donc par lecture).
local function premiereLigne(nom)
  local faite = false
  return function(...)
    if not faite then faite = true; lib.Sonder(nom, ...) end
  end
end

-- AuctionDB v2.8.1 : AuctionDBForeverSaved.houses["<région-règles> <Faction>"] = { items = { [itemID] = "heure,min,médiane,
-- qté heure,…" (du plus ancien au plus récent ; min 0 : seulement des enchères sans achat immédiat) }, scans = { {heure, …} } }.
-- Sa maison de la faction du personnage, la plus récemment scannée (la clé dit la région, pas le royaume), et l'heure de
-- ce dernier scan.
local function maisonAuctionDB()
  local sv, faction = AuctionDBForeverSaved, lib.Faction()
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

-- Chaque fournisseur : lecteur() rend une fonction (itemID) -> { champ = valeur } s'il est présent, sinon nil. lourds :
-- les champs qu'il donne encore à côté du scan de GameData (pas de copie), frais() : ses données valent pour ton HV.
lib.fournisseurs = {
  [HV] = {
    { nom = "Auctionator", provenance = "autre add-on", champs = { "min", "age" },
      lecteur = function()
        local api = Auctionator and Auctionator.API and Auctionator.API.v1
        if not (api and api.GetAuctionPriceByItemID and api.GetAuctionAgeByItemID) then return nil end
        local sonder = premiereLigne("prix Auctionator")
        return function(id)
          local p = api.GetAuctionPriceByItemID(APPELANT, id)
          if not p then sonder(p) return nil end
          local age = api.GetAuctionAgeByItemID(APPELANT, id) -- jours ; nil au-delà de 21
          sonder(p, age)
          return { min = age == 0 and p or nil, age = age } -- pas vu aujourd'hui : plus en vente
        end
      end },
    -- ponytail: TSM n'est pas installé ici, écrit d'après son API publique documentée, jamais essayé en jeu.
    { nom = "TSM", provenance = "autre add-on", champs = { "min" },
      lecteur = function()
        if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
        local sonder = premiereLigne("prix TSM")
        return function(id)
          local p = TSM_API.GetCustomPriceValue("dbminbuyout", "i:" .. id)
          sonder(p)
          return p and { min = p }
        end
      end },
    { nom = "AuctionDB", provenance = "autre add-on", fragile = true, champs = { "min", "qty", "hist" }, lourds = { "hist" },
      frais = function() local _, quand = maisonAuctionDB() return quand ~= nil and time() - quand < AUCTIONDB_RECENT end,
      lecteur = function()
        local h, quand = maisonAuctionDB()
        if not h then return nil end
        local sondee = false
        return function(id)
          local s = h.items[id]
          if not sondee then -- première ligne seulement ; son début : un historique peut être long
            sondee = true; lib.Sonder("prix AuctionDB", type(s) == "string" and s:sub(1, 40) or s)
          end
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

-- Le dernier scan du socle pour ton HV (ns.coursHV : { hv = AzerothCommuneMarket, depot }), en lecteur du même
-- genre : un objet absent de ce scan est plus en vente. 2e retour : ce scan.
local function lecteurGameData(d)
  local h = maison()
  local m = h and d and d.hv and d.hv[h]
  if not m then return nil end
  return function(id)
    local r = { qty = 0, hist = m.hist and m.hist[id] }
    for k, v in pairs(m.items and m.items[id] or {}) do r[k] = v end
    return r
  end, m
end

local function presents(typeDeDonnees)
  local out = {}
  for _, f in ipairs(lib.fournisseurs[typeDeDonnees] or {}) do
    local ok, lire = pcall(f.lecteur)
    if ok and lire then
      local frais = false
      if f.frais then local okF, v = pcall(f.frais); frais = okF and v end
      out[#out + 1] = { nom = f.nom, provenance = f.provenance, fragile = f.fragile, champs = f.champs, lourds = f.lourds,
        frais = frais, lire = lire }
    end
  end
  return out
end

-- Les champs que GameData garde à son scan : tous, sauf un champ lourd qu'un fournisseur présent tient, frais, pour ton HV.
function lib:ChampsARelever(typeDeDonnees)
  local reste = {}
  for _, c in ipairs(CHAMPS[typeDeDonnees] or {}) do reste[c] = true end
  if not maison() then return reste end
  for _, f in ipairs(presents(typeDeDonnees)) do
    if f.frais then for _, c in ipairs(f.lourds or {}) do reste[c] = nil end end
  end
  return reste
end

-- Appelé par lib:Lire pour un type qui a des fournisseurs ; d, lotGD : ce que rend GameData (nil sans lui ou sans relevé).
-- Rend { objet = fn(itemID) -> ligne ou nil, hv, depot } et le lot { provenance, fournisseur, champs, releve, fragile, scan }.
-- ligne = { min, qty, auctions, tiers, hist, age, sources = { champ = nom du fournisseur } }. Lot : celui de GameData
-- (relevé direct) s'il a scanné ton HV, sinon la provenance du premier fournisseur (« autre add-on » et son nom ; un autre
-- add-on ne dit pas son build : ni build ni date) ; champs = { champ = qui le donne } ; releve : le lot de GameData ;
-- scan = { time (heure du jeu, time()), scanned (date lisible) } : le dernier scan de GameData pour ton HV, absent sans lui
-- (le lot de GameData vaut pour tous ses HV, scan pour le tien).
function lib:LireParFournisseurs(typeDeDonnees, d, lotGD, avecGameData)
  local chaine = presents(typeDeDonnees)
  local gd, scan
  if avecGameData then gd, scan = lecteurGameData(d) end
  if gd then -- son scan fait foi ; un fournisseur ne donne plus que ses champs lourds (l'historique), avant GameData
    -- même s'il n'est plus frais : un historique de plusieurs jours reste juste quand son dernier point a 7 h, alors que
    -- celui de GameData peut n'avoir qu'un point (il le recommence quand AuctionDB était frais). « frais » ne décide que
    -- de ce que GameData garde à son scan (ChampsARelever).
    local avant = {}
    for _, f in ipairs(chaine) do
      if f.lourds then f.champs = f.lourds; avant[#avant + 1] = f end
    end
    avant[#avant + 1] = { nom = "GameData", provenance = "relevé direct", champs = CHAMPS[typeDeDonnees], lire = gd }
    chaine = avant
  end
  if #chaine == 0 then return nil, avecGameData and "pas encore relevé" or "pas de GameData ni de fournisseur" end
  local champs, lot = {}, {}
  for _, f in ipairs(chaine) do
    for _, c in ipairs(f.champs) do
      if not champs[c] then champs[c], lot.fragile = f.nom, lot.fragile or f.fragile end
    end
  end
  if gd then for k, v in pairs(lotGD or {}) do lot[k] = v end
  else lot.provenance, lot.fournisseur = chaine[1].provenance, chaine[1].nom end
  lot.champs, lot.releve = champs, lotGD
  lot.scan = scan and { time = scan.time, scanned = scan.scanned }
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
