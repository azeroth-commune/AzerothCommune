-- Azeroth Commune, la base, partie commerce : recettes, maîtres de métier, marchands et hôtel des ventes.
--   AzerothCommuneDB.recipes[clé]  : chaque recette vue dans une fenêtre de métier, avec ce qu'elle produit et ses
--                              composants. Clé = ID du sort de la recette quand le jeu le donne, sinon « Métier:Nom ».
--   chars[perso].recipes      : par métier, rang, maximum et recettes connues (clé -> difficulté,
--                              ou true quand relevée sans fenêtre).
--   AzerothCommuneDB.trainers[npc]  : ce que chaque maître enseigne, à quel prix, quel rang et quel niveau requis.
--   AzerothCommuneDB.vendors[npc]   : ce que chaque marchand vend, à quel prix, par combien, en stock limité ou non.
--   AzerothCommuneDB.ecarts[clé]    : les écarts entre un maître ou un marchand vu et la réserve des recettes (#84).
--   AzerothCommuneDB.taxi[départ]   : prix des vols depuis chaque maître de vol ouvert.
--   AzerothCommuneMarket[maison] : dernier scan complet de l'hôtel des ventes, sous la maison de l'HV (lib.MaisonHV,
--                              « n° de serveur-faction », « 6942-Alliance ») : par objet, le prix unitaire le
--                              plus bas, la quantité en vente et les paliers de prix les moins chers ; l'historique,
--                              seulement si aucun fournisseur ne le tient (AuctionDB frais : Fournisseurs.lua).
-- Rien ne se lit sans la fenêtre ouverte (sauf les recettes connues, relevées aussi à la connexion parmi celles déjà
-- vues) : ouvre tes métiers, parle aux maîtres et aux marchands, ouvre l'HV.
local _, ns = ...
local lib = AzerothCommune -- royaume, faction, maison de l'HV, relevé des recettes : relevés et sondés par AzerothCommune.lua

local function itemIDOf(link) return tonumber(link and link:match("item:(%d+)")) end

-- L'ID du sort d'une recette se lit dans son lien (« |Henchant:2662| » ou « |Hspell:…| ») ;
-- sans lien, le métier et le nom servent de clé.
local function recipeKey(link, prof, name)
  return tonumber(link and (link:match("enchant:(%d+)") or link:match("spell:(%d+)"))) or (prof .. ":" .. name)
end
ns.itemIDOf, ns.recipeKey = itemIDOf, recipeKey

local function safe(name, fn, ...)
  local ok, err = pcall(fn, ...)
  AzerothCommuneDB.errors[name] = (not ok) and tostring(err) or nil
end

-- Le PNJ de la fenêtre ouverte : son ID (6e champ du GUID « Creature-0-…-npcID-… ») et où on l'a vu.
local function npc()
  local guid = UnitGUID("npc")
  local id = guid and tonumber((select(6, strsplit("-", guid))))
  local map = C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition(map, "player")
  local x, y = nil, nil
  if pos then x, y = pos:GetXY() end
  return id or UnitName("npc"), {
    name = UnitName("npc"), zone = GetZoneText(), subzone = GetSubZoneText(), map = map,
    x = x and math.floor(x * 1000) / 10, y = y and math.floor(y * 1000) / 10,
    faction = lib.Faction(), seen = ns.now(),
  }
end

---------------------------------------------------------------------------------------------------
-- Recettes. Sur Forever les métiers passent par l'API moderne C_TradeSkillUI (GetTradeSkillLine n'existe pas). Le
-- relevé de la fenêtre ouverte est dans AzerothCommune.lua (lib:ReleverRecettes) ; la base sauvegarde ce qu'il rend.
-- Une fenêtre ne relève qu'un métier : le lot des recettes d'un perso n'est relevé entier (plus peut-être périmé) que
-- quand chacun de ses métiers a été relevé sous ce build (build noté par métier). Rend le 2e retour attendu par ns.run.
local function releveRecettes(c)
  for _, m in pairs(c.recipes) do if m.build ~= ns.build() then return "partiel" end end
  return true
end

local function saveProfession(c, prof, rank, max, known)
  c.recipes = c.recipes or {}
  c.recipes[prof] = { rank = rank, max = max, known = known, scanned = ns.now(), build = ns.build() }
  return releveRecettes(c)
end

-- Rend false si rien n'a été relevé, sinon le 2e retour de ns.run. Sans fiche c (base des recettes souscrite seule) : les
-- recettes vues seulement.
local function scanTradeSkill(c)
  local r, why, prof = lib:ReleverRecettes()
  if why == "liste pas à jour" then ns.retryTrade() return false end
  AzerothCommuneDB.trade_seen = AzerothCommuneDB.trade_seen or {}
  if r or why == "liste vide" then
    AzerothCommuneDB.trade_seen[r and r.metier or prof] = ns.now() .. " : " .. (r and r.total or "aucune") .. " recette(s) données par le jeu"
  end
  if not r then return false end -- pas notre métier, ou données pas prêtes : TRADE_SKILL_LIST_UPDATE suivra
  for id, rec in pairs(r.recettes) do AzerothCommuneDB.recipes[id] = rec end
  AzerothCommuneDB.errors["recipes:" .. r.metier] = r.premiereErreur and (r.illisibles .. " recette(s) illisible(s), ex. " .. r.premiereErreur) or nil
  if not c then return false end
  c.recipes = c.recipes or {}
  local m = lib:RangerRecettes(c.recipes, r) -- la liste de la fenêtre prime, sans perdre une connue relevée sans elle
  m.scanned, m.build = ns.now(), ns.build()
  return releveRecettes(c)
end

-- Lu par AzerothCommune:Lire (type « recettes connues ») : les recettes vues et, par perso, ses métiers et recettes connues.
ns.lire["recettes connues"] = function()
  local persos, lots = {}, {}
  for k, c in pairs(AzerothCommuneDB.chars) do persos[k], lots[k] = c.recipes, c.recipes and c.lots and c.lots.recipes end
  return { recettes = AzerothCommuneDB.recipes, persos = persos }, { persos = lots }
end

-- La réserve : RecettesClassic.lua (nom historique), généré par tools/build_recipe_data_client.py de l'atelier depuis les
-- tables du client Forever et ses correctifs en cache (#54), hors du repo tant que la licence n'est pas choisie : absent
-- d'un repo cloné tel quel. Mise en forme une fois dans la forme des recettes vues, chaque ligne marquée « extrait du
-- client », avec les seuils jaune et gris du client (vert = (jaune + gris) / 2) et, depuis #64, la source de la recette
-- (« d'emblée », « maître », « patron vendu », « retirée », « inconnue »), la provenance de cette source (« extrait du
-- client », « source externe » : Fabrikao, ou « relevé direct » : un maître de l'atelier, #83), la compétence pour l'apprendre (level), le prix du
-- patron (cuivre, nil sans), le temps de recharge (secondes, 0 sans) et, depuis #67, la condition d'accès (« spécialisation : … »,
-- « réputation : … », « plus enseignée », nil sans) et, depuis Maitrise#15, l'objet patron qui l'enseigne (patron : marchand, butin
-- ou quête, nil sans) : le générateur en décide. Un enchantement n'a pas
-- d'objet produit (output nil). Depuis #80, les marchands du patron (Fabrikao, source externe ; nil sans), chacun
-- { pnj, nom, prix (cuivre, nil inconnu), carte (uiMapID), x, y (pourcentage de la carte ; nil sans), faction (« Alliance »,
-- « Horde », nil : les deux ou inconnue) } d'après la table des PNJ de la réserve (ns.recettesPNJ). Depuis #81, la provenance
-- de la compétence pour l'apprendre (level_provenance, 17e champ) : « règle » (la règle du décalage), « incertaine » (recette
-- ajoutée par Forever ou seuils incomplets : Fabrikao), « patron » (la compétence requise de l'objet patron, dans le client),
-- « extrait du client » (d'emblée) ; nil dans une réserve d'avant #81. Depuis #83, les relevés directs de l'atelier : une recette
-- vue chez un maître de l'atelier a sa compétence, la source « maître », source_provenance et level_provenance « relevé direct »
-- et la date du relevé (level_date, 18e champ, « AAAA-MM-JJ hh:mm:ss » ; nil sans) ; les marchands vus complètent ceux de Fabrikao.
-- Depuis #70, le temps d'incantation (cast, 19e champ, secondes, du client ; nil sans) ; depuis #71, les outils demandés
-- (outils, 20e champ : des clés de ns.recettesOutils, rendues { { nom, objets = { objet qui convient, … } }, … } ; nil sans).
local reserve, brute
local function fichePNJ(id) -- un PNJ hors de la table garde son ID, sans nom ni position
  local p = ns.recettesPNJ and ns.recettesPNJ[id] or {}
  return { pnj = id, nom = p[1], carte = p[2], x = p[3], y = p[4], faction = p[5] }
end
-- Le lot des marchands et des maîtres de la réserve (ns.recettesMarchandsLot : provenance « source externe », source
-- « Fabrikao », version, date de ses données), en copie ; nil sans réserve.
local function lotMarchands()
  if not ns.recettesMarchandsLot then return nil end
  local lot = {}
  for f, v in pairs(ns.recettesMarchandsLot) do lot[f] = v end
  return lot
end
local function marchandsDe(liste)
  local out = {}
  for i = 1, #liste, 2 do
    local m = fichePNJ(liste[i])
    m.prix = liste[i + 1] ~= 0 and liste[i + 1] or nil
    out[#out + 1] = m
  end
  return out
end
local function outilsDe(cles)
  local out = {}
  for _, k in ipairs(cles) do
    local o = ns.recettesOutils and ns.recettesOutils[k]
    if o then out[#out + 1] = { nom = o[1], objets = o[2] } end
  end
  return out
end
local function reserveRecettes()
  if reserve == nil or brute ~= ns.recettesClassic then
    brute, reserve = ns.recettesClassic, {}
    -- { objet, produit min, produit max, métier, nom, { composant, quantité, … }, compétence, jaune, gris, source,
    --   provenance de la source, prix du patron, recharge, condition (nil sans), objet patron (nil sans),
    --   marchands du patron ({ PNJ, prix, … }, nil sans), provenance de la compétence, date du relevé direct,
    --   temps d'incantation, outils demandés }
    for k, c in pairs(brute or {}) do
      local reagents = {}
      for i = 1, #c[6], 2 do reagents[#reagents + 1] = { id = c[6][i], qty = c[6][i + 1] } end
      reserve[k] = { output = c[1], made_min = c[2], made_max = c[3], profession = c[4], name = c[5], reagents = reagents,
        level = c[7], yellow = c[8], grey = c[9], source = c[10], source_provenance = c[11],
        pattern_price = c[12] ~= 0 and c[12] or nil, cooldown = c[13], condition = c[14], patron = c[15],
        marchands = c[16] and marchandsDe(c[16]), level_provenance = c[17], level_date = c[18], cast = c[19],
        outils = c[20] and outilsDe(c[20]), provenance = "extrait du client" }
    end
  end
  return reserve
end

-- À la connexion, sans fenêtre : les recettes connues parmi celles déjà vues (tous persos) et la réserve, toutes interrogées
-- (même une recette de la réserve dont l'objet a une recette vue), relevées par AzerothCommune.lua.
local function scanKnownRecipes()
  if not ns.souscrit("recettes connues") then return end
  local c = ns.char()
  c.recipes = c.recipes or {}
  local candidates = {}
  for k, r in pairs(reserveRecettes()) do candidates[k] = r end
  for k, r in pairs(AzerothCommuneDB.recipes) do candidates[k] = r end
  -- ajoute des connues sans rien retirer : relevé partiel, noté une fois fini (il court sur plusieurs images)
  lib:ReleverRecettesSansFenetre(c.recipes, candidates, function() ns.noterLot("recipes", false, c.lots) end)
end

-- Le relevé des maîtres de métier passe devant la réserve (#72) : pour chaque service d'un maître relevé (AzerothCommuneDB.trainers),
-- la recette qu'il enseigne prend level = la compétence demandée (skill_rank), source « maître », source_provenance et
-- level_provenance « relevé direct », level_date = la date de ce relevé (seen du maître, #83) et prix_maitre = son prix (cuivre) ;
-- la base livrée se trompe parfois de 25 points (#68).
-- Rapprochement, dans le métier du service (service.skill, le nom du métier) : par l'objet enseigné (service.item = output de
-- la recette) quand une seule recette du métier le produit, sinon par le nom exact (un enchantement n'a pas d'objet : par
-- son nom). Un service qui ne rapproche rien (« Minage d'apprenti », une compétence de classe) est ignoré. Plusieurs maîtres
-- pour une recette : la compétence la plus basse, puis le prix le plus bas. d est modifié (ses lignes sont déjà des copies
-- ou des lignes de la réserve : une ligne touchée est remplacée par une copie, jamais modifiée sur place).
-- Le rapprochement d'un service de maître (avec skill et skill_rank) à sa recette de d, limité aux métiers de metiers
-- ({ [métier] = true }) : rend function(service) -> clé de la recette, ou nil. Plusieurs recettes du métier pour ce service
-- (même nom, même objet : deux enchantements d'époques différentes…) : nil, on ne choisit pas (pas d'état deviné ;
-- relecture de la PR #74).
local function rapprocheur(d, metiers)
  local parObjet, parNom = {}, {}
  for k, r in pairs(d) do
    local m = r.profession
    if m and metiers[m] and r.name then
      parNom[m] = parNom[m] or {}
      parNom[m][r.name] = parNom[m][r.name] or {}
      table.insert(parNom[m][r.name], k)
      if r.output then
        parObjet[m] = parObjet[m] or {}
        parObjet[m][r.output] = parObjet[m][r.output] or {}
        table.insert(parObjet[m][r.output], k)
      end
    end
  end
  return function(sv)
    local m = sv.skill
    local cles = sv.item and parObjet[m] and parObjet[m][sv.item]
    if not cles or #cles ~= 1 then cles = parNom[m] and parNom[m][sv.name] end
    return cles and #cles == 1 and cles[1] or nil
  end
end
local function metiersDe(services, metiers)
  for _, sv in ipairs(services or {}) do
    if sv.skill and sv.skill_rank then metiers[sv.skill] = true end
  end
  return metiers
end

local function appliquerMaitres(d)
  -- ponytail: la base est lue souvent ; on n'indexe que les métiers d'un maître relevé (rien sans maître).
  local metiers = {}
  for _, t in pairs(AzerothCommuneDB.trainers or {}) do metiersDe(t.services, metiers) end
  if not next(metiers) then return 0 end
  local recette = rapprocheur(d, metiers)
  local meilleur, quand = {}, {} -- clé -> service retenu, date du relevé de son maître
  for _, t in pairs(AzerothCommuneDB.trainers or {}) do
    for _, sv in ipairs(t.services or {}) do
      local k = sv.skill and sv.skill_rank and recette(sv)
      if k then
        local b = meilleur[k]
        if not b or sv.skill_rank < b.skill_rank or (sv.skill_rank == b.skill_rank and (sv.cost or 0) < (b.cost or 0)) then
          meilleur[k], quand[k] = sv, t.seen
        end
      end
    end
  end
  local n = 0
  for k, sv in pairs(meilleur) do
    local copie = {}
    for f, v in pairs(d[k]) do copie[f] = v end
    copie.level, copie.source, copie.source_provenance, copie.prix_maitre = sv.skill_rank, "maître", "relevé direct", sv.cost
    copie.level_provenance, copie.level_date = "relevé direct", quand[k]
    if copie.condition == "plus enseignée" then copie.condition = nil end -- un maître l'enseigne : elle l'est encore
    d[k] = copie
    n = n + 1
  end
  return n
end

-- Lu par AzerothCommune:Lire (type « base des recettes ») : les recettes vues, puis la réserve pour les objets qu'aucune
-- recette vue ne fabrique. Une recette vue que la réserve connaît aussi en prend la compétence pour l'apprendre (et sa provenance), les seuils
-- jaune et gris, la source, le prix du patron, le temps de recharge, la condition, le patron et ses marchands, le temps
-- d'incantation et les outils (la fenêtre de métier ne les donne pas), sur une copie.
-- Puis les maîtres relevés (appliquerMaitres) l'emportent sur les deux. Lot : relevé direct dès qu'une recette est vue ou
-- qu'un maître en a donné une ; la réserve seule, comme le catalogue des objets : le lot de la réserve (extrait du client),
-- peut-être périmé sous un autre build ou sans lot.
ns.lire["base des recettes"] = function()
  local vues, res, d, fait = AzerothCommuneDB.recipes or {}, reserveRecettes(), {}, {}
  for k, r in pairs(vues) do
    local c = res[k]
    if c and r.level == nil then
      local copie = { level = c.level, level_provenance = c.level_provenance, level_date = c.level_date, yellow = c.yellow, grey = c.grey, source = c.source,
        source_provenance = c.source_provenance, pattern_price = c.pattern_price, cooldown = c.cooldown, condition = c.condition, patron = c.patron,
        marchands = c.marchands, cast = c.cast, outils = c.outils }
      for f, v in pairs(r) do copie[f] = v end
      r = copie
    end
    d[k] = r
    if r.output then fait[r.output] = true end
  end
  for k, r in pairs(res) do
    if d[k] == nil and not fait[r.output] then d[k] = r end
  end
  if appliquerMaitres(d) > 0 or next(vues) then return d, { provenance = "relevé direct", marchands = lotMarchands() } end
  local lot = { marchands = lotMarchands() }
  for f, v in pairs(ns.recettesClassicLot or {}) do lot[f] = v end
  -- ponytail: GetBuildInfo est toujours là en jeu ; le garde sert aux check.lua des add-ons qui ne le bouchonnent pas.
  lot.provenance, lot.perime = "extrait du client", not (GetBuildInfo and lot.build == lib.Build()) or nil
  return d, lot
end

-- Les maîtres d'un métier (« Forge », les noms de métier de la base des recettes), d'après la réserve (Fabrikao, source
-- externe, #80) : { { pnj, nom, carte, x, y, faction }, … } (champs comme les marchands de la base des recettes), dans
-- l'ordre de Fabrikao (niveau du PNJ), et leur lot { provenance = « source externe », source = « Fabrikao », version, date
-- (de ses données) } ; nil pour un métier inconnu ou sans réserve. Copies : à modifier sans risque.
function lib.MaitresDuMetier(metier)
  local ids = ns.recettesMaitres and ns.recettesMaitres[metier]
  if not ids then return nil end
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = fichePNJ(id) end
  return out, lotMarchands()
end

local function scanCraft(c) -- la fenêtre « Craft » de vanilla (Enchantement), si ce client l'a encore
  if not GetCraftDisplaySkillLine then return false end
  local prof, rank, max = GetCraftDisplaySkillLine()
  if not prof then return false end
  local known = {}
  for i = 1, GetNumCrafts() do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local key = recipeKey(link, prof, name)
      local reagents = {}
      for r = 1, GetCraftNumReagents(i) do
        local rname, _, qty = GetCraftReagentInfo(i, r)
        reagents[r] = { id = itemIDOf(GetCraftReagentItemLink(i, r)), qty = qty, name = rname }
      end
      AzerothCommuneDB.recipes[key] = { profession = prof, name = name, output = itemIDOf(link), made_min = 1, reagents = reagents }
      known[key] = kind
    end
  end
  return saveProfession(c, prof, rank, max, known)
end

---------------------------------------------------------------------------------------------------
-- Écarts (#84) : quand un relevé direct du joueur (la fenêtre d'un maître ou d'un marchand) contredit la réserve (la base
-- livrée), l'écart est noté dans AzerothCommuneDB.ecarts[genre:recette:PNJ] = { genre, recette (clé), nom (de la recette),
-- attendu (la réserve), vu (le relevé), pnj, pnjNom, patron (l'objet patron de la réserve), date } ; un écart revu remplace
-- le précédent (nouvelle date). La donnée du joueur l'emporte déjà (appliquerMaitres, lire.marchands) : rien d'autre n'est
-- corrigé. Lus par AC.Ecarts() (Diagnostic). Genres :
--   « compétence »       : un maître enseigne la recette à une autre compétence que celle de la réserve (attendu nil ou 0 :
--                          la réserve ne la connaissait pas) ; revue à la même compétence, l'écart s'efface ;
--   « patron absent »    : la réserve dit que ce marchand vend le patron, il ne l'a pas ;
--   « marchand inconnu » : il vend le patron, la réserve ne le compte pas parmi ses marchands.
local function noterEcart(genre, k, r, pnj, info, attendu, vu)
  AzerothCommuneDB.ecarts[genre .. ":" .. k .. ":" .. pnj] = { genre = genre, recette = k, nom = r.name, attendu = attendu, vu = vu,
    pnj = pnj, pnjNom = info.name, patron = r.patron, date = ns.now() }
end
-- ponytail: un service caché par les filtres du joueur n'est pas revu, son écart reste tel quel.
local function ecartsMaitre(pnj, info)
  local metiers = metiersDe(info.services, {})
  if not next(metiers) then return end
  local res = reserveRecettes()
  local recette = rapprocheur(res, metiers)
  for _, sv in ipairs(info.services) do
    local k = sv.skill and sv.skill_rank and recette(sv)
    if k and res[k].level ~= sv.skill_rank then
      noterEcart("compétence", k, res[k], pnj, info, res[k].level, sv.skill_rank)
    elseif k then
      AzerothCommuneDB.ecarts["compétence:" .. k .. ":" .. pnj] = nil
    end
  end
end
-- La liste d'un marchand dit tout ce qu'il vend : ses écarts sont refaits à chaque relevé. Seules les recettes dont la réserve
-- expose l'objet patron sont comparées.
-- ponytail: un patron en stock limité épuisé disparaît peut-être de la liste (à vérifier en jeu) : noté « patron absent » ;
-- un patron qui se lie à la prise n'a pas d'objet dans la réserve, pas comparé.
local function ecartsMarchand(pnj, info)
  for cle, e in pairs(AzerothCommuneDB.ecarts) do
    if e.pnj == pnj and e.genre ~= "compétence" then AzerothCommuneDB.ecarts[cle] = nil end
  end
  local vend = {}
  for _, it in ipairs(info.items) do if it.id then vend[it.id] = true end end
  for k, r in pairs(reserveRecettes()) do
    if r.patron then
      local annonce = false
      for _, m in ipairs(r.marchands or {}) do annonce = annonce or m.pnj == pnj end
      if annonce and not vend[r.patron] then noterEcart("patron absent", k, r, pnj, info, "en vente", "absent")
      elseif vend[r.patron] and not annonce then noterEcart("marchand inconnu", k, r, pnj, info, "absent", "en vente") end
    end
  end
end

-- Un écart que la réserve en cours a réglé (régénérée depuis le relevé) est effacé ; « attendu » suit la réserve en cours.
local function regle(e, r)
  if not r then return true end -- recette sortie de la réserve
  if e.genre == "compétence" then
    e.attendu = r.level
    return r.level == e.vu
  end
  local annonce = false
  for _, m in ipairs(r.marchands or {}) do annonce = annonce or m.pnj == e.pnj end
  return annonce == (e.genre == "marchand inconnu")
end
-- Les écarts notés, en copies : { { genre, recette, nom, attendu, vu, pnj, pnjNom, patron, date }, … } ({} sans écart).
function lib.Ecarts()
  local out, ecarts = {}, AzerothCommuneDB and AzerothCommuneDB.ecarts or {}
  local res = next(ecarts) and reserveRecettes()
  for cle, e in pairs(ecarts) do
    if regle(e, res[e.recette]) then
      ecarts[cle] = nil
    else
      local c = {}
      for f, v in pairs(e) do c[f] = v end
      out[#out + 1] = c
    end
  end
  return out
end

---------------------------------------------------------------------------------------------------
-- Maîtres de métier (et de classe). Les filtres « disponible / indisponible / déjà appris » du joueur
-- cachent des lignes : on les note pour savoir si la liste est complète.
local function scanTrainer()
  local id, info = npc()
  local services = {}
  for i = 1, GetNumTrainerServices() do
    local name, rank, category = GetTrainerServiceInfo(i)
    if name and category ~= "header" then
      local skill, skillRank = GetTrainerServiceSkillReq(i)
      services[#services + 1] = {
        name = name, rank = rank ~= "" and rank or nil, category = category, cost = (GetTrainerServiceCost(i)),
        skill = skill, skill_rank = skillRank, level = GetTrainerServiceLevelReq(i),
        item = GetTrainerServiceItemLink and itemIDOf(GetTrainerServiceItemLink(i)) or nil,
      }
    end
  end
  info.services = services
  info.filters = {}
  for _, f in ipairs({ "available", "unavailable", "used" }) do
    info.filters[f] = GetTrainerServiceTypeFilter and (GetTrainerServiceTypeFilter(f) and true or false) or nil
  end
  info.tradeskill = IsTradeskillTrainer and IsTradeskillTrainer() or nil
  AzerothCommuneDB.trainers[id] = info
  ns.noterLot("maîtres de métier")
  ecartsMaitre(id, info)
end

---------------------------------------------------------------------------------------------------
-- Marchands : tout ce qu'ils vendent, au prix que paie ce perso (remises de réputation comprises).
local function scanMerchant()
  local id, info = npc()
  local items = {}
  for i = 1, GetMerchantNumItems() do
    local m = C_MerchantFrame.GetItemInfo(i)
    if m then
      local row = {
        id = (GetMerchantItemID and GetMerchantItemID(i)) or itemIDOf(GetMerchantItemLink(i)), name = m.name, price = m.price,
        stack = m.stackCount, limited = (m.numAvailable or -1) >= 0 and m.numAvailable or nil,
      }
      if m.hasExtendedCost then -- payé en objets ou en monnaie (insignes, réputation…)
        row.cost_items = {}
        for j = 1, GetMerchantItemCostInfo(i) do
          local _, value, link, currency = GetMerchantItemCostItem(i, j)
          row.cost_items[j] = { id = itemIDOf(link), currency = currency, qty = value }
        end
      end
      items[#items + 1] = row
    end
  end
  info.items = items
  AzerothCommuneDB.vendors[id] = info
  ns.noterLot("marchands")
  ecartsMarchand(id, info)
end

---------------------------------------------------------------------------------------------------
-- Maîtres de vol : le prix de chaque destination depuis celui-ci. AzerothCommuneDB.taxi[départ][arrivée] = prix (cuivre).
local function scanTaxi()
  local here, costs = nil, {}
  for i = 1, NumTaxiNodes() do
    local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
    if kind == "CURRENT" then here = name
    elseif kind == "REACHABLE" then costs[name] = TaxiNodeCost(i) end
  end
  if here then
    AzerothCommuneDB.taxi = AzerothCommuneDB.taxi or {}
    AzerothCommuneDB.taxi[here] = costs
    ns.noterLot("prix des vols")
  end
end

---------------------------------------------------------------------------------------------------
-- Hôtel des ventes : scan complet (C_AuctionHouse.ReplicateItems). Ce qu'on sait de Forever (AuctionDB, GPL,
-- commentaires de son Scan.lua) : environ 85 000 entrées, données en ~10 s, index 0..n-1, un scan par 15 min
-- et par session (une 2e demande est ignorée), REPLICATE_ITEM_LIST_UPDATE arrive une fois avec les données
-- puis des milliers de fois pendant que les infos d'objets chargent ; itemID, quantité et prix d'achat
-- immédiat sont toujours là. Le prix d'achat immédiat vaut pour toute la pile.
-- Le scan est demandé à l'ouverture de l'HV si le dernier date de plus de 15 min ; si un autre add-on
-- (AuctionDB) l'a déjà demandé, on lit simplement les mêmes données.
-- Paliers gardés : jusqu'à couvrir 60 % de ce qui est en vente (et au moins 2 000 unités), au plus 60 prix. Les 8
-- premiers ne voyaient que la fine couche bon marché d'un marché à deux étages (le charbon : 530 unités à 4-5 pa,
-- le gros à 13 pa, le 18/11/2026) ; le Négoce lit l'échelle entière.
local SCAN_COOLDOWN, BATCH, TIERS = 15 * 60, 2000, 60
local ahOpen, reading, lastRequest, readAt = false, false, 0, nil

local function house() return lib.MaisonHV() end
-- ponytail: un HV par royaume et faction ; les HV neutres (gobelins) se mélangent à celui de la faction.

-- rows : { {id, count, buyout}, … } -> { [itemID] = { min, qty, auctions, tiers = { {price, qty}, … } } }
local function aggregate(rows)
  local by = {}
  for _, r in ipairs(rows) do
    local count = (r.count and r.count > 0) and r.count or 1
    if r.id and r.buyout and r.buyout > 0 then
      local t = by[r.id] or {}
      t[#t + 1] = { math.floor(r.buyout / count), count }
      by[r.id] = t
    end
  end
  local out = {}
  for id, list in pairs(by) do
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local tiers, qty, cover = {}, 0, math.max(2000, total * 0.6)
    for _, e in ipairs(list) do
      local last = tiers[#tiers]
      if last and last.price == e[1] then last.qty = last.qty + e[2]
      elseif #tiers < TIERS and qty < cover then tiers[#tiers + 1] = { price = e[1], qty = e[2] } end
      qty = qty + e[2]
    end
    out[id] = { min = list[1][1], qty = qty, auctions = #list, tiers = tiers }
  end
  return out
end
ns.aggregate = aggregate

-- L'historique (lourd) n'est pas copié quand un fournisseur le tient, frais, pour cet HV (Fournisseurs.lua) ; prix,
-- quantité, annonces et paliers que le scan vient de voir sont toujours gardés : ils font foi.
local function historiqueFourni() return not lib:ChampsARelever("cours de l'HV").hist end

local function readReplicate()
  local n = C_AuctionHouse.GetNumReplicateItems()
  local rows, i = {}, 0
  local function step()
    for idx = i, math.min(i + BATCH, n) - 1 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
      rows[#rows + 1] = { id = itemID, count = count, buyout = buyout }
    end
    i = i + BATCH
    if i < n then return C_Timer.After(0, step) end -- 2000 entrées par frame : pas de gel
    local items = aggregate(rows)
    local h = house()
    -- Historique : prix le plus bas et quantité en vente à chaque scan (les 12 derniers), pour estimer ce qui part.
    local hist = AzerothCommuneMarket[h] and AzerothCommuneMarket[h].hist or {}
    local stamp = time()
    for id, it in pairs(items) do
      local list = hist[id] or {}
      list[#list + 1] = { stamp, it.min, it.qty }
      while #list > 12 do table.remove(list, 1) end
      hist[id] = list
    end
    for id, list in pairs(hist) do -- plus rien en vente : tout est parti (ou retiré)
      if not items[id] and list[#list][1] ~= stamp then
        list[#list + 1] = { stamp, nil, 0 }
        while #list > 12 do table.remove(list, 1) end
      end
    end
    AzerothCommuneMarket[h] = { scanned = ns.now(), time = stamp, auctions = n, items = items, hist = not historiqueFourni() and hist or nil }
    -- ponytail: lot entier, un seul HV relevé en pratique ; un lot par HV si un joueur en relève plusieurs (sinon l'HV
    -- de l'autre faction passe pour frais après un nouveau build)
    ns.noterLot("cours de l'HV", true)
    reading, readAt = false, GetTime()
    print(("Azeroth Commune : hôtel des ventes lu, %d enchères. /reload pour l'écrire sur le disque."):format(n))
    lib:Signaler("cours de l'HV") -- les abonnés de AzerothCommune:QuandReleve("cours de l'HV")
  end
  step()
end

-- Dépôt d'une annonce. Règle : 15 % du prix de revente au marchand par tranche de 12 h (30 % pour 24 h), avec sur
-- Forever un minimum de 1 pa par annonce (voulu par Blizzard, annoncé à 1 pc « bientôt » ; Icy Veins, nov. 2026).
-- HV ouvert, on vérifie avec le jeu (C_AuctionHouse.CalculateCommodityDeposit, 24 h) : le taux sur 1 000 unités
-- (le minimum n'y joue pas) et le minimum sur une seule unité d'un objet bon marché. Résultats : AzerothCommuneDB.deposit.
local function learnDeposit()
  local rates, mins = {}, {}
  for id, d in pairs(ns.VENDOR_DB or {}) do
    local sell = d[4]
    if sell and sell > 0 then
      local many = C_AuctionHouse.CalculateCommodityDeposit(id, 2, 1000)
      if many and many > 0 then
        local rate = many / (1000 * sell)
        rates[#rates + 1] = rate
        local one = C_AuctionHouse.CalculateCommodityDeposit(id, 2, 1)
        if one and one > rate * sell + 1 then mins[#mins + 1] = one end -- le minimum l'a emporté
      end
      if #rates >= 20 then break end
    end
  end
  if #rates == 0 then return end
  local function median(t) table.sort(t) return t[math.floor((#t + 1) / 2)] end
  AzerothCommuneDB.deposit = { rate24 = median(rates), min = #mins > 0 and median(mins) or nil, checked = ns.now() }
end

local function requestScan()
  if GetTime() - lastRequest < SCAN_COOLDOWN then return end
  lastRequest = GetTime()
  C_AuctionHouse.ReplicateItems()
end

---------------------------------------------------------------------------------------------------
-- Ces événements arrivent en rafale : un seul scan, une demi-seconde après le dernier.
local tradeToken, retries = 0, 0
local function queueTrade()
  tradeToken = tradeToken + 1
  local mine = tradeToken
  C_Timer.After(0.5, function()
    if mine ~= tradeToken then return end
    if ns.souscrit("recettes connues") then
      ns.run("recipes", function(c) local releve = scanTradeSkill(c); return c.recipes, releve end)
    elseif ns.souscrit("base des recettes") then -- les recettes vues seules, pas les connues du perso
      safe("recipes_base", scanTradeSkill)
    end
  end)
end
function ns.retryTrade() -- liste pas encore à jour : jusqu'à 4 nouveaux essais
  retries = retries + 1
  if retries <= 4 then C_Timer.After(0.6, queueTrade) end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE",
  "TRAINER_SHOW", "TRAINER_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TAXIMAP_OPENED",
  "REPLICATE_ITEM_LIST_UPDATE" }) do
  pcall(f.RegisterEvent, f, e)
end

-- Le type de données que relève chaque fenêtre : rien n'est lu sans souscription à ce type (Souscriptions.lua). Les recettes
-- passent par queueTrade (recettes connues, ou base des recettes seule) et ns.run, qui vérifient eux-mêmes.
-- ponytail: la fenêtre « Craft » de vanilla (scanCraft) ne relève que sous « recettes connues » ; Forever ne l'a plus.
local TYPE_DE = { TRAINER_SHOW = "maîtres de métier", TRAINER_UPDATE = "maîtres de métier", MERCHANT_SHOW = "marchands",
  MERCHANT_UPDATE = "marchands", TAXIMAP_OPENED = "prix des vols", AUCTION_HOUSE_SHOW = "cours de l'HV",
  REPLICATE_ITEM_LIST_UPDATE = "cours de l'HV" }

f:SetScript("OnEvent", function(_, event)
  -- diagnostic : la dernière fois que chaque événement est arrivé (pour savoir si une fenêtre a bien été vue)
  AzerothCommuneDB.events = AzerothCommuneDB.events or {}
  AzerothCommuneDB.events[event] = ns.now()
  if TYPE_DE[event] and not ns.souscrit(TYPE_DE[event]) then return end
  if event == "PLAYER_LOGIN" then
    C_Timer.After(5, function() safe("recipes_login", scanKnownRecipes) end)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    retries = 0
    queueTrade()
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    ns.run("recipes", function(c) local releve = scanCraft(c); return c.recipes, releve end)
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    safe("trainer", scanTrainer)
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
    safe("merchant", scanMerchant)
  elseif event == "TAXIMAP_OPENED" then
    safe("taxi", scanTaxi)
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    safe("auction_request", requestScan)
    C_Timer.After(2, function() safe("auction_deposit", learnDeposit) end)
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" and ahOpen and not reading then
    -- une lecture par scan : les milliers d'événements suivants (infos d'objets qui chargent) sont ignorés
    if readAt and GetTime() - readAt < SCAN_COOLDOWN then return end
    reading = true
    safe("auction_read", readReplicate)
  end
end)

function ns.commerceStatus()
  local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
  local m = AzerothCommuneMarket[house()]
  return ("Recettes : %d. Maîtres : %d. Marchands : %d. Hôtel des ventes : %s."):format(
    count(AzerothCommuneDB.recipes), count(AzerothCommuneDB.trainers), count(AzerothCommuneDB.vendors),
    m and (count(m.items) .. " objets, scan du " .. m.scanned) or "pas encore scanné (ouvre l'HV)")
end
