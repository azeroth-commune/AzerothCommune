-- Royaume, faction et maison de l'HV relevés par la lib, qui les sonde (GameData#24).
local function export(cle)
    for _, e in ipairs(LibStub("LibCommune-1.0").Exports()) do if e.cle == cle then return e.donnees() end end
end

test("la fiche du perso et l'export de l'HV prennent royaume, faction et maison de la lib", function()
    local lib = LibStub("LibCommune-1.0")
    lib:Souscrire("inventaires") -- la fiche n'est relevée que pour un type souscrit
    local fiche = export("perso")[lib.Personnage().guid].character
    assertType("table", fiche)
    assertEquals(lib.Royaume(), fiche.realm)
    assertEquals(lib.Faction(), fiche.faction)
    assertEquals(lib.MaisonHV(), export("hv").hv)
end)
