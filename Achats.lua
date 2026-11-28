-- Azeroth Commune, la base, achats immédiats à l'HV (Composants#43, AzerothCommune#116) : l'achat confirmé, quel que soit
-- le chemin (HV du jeu, Auctionator, mode marchand du Négoce), est
--   * ajouté au courrier relevé du perso connecté (chars[perso].mail, type « inventaires »), sans attendre d'ouvrir la boîte ;
--     la relève suivante de la boîte (Base.lua) remplace le champ entier : la vérité efface un achat mal compté ;
--   * annoncé aux add-ons par AzerothCommune:QuandAchatHV(fn) : fn(id, quantité, prix total en cuivre, GUID du perso).
-- Le courrier n'est complété que si « inventaires » est souscrit ; le rappel est appelé dans tous les cas (un signal, pas
-- un relevé). Marchandise : ConfirmCommoditiesPurchase retient l'achat au total du devis (COMMODITY_PRICE_UPDATED), compté à
-- COMMODITY_PURCHASE_SUCCEEDED (COMMODITY_PURCHASED, s'il arrive le premier, le compte aussi : un achat ne compte qu'une
-- fois), oublié à COMMODITY_PURCHASE_FAILED. Objet à l'unité : PlaceBid au prix d'achat immédiat retient l'objet lu par
-- GetAuctionInfoByID, compté à AUCTION_HOUSE_PURCHASE_COMPLETED ; une enchère plus basse ne compte pas.
-- Les appels du jeu sont crochetés (hooksecurefunc, jamais remplacés) : tout plantage est avalé, le jeu n'en sait rien.
-- Sonde « achat HV » : l'objet, la quantité et le prix de chaque achat compté sont des nombres ; un événement du jeu
-- qui change de forme la met au rouge.
local _, ns = ...
local lib = AzerothCommune

lib.DeclarerSonde("achat HV", "un achat confirmé à l'HV donne un objet, une quantité et un prix, des nombres",
  function(id, qte, prix) return type(id) == "number" and type(qte) == "number" and qte > 0 and type(prix) == "number" end)

ns.rappelsAchat = {}
function lib:QuandAchatHV(fn)
  table.insert(ns.rappelsAchat, fn)
  return true
end

local function compter(id, qte, prix)
  lib.Sonder("achat HV", id, qte, prix)
  if type(id) ~= "number" or type(qte) ~= "number" then return end
  local guid = lib.Personnage().guid
  if ns.souscrit("inventaires") then
    local c = ns.char()
    c.mail = c.mail or {}
    table.insert(c.mail, { sender = "Hôtel des ventes", subject = "Achat immédiat", money = 0, cod = 0, items = { { id = id, count = qte } } })
  end
  for _, fn in ipairs(ns.rappelsAchat) do
    local ok, err = pcall(fn, id, qte, prix, guid)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

local devis, enCours = {}, nil -- devis[id] = total annoncé ; enCours = { id, qte, total } : marchandise confirmée, pas encore comptée
local unites = {} -- unites[auctionID] = { id, qte, prix } : PlaceBid au prix d'achat immédiat, pas encore compté
local achete

local function crocheter(nom, fn)
  if C_AuctionHouse and C_AuctionHouse[nom] then pcall(hooksecurefunc, C_AuctionHouse, nom, function(...) pcall(fn, ...) end) end
end
crocheter("StartCommoditiesPurchase", function(id) achete = id end)
crocheter("ConfirmCommoditiesPurchase", function(id, qte) enCours = { id = id, qte = qte, total = devis[id] } end)
crocheter("PlaceBid", function(auctionID, mise)
  local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
  if info and info.buyoutAmount and info.buyoutAmount > 0 and mise >= info.buyoutAmount then
    unites[auctionID] = { id = info.itemKey and info.itemKey.itemID, qte = info.quantity, prix = info.buyoutAmount }
  end
end)

local f = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "COMMODITY_PURCHASED",
  "AUCTION_HOUSE_PURCHASE_COMPLETED" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, a1, a2)
  pcall(function()
    if event == "COMMODITY_PRICE_UPDATED" then
      if achete then devis[achete] = a2 end -- prix total du devis de l'achat commencé
    elseif event == "COMMODITY_PURCHASE_FAILED" then
      enCours = nil
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" or event == "COMMODITY_PURCHASED" then
      local a = enCours
      enCours = nil -- l'autre des deux événements, arrivé ensuite, ne trouve plus rien à compter
      if a then compter(a.id, a.qte, a.total) end
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
      local u = unites[a1]
      unites[a1] = nil
      if u then compter(u.id, u.qte, u.prix) end
    end
  end)
end)
