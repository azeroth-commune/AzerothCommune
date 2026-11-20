-- GameData, souscriptions : on ne relève que les types de données auxquels un add-on a souscrit (lib:Souscrire de
-- LibCommune). GameDataDB.souscriptions[type] = date de la dernière souscription (time()). Elle vaut pour tout le joueur :
--   à la connexion de n'importe quel personnage, GameData relève les types souscrits, même si l'add-on qui a souscrit n'y
--   est pas activé.
-- Un type sans nouvelle souscription depuis 30 jours cesse d'être relevé ; ses données restent jusqu'à ce que le joueur
-- les efface. /gdata souscriptions : la liste ; /gdata effacer <type> ; /gdata souscrire <type|tout> (le joueur souscrit lui-même,
-- pour ses exports).
local _, ns = ...
local DUREE = 30 * 24 * 3600

-- Où chaque type de données du catalogue (LibCommune) range ce qu'il relève : champs de chaque perso
-- (GameDataDB.chars[perso][champ]), champs de GameDataDB, ou une SavedVariable entière.
local RANGEMENT = {
  inventaires = { persos = { "character", "equipped", "bags", "bank", "mail", "currencies" } },
  ["réputations"] = { persos = { "reputations" } },
  ["métiers et compétences"] = { persos = { "professions", "skills" } },
  ["quêtes terminées"] = { persos = { "quests_done" } },
  ["recettes connues"] = { persos = { "recipes" }, base = { "recipes", "trade_seen" } },
  ["maîtres de métier"] = { base = { "trainers" } },
  marchands = { base = { "vendors" } },
  ["prix des vols"] = { base = { "taxi" } },
  ["add-ons installés"] = { base = { "addons", "addons_scanned" } },
  ["cours de l'HV"] = { base = { "deposit" }, sv = "GameDataMarket" },
  objets = { sv = "GameDataItems" },
}
ns.rangement = RANGEMENT
local typeDuChamp = {}
for nom, r in pairs(RANGEMENT) do for _, c in ipairs(r.persos or {}) do typeDuChamp[c] = nom end end

function ns.souscrire(nom) -- appelé par lib:Souscrire ; avant la lecture des SavedVariables, retenu à la connexion
  if not (RANGEMENT[nom] and GameDataDB) then return end
  GameDataDB.souscriptions = GameDataDB.souscriptions or {}
  GameDataDB.souscriptions[nom] = time()
end

function ns.souscrit(nom) -- une souscription en cours : ce type est à relever
  local quand = GameDataDB and GameDataDB.souscriptions and GameDataDB.souscriptions[nom]
  return quand ~= nil and time() - quand < DUREE
end
function ns.champSouscrit(champ) return ns.souscrit(typeDuChamp[champ]) end

function ns.retenirSouscriptions() -- à la connexion, avant tout relevé : les souscriptions faites pendant le chargement
  local lib = LibStub and LibStub("LibCommune-1.0", true)
  for nom in pairs(lib and lib.souscriptions or {}) do ns.souscrire(nom) end
end

---------------------------------------------------------------------------------------------------
local function plein(v) return v ~= nil and (type(v) ~= "table" or next(v) ~= nil) end
local function aDesDonnees(r)
  for _, c in pairs(GameDataDB.chars) do
    for _, f in ipairs(r.persos or {}) do if plein(c[f]) then return true end end
  end
  for _, f in ipairs(r.base or {}) do if plein(GameDataDB[f]) then return true end end
  if r.sv == "GameDataItems" then return plein(GameDataItems.items) end
  return r.sv ~= nil and plein(_G[r.sv])
end

---------------------------------------------------------------------------------------------------
-- Lots (GameData#5). Au chargement : les données d'avant les lots reçoivent une provenance plausible (relevé direct :
-- GameData ne sauvegarde que ce qu'il relève en jeu), build inconnu ; puis tout lot figé sous un autre build que celui
-- du client est marqué perime (peut-être périmé). Rien n'est effacé ; un nouveau relevé entier du lot lève la marque.
function ns.verifierLots()
  local build = tonumber((select(2, GetBuildInfo())))
  for nom, r in pairs(RANGEMENT) do
    if not r.persos and not GameDataDB.lots[nom] and aDesDonnees(r) then GameDataDB.lots[nom] = { provenance = "relevé direct" } end
  end
  local function marquer(l) if l.build ~= build then l.perime = true end end
  for _, l in pairs(GameDataDB.lots) do marquer(l) end
  for _, c in pairs(GameDataDB.chars) do
    c.lots = c.lots or {}
    for f in pairs(typeDuChamp) do
      if c[f] ~= nil and not c.lots[f] then c.lots[f] = { provenance = "relevé direct", date = c.scanned and c.scanned[f] } end
    end
    c.scanned = nil -- la date du relevé est dans le lot
    for _, l in pairs(c.lots) do marquer(l) end
  end
end

---------------------------------------------------------------------------------------------------
-- Accesseurs lus par LibCommune (lib:Lire ; le nom de chacun est dans le catalogue) : les données et leur lot. Par
-- perso : persos[perso] = le champ s'il est seul, sinon { champ = … }, et lots.persos[perso] = le lot le moins frais de
-- ses champs (un peut-être périmé d'abord, sinon le plus ancien) ; recettesConnues est dans Commerce.lua.
local function moinsFrais(a, b)
  if not a or not b then return a or b end
  if not a.perime ~= not b.perime then return a.perime and a or b end
  return (a.date or "") <= (b.date or "") and a or b
end
local function parPerso(nom)
  local champs, persos, lots = RANGEMENT[nom].persos, {}, {}
  for k, c in pairs(GameDataDB.chars) do
    for _, f in ipairs(champs) do
      if c[f] ~= nil then
        if #champs == 1 then persos[k] = c[f] else persos[k] = persos[k] or {}; persos[k][f] = c[f] end
        lots[k] = moinsFrais(lots[k], c.lots and c.lots[f])
      end
    end
  end
  return { persos = persos }, { persos = lots }
end
function ns.inventaires() return parPerso("inventaires") end
function ns.reputations() return parPerso("réputations") end
function ns.metiersEtCompetences() return parPerso("métiers et compétences") end
function ns.quetesTerminees() return parPerso("quêtes terminées") end
function ns.maitresDeMetier() return GameDataDB.trainers, GameDataDB.lots["maîtres de métier"] end
function ns.prixDesVols() return GameDataDB.taxi, GameDataDB.lots["prix des vols"] end
function ns.addonsInstalles() return GameDataDB.addons, GameDataDB.lots["add-ons installés"] end
function ns.coursHV()
  if next(GameDataMarket) then return { hv = GameDataMarket, depot = GameDataDB.deposit }, GameDataDB.lots["cours de l'HV"] end
end
function ns.objets() return GameDataItems.items, GameDataDB.lots.objets end

-- Marchands : un lot mixte. Les marchands vus en jeu (relevé direct) et la base VendorData.lua, générée hors jeu (quel
-- PNJ vend quoi : cMaNGOS, source externe ; prix, lots et piles : client Forever, extrait du client), dont la ligne vaut
-- donc « source externe », la moins fiable de ses deux sources. La provenance la plus fiable gagne : un marchand vu en
-- jeu prend toute sa liste au relevé (elle dit aussi ce qu'il ne vend pas), la base ne remplit que les marchands pas vus.
-- Une ligne de la base porte aussi la revente au marchand (sell) et la taille de pile (maxStack) ; un PNJ amical pour la
-- seule faction adverse du personnage connecté n'en fait pas partie.
local parPNJ, pourFaction -- ponytail: VendorData ne change pas en jeu, regroupée par PNJ une fois par faction
local function vendorDataParPNJ()
  local faction = (UnitFactionGroup("player") or ""):sub(1, 1) -- "A", "H", ou "" (pas encore connue : pas de filtre)
  if pourFaction ~= faction then
    parPNJ, pourFaction = {}, faction
    for id, d in pairs(ns.VENDOR_DB or {}) do
      for pnj, seule in d[3]:gmatch("(%d+)(%a?)") do
        if seule == "" or faction == "" or seule == faction then
          pnj = tonumber(pnj)
          parPNJ[pnj] = parPNJ[pnj] or { items = {} }
          table.insert(parPNJ[pnj].items, { id = id, price = d[1], stack = d[2], sell = d[4], maxStack = d[5] })
        end
      end
    end
  end
  return parPNJ
end
function ns.marchands()
  local lib = LibStub("LibCommune-1.0")
  if not lib.Fusionner then return GameDataDB.vendors end -- LibCommune d'avant la mineure 4 : pas de lot mixte
  local d, provenance = lib.Fusionner({ { donnees = GameDataDB.vendors, provenance = "relevé direct" },
    { donnees = vendorDataParPNJ(), provenance = "source externe" } })
  if provenance == "relevé direct" then return d, GameDataDB.lots.marchands end
  -- ponytail: VendorData.lua ne dit pas sous quel build ni quand il a été généré : build inconnu, donc peut-être périmé ;
  -- à lire ici le jour où tools/build_vendor_data.py l'écrit.
  return d, { provenance = provenance, perime = true }
end

function ns.effacer(nom)
  local r = RANGEMENT[nom]
  for _, c in pairs(GameDataDB.chars) do
    for _, f in ipairs(r.persos or {}) do
      c[f] = nil
      if c.lots then c.lots[f] = nil end
      if c.errors then c.errors[f] = nil end
    end
  end
  for _, f in ipairs(r.base or {}) do GameDataDB[f] = type(GameDataDB[f]) == "table" and {} or nil end
  if r.sv then _G[r.sv] = {} end
  GameDataDB.lots[nom] = nil
  if nom == "objets" then ns.itemsReady() end -- le balayage repart de 1 (s'il est souscrit)
end

local function noms()
  local t = {}
  for nom in pairs(RANGEMENT) do t[#t + 1] = nom end
  table.sort(t)
  return t
end

-- /gdata souscriptions | effacer <type> | souscrire <type|tout> ; rend true si la commande est la sienne.
function ns.souscriptionsCommand(cmd, rest)
  if cmd == "souscriptions" then
    print("GameData : souscriptions des add-ons aux types de données (relevés sur chaque personnage à sa connexion) :")
    for _, nom in ipairs(noms()) do
      local quand = GameDataDB.souscriptions and GameDataDB.souscriptions[nom]
      local etat = not quand and "aucune souscription"
        or ns.souscrit(nom) and ("souscrit le " .. date("%Y-%m-%d", quand) .. ", relevé")
        or ("plus de souscription depuis 30 jours (dernière le " .. date("%Y-%m-%d", quand) .. "), plus relevé")
      print(("  %s : %s%s"):format(nom, etat, aDesDonnees(RANGEMENT[nom]) and " (données gardées)" or ""))
    end
    print("  /gdata effacer <type> : effacer ses données. /gdata souscrire <type|tout> : y souscrire toi-même.")
    return true
  end
  if cmd ~= "effacer" and cmd ~= "souscrire" then return false end
  local nom = rest:lower()
  for n in pairs(RANGEMENT) do if n:lower() == nom then nom = n end end -- « cours de l'HV » : la clé a des majuscules
  if cmd == "souscrire" and nom == "tout" then
    for _, n in ipairs(noms()) do ns.souscrire(n) end
    print("GameData : souscrit à tous les types ; relevés dès maintenant (objets : à la prochaine connexion).")
    return true
  end
  if not RANGEMENT[nom] then
    print(("GameData : type « %s » inconnu. Types : %s."):format(nom, table.concat(noms(), ", ")))
    return true
  end
  if cmd == "effacer" then
    ns.effacer(nom)
    print(("GameData : données « %s » effacées%s. /reload pour l'écrire sur le disque."):format(nom,
      ns.souscrit(nom) and " (le type a encore une souscription : il sera relevé à nouveau)" or ""))
  else
    ns.souscrire(nom)
    print(("GameData : « %s » souscrit ; relevé sur chaque personnage à sa connexion, pendant 30 jours."):format(nom))
  end
  return true
end
