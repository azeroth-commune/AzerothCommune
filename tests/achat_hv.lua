-- Achat immédiat à l'HV (AzerothCommune#116) dans wow-ui-sim : relevé au courrier du perso connecté et rappel aux add-ons.
-- Les appels du jeu (C_AuctionHouse) sont ceux du simulateur, crochetés par le socle ; les événements sont tirés à la main.
local lib = AzerothCommune
local ID_MARCHANDISE, ID_UNITE = 2589, 4306
local recus = {}
lib:QuandAchatHV(function(...) recus[#recus + 1] = { ... } end)
lib:Souscrire("inventaires")

local function courrier()
    local d = lib:Lire("inventaires")
    local _, fiche = next(d and d.persos or {})
    return fiche and fiche.mail or {}
end
local function quantite(id)
    local n = 0
    for _, m in ipairs(courrier()) do
        for _, it in ipairs(m.items or {}) do if it.id == id then n = n + it.count end end
    end
    return n
end
local function acheterMarchandise(id, qte, total, issue)
    C_AuctionHouse.StartCommoditiesPurchase(id, qte)
    FireEvent("COMMODITY_PRICE_UPDATED", total / qte, total)
    C_AuctionHouse.ConfirmCommoditiesPurchase(id, qte)
    if issue then FireEvent(issue) end
end
local function avecAnnonce(info, fn)
    local avant = C_AuctionHouse.GetAuctionInfoByID
    C_AuctionHouse.GetAuctionInfoByID = function() return info end
    local ok, err = pcall(fn)
    C_AuctionHouse.GetAuctionInfoByID = avant
    assert(ok, err)
end

test("la sonde « achat HV » est déclarée", function()
    assertNotNil(lib.Sondes()["achat HV"])
end)

test("marchandise : Confirm puis SUCCEEDED, l'objet et sa quantité au courrier avec leur id, et le rappel une fois", function()
    local avant, n = quantite(ID_MARCHANDISE), #recus
    acheterMarchandise(ID_MARCHANDISE, 20, 5000, "COMMODITY_PURCHASE_SUCCEEDED")
    assertEquals(avant + 20, quantite(ID_MARCHANDISE))
    assertEquals(n + 1, #recus)
    local r = recus[#recus]
    assertEquals(ID_MARCHANDISE, r[1]); assertEquals(20, r[2]); assertEquals(5000, r[3])
    assertEquals(lib.Personnage().guid, r[4])
    assertEquals("vert", lib.Sondes()["achat HV"].etat)
end)

test("marchandise : Confirm puis FAILED n'ajoute rien", function()
    local avant, n = quantite(ID_MARCHANDISE), #recus
    acheterMarchandise(ID_MARCHANDISE, 5, 900, "COMMODITY_PURCHASE_FAILED")
    FireEvent("COMMODITY_PURCHASE_SUCCEEDED") -- un SUCCEEDED égaré après l'échec ne compte pas non plus
    assertEquals(avant, quantite(ID_MARCHANDISE))
    assertEquals(n, #recus)
end)

test("marchandise : COMMODITY_PURCHASED après SUCCEEDED ne double pas ; seul, il compte", function()
    local avant, n = quantite(ID_MARCHANDISE), #recus
    acheterMarchandise(ID_MARCHANDISE, 10, 2000, "COMMODITY_PURCHASE_SUCCEEDED")
    FireEvent("COMMODITY_PURCHASED", ID_MARCHANDISE, 10)
    assertEquals(avant + 10, quantite(ID_MARCHANDISE))
    assertEquals(n + 1, #recus)
    acheterMarchandise(ID_MARCHANDISE, 3, 600, "COMMODITY_PURCHASED")
    FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
    assertEquals(avant + 13, quantite(ID_MARCHANDISE))
    assertEquals(n + 2, #recus)
end)

test("objet à l'unité : PlaceBid au prix d'achat immédiat puis PURCHASE_COMPLETED ; une enchère plus basse ne compte pas", function()
    local info = { itemKey = { itemID = ID_UNITE }, quantity = 1, buyoutAmount = 70000, bidAmount = 1000 }
    local avant, n = quantite(ID_UNITE), #recus
    avecAnnonce(info, function()
        C_AuctionHouse.PlaceBid(777, 50000) -- sous le prix d'achat : une enchère
        FireEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 777)
        assertEquals(avant, quantite(ID_UNITE))
        C_AuctionHouse.PlaceBid(778, 70000)
        assertEquals(avant, quantite(ID_UNITE), "pas compté avant la confirmation")
        FireEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 778)
    end)
    assertEquals(avant + 1, quantite(ID_UNITE))
    assertEquals(n + 1, #recus)
    local r = recus[#recus]
    assertEquals(ID_UNITE, r[1]); assertEquals(1, r[2]); assertEquals(70000, r[3])
end)

test("une relève de la boîte remplace le champ mail entier", function()
    assertTrue(#courrier() > 0)
    local nb, hdr, item, lien = GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem, GetInboxItemLink
    GetInboxNumItems = function() return 1 end
    GetInboxHeaderInfo = function() return nil, nil, "Quelqu'un", "Salut", 0, 0, 10, true end
    GetInboxItemLink = function(_, a) if a == 1 then return "|cffffffff|Hitem:2447::::::::|h[Pointe-de-paix]|h|r" end end
    GetInboxItem = function() return "nom", 1, nil, 4 end
    local ok, err = pcall(FireEvent, "MAIL_INBOX_UPDATE")
    GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem, GetInboxItemLink = nb, hdr, item, lien
    assert(ok, err)
    assertEquals(1, #courrier())
    assertEquals(2447, courrier()[1].items[1].id)
    assertEquals(4, courrier()[1].items[1].count)
    assertEquals(0, quantite(ID_MARCHANDISE))
end)
