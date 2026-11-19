-- Fournisseurs des cours de l'HV dans wow-ui-sim (tools/sim.sh test LibCommune) : Fournisseurs.lua chargé par le TOC,
-- avec GameData, et une fausse API d'Auctionator le temps d'un test (si le vrai Auctionator est chargé, il est remis après).
test("Fournisseurs.lua est chargé avec la lib", function()
    local lib = LibStub("LibCommune-1.0")
    assertEquals(1, lib.versions.fournisseurs)
    assertType("function", lib.ChampsARelever)
    assertType("table", lib.fournisseurs["cours de l'HV"])
end)

test("cours de l'HV avec GameData : son relevé, ou pas encore relevé", function()
    local lib = LibStub("LibCommune-1.0")
    local hv, lot = lib:Lire("cours de l'HV")
    if hv then
        assertType("function", hv.objet)
        assertType("table", lot.champs)
        print("cours de l'HV : prix par " .. tostring(lot.champs.min) .. (lot.fournisseur and (" (" .. lot.provenance .. ")") or ""))
    else
        assertEquals("pas encore relevé", lot)
    end
end)

test("fausse API d'Auctionator, sans scan de GameData : prix venus d'elle, provenance autre add-on", function()
    local lib = LibStub("LibCommune-1.0")
    local vrai, coursHV = Auctionator, GameDataAPI.coursHV
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) if id == 2772 then return 95 end end,
        GetAuctionAgeByItemID = function(_, id) if id == 2772 then return 0 end end } } }
    GameDataAPI.coursHV = function() end -- GameData sans scan de l'HV
    local ok, err = pcall(function()
        local hv, lot = lib:Lire("cours de l'HV")
        assertNotNil(hv)
        assertEquals(95, hv.objet(2772).min)
        assertEquals("Auctionator", hv.objet(2772).sources.min)
        assertEquals("autre add-on", lot.provenance)
        assertEquals("Auctionator", lot.fournisseur)
    end)
    Auctionator, GameDataAPI.coursHV = vrai, coursHV
    assertTrue(ok, err)
end)

test("avec un fournisseur, GameData garde toujours prix, quantité, annonces, paliers de son scan", function()
    local lib = LibStub("LibCommune-1.0")
    local reste = lib:ChampsARelever("cours de l'HV")
    assertTrue(reste.min)
    assertTrue(reste.qty)
    assertTrue(reste.auctions)
    assertTrue(reste.tiers)
    if Auctionator then print("vrai Auctionator chargé : GameData garde le prix") end
end)
