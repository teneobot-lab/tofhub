-- esp_objects.lua | ESP objek di dalam workspace.<mapName>; kata kunci per kategori bisa diubah di UI
return function(Hub)
    local Cfg, Config, CS, U, Gfx = Hub.Cfg, Hub.Config, Hub.CS, Hub.util, Hub.Gfx
    local Core, OBJ_GROUPS, G = Hub.Core, Hub.OBJ_GROUPS, Hub.Game

    local Obj = { tracked = {}, shown = {} }
    Hub.Obj = Obj

    local function rebuildKeys()
        for _, g in ipairs(OBJ_GROUPS) do g.keys = U.splitKeys(Cfg[g.keyCfg]) end
    end
    rebuildKeys()

    local function groupOf(name)
        local l = name:lower()
        for _, g in ipairs(OBJ_GROUPS) do
            for _, k in ipairs(g.keys) do
                if l:find(k, 1, true) then return g, k end
            end
        end
    end

    local function insideCharacter(inst)
        local p = inst.Parent
        while p and p ~= workspace do
            if p:IsA("Model") and p:FindFirstChildOfClass("Humanoid") then return true end
            p = p.Parent
        end
        return false
    end
    local function hasTrackedAncestor(inst)
        local p = inst.Parent
        while p and p ~= workspace do
            if Obj.tracked[p] then return true end
            p = p.Parent
        end
        return false
    end
    local function isContainer(inst, key)
        if not inst:IsA("Model") then return false end
        if inst.Name:sub(-1):lower() ~= "s" then return false end
        for _, c in ipairs(inst:GetChildren()) do
            if c:IsA("Model") and c.Name:lower():find(key, 1, true) then return true end
        end
        return false
    end

    function Obj.untrack(inst)
        local rec = Obj.tracked[inst]
        if rec then
            Gfx.dropGui(rec)
            pcall(function() rec.conn:Disconnect() end)
            Obj.tracked[inst] = nil
        end
    end

    local function consider(inst)
        if Obj.tracked[inst] then return end
        if not (inst:IsA("Model") or inst:IsA("BasePart")) then return end
        local g, key = groupOf(inst.Name)
        if not g then return end
        -- hanya di dalam workspace.<mapName> (membuang dekor Lobby); jika Map belum ada, abaikan Lobby/FakeCharacters
        local map = workspace:FindFirstChild(G.mapName or "Map")
        if map then
            if not inst:IsDescendantOf(map) then return end
        elseif G.zombieSkip[U.topName(inst)] then
            return
        end
        if g.id == "Gate" and not inst:IsA("Model") then return end -- Part "gate" bertag gatespot = titik spawn
        if inst:FindFirstChildOfClass("Humanoid") then return end
        if hasTrackedAncestor(inst) or isContainer(inst, key) or insideCharacter(inst) then return end
        if inst:IsA("Model") then
            for other in pairs(Obj.tracked) do
                if other ~= inst and other:IsDescendantOf(inst) then Obj.untrack(other) end
            end
        end
        local rec = { inst = inst, g = g }
        rec.conn = inst.AncestryChanged:Connect(function()
            if not inst:IsDescendantOf(workspace) then Obj.untrack(inst) end
        end)
        Obj.tracked[inst] = rec
    end

    function Obj.rescan()
        rebuildKeys()
        for inst in pairs(Obj.tracked) do Obj.untrack(inst) end
        Hub.Index.rescan("objects")
    end

    Hub.Index.subscribe("objects", consider)
    for _, g in ipairs(OBJ_GROUPS) do Config.watch(g.keyCfg, Obj.rescan) end

    local function progressOf(inst)
        for k, v in pairs(inst:GetAttributes()) do
            local kl = tostring(k):lower()
            if type(v) == "number" and (kl:find("progress") or kl:find("percent")) then
                return math.floor(v + 0.5) -- RepairProgress berskala 0..100
            end
        end
        for _, c in ipairs(inst:GetChildren()) do
            if c:IsA("NumberValue") or c:IsA("IntValue") then
                local nl = c.Name:lower()
                if nl:find("progress") or nl:find("percent") then return math.floor(c.Value + 0.5) end
            end
        end
    end

    local function update()
        local myRoot = Core.myRoot()
        local list = {}
        for inst, rec in pairs(Obj.tracked) do
            local part = rec.part
            if not (part and part.Parent) then
                part = inst:IsA("BasePart") and inst or inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
                rec.part = part
            end
            local g = rec.g
            local dist = (part and myRoot) and (part.Position - myRoot.Position).Magnitude or 0
            if Cfg[g.on] and part and dist <= Cfg[g.dist] then
                rec.dist = dist
                list[#list + 1] = rec
            else
                Gfx.dropGui(rec)
            end
        end
        table.sort(list, function(a, b) return a.dist < b.dist end)
        local shown, hlCount = {}, 0
        local hlMax = (Cfg.PerfMode and Cfg.PerfESP) and 5 or 16
        for _, g in ipairs(OBJ_GROUPS) do shown[g.id] = 0 end
        local cap = (Hub.Perf and Hub.Perf.maxObjects) or 1e9
        for i, rec in ipairs(list) do
            local g = rec.g
            local ok = i <= cap and pcall(function()
                local col = Cfg[g.col]
                if Cfg[g.label] then
                    Gfx.ensureBB(rec, 200, 18, 2)
                    local txt = g.name
                    if g.id == "Gen" then
                        local pr = progressOf(rec.inst)
                        if pr then txt = txt .. " " .. pr .. "%" end
                    elseif g.id == "Hook" and not CS:HasTag(rec.inst, G.hookTag) then
                        txt = txt .. " [TERISI]"
                    end
                    Gfx.styleLabel(rec, col, txt .. "  " .. math.floor(rec.dist) .. "m")
                    Gfx.placeBB(rec, rec.part)
                else
                    Gfx.dropBB(rec)
                end
                if Cfg[g.chams] and hlCount < hlMax then
                    hlCount += 1
                    Gfx.ensureHL(rec)
                    rec.hl.FillColor, rec.hl.OutlineColor = col, col
                    rec.hl.FillTransparency = 0.75
                    Gfx.placeHL(rec, rec.inst)
                else
                    Gfx.dropHL(rec)
                end
            end)
            if ok then shown[g.id] += 1 else Gfx.dropGui(rec) end
        end
        Obj.shown = shown
    end

    function Obj.clearAll()
        for inst in pairs(Obj.tracked) do Obj.untrack(inst) end
    end

    Hub.register({ id = "esp_objects", interval = 0.2, update = update, cleanup = Obj.clearAll })
end
