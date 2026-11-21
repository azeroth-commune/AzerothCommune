-- Fournisseurs des cours de l'HV dans wow-ui-sim (tools/sim.sh test AzerothCommune) : Fournisseurs.lua chargé par le TOC,
-- avec la base, et une fausse API d'Auctionator le temps d'un test (si le vrai Auctionator est chargé, il est remis après).
-- Le scan de l'HV de la base est la SavedVariable AzerothCommuneMarket, remplacée le temps d'un test.
test("Fournisseurs.lua est chargé avec le socle", function()
    local lib = AzerothCommune
    assertType("function", lib.ChampsARelever)
    assertType("table", lib.fournisseurs["cours de l'HV"])
end)

test("cours de l'HV avec la base : son relevé, ou pas encore relevé", function()
    local lib = AzerothCommune
    local hv, lot = lib:Lire("cours de l'HV")
    if hv then
        assertType("function", hv.objet)
        assertType("table", lot.champs)
        if lot.scan then assertType("number", lot.scan.time) print("dernier scan de ton HV : " .. tostring(lot.scan.scanned)) end
        print("cours de l'HV : prix par " .. tostring(lot.champs.min) .. (lot.fournisseur and (" (" .. lot.provenance .. ")") or ""))
    else
        assertEquals("pas encore relevé", lot)
    end
end)

test("fausse API d'Auctionator, sans scan de la base : prix venus d'elle, provenance autre add-on", function()
    local lib = AzerothCommune
    local vrai, marche = Auctionator, AzerothCommuneMarket
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) if id == 2772 then return 95 end end,
        GetAuctionAgeByItemID = function(_, id) if id == 2772 then return 0 end end } } }
    AzerothCommuneMarket = {} -- la base sans scan de l'HV
    local ok, err = pcall(function()
        local hv, lot = lib:Lire("cours de l'HV")
        assertNotNil(hv)
        assertEquals(95, hv.objet(2772).min)
        assertEquals("Auctionator", hv.objet(2772).sources.min)
        assertEquals("autre add-on", lot.provenance)
        assertEquals("Auctionator", lot.fournisseur)
    end)
    Auctionator, AzerothCommuneMarket = vrai, marche
    assertTrue(ok, err)
end)

test("avec un fournisseur, la base garde toujours prix, quantité, annonces, paliers de son scan", function()
    local lib = AzerothCommune
    local reste = lib:ChampsARelever("cours de l'HV")
    assertTrue(reste.min)
    assertTrue(reste.qty)
    assertTrue(reste.auctions)
    assertTrue(reste.tiers)
    if Auctionator then print("vrai Auctionator chargé : la base garde le prix") end
end)

test("scan de la base pour ton HV : son heure dans le lot (scan = { time, scanned })", function()
    local lib = AzerothCommune
    local marche = AzerothCommuneMarket
    local maison = lib.MaisonHV() or "?" -- « n° de serveur-faction », la clé des scans de l'HV (LibCommune#35)
    AzerothCommuneMarket = { [maison] = { time = 1234, scanned = "2026-11-20 10:00:00", items = { [2772] = { min = 100, qty = 5 } } } }
    local ok, err = pcall(function()
        local hv, lot = lib:Lire("cours de l'HV")
        assertNotNil(hv)
        assertEquals(1234, lot.scan.time)
        assertEquals("2026-11-20 10:00:00", lot.scan.scanned)
        assertNil(lot.scan.items)
    end)
    AzerothCommuneMarket = marche
    assertTrue(ok, err)
end)
