-- Lectures « munitions » et « aspect » du cœur de combat (BeAGoodPal#27) : les réponses du jeu (UnitUsesAmmo,
-- GetInventoryItemID, GetInventoryItemCount, C_Item.GetItemCount ; C_Spell.GetSpellName,
-- C_UnitAuras.GetAuraDataBySpellName, C_Secrets.ShouldSpellAuraBeSecret, InCombatLockdown ; issecretvalue) sont
-- remplacées le temps d'un test.
local SECRET = {} -- la valeur témoin que l'issecretvalue remplacé reconnaît
local RIEN = {} -- remplace par nil
local AMMO = 0 -- INVSLOT_AMMO
-- Les aspects par l'ID de leur premier rang : leur nom (le client en donne un par langue) est ce qui est cherché dans
-- les auras, pour tous les rangs.
local ASPECTS = { [13165] = "Aspect du faucon", [13163] = "Aspect du singe", [5118] = "Aspect du guépard",
                  [13159] = "Aspect de la meute", [13161] = "Aspect de la bête", [20043] = "Aspect de la nature" }

-- Pose les remplacements (« nom » ou « table.champ » → valeur) le temps de fn, puis remet tout, même si fn échoue.
local function avec(jeu, fn)
    local remettre = {}
    for cle, v in pairs(jeu) do
        local nom, champ = cle:match("^([^.]+)%.?(.*)$")
        local t, k = _G, nom
        if champ ~= "" then
            if _G[nom] == nil then _G[nom] = {}; remettre[#remettre + 1] = function() _G[nom] = nil end end
            t, k = _G[nom], champ
        end
        local avant = t[k]
        if v == RIEN then v = nil end
        t[k] = v
        table.insert(remettre, 1, function() t[k] = avant end)
    end
    local ok, err = pcall(fn)
    for _, f in ipairs(remettre) do f() end
    assert(ok, err)
end

local function suiveur()
    local recu = {}
    return recu, function(v) recu[#recu + 1] = v == nil and "nil" or v end
end

-- La valeur rendue tout de suite à un nouveau suiveur de lecture, avec ces réponses du jeu.
local function lire(lecture, jeu)
    local recu, fn = suiveur()
    avec(jeu, function()
        assertTrue(AzerothCommune:Suivre(lecture, fn))
        AzerothCommune:NePlusSuivre(lecture, fn)
    end)
    assertEquals(1, #recu, "rappelé une fois, tout de suite")
    if recu[1] ~= "nil" then return recu[1] end
end

-- Munitions. r = { utilise, id (l'objet de l'emplacement), compte (de l'emplacement), sacs (le compte de cet objet) }
local function munitions(r)
    return {
        UnitUsesAmmo = function(u) if u == "player" then return r.utilise end end,
        GetInventoryItemID = function(u, slot) if u == "player" and slot == AMMO then return r.id end end,
        GetInventoryItemCount = function(u, slot) if u == "player" and slot == AMMO then return r.compte end end,
        ["C_Item.GetItemCount"] = function(id) if id == r.id then return r.sacs end end,
        issecretvalue = function(v) return v == SECRET end,
    }
end

test("munitions : le compte de l'emplacement, sinon celui de cet objet dans les sacs ; 0 sans munitions placées ; false si l'arme n'en utilise pas", function()
    assertEquals(812, lire("munitions", munitions { utilise = true, id = 2512, compte = 812, sacs = 812 }))
    -- L'emplacement répond 1 (ou rien, ou un secret) : le compte de cet objet dans les sacs.
    assertEquals(640, lire("munitions", munitions { utilise = true, id = 2512, compte = 1, sacs = 640 }))
    assertEquals(640, lire("munitions", munitions { utilise = true, id = 2512, compte = SECRET, sacs = 640 }))
    assertEquals(1, lire("munitions", munitions { utilise = true, id = 2512, compte = 1, sacs = 1 }))
    assertEquals(0, lire("munitions", munitions { utilise = true, id = nil }), "emplacement vide : rien à tirer")
    assertEquals(false, lire("munitions", munitions { utilise = false, id = 2512, compte = 812, sacs = 812 }))
end)

test("munitions inconnues (nil, jamais 0 deviné) : l'arme ne dit pas, ou le compte ne répond pas", function()
    assertNil(lire("munitions", munitions { utilise = nil, id = 2512, compte = 812, sacs = 812 }))
    assertNil(lire("munitions", munitions { utilise = SECRET, id = 2512, compte = 812, sacs = 812 }))
    assertNil(lire("munitions", munitions { utilise = true, id = SECRET, compte = 812, sacs = 812 }))
    assertNil(lire("munitions", munitions { utilise = true, id = 2512, compte = SECRET, sacs = SECRET }))
    assertNil(lire("munitions", munitions { utilise = true, id = 2512, compte = nil, sacs = nil }))
end)

-- Espionne RegisterEvent, RegisterUnitEvent et UnregisterEvent des cadres le temps de fn(notes) ; note « +EV » ou
-- « +EV unité » ou « -EV ».
local function espionner(fn)
    local m = getmetatable(CreateFrame("Frame")).__index
    local reg, unit, unreg, notes = m.RegisterEvent, m.RegisterUnitEvent, m.UnregisterEvent, {}
    m.RegisterEvent = function(self, ev, ...) notes[#notes + 1] = "+" .. ev; return reg(self, ev, ...) end
    m.RegisterUnitEvent = function(self, ev, u, ...) notes[#notes + 1] = "+" .. ev .. " " .. tostring(u); return unit(self, ev, u, ...) end
    m.UnregisterEvent = function(self, ev, ...) notes[#notes + 1] = "-" .. ev; return unreg(self, ev, ...) end
    local ok, err = pcall(fn, notes)
    m.RegisterEvent, m.RegisterUnitEvent, m.UnregisterEvent = reg, unit, unreg
    assert(ok, err)
end

local function contient(notes, x)
    for _, n in ipairs(notes) do if n == x then return true end end
    return false
end

test("munitions : relues aux changements de sacs et d'équipement, écoutés seulement pendant le suivi", function()
    local AC = AzerothCommune
    local r = { utilise = true, id = 2512, compte = 812, sacs = 812 }
    avec(munitions(r), function()
        espionner(function(notes)
            local recu, fn = suiveur()
            assertTrue(AC:Suivre("munitions", fn))
            assertTrue(contient(notes, "+BAG_UPDATE"), table.concat(notes, " "))
            assertTrue(contient(notes, "+PLAYER_EQUIPMENT_CHANGED"), table.concat(notes, " "))
            assertTrue(contient(notes, "+UNIT_INVENTORY_CHANGED player"), "seulement pour le joueur : " .. table.concat(notes, " "))
            r.compte, r.sacs = 811, 811
            FireEvent("BAG_UPDATE", 4)
            assertEquals(811, recu[2])
            r.utilise = false
            FireEvent("PLAYER_EQUIPMENT_CHANGED", 18, false)
            assertEquals(false, recu[3])
            assertTrue(AC:NePlusSuivre("munitions", fn))
            assertTrue(contient(notes, "-BAG_UPDATE") and contient(notes, "-UNIT_INVENTORY_CHANGED"), table.concat(notes, " "))
            r.utilise = true
            FireEvent("BAG_UPDATE", 4)
            assertEquals(3, #recu, "plus suivi : plus rappelé")
        end)
    end)
end)

local function noteParLaSonde(s, x)
    for i = 1, (s.valeur and s.valeur.n or 0) do if s.valeur[i] == x then return true end end
    return false
end

test("sonde des munitions : verte sur des réponses attendues, rouge sur un secret, une erreur ou une fonction disparue", function()
    local AC = AzerothCommune
    assertEquals(812, lire("munitions", munitions { utilise = true, id = 2512, compte = 812, sacs = 812 }))
    local s = AC.Sondes()["munitions"]
    assertNotNil(s, "sonde déclarée")
    assertType("string", s.attente)
    assertEquals("vert", s.etat)
    assertEquals(0, lire("munitions", munitions { utilise = true, id = nil }))
    assertEquals("vert", AC.Sondes()["munitions"].etat, "emplacement vide : une réponse attendue")
    assertEquals(640, lire("munitions", munitions { utilise = true, id = 2512, compte = SECRET, sacs = 640 }))
    s = AC.Sondes()["munitions"]
    assertEquals("rouge", s.etat)
    assertTrue(noteParLaSonde(s, "secret"), "la sonde note le secret, pas la valeur")
    local j = munitions { utilise = true, id = 2512, compte = 812, sacs = 812 }
    j.GetInventoryItemCount = function() error("API changée") end
    assertEquals(812, lire("munitions", j))
    assertEquals("rouge", AC.Sondes()["munitions"].etat)
    j = munitions { utilise = true, id = 2512, compte = 812, sacs = 812 }
    j.UnitUsesAmmo = RIEN
    assertNil(lire("munitions", j))
    s = AC.Sondes()["munitions"]
    assertEquals("rouge", s.etat)
    assertTrue(noteParLaSonde(s, "absente"), "la sonde note la fonction absente")
end)

-- Aspect. r = { actif = ID du premier rang de l'aspect présent (ou SECRET : réponse secrète), combat, secret = ce que
-- rend ShouldSpellAuraBeSecret, filtres = { notés } }
local function aspect(r)
    r.filtres = {}
    return {
        ["C_Spell.GetSpellName"] = function(id) return ASPECTS[id] end,
        ["C_UnitAuras.GetAuraDataBySpellName"] = function(u, nom, filtre)
            r.filtres[#r.filtres + 1] = filtre
            if u ~= "player" then return nil end
            if r.actif == SECRET then return SECRET end
            if r.actif and ASPECTS[r.actif] == nom then return { name = nom, spellId = 14320 } end
        end,
        ["C_Secrets.ShouldSpellAuraBeSecret"] = function(id) if ASPECTS[id] then return r.secret end end,
        InCombatLockdown = function() return r.combat end,
        issecretvalue = function(v) return v == SECRET end,
    }
end

test("aspect : l'actif (tous rangs, par son nom), les tiens seulement ; « aucun » quand le jeu le dit", function()
    local noms = { [13165] = "faucon", [13163] = "singe", [5118] = "guépard", [13159] = "meute", [13161] = "bête", [20043] = "nature" }
    for id, nom in pairs(noms) do
        assertEquals(nom, lire("aspect", aspect { actif = id, combat = false, secret = false }))
        assertEquals(nom, lire("aspect", aspect { actif = id, combat = true, secret = true }), "trouvé en combat : " .. nom)
    end
    local r = { actif = 13165, combat = false, secret = false }
    lire("aspect", aspect(r))
    for _, f in ipairs(r.filtres) do assertEquals("HELPFUL|PLAYER", f, "la Meute d'un autre chasseur ne compte pas") end
    -- Rien trouvé hors combat : aucun ; en combat, seulement si le jeu dit que ces auras ne sont pas secrètes.
    assertEquals("aucun", lire("aspect", aspect { combat = false, secret = true }))
    assertEquals("aucun", lire("aspect", aspect { combat = true, secret = false }))
end)

test("aspect inconnu (nil, jamais « aucun » deviné) : réponse secrète, ou rien trouvé en combat sans que le jeu dise que c'est lisible", function()
    assertNil(lire("aspect", aspect { actif = SECRET, combat = false, secret = false }))
    assertNil(lire("aspect", aspect { combat = true, secret = true }))
    assertNil(lire("aspect", aspect { combat = true, secret = nil }))
    local j = aspect { combat = false, secret = false }
    j["C_Spell.GetSpellName"] = function() return nil end -- un ID que ce client ne connaît pas
    assertNil(lire("aspect", j))
end)

test("aspect : relu à UNIT_AURA du joueur seulement, et à la fin du combat ; écouté seulement pendant le suivi", function()
    local AC = AzerothCommune
    local r = { actif = 13165, combat = false, secret = false }
    avec(aspect(r), function()
        espionner(function(notes)
            local recu, fn = suiveur()
            assertTrue(AC:Suivre("aspect", fn))
            assertTrue(contient(notes, "+UNIT_AURA player"), table.concat(notes, " "))
            assertTrue(contient(notes, "+PLAYER_REGEN_ENABLED"), table.concat(notes, " "))
            assertEquals("faucon", recu[1])
            r.actif = 5118
            FireEvent("UNIT_AURA", "player")
            assertEquals("guépard", recu[2])
            r.actif, r.combat, r.secret = nil, true, true
            FireEvent("UNIT_AURA", "player")
            assertEquals("nil", recu[3])
            r.combat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            assertEquals("aucun", recu[4])
            assertTrue(AC:NePlusSuivre("aspect", fn))
            assertTrue(contient(notes, "-UNIT_AURA") and contient(notes, "-PLAYER_REGEN_ENABLED"), table.concat(notes, " "))
            r.actif = 13163
            FireEvent("UNIT_AURA", "player")
            assertEquals(4, #recu, "plus suivi : plus rappelé")
        end)
    end)
end)

test("sonde de l'aspect : verte sur des réponses attendues, rouge sur un secret, un nom inconnu ou une fonction disparue", function()
    local AC = AzerothCommune
    assertEquals("faucon", lire("aspect", aspect { actif = 13165, combat = false, secret = false }))
    local s = AC.Sondes()["aspect"]
    assertNotNil(s, "sonde déclarée")
    assertType("string", s.attente)
    assertEquals("vert", s.etat)
    assertNil(lire("aspect", aspect { actif = SECRET, combat = false, secret = false }))
    s = AC.Sondes()["aspect"]
    assertEquals("rouge", s.etat)
    assertTrue(noteParLaSonde(s, "secret"), "la sonde note le secret")
    assertEquals("aucun", lire("aspect", aspect { combat = false, secret = false }))
    assertEquals("vert", AC.Sondes()["aspect"].etat)
    local j = aspect { combat = false, secret = false }
    j["C_Spell.GetSpellName"] = function() return nil end
    lire("aspect", j)
    assertEquals("rouge", AC.Sondes()["aspect"].etat, "un aspect sans nom dans ce client : son ID a changé")
    j = aspect { combat = true, secret = false }
    j["C_Secrets.ShouldSpellAuraBeSecret"] = RIEN
    assertNil(lire("aspect", j))
    s = AC.Sondes()["aspect"]
    assertEquals("rouge", s.etat)
    assertTrue(noteParLaSonde(s, "absente"), "la sonde note la fonction absente")
end)

test("sondes des munitions et de l'aspect rangées avec les autres (Sondes(), donc Diagnostic)", function()
    local etat = AzerothCommune.Sondes()
    local rang = {}
    for i, s in ipairs(etat) do rang[s.nom] = i end
    assertNotNil(rang["munitions"])
    assertNotNil(rang["aspect"])
    assertTrue(rang["munitions"] > rang["build"] and rang["aspect"] > rang["build"])
end)
