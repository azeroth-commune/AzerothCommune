-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test AzerothCommune). Le catalogue des objets (CatalogueObjets.lua,
-- #52) est généré et hors du repo (tools/build_item_catalog.py de l'atelier) : à générer ou copier dans une branche en worktree.
test("catalogue des objets : chargé par la TOC, il complète les objets relevés ; la recherche trouve un objet ni vu ni fabricable", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("objets"))
    assertTrue(lib:Souscrire("base des recettes"))
    local objets = lib:Lire("objets")
    assertNotNil(objets, "objets vides (CatalogueObjets.lua présent ?)")
    local fabrique = {}
    for _, r in pairs(lib:Lire("base des recettes") or {}) do if r.output then fabrique[r.output] = true end end
    -- L'objet du catalogue au plus petit ID qui n'est ni relevé ni fabriqué (les SavedVariables du jeu sont lues).
    local n, cible = 0, nil
    for id, it in pairs(objets) do
        if it.provenance == "extrait du client" then
            n = n + 1
            assertType("string", it.name)
            assertType("number", it.quality)
            if not fabrique[id] and (not cible or id < cible) then cible = id end
        end
    end
    assertTrue(n > 15000, "catalogue chargé : " .. n .. " objets extraits du client")
    assertTrue(not objets[77] or objets[77].provenance == nil, "objet périmé écarté du catalogue ([PÉRIMÉ] Jacque de tailleur en tissu)")
    local nom = objets[cible].name
    local trouve = false
    for _, e in ipairs(lib.ChercherObjets(nom, 100)) do trouve = trouve or (e.id == cible and not e.fabricable) end
    assertTrue(trouve, "trouvé par son nom : " .. cible .. " " .. nom)
    print(("catalogue des objets : %d objets extraits du client ; « %s » (%d), ni vu ni fabricable, trouvé"):format(n, nom, cible))
end)
