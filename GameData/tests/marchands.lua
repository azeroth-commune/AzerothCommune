-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test GameData). La base VendorData.lua est générée et hors du repo
-- (tools/build_vendor_data.py) : à générer ou copier dans une branche en worktree.
test("marchands de la base : revente, taille de pile, et seulement les PNJ amicaux pour ta faction", function()
    local m = LibStub("LibCommune-1.0"):Lire("marchands")
    assertType("table", m)
    -- 982 n'est amical que pour la Horde, 151 que pour l'Alliance (QuestieDB) ; tous deux vendent l'objet 159.
    local horde = UnitFactionGroup("player") == "Horde"
    local ami, adverse = m[horde and 982 or 151], m[horde and 151 or 982]
    assertNil(adverse)
    assertType("table", ami)
    local ligne
    for _, it in ipairs(ami.items) do if it.id == 159 then ligne = it end end
    assertType("table", ligne)
    assertEquals(25, ligne.price)
    assertEquals(5, ligne.stack)
    assertTrue(ligne.sell > 0)
    assertEquals(20, ligne.maxStack)
end)
