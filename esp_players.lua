-- esp_players.lua | ESP Killer / Survivor
return function(Hub)
    local Players, Cfg, Gfx = Hub.Players, Hub.Cfg, Hub.Gfx
    local CAT, Core, LP = Hub.CAT, Hub.Core, Hub.LP

    local ESP = { rec = {}, shown = { Killer = 0, Surv = 0 } }
    Hub.ESP = ESP

    function ESP.clear(p)
        local r = ESP.rec[p]
        if r then
            Gfx.dropGui(r)
            ESP.rec[p] = nil
        end
    end
    function ESP.clearAll()
        for p in pairs(ESP.rec) do ESP.clear(p) end
    end

    local function update()
        local myRoot = Core.myRoot()
        local shown = { Killer = 0, Surv = 0 }
        for _, p in ipairs(Players:GetPlayers()) do
            local ch = p.Character
            local drawn = false
            if p ~= LP and ch then
                local isK = Core.killerMap[p] == true
                local cat = isK and CAT.Killer or CAT.Surv
                local hum = ch:FindFirstChildOfClass("Humanoid")
                local root = ch:FindFirstChild("HumanoidRootPart")
                if Cfg[cat.on] and hum and hum.Health > 0 and root then
                    local dist = myRoot and (root.Position - myRoot.Position).Magnitude or 0
                    if dist <= Cfg[cat.dist] then
                        local rec = ESP.rec[p] or {}
                        ESP.rec[p] = rec
                        local ok = pcall(function()
                            local col = Cfg[cat.col]
                            if Cfg[cat.chams] then
                                Gfx.ensureHL(rec)
                                rec.hl.FillColor, rec.hl.OutlineColor = col, col
                                rec.hl.FillTransparency = Cfg.FillT / 100
                                Gfx.placeHL(rec, ch)
                            else
                                Gfx.dropHL(rec)
                            end
                            local parts, head, info = {}, {}, {}
                            if Cfg.ShowRole and isK then head[#head + 1] = "[KILLER]" end
                            if Cfg.ShowName then head[#head + 1] = p.DisplayName end
                            if #head > 0 then parts[#parts + 1] = table.concat(head, " ") end
                            if Cfg.ShowDist then info[#info + 1] = math.floor(dist) .. "m" end
                            if Cfg.ShowHP then info[#info + 1] = math.floor(hum.Health) .. " HP" end
                            if #info > 0 then parts[#parts + 1] = table.concat(info, " | ") end
                            if Cfg[cat.label] and #parts > 0 then
                                Gfx.ensureBB(rec, 220, 50, 3)
                                Gfx.styleLabel(rec, col, table.concat(parts, "\n"))
                                Gfx.placeBB(rec, ch:FindFirstChild("Head") or root)
                            else
                                Gfx.dropBB(rec)
                            end
                        end)
                        if ok then
                            drawn = true
                            shown[cat.id] += 1
                        else
                            Gfx.dropGui(rec)
                        end
                    end
                end
            end
            if not drawn then ESP.clear(p) end
        end
        ESP.shown = shown
    end

    Hub.register({
        id = "esp_players",
        interval = 0.2,
        init = function() Hub.track(Players.PlayerRemoving:Connect(ESP.clear)) end,
        update = update,
        cleanup = ESP.clearAll,
    })
end
