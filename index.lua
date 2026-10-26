-- index.lua | satu scanner workspace untuk semua modul (Objek, Zombie, dst)
-- Modul mendaftar lewat Index.subscribe(id, consider). `consider(inst)` menerima Model, BasePart, dan Humanoid.
-- Scan ulang satu modul memakai cache (bukan GetDescendants lagi).
return function(Hub)
    local Index = {
        subs = {}, byId = {}, ready = false,
        cache = setmetatable({}, { __mode = "k" }),
    }
    Hub.Index = Index

    local function relevant(d)
        return d:IsA("Model") or d:IsA("BasePart") or d:IsA("Humanoid")
    end

    local function replay(sub)
        local list = {}
        for d in pairs(Index.cache) do list[#list + 1] = d end
        task.spawn(function()
            local n = 0
            for _, d in ipairs(list) do
                if Hub.Dead then return end
                if d.Parent then Hub.safe("index:" .. sub.id, sub.consider, d) end
                n += 1
                if n % 2000 == 0 then task.wait() end
            end
        end)
    end

    function Index.subscribe(id, consider)
        local sub = { id = id, consider = consider }
        Index.subs[#Index.subs + 1] = sub
        Index.byId[id] = sub
        if Index.ready then replay(sub) end
    end

    function Index.rescan(id)
        local sub = Index.byId[id]
        if sub then replay(sub) end
    end

    function Index.start()
        Hub.track(workspace.DescendantAdded:Connect(function(d)
            if not relevant(d) then return end
            Index.cache[d] = true
            task.defer(function()
                if Hub.Dead or not d.Parent then return end
                for _, sub in ipairs(Index.subs) do
                    Hub.safe("index:" .. sub.id, sub.consider, d)
                end
            end)
        end))
        Hub.track(workspace.DescendantRemoving:Connect(function(d)
            Index.cache[d] = nil
        end))

        task.spawn(function()
            local n = 0
            for _, d in ipairs(workspace:GetDescendants()) do
                if Hub.Dead then return end
                if relevant(d) then
                    Index.cache[d] = true
                    for _, sub in ipairs(Index.subs) do
                        Hub.safe("index:" .. sub.id, sub.consider, d)
                    end
                end
                n += 1
                if n % 2000 == 0 then task.wait() end
            end
            Index.ready = true
        end)
    end

    Hub.onReady(Index.start) -- mulai setelah semua modul sempat subscribe
end
