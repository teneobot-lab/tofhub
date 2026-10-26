-- roles.lua | deteksi Killer vs Survivor
-- Berbasis event: perubahan atribut / team / karakter menandai `dirty`, hitung ulang hanya saat dirty
-- (plus pengaman tiap 5 detik untuk sinyal yang tidak punya event, mis. tag).
return function(Hub)
    local Players, CS, LP = Hub.Players, Hub.CS, Hub.LP
    local Cfg, Config, U = Hub.Cfg, Hub.Config, Hub.util
    local RG = Hub.Game.roles

    Config.declare({ KillerCount = 1, ManualKiller = "" })

    local Core = { killers = {}, killerMap = {}, info = {}, dirty = true, since = 0 }
    Hub.Core = Core

    local function hasAny(ch, list)
        for _, a in ipairs(list) do
            if ch:GetAttribute(a) ~= nil then return true end
        end
        return false
    end

    local function isStrBool(v) return type(v) == "string" or type(v) == "boolean" end

    local function signalsOf(p)
        local ch = p.Character
        local sig = {}
        sig["team"] = { v = p.Team and p.Team.Name or "-", w = 2 }
        local par = ch and ch.Parent
        sig["folder"] = { v = (par and par ~= workspace) and par.Name or "-", w = 2 }
        for _, pair in ipairs({ { "P", p }, { "C", ch } }) do
            local obj = pair[2]
            if obj then
                for k, v in pairs(obj:GetAttributes()) do
                    if isStrBool(v) then
                        local kl = tostring(k):lower()
                        local roleish = kl:find("kill") or kl:find("role") or kl:find("team") or kl:find("class")
                            or kl:find("side") or kl:find("surv")
                        sig[pair[1] .. "." .. tostring(k)] = { v = tostring(v), w = roleish and 2 or 1 }
                    end
                end
            end
        end
        local tg = ch and CS:GetTags(ch) or {}
        table.sort(tg)
        sig["tags"] = { v = table.concat(tg, ","), w = 1 }
        sig["ci"] = { v = tostring(ch ~= nil and ch:FindFirstChild("CheckInterractable") ~= nil), w = 1 }
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        sig["maxhp"] = { v = hum and tostring(hum.MaxHealth) or "-", w = 1 }
        return sig
    end

    function Core.detect()
        local plist = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then plist[#plist + 1] = p end
        end
        local N, K = #plist, math.max(1, Cfg.KillerCount)
        local sig, names = {}, {}
        for _, p in ipairs(plist) do
            sig[p] = signalsOf(p)
            for name in pairs(sig[p]) do names[name] = true end
        end

        local score, why = {}, {}
        local function add(p, n, r)
            if p == LP then return end
            score[p] = (score[p] or 0) + n
            why[p] = (why[p] or "") .. r .. " "
        end

        if N >= 3 then
            for name in pairs(names) do
                local groups, order, w = {}, {}, 1
                local kHits, sHits = {}, {}
                local nl = name:lower()
                for _, p in ipairs(plist) do
                    local c = sig[p][name]
                    local v = c and c.v or "-"
                    if c then w = math.max(w, c.w) end
                    if not groups[v] then groups[v] = {} order[#order + 1] = v end
                    table.insert(groups[v], p)
                    local vl = v:lower()
                    if vl:find("killer") or (nl:find("killer") and vl == "true") then kHits[#kHits + 1] = p end
                    if vl:find("surviv") or (nl:find("surviv") and vl == "true") then sHits[#sHits + 1] = p end
                end
                if #kHits >= 1 and #kHits <= K then
                    for _, p in ipairs(kHits) do add(p, 3, name .. "=killer") end
                end
                if #sHits >= 2 and (N - #sHits) >= 1 and (N - #sHits) <= K then
                    local set = {}
                    for _, p in ipairs(sHits) do set[p] = true end
                    for _, p in ipairs(plist) do
                        if not set[p] then add(p, 2, name .. "!=surv") end
                    end
                end
                if #order == 2 then
                    local a, b = groups[order[1]], groups[order[2]]
                    local small, big = a, b
                    if #b < #a then small, big = b, a end
                    if #small <= K and #big >= 2 and #small < #big then
                        for _, p in ipairs(small) do add(p, w, name .. "~") end
                    end
                end
            end
        end

        -- sinyal pasti dari atribut karakter (daftar atribut ada di games.lua)
        local isSurv = {}
        for _, p in ipairs(plist) do
            local ch = p.Character
            if hasAny(ch, RG.killerAttrs) then
                add(p, 10, "attr-killer")
            elseif hasAny(ch, RG.survivorAttrs) then
                isSurv[p] = true
            end
        end
        for p in pairs(isSurv) do score[p] = nil why[p] = nil end

        local cand = {}
        for p, s in pairs(score) do
            if s >= 2 then cand[#cand + 1] = p end
        end
        table.sort(cand, function(a, b)
            if score[a] ~= score[b] then return score[a] > score[b] end
            return a.UserId < b.UserId
        end)
        local killers = {}
        for i = 1, math.min(K, #cand) do
            local nxt = cand[i + 1]
            if i == K and nxt and score[nxt] == score[cand[i]] then break end
            killers[#killers + 1] = cand[i]
        end

        if Cfg.ManualKiller ~= "" then
            local mp = Players:FindFirstChild(Cfg.ManualKiller)
            if mp and mp ~= LP then
                killers = { mp }
                why[mp] = "manual "
                score[mp] = 99
            end
        end

        local map, info = {}, {}
        for _, p in ipairs(killers) do map[p] = true end
        for _, p in ipairs(plist) do
            info[#info + 1] = { p = p, killer = map[p] == true, score = score[p] or 0, why = why[p] or "" }
        end
        table.sort(info, function(a, b)
            if a.killer ~= b.killer then return a.killer end
            return a.p.Name < b.p.Name
        end)
        Core.killers, Core.killerMap, Core.info = killers, map, info
    end

    function Core.myRoot()
        return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    end

    function Core.dump()
        local out = {}
        for _, p in ipairs(Players:GetPlayers()) do
            local ch = p.Character
            out[#out + 1] = ("== %s%s | team=%s | char=%s"):format(p.Name, p == LP and " (ME)" or "", tostring(p.Team), ch and U.pathOf(ch) or "nil")
            for _, pair in ipairs({ { "P", p }, { "C", ch } }) do
                if pair[2] then
                    for k, v in pairs(pair[2]:GetAttributes()) do
                        out[#out + 1] = ("  %s.%s = %s"):format(pair[1], k, tostring(v))
                    end
                end
            end
            if ch then
                local hum = ch:FindFirstChildOfClass("Humanoid")
                out[#out + 1] = ("  tags=%s maxhp=%s ci=%s"):format(table.concat(CS:GetTags(ch), ","),
                    hum and tostring(hum.MaxHealth) or "-", tostring(ch:FindFirstChild("CheckInterractable") ~= nil))
                local kids = {}
                for i, c in ipairs(ch:GetChildren()) do
                    if i > 40 then kids[#kids + 1] = "..." break end
                    kids[#kids + 1] = c.ClassName .. ":" .. c.Name
                end
                out[#out + 1] = "  children=" .. table.concat(kids, ", ")
            end
        end
        for _, e in ipairs(Core.info) do
            out[#out + 1] = ("[hasil] %s killer=%s skor=%d %s"):format(e.p.Name, tostring(e.killer), e.score, e.why)
        end
        return table.concat(out, "\n")
    end

    --========================================================
    -- EVENT -> dirty
    --========================================================
    local function mark() Core.dirty = true end
    local playerConns, charConns = {}, {}

    local function disconnectAll(list)
        if list then
            for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
        end
    end

    local function hookPlayer(p)
        disconnectAll(playerConns[p])
        local function hookChar(ch)
            disconnectAll(charConns[p])
            charConns[p] = nil
            mark()
            if ch then charConns[p] = { ch.AttributeChanged:Connect(mark) } end
        end
        playerConns[p] = {
            p.CharacterAdded:Connect(hookChar),
            p.CharacterRemoving:Connect(function() hookChar(nil) end),
            p.AttributeChanged:Connect(mark),
            p:GetPropertyChangedSignal("Team"):Connect(mark),
        }
        if p.Character then hookChar(p.Character) end
    end

    local function unhookPlayer(p)
        disconnectAll(playerConns[p])
        disconnectAll(charConns[p])
        playerConns[p], charConns[p] = nil, nil
        mark()
    end

    Config.watch("KillerCount", mark)
    Config.watch("ManualKiller", mark)

    Hub.register({
        id = "roles",
        interval = 0.25,
        init = function()
            for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
            Hub.track(Players.PlayerAdded:Connect(hookPlayer))
            Hub.track(Players.PlayerRemoving:Connect(unhookPlayer))
        end,
        update = function(dt)
            Core.since += dt
            if Core.dirty or Core.since >= 5 then
                Core.dirty, Core.since = false, 0
                Core.detect()
            end
        end,
        cleanup = function()
            for _, list in pairs(playerConns) do disconnectAll(list) end
            for _, list in pairs(charConns) do disconnectAll(list) end
            playerConns, charConns = {}, {}
        end,
    })
end
