-- Royaume, faction et maison de l'HV relevés par la lib, qui les sonde (GameData#24). Le royaume est le numéro de serveur
-- du GUID (LibCommune#35), la maison de l'HV « n°-faction ».
local function export(cle)
    for _, e in ipairs(LibStub("LibCommune-1.0").Exports()) do if e.cle == cle then return e.donnees() end end
end

test("la fiche du perso et l'export de l'HV prennent royaume, faction et maison de la lib", function()
    local lib = LibStub("LibCommune-1.0")
    lib:Souscrire("inventaires") -- la fiche n'est relevée que pour un type souscrit
    local fiche = export("perso")[lib.Personnage().guid].character
    assertType("table", fiche)
    assertEquals(lib.Royaume(), fiche.realm)
    assertEquals(UnitGUID("player"):match("^Player%-(%d+)%-"), fiche.realm)
    assertNil(export("perso")[lib.Personnage().guid].adresse) -- plus d'adresse dans la fiche
    assertEquals(lib.Faction(), fiche.faction)
    assertEquals(lib.MaisonHV(), export("hv").hv)
    assertEquals(fiche.realm .. "-" .. fiche.faction, export("hv").hv)
end)
