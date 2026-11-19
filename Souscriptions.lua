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
-- Accesseurs lus par LibCommune (lib:Lire ; le nom de chacun est dans le catalogue). Par perso : persos[perso] = le
-- champ s'il est seul, sinon { champ = … } ; recettesConnues est dans Commerce.lua.
local function parPerso(nom)
  local champs, persos = RANGEMENT[nom].persos, {}
  for k, c in pairs(GameDataDB.chars) do
    if #champs == 1 then persos[k] = c[champs[1]]
    else
      for _, f in ipairs(champs) do
        if c[f] ~= nil then persos[k] = persos[k] or {}; persos[k][f] = c[f] end
      end
    end
  end
  return { persos = persos }
end
function ns.inventaires() return parPerso("inventaires") end
function ns.reputations() return parPerso("réputations") end
function ns.metiersEtCompetences() return parPerso("métiers et compétences") end
function ns.quetesTerminees() return parPerso("quêtes terminées") end
function ns.maitresDeMetier() return GameDataDB.trainers end
function ns.marchands() return GameDataDB.vendors end
function ns.prixDesVols() return GameDataDB.taxi end
function ns.addonsInstalles() return GameDataDB.addons end
function ns.coursHV() if next(GameDataMarket) then return { hv = GameDataMarket, depot = GameDataDB.deposit } end end
function ns.objets() return GameDataItems.items end

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

function ns.effacer(nom)
  local r = RANGEMENT[nom]
  for _, c in pairs(GameDataDB.chars) do
    for _, f in ipairs(r.persos or {}) do
      c[f] = nil
      if c.scanned then c.scanned[f] = nil end
      if c.errors then c.errors[f] = nil end
    end
  end
  for _, f in ipairs(r.base or {}) do GameDataDB[f] = type(GameDataDB[f]) == "table" and {} or nil end
  if r.sv then _G[r.sv] = {} end
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
