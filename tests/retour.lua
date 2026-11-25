-- /ac retour : la fenêtre du rapport à copier (versions, sondes rouges, erreurs de relevé, erreurs Lua de nos add-ons).

local function rapport()
    SlashCmdList.AZEROTHCOMMUNE("retour")
    local f = _G.AzerothCommuneRetour
    assertNotNil(f, "fenêtre créée")
    assertTrue(f:IsShown(), "fenêtre montrée")
    return _G.AzerothCommuneRetourTexte:GetText()
end

test("/ac retour : le rapport dit le client, nos add-ons et leurs versions, sans nom de perso", function()
    local t = rapport()
    assertTrue(t:find("Client ", 1, true) ~= nil, t)
    assertTrue(t:find("AzerothCommune " .. C_AddOns.GetAddOnMetadata("AzerothCommune", "Version"), 1, true) ~= nil, t)
    assertTrue(t:find("Sondes rouges : ", 1, true) ~= nil, t)
    assertNil(t:find(UnitName("player"), 1, true), "pas de nom de perso")
    _G.AzerothCommuneRetour:Hide()
end)

test("/ac retour : une erreur Lua d'un de nos add-ons y est, celle d'un autre add-on non", function()
    local h = geterrorhandler()
    h("Interface/AddOns/AzerothCommune/Base.lua:1: erreur de test du retour")
    h("Interface/AddOns/AutreAddOn/X.lua:1: erreur d'un autre")
    h("Interface/AddOns/AzerothCommune/Base.lua:1: erreur de test du retour")
    local t = rapport()
    assertTrue(t:find("2×] Interface/AddOns/AzerothCommune/Base.lua:1: erreur de test du retour", 1, true) ~= nil, t)
    assertNil(t:find("erreur d'un autre", 1, true), t)
    _G.AzerothCommuneRetour:Hide()
end)
