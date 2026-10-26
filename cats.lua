-- cats.lua | kategori ESP (data-driven) + config ESP umum
-- Kategori baru cukup ditambah satu baris di CATS.
return function(Hub)
    local C3 = Color3.fromRGB
    local kw = Hub.Game.keywords or {}

    local CATS = {
        { id = "Killer", name = "Killer", kind = "role", on = "ESPKiller", col = "KillerColor", def = C3(235, 50, 50) },
        { id = "Surv", name = "Survivor", kind = "role", on = "ESPSurv", col = "SurvColor", def = C3(80, 220, 110) },
        { id = "Zombie", name = "Zombie", kind = "npc", on = "ESPZombie", col = "ZombieColor", def = C3(150, 255, 60) },
        { id = "Gen", name = "Generator", kind = "obj", on = "ObjGen", col = "ColGen", def = C3(255, 220, 60) },
        { id = "Hook", name = "Hook", kind = "obj", on = "ObjHook", col = "ColHook", def = C3(255, 140, 40) },
        { id = "Gate", name = "Gate", kind = "obj", on = "ObjGate", col = "ColGate", def = C3(60, 210, 230) },
        { id = "Pallet", name = "Pallet", kind = "obj", on = "ObjPallet", col = "ColPallet", def = C3(190, 90, 255) },
        { id = "Window", name = "Window", kind = "obj", on = "ObjWindow", col = "ColWindow", def = C3(80, 130, 255) },
    }

    local CAT, OBJ_GROUPS = {}, {}
    local defaults = {
        ShowName = true, ShowDist = true, ShowHP = true, ShowRole = true,
        FillT = 65, TextSize = 12, ESPMode = "CoreGui",
        ZomAll = false,
    }

    for _, c in ipairs(CATS) do
        CAT[c.id] = c
        c.chams, c.label, c.dist = "Chams_" .. c.id, "Label_" .. c.id, "Dist_" .. c.id
        defaults[c.on] = true
        defaults[c.col] = c.def
        defaults[c.chams] = (c.kind ~= "obj") -- objek: label saja (hemat batas Highlight Roblox)
        defaults[c.label] = true
        defaults[c.dist] = 2000
        if c.kind ~= "role" then
            c.keyCfg = "Key" .. c.id -- KeyGen, KeyHook, ..., KeyZombie
            c.keyDef = kw[c.id] or ""
            defaults[c.keyCfg] = c.keyDef
        end
        if c.kind == "obj" then OBJ_GROUPS[#OBJ_GROUPS + 1] = c end
    end

    Hub.Config.declare(defaults)
    Hub.CATS, Hub.CAT, Hub.OBJ_GROUPS = CATS, CAT, OBJ_GROUPS
end
