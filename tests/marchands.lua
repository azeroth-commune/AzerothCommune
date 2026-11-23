-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test AzerothCommune). La base VendorData.lua est générée
-- (tools/build_vendor_data.py de l'atelier) et commitée : une source par objet selon sa catégorie (#82).
test("marchands de la base : revente, taille de pile, et seulement les PNJ amicaux pour ta faction", function()
    local m = AzerothCommune:Lire("marchands")
    assertType("table", m)
    -- 982 n'est amical que pour la Horde, 1464 que pour l'Alliance (QuestieDB) ; tous deux vendent la viande séchée (117).
    local horde = UnitFactionGroup("player") == "Horde"
    local ami, adverse = m[horde and 982 or 1464], m[horde and 1464 or 982]
    assertNil(adverse)
    assertType("table", ami)
    local ligne
    for _, it in ipairs(ami.items) do if it.id == 117 then ligne = it end end
    assertType("table", ligne)
    assertEquals(25, ligne.price)
    assertEquals(5, ligne.stack)
    assertTrue(ligne.sell > 0)
    assertEquals(20, ligne.maxStack)
end)

local function vend(m, pnj, id)
    for _, it in ipairs((m[pnj] or {}).items or {}) do if it.id == id then return true end end
    return false
end

test("partage par catégorie : un composant d'après Fabrikao seul, jamais les marchands de QuestieDB en plus", function()
    local m = AzerothCommune:Lire("marchands")
    -- Bûches épaisses (272941), composant ajouté par Forever : 2664 (neutre) le vend d'après Fabrikao ; 242498 (amical pour
    -- les deux) le vend d'après QuestieDB seulement, qui ne fait pas foi pour un composant. 242498 vend d'autres objets.
    assertTrue(vend(m, 2664, 272941))
    assertType("table", m[242498])
    assertFalse(vend(m, 242498, 272941))
end)

test("prix d'achat marchand : un composant propre à Forever et un objet hors artisanat", function()
    local lib = AzerothCommune
    local pm = lib:PrixMarchands()
    assertTrue(pm[272941] > 0) -- Bûches épaisses : Fabrikao
    local c, src = lib:PrixAchat(272941, 3, {}, pm)
    assertEquals("marchand", src)
    assertEquals(3 * pm[272941], c)
    c, src = lib:PrixAchat(2512, 400, {}, pm) -- Flèche grossière (munitions), QuestieDB : 10 pc les 200
    assertEquals("marchand", src)
    assertEquals(20, c)
end)
