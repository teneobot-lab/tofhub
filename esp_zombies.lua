-- esp_zombies.lua | ESP NPC berhumanoid selain pemain (kata kunci di Cfg.KeyZombie)
return function(Hub)
    local Players, Cfg, Config, U, Gfx = Hub.Players, Hub.Cfg, Hub.Config, Hub.util, Hub.Gfx
    local Core, CAT, G = Hub.Core, Hub.CAT, Hub.Game

    local Zom = { tracked = {}, keys = {}, shown = 0 }
    Hub.Zom = Zom

    function Zom.rebuild() Zom.keys = U.splitKeys(Cfg.KeyZombie) end
    Zom.rebuild()
    Config.watch("KeyZombie", Zom.rebuild)

    function Zom.matches(model)
        local nl = model.Name:lower()
        for _, k in ipairs(Zom.keys) do
            if nl:find(k, 1, true) then return true end
        end
        return false
    end

    function Zom.untrack(model)
        local rec = Zom.tracked[model]
        if rec then
            Gfx.dropGui(rec)
            Zom.tracked[model] = nil
        end
    end

    -- menerima Model atau Humanoid dari Index (urutan kemunculan keduanya bisa terbalik)
    local function consider(inst)
        local model
        if inst:IsA("Humanoid") then
            model = inst.Parent
        elseif inst:IsA("Model") then
            model = inst
        else
            return
        end
        if not model or Zom.tracked[model] or not model:IsA("Model") then return end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        if not model:IsDescendantOf(workspace) then return end
        if Players:GetPlayerFromCharacter(model) then return end
        if model.Name == "cutscenecam" or G.zombieSkip[U.topName(model)] then return end
        Zom.tracked[model] = { model = model, hum = hum }
    end
    Hub.Index.subscribe("zombies", consider)

    local function update()
        local cat = CAT.Zombie
        local myRoot = Core.myRoot()
        local list = {}
        for model, rec in pairs(Zom.tracked) do
            local hum = rec.hum
            if not model.Parent or not hum or not hum.Parent then
                Zom.untrack(model)
            else
                local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                local dist = (root and myRoot) and (root.Position - myRoot.Position).Magnitude or 0
                if Cfg[cat.on] and hum.Health > 0 and root and dist <= Cfg[cat.dist]
                    and (Cfg.ZomAll or Zom.matches(model)) then
                    rec.root, rec.dist = root, dist
                    list[#list + 1] = rec
                else
                    Gfx.dropGui(rec)
                end
            end
        end
        table.sort(list, function(a, b) return a.dist < b.dist end)
        local col = Cfg[cat.col]
        local hlMax = (Cfg.PerfMode and Cfg.PerfESP) and 3 or 8
        for i, rec in ipairs(list) do
            local ok = pcall(function()
                if Cfg[cat.label] then
                    Gfx.ensureBB(rec, 180, 44, 3)
                    local info = {}
                    if Cfg.ShowDist then info[#info + 1] = math.floor(rec.dist) .. "m" end
                    if Cfg.ShowHP then info[#info + 1] = math.floor(rec.hum.Health) .. " HP" end
                    Gfx.styleLabel(rec, col, "ZOMBIE" .. (#info > 0 and ("\n" .. table.concat(info, " | ")) or ""))
                    Gfx.placeBB(rec, rec.model:FindFirstChild("Head") or rec.root)
                else
                    Gfx.dropBB(rec)
                end
                if Cfg[cat.chams] and i <= hlMax then
                    Gfx.ensureHL(rec)
                    rec.hl.FillColor, rec.hl.OutlineColor = col, col
                    rec.hl.FillTransparency = Cfg.FillT / 100
                    Gfx.placeHL(rec, rec.model)
                else
                    Gfx.dropHL(rec)
                end
            end)
            if not ok then Gfx.dropGui(rec) end
        end
        Zom.shown = #list
    end

    function Zom.clearAll()
        for m in pairs(Zom.tracked) do Zom.untrack(m) end
    end

    Hub.register({ id = "esp_zombies", interval = 0.2, update = update, cleanup = Zom.clearAll })
end
