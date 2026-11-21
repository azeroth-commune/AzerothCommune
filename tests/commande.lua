-- /gdata export sans fenêtre (LibCommune#33) : la liste à cliquer est dans Diagnostic ; GameData garde la commande.

test("/gdata export sans clé : la liste des clés dans le chat, plus de fenêtre GameData", function()
    local dits, garde = {}, print
    print = function(m) dits[#dits + 1] = tostring(m) end
    local ok, err = pcall(SlashCmdList.GAMEDATA, "export")
    print = garde
    assert(ok, err)
    assertNil(GameDataExportFrame)
    local liste = table.concat(dits, "\n")
    for _, e in ipairs(LibStub("LibCommune-1.0").Exports()) do
        assertTrue(liste:find(e.cle, 1, true) ~= nil, "clé " .. e.cle .. " dans : " .. liste)
    end
end)

test("/gdata export <clé> : l'export déclaré, photographié par la lib", function()
    local lib = LibStub("LibCommune-1.0")
    local recu, nom
    local garde = lib.Exporter
    lib.Exporter = function(v, n) recu, nom = v, n end
    SlashCmdList.GAMEDATA("export perso")
    lib.Exporter = garde
    assertEquals("gamedata-perso", nom)
    assertType("table", recu)
end)
