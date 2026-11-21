-- Sondes d'identité dans wow-ui-sim (tools/sim.sh test LibCommune, LibCommune#30) : relancées après le chargement,
-- vertes. Une sonde rouge fait échouer le test en disant ce que le simulateur a rendu (un royaume vide n'est pas masqué).
-- Seule exception, dite par son propre test : le simulateur ne donne pas de nom de famille au personnage par défaut
-- (« Uther », il n'en donne qu'avec WOW_SIM_WTF_CHARACTER=Prénom-Nom), la sonde du nom y est donc rouge, à raison.
local IDENTITE = { "build", "royaume", "royaume normalisé", "faction", "maison de l'HV", "GUID", "nom" }
local SANS_NOM_DE_FAMILLE = not select(2, UnitName("player"))

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
        if s.etat ~= "vert" and not (nom == "nom" and SANS_NOM_DE_FAMILLE) then
            rouges[#rouges + 1] = ("%s %s (%s ; reçu %s, build %s)"):format(nom, s.etat, s.attente, montrer(s.valeur), tostring(s.build))
        end
    end
    if #rouges > 0 then error("sondes pas vertes dans le simulateur : " .. table.concat(rouges, " | "), 0) end
end)

test("royaume, royaume normalisé, maison de l'HV rendus par la lib, et non vides", function()
    local lib = LibStub("LibCommune-1.0")
    local royaume = lib.Royaume()
    assertType("string", royaume)
    assertTrue(royaume ~= "", "le simulateur rend un royaume vide (GetRealmName)")
    assertTrue(lib.RoyaumeNormalise() ~= "", "le simulateur rend un royaume normalisé vide (GetNormalizedRealmName)")
    assertEquals(royaume .. "-" .. lib.Faction(), lib.MaisonHV())
    assertType("number", lib.Build())
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
