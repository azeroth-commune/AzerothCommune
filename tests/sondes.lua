-- Sondes d'identité dans wow-ui-sim (tools/sim.sh test LibCommune, LibCommune#30) : relancées après le chargement,
-- vertes. Une sonde rouge fait échouer le test en disant ce que le simulateur a rendu (rien n'est masqué).
-- Exceptions, chacune dite par son propre test (lacunes du simulateur, pas de la lib) :
--   * le simulateur ne donne pas de nom de famille au personnage par défaut (« Uther », il n'en donne qu'avec
--     WOW_SIM_WTF_CHARACTER=Prénom-Nom) : la sonde du nom y est rouge, à raison ;
--   * son GUID peut porter le numéro de serveur 0 (« Player-0-… ») : les sondes du royaume et de la maison de l'HV y
--     sont alors rouges, à raison (LibCommune#35 : le royaume est le numéro de serveur du GUID).
local IDENTITE = { "build", "royaume", "faction", "maison de l'HV", "GUID", "nom" }
local SANS_NOM_DE_FAMILLE = not select(2, UnitName("player"))
local NUMERO = tostring(UnitGUID("player")):match("^Player%-(%d+)%-")
local SERVEUR_0 = tonumber(NUMERO) == 0
local LACUNES = { nom = SANS_NOM_DE_FAMILLE, royaume = SERVEUR_0, ["maison de l'HV"] = SERVEUR_0 }

local function montrer(v)
    if type(v) ~= "table" then return tostring(v) == "" and '""' or tostring(v) end
    local t = {}
    for i = 1, v.n do t[i] = tostring(v[i]) end
    return table.concat(t, ", ")
end

test("sondes d'identité : vertes après le chargement (relancées)", function()
    local lib = LibStub("LibCommune-1.0")
    local etat, rouges = lib.RelancerSondes(), {}
    for _, nom in ipairs(IDENTITE) do
        local s = etat[nom]
        assertNotNil(s, "sonde déclarée : " .. nom)
        if s.etat ~= "vert" and not LACUNES[nom] then
            rouges[#rouges + 1] = ("%s %s (%s ; reçu %s, build %s)"):format(nom, s.etat, s.attente, montrer(s.valeur), tostring(s.build))
        end
    end
    if #rouges > 0 then error("sondes pas vertes dans le simulateur : " .. table.concat(rouges, " | "), 0) end
    assertNil(etat["royaume normalisé"], "plus de royaume normalisé (LibCommune#35)")
end)

test("royaume = numéro de serveur du GUID, maison de l'HV « n°-faction » ; numéro 0 du simulateur dit, pas masqué", function()
    local lib = LibStub("LibCommune-1.0")
    local guid = UnitGUID("player")
    assertType("string", guid)
    assertNotNil(NUMERO, "le simulateur rend un GUID d'une autre forme que Player-<n°>-… : " .. guid)
    assertEquals(NUMERO, lib.Royaume())
    assertEquals(NUMERO .. "-" .. lib.Faction(), lib.MaisonHV())
    assertNil(lib.RoyaumeNormalise)
    assertType("number", lib.Build())
    local etat = lib.Sondes()
    if SERVEUR_0 then
        print("LACUNE DU SIMULATEUR : UnitGUID(\"player\") = " .. guid .. ", numéro de serveur 0 ; sondes royaume et maison de l'HV rouges, à raison")
        assertEquals("rouge", etat.royaume.etat)
        assertEquals("rouge", etat["maison de l'HV"].etat)
    else
        assertEquals("vert", etat.royaume.etat)
        assertEquals("vert", etat["maison de l'HV"].etat)
    end
end)

test("nom : vert avec un nom de famille ; rouge si le simulateur n'en donne pas (lacune du simulateur, pas de la lib)", function()
    local lib = LibStub("LibCommune-1.0")
    local s = lib.RelancerSondes().nom
    local prenom, nomDeFamille = UnitName("player")
    assertType("string", prenom)
    if nomDeFamille and nomDeFamille ~= "" then
        assertEquals("vert", s.etat)
    else
        assertEquals("rouge", s.etat) -- la sonde voit le nom de famille manquant
        assertEquals(prenom, lib.Personnage().nom) -- et le relevé rend quand même le prénom, inchangé
    end
end)

-- Sondes des autres relevés (LibCommune#31) : déclarées par chaque fichier de la lib. Les sacs se relancent sans contexte
-- (un sac vide laisse la sonde de l'objet « pas encore vue ») ; les autres attendent leur contexte (fenêtre de métier,
-- objet en cache, fournisseur présent) et ne sont jamais rouges dans le simulateur.
local AUTRES = { "emplacements d'un conteneur", "objet d'un conteneur", "recettes", "nom d'objet", "prix Auctionator", "prix TSM", "prix AuctionDB" }

test("sondes des sacs, recettes, noms d'objets et fournisseurs : déclarées, aucune rouge après relance", function()
    local lib = LibStub("LibCommune-1.0")
    local etat, rouges = lib.RelancerSondes(), {}
    for _, nom in ipairs(AUTRES) do
        local s = etat[nom]
        assertNotNil(s, "sonde déclarée : " .. nom)
        assertType("string", s.attente)
        if s.etat == "rouge" then rouges[#rouges + 1] = ("%s (%s ; reçu %s)"):format(nom, s.attente, montrer(s.valeur)) end
    end
    if #rouges > 0 then error("sondes rouges dans le simulateur : " .. table.concat(rouges, " | "), 0) end
    assertEquals("vert", etat["emplacements d'un conteneur"].etat)
    print("objet d'un conteneur : " .. etat["objet d'un conteneur"].etat)
end)

test("sacs lus par la lib : la sonde de l'objet suit le premier objet vu", function()
    local lib = LibStub("LibCommune-1.0")
    local sacs = lib.Conteneurs(lib.EstSac)
    assertType("table", sacs)
    local premier
    for _, c in pairs(sacs) do premier = premier or c.items[1] end
    local s = lib.Sondes()["objet d'un conteneur"]
    if premier then assertEquals("vert", s.etat) else assertEquals("pas encore vue", s.etat) end
end)
