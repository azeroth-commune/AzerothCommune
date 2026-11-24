-- Écarts (#84) dans wow-ui-sim (tools/sim.sh test AzerothCommune) : un maître simulé (sa fenêtre bouchonnée, puis
-- TRAINER_SHOW) qui contredit la réserve des recettes livrée avec le socle.

-- Les fonctions du jeu remplacées le temps du test, rendues ensuite (même si le test échoue).
local function avec(bouchons, fn)
    local avant = {}
    for nom, f in pairs(bouchons) do avant[nom] = _G[nom]; _G[nom] = f end
    local ok, err = pcall(fn)
    for nom in pairs(bouchons) do _G[nom] = avant[nom] end
    assert(ok, err)
end

test("écarts : un maître simulé qui contredit la réserve est noté, et la donnée du joueur l'emporte", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("maîtres de métier"))
    local PNJ, guid = 99984, UnitGUID
    -- Ceinture runique en cuivre (2666, Forge, objet 2857) enseignée à la compétence 1 : la plus basse, elle gagne sur tout
    -- maître déjà relevé ; la réserve dit autre chose (45 par la règle du décalage le 24/11).
    avec({
        UnitGUID = function(u) if u == "npc" then return "Creature-0-1-2-3-" .. PNJ .. "-0" end return guid(u) end,
        GetNumTrainerServices = function() return 1 end,
        GetTrainerServiceInfo = function() return "Ceinture runique en cuivre", "", "available" end,
        GetTrainerServiceSkillReq = function() return "Forge", 1 end,
        GetTrainerServiceCost = function() return 0 end,
        GetTrainerServiceLevelReq = function() return 1 end,
        GetTrainerServiceItemLink = function() return "|cffffffff|Hitem:2857::::::::|h[Ceinture runique en cuivre]|h|r" end,
    }, function() FireEvent("TRAINER_SHOW") end)
    local ecart
    for _, e in ipairs(lib.Ecarts()) do if e.pnj == PNJ then ecart = e end end
    assertNotNil(ecart, "écart noté")
    assertEquals("compétence", ecart.genre)
    assertEquals(2666, ecart.recette)
    assertEquals("Ceinture runique en cuivre", ecart.nom)
    assertType("number", ecart.attendu)
    assertTrue(ecart.attendu ~= 1, "attendu : " .. tostring(ecart.attendu))
    assertEquals(1, ecart.vu)
    assertType("string", ecart.date)
    local base = lib:Lire("base des recettes")
    assertEquals(1, base[2666].level)
    assertEquals("relevé direct", base[2666].level_provenance)
    -- Rien ne reste pour les tests suivants (le maître simulé et son écart, dans la base).
    AzerothCommuneDB.trainers[PNJ], AzerothCommuneDB.ecarts["compétence:2666:" .. PNJ] = nil, nil
end)
