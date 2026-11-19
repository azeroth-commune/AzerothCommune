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

test("fausse API d'Auctionator : prix venus d'elle, provenance autre add-on, prix plus à relever par GameData", function()
    local lib = LibStub("LibCommune-1.0")
    local vrai = Auctionator
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) if id == 2772 then return 95 end end } } }
    local ok, err = pcall(function()
        local hv, lot = lib:Lire("cours de l'HV")
        assertNotNil(hv)
        assertEquals(95, hv.objet(2772).min)
        assertEquals("Auctionator", hv.objet(2772).sources.min)
        assertEquals("autre add-on", lot.provenance)
        assertEquals("Auctionator", lot.fournisseur)
        local reste = lib:ChampsARelever("cours de l'HV")
        assertTrue(reste.min == nil)
        assertTrue(reste.tiers)
    end)
    Auctionator = vrai
    assertTrue(ok, err)
end)
