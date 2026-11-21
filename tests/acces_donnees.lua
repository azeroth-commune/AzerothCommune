-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test AzerothCommune) : le socle chargé dans l'interface Forever
-- simulée, son API publique par le global AzerothCommune.
-- L'API publique, sous les noms de l'ancienne lib ; ni LibStub("LibCommune-1.0") ni GameDataAPI (ADR 0002).
local API = { "Lire", "Souscrire", "QuandReleve", "Signaler", "Personnage", "Destinataire", "Royaume", "MaisonHV", "Faction",
    "Build", "Sondes", "RelancerSondes", "DeclarerSonde", "Sonder", "Conteneurs", "EstSac", "EstBanque", "Fusionner",
    "PrixAchat", "PrixMarchands", "Fenetre", "Tableau", "TrierLignes", "Argent", "ArgentCourt", "ArgentSigne", "NomObjet",
    "RetenirObjet", "TrouverObjet", "Capturer", "BoutonCapture", "Exporter", "JsonSur", "Regrouper", "Exports" }

test("le global AzerothCommune porte l'API publique ; plus de LibCommune ni de GameDataAPI", function()
    assertType("table", AzerothCommune)
    for _, nom in ipairs(API) do assertType("function", AzerothCommune[nom]) end
    assertNil(GameDataAPI)
    assertNil(LibStub and LibStub("LibCommune-1.0", true))
    assertNil(AzerothCommune.versions)
    assertNil(AzerothCommune.listeSondes)
end)

test("type inconnu : indisponible avec raison", function()
    local lib = AzerothCommune
    local data, raison = lib:Lire("pas un type")
    assertNil(data)
    assertEquals("type inconnu", raison)
end)

test("recettes connues : données ou raison connue", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("recettes connues"))
    local data, raison = lib:Lire("recettes connues", "tous")
    if data then
        assertType("table", data.recettes)
        local n = 0 for _ in pairs(data.persos) do n = n + 1 end
        print("recettes connues : " .. n .. " personnage(s) lus dans la base")
    else
        assertEquals("pas encore relevé", raison)
        print("recettes connues indisponibles : " .. raison)
    end
end)

test("recettes connues sans fenêtre : l'API de Forever est là et le relevé tourne", function()
    assertType("function", IsPlayerSpell)
    assertType("function", GetProfessions)
    assertType("function", GetProfessionInfo)
    local lib = AzerothCommune
    local metiers, fini = {}, false
    -- sans métier, aucune recette candidate : le relevé finit tout de suite
    local ok = lib:ReleverRecettesSansFenetre(metiers, {}, function() fini = true end)
    assertTrue(ok)
    if next({ GetProfessions() }) == nil then assertTrue(fini) end
    assertNil(lib.RemettreRecettes) -- plus de remise par un add-on (#48)
end)

-- #48 : la réserve Classic (RecettesClassic.lua, générée, hors du repo : à copier dans un worktree) est chargée par la TOC
-- du socle, privée ; elle se lit par la base des recettes, chaque recette avec sa provenance.
test("base des recettes : la réserve du socle chargée, chaque recette avec sa provenance", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    assertNil(HandshakeClassicRecipes)
    local data, lot = lib:Lire("base des recettes")
    assertNotNil(data, "base des recettes vide (RecettesClassic.lua présent ?)")
    assertType("table", lot)
    local reserve, vues = 0, 0
    for _, r in pairs(data) do
        if r.provenance == "source externe" then
            reserve = reserve + 1
            assertType("number", r.output)
            assertType("string", r.profession)
            assertType("table", r.reagents)
        else
            vues = vues + 1
        end
    end
    assertTrue(reserve > 500, "réserve chargée : " .. reserve .. " recettes")
    print("base des recettes : " .. vues .. " vue(s), " .. reserve .. " de la réserve")
end)

test("catalogue : chaque type se lit dans la base, ou pas encore relevé", function()
    local lib = AzerothCommune
    for nom, t in pairs(lib.types) do
        local data, raison = lib:Lire(nom, "tous")
        if not data then assertEquals("pas encore relevé", raison) end
    end
end)

test("souscription retenue par la base avec sa date, pour tout le joueur", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("marchands"))
    assertType("number", AzerothCommuneDB.souscriptions.marchands)
end)

test("provenance : chaque type lu rend son lot, au build du client simulé", function()
    assertType("function", GetBuildInfo)
    local version, build = GetBuildInfo()
    assertType("string", version)
    assertNotNil(tonumber(build))
    assertType("table", AzerothCommuneDB.lots) -- lots vérifiés au chargement de la base
    local lib = AzerothCommune
    for nom, t in pairs(lib.types) do
        local data, l = lib:Lire(nom, "tous")
        if data and not t.parPerso then assertType("table", l) end
        if data and t.parPerso then assertType("table", l.persos) end
    end
end)

test("sacs lus à l'instant : l'API des conteneurs de Forever est là", function()
    local lib = AzerothCommune
    assertType("table", Enum.BagIndex)
    assertType("function", lib.Conteneurs)
    local sacs = lib.Conteneurs(lib.EstSac)
    assertType("table", sacs)
    for nom, sac in pairs(sacs) do
        assertTrue(lib.EstSac(nom))
        assertType("number", sac.size)
        assertType("table", sac.items)
        for _, it in ipairs(sac.items) do -- chaque objet : son ID, sa quantité et son lien (LibCommune#20)
            assertType("number", it.id)
            assertType("number", it.count)
            assertType("string", it.link)
        end
    end
end)

test("signal « type relevé à nouveau » : les rappels appelés, sans crochet (le scan de l'HV lui-même : check.lua)", function()
    local lib = AzerothCommune
    local _, raison = lib:QuandReleve("pas un type", print)
    assertEquals("type inconnu", raison)
    local recus, actif = {}, true
    local function rappel(t) if actif then recus[#recus + 1] = t end end -- les rappels sont privés (#45) : il se tait
    assertTrue(lib:QuandReleve("cours de l'HV", rappel))
    assertNil(lib.AccrocherGameData)
    assertNil(lib.rappels)
    lib:Signaler("cours de l'HV")
    actif = false
    assertEquals(1, #recus)
    assertEquals("cours de l'HV", recus[1])
end)

test("personnage connecté : GUID et nom, plus d'adresse ; chuchoté par son nom complet", function()
    local lib = AzerothCommune
    local p = lib.Personnage()
    assertType("string", p.guid)
    assertEquals(UnitGUID("player"), p.guid)
    assertType("string", p.nom)
    assertNil(p.adresse)
    assertEquals(p.nom, lib.Destinataire(p.nom))
    print("personnage : " .. p.guid .. " / " .. p.nom)
end)

test("lire par GUID : persos rangé par GUID", function()
    local lib = AzerothCommune
    local data = lib:Lire("inventaires", "tous")
    if not data then lib:Souscrire("inventaires"); SlashCmdList.AZEROTHCOMMUNE("") data = lib:Lire("inventaires", "tous") end -- /ac : relevé tout de suite
    assertNotNil(data, "inventaires relevés par la base")
    local n = 0
    for cle in pairs(data.persos) do n = n + 1; assertTrue(cle:find("^Player%-") ~= nil, "clé " .. cle) end
    assertTrue(n > 0, "au moins le personnage connecté")
    local moi = lib:Lire("inventaires", UnitGUID("player"))
    assertNotNil(moi and moi.persos[UnitGUID("player")], "lu par son GUID")
    assertEquals(lib.Personnage().nom, moi.persos[UnitGUID("player")].character.name)
end)

test("prix d'achat exposé par la lib : un coût ou rien, sans erreur", function()
    local lib = AzerothCommune
    assertType("function", lib.PrixAchat)
    assertType("table", lib:PrixMarchands())
    local c, src = lib:PrixAchat(2772, 5)
    if c then assertType("number", c); assertTrue(src == "marchand" or src == "HV") end
    assertEquals(300, (lib:PrixAchat(1, 3, { [1] = { min = 100 } }, {})))
end)
