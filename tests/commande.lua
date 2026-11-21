-- /ac, la commande du socle (elle remplace /gdata) : résumé, souscriptions, export <clé> (LibCommune#33 : la liste à
-- cliquer est dans Diagnostic).

local function dire(cmd)
    local dits, garde = {}, print
    print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end dits[#dits + 1] = table.concat(t, " ") end
    local ok, err = pcall(SlashCmdList.AZEROTHCOMMUNE, cmd)
    print = garde
    assert(ok, err)
    return table.concat(dits, "\n")
end

test("/ac remplace /gdata", function()
    assertEquals("/ac", SLASH_AZEROTHCOMMUNE1)
    assertNil(SlashCmdList.GAMEDATA)
    assertNil(SLASH_GAMEDATA1)
end)

test("/ac : le résumé de la base", function()
    local dit = dire("")
    assertTrue(dit:find("Azeroth Commune : %d+ perso") ~= nil, dit)
    assertTrue(dit:find("/ac export", 1, true) ~= nil, dit)
end)

test("/ac souscriptions : chaque type, souscrit ou non", function()
    AzerothCommune:Souscrire("inventaires")
    local dit = dire("souscriptions")
    for nom in pairs(AzerothCommune.types) do assertTrue(dit:find(nom, 1, true) ~= nil, nom .. " dans : " .. dit) end
    assertTrue(dit:find("inventaires : souscrit le", 1, true) ~= nil, dit)
end)

test("/ac export sans clé : la liste des clés dans le chat", function()
    local liste = dire("export")
    for _, e in ipairs(AzerothCommune.Exports()) do
        assertTrue(liste:find(e.cle, 1, true) ~= nil, "clé " .. e.cle .. " dans : " .. liste)
    end
end)

test("/ac export <clé> : l'export déclaré, photographié sous le nom ac-<clé>", function()
    local lib = AzerothCommune
    local recu, nom
    local garde = lib.Exporter
    lib.Exporter = function(v, n) recu, nom = v, n end
    dire("export perso")
    lib.Exporter = garde
    assertEquals("ac-perso", nom)
    assertType("table", recu)
end)
