-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test AzerothCommune) : le socle chargé dans l'interface Forever
-- simulée, son API publique par le global AzerothCommune.
-- L'API publique, sous les noms de l'ancienne lib ; ni LibStub("LibCommune-1.0") ni GameDataAPI (ADR 0002).
local API = { "Lire", "Souscrire", "QuandReleve", "Signaler", "Personnage", "Destinataire", "Royaume", "MaisonHV", "Faction",
    "Build", "Sondes", "RelancerSondes", "DeclarerSonde", "Sonder", "Conteneurs", "EstSac", "EstBanque", "Fusionner",
    "PrixAchat", "PrixMarchands", "Fenetre", "Tableau", "TrierLignes", "Argent", "ArgentCourt", "ArgentSigne", "NomObjet",
    "RetenirObjet", "TrouverObjet", "ChercherObjets", "Capturer", "BoutonCapture", "Exporter", "JsonSur", "Regrouper", "Exports" }

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

-- #48, #54 : la réserve extraite du client (RecettesClassic.lua, générée, hors du repo : à copier dans un worktree) est
-- chargée par la TOC du socle, privée ; elle se lit par la base des recettes, chaque recette avec sa provenance, sa
-- compétence requise et ses seuils jaune et gris.
local SOURCES = { ["d'emblée"] = true, ["maître"] = true, ["patron vendu"] = true, ["retirée"] = true, inconnue = true }
test("base des recettes : la réserve du socle chargée, chaque recette avec sa provenance", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    assertNil(HandshakeClassicRecipes)
    local data, lot = lib:Lire("base des recettes")
    assertNotNil(data, "base des recettes vide (RecettesClassic.lua présent ?)")
    assertType("table", lot)
    local reserve, vues = 0, 0
    for _, r in pairs(data) do
        if r.provenance == "extrait du client" then
            reserve = reserve + 1
            if r.output ~= nil then assertType("number", r.output) end -- nil : un enchantement (#64)
            assertType("string", r.profession)
            assertType("table", r.reagents)
            assertType("number", r.level) -- 0 : inconnue (Bottes d'hiver 44953 : absente de Classic, sans seuils dans le client)
            assertTrue(r.grey >= r.yellow, "seuils : " .. tostring(r.name))
            assertTrue(SOURCES[r.source], "source : " .. tostring(r.name) .. " " .. tostring(r.source))
            assertTrue(r.source_provenance == "extrait du client" or r.source_provenance == "source externe")
            assertType("number", r.cooldown)
            assertTrue(r.yellow <= 0 or r.level <= r.yellow, "compétence au-dessus du jaune (#62) : " .. tostring(r.name))
            assertEquals(r.source == "patron vendu", r.pattern_price ~= nil)
        else
            vues = vues + 1
        end
    end
    assertTrue(reserve > 1000, "réserve chargée : " .. reserve .. " recettes")
    -- Une recette propre à Forever (potion de soins inférieure, passée au secourisme), absente de Classic.
    local potion = data[1244432]
    assertTrue(potion ~= nil and potion.profession == "Secourisme" and potion.output == 858, "recette de Forever")
    print("base des recettes : " .. vues .. " vue(s), " .. reserve .. " de la réserve")
end)

-- #64 : source, compétence pour l'apprendre, prix du patron et temps de recharge, sur les exemples vérifiés de l'issue ;
-- les enchantements d'objet entrent dans la réserve, sans objet produit.
test("base des recettes : source, compétence, patron et recharge de chaque recette", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("base des recettes"))
    local data = lib:Lire("base des recettes")
    local rouleau, robe, lunaire = data[18401], data[18406], data[18560]
    assertEquals("maître", rouleau.source) -- Rouleau d'étoffe runique
    assertTrue(rouleau.level <= 210, "compétence du rouleau : " .. rouleau.level)
    assertEquals("patron vendu", robe.source) -- Robe en étoffe runique
    assertTrue(robe.pattern_price > 0)
    assertTrue(math.abs(lunaire.cooldown - 95 * 3600) < 3600, "recharge de l'étoffe lunaire : " .. lunaire.cooldown)
    assertEquals("inconnue", data[19435].source) -- Bottes en étoffe lunaire (recette de quête)
    assertEquals("d'emblée", data[2149].source) -- Bottes en cuir cousu main
    assertEquals("extrait du client", data[2149].source_provenance)
    local ench = data[13501] -- Ench. de bracelets (Endurance inférieure)
    assertNotNil(ench, "enchantement dans la réserve")
    assertNil(ench.output)
    assertEquals("Enchantement", ench.profession)
    assertTrue(#ench.reagents > 0 and ench.yellow > 0 and ench.grey >= ench.yellow)
    assertEquals("maître", ench.source)
end)

-- #49 : la recherche d'objets de la suite, parmi les objets vus et les objets fabriqués de la base des recettes.
test("recherche d'objets : objets fabriqués de la base des recettes, sans doublon, en nombre limité", function()
    local lib = AzerothCommune
    assertTrue(lib:Souscrire("objets"))
    assertTrue(lib:Souscrire("base des recettes"))
    local trouves = lib.ChercherObjets("bronze")
    assertEquals(8, #trouves)
    local vus = {}
    for _, e in ipairs(trouves) do
        assertType("number", e.id)
        assertType("string", e.name)
        assertNil(vus[e.id], "doublon : " .. e.id)
        vus[e.id] = true
    end
    assertTrue(trouves[1].fabricable, "fabricables d'abord")
    local pantalon = false
    for _, e in ipairs(lib.ChercherObjets("cuir cousu main", 30)) do pantalon = pantalon or e.id == 2303 end
    assertTrue(pantalon, "objet de la réserve trouvé par le nom de sa recette")
    assertEquals(0, #lib.ChercherObjets("b"))
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
