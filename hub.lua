-- hub.lua | runtime inti: track, safe, registri fitur, scheduler, unload, util
-- Konvensi semua modul: `return function(Hub) ... end`
return function(Hub)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local CS = game:GetService("CollectionService")

    Hub.Players, Hub.RunService, Hub.CS = Players, RunService, CS
    Hub.LP = Players.LocalPlayer
    Hub.Dead = false
    Hub.container = (gethui and gethui()) or game:GetService("CoreGui")

    local conns, beforeFns, afterFns, readyFns = {}, {}, {}, {}
    function Hub.track(c) conns[#conns + 1] = c return c end
    function Hub.beforeUnload(fn) beforeFns[#beforeFns + 1] = fn end -- jalan saat Hub belum Dead (mis. simpan config)
    function Hub.atUnload(fn) afterFns[#afterFns + 1] = fn end      -- jalan setelah semua cleanup fitur
    function Hub.onReady(fn) readyFns[#readyFns + 1] = fn end       -- jalan sesudah semua init fitur

    -- jalankan fungsi aman; error disimpan di Hub.Err (tampil di Dashboard > Diagnostik)
    Hub.Err = {}
    function Hub.safe(name, fn, ...)
        local ok, e = pcall(fn, ...)
        if ok then
            Hub.Err[name] = nil
        else
            e = tostring(e)
            if Hub.Err[name] ~= e then warn("[TOFHub] " .. name .. ": " .. e) end
            Hub.Err[name] = e
        end
        return ok
    end

    --========================================================
    -- UTIL
    --========================================================
    local U = {}
    function U.hex(c)
        return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    function U.parseHex(s)
        s = tostring(s):gsub("#", ""):gsub("%s", "")
        if #s == 6 and s:match("^%x+$") then
            return Color3.fromRGB(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16))
        end
    end
    function U.pathOf(i)
        local ok, r = pcall(function() return i:GetFullName() end)
        return ok and r or tostring(i)
    end
    function U.splitKeys(s)
        local t = {}
        for w in tostring(s):gmatch("[^,%s]+") do t[#t + 1] = w:lower() end
        return t
    end
    function U.esc(s)
        s = tostring(s)
        s = s:gsub("&", "&amp;")
        s = s:gsub("<", "&lt;")
        s = s:gsub(">", "&gt;")
        return s
    end
    function U.topName(inst)
        local p = inst
        while p.Parent and p.Parent ~= workspace do p = p.Parent end
        return p.Name
    end
    Hub.util = U

    --========================================================
    -- REGISTRI FITUR
    -- def = { id, interval?, init?(Hub), update?(dt), render?(dt), priority?, when?(), cleanup? }
    --========================================================
    Hub.features, Hub.byId = {}, {}
    function Hub.register(def)
        assert(type(def) == "table" and def.id, "fitur butuh id")
        assert(not Hub.byId[def.id], "id fitur ganda: " .. tostring(def.id))
        def._acc = 0
        Hub.byId[def.id] = def
        Hub.features[#Hub.features + 1] = def
        return def
    end

    function Hub.start()
        for _, f in ipairs(Hub.features) do
            if f.init then Hub.safe(f.id .. ":init", f.init, Hub) end
            if f.render then
                local name = "TOFHub_" .. f.id
                local ok = pcall(function()
                    RunService:BindToRenderStep(name, f.priority or Enum.RenderPriority.Last.Value, function(dt)
                        if not Hub.Dead then Hub.safe(f.id .. ":render", f.render, dt) end
                    end)
                end)
                if ok then f._bound = name end
            end
        end

        -- satu koneksi Heartbeat untuk semua fitur
        Hub.track(RunService.Heartbeat:Connect(function(dt)
            if Hub.Dead then return end
            for _, f in ipairs(Hub.features) do
                if f.update then
                    local run = true
                    if f.when then
                        local ok, r = pcall(f.when)
                        run = ok and r
                    end
                    if run then
                        f._acc += dt
                        if f._acc >= (f.interval or 0) then
                            local step = f._acc
                            f._acc = 0
                            Hub.safe(f.id, f.update, step)
                        end
                    end
                end
            end
        end))

        for _, fn in ipairs(readyFns) do pcall(fn) end
    end

    function Hub.unload()
        if Hub.Dead then return end
        for _, fn in ipairs(beforeFns) do pcall(fn) end
        Hub.Dead = true
        for i = #Hub.features, 1, -1 do
            local f = Hub.features[i]
            if f._bound then pcall(function() RunService:UnbindFromRenderStep(f._bound) end) end
            if f.cleanup then pcall(f.cleanup) end
        end
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        for _, fn in ipairs(afterFns) do pcall(fn) end
        if getgenv then getgenv().TOFHubUnload = nil end
    end
end
