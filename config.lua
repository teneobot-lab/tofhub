-- config.lua | Cfg + simpan otomatis + profil + migrasi versi
-- Modul lain mendaftarkan key-nya sendiri lewat Config.declare(defaults, { volatile = {...} })
return function(Hub)
    local Http = game:GetService("HttpService")
    local U = Hub.util

    local VER = 5
    local FILE = "TOFHub_config.json"
    local DIR = "TOFHub_profiles"

    local Cfg, Default = {}, {}
    local volatile = { ManualKiller = true } -- tidak pernah disimpan / dimuat
    local watchers = {}
    local saved = {}
    local Config = { VER = VER, Cfg = Cfg, Default = Default }
    Hub.Cfg, Hub.Config = Cfg, Config

    --========================================================
    -- MIGRASI: MIGRATIONS[n] mengubah data versi n -> n+1
    -- Config lama TIDAK dibuang; key yang tidak dikenal diabaikan, key yang cocok tetap dipakai.
    --========================================================
    local MIGRATIONS = {
        [4] = function(d) return d end, -- v4 -> v5: struktur sama
        -- [5] = function(d) d.NamaBaru = d.NamaLama d.NamaLama = nil return d end,
    }
    local function migrate(d)
        local v = tonumber(d.Ver) or 1
        if v > VER then return nil end -- dibuat versi script yang lebih baru
        while v < VER do
            local m = MIGRATIONS[v]
            if m then d = m(d) or d end
            v += 1
        end
        d.Ver = VER
        return d
    end
    local function decodeJSON(raw)
        local ok, d = pcall(function() return Http:JSONDecode(raw) end)
        if ok and type(d) == "table" then return migrate(d) end
    end

    if readfile and isfile and isfile(FILE) then
        local ok, raw = pcall(readfile, FILE)
        if ok then saved = decodeJSON(raw) or {} end
    end

    --========================================================
    -- DEKLARASI / AKSES
    --========================================================
    local function coerce(key, v)
        local cur = Cfg[key]
        if typeof(cur) == "Color3" then return U.parseHex(v) end
        if type(v) == type(cur) then return v end
        return nil
    end

    -- urutan nilai: default modul -> override game -> nilai tersimpan
    function Config.declare(defaults, opts)
        if opts and opts.volatile then
            for _, k in ipairs(opts.volatile) do volatile[k] = true end
        end
        local gd = (Hub.Game and Hub.Game.defaults) or {}
        for k, v in pairs(defaults) do
            if Cfg[k] == nil then
                if gd[k] ~= nil then v = gd[k] end
                Cfg[k], Default[k] = v, v
                if not volatile[k] and saved[k] ~= nil then
                    local c = coerce(k, saved[k])
                    if c ~= nil then Cfg[k] = c end
                end
            end
        end
    end

    function Config.watch(key, fn)
        watchers[key] = watchers[key] or {}
        table.insert(watchers[key], fn)
    end

    local function encode()
        local out = { Ver = VER }
        for k, v in pairs(Cfg) do
            if not volatile[k] then
                out[k] = (typeof(v) == "Color3") and ("#" .. U.hex(v)) or v
            end
        end
        return Http:JSONEncode(out)
    end

    function Config.flush()
        if not writefile then return end
        pcall(writefile, FILE, encode())
    end

    local saveToken = 0
    function Config.markDirty()
        if not writefile then return end
        saveToken += 1
        local t = saveToken
        task.delay(1, function()
            if t ~= saveToken or Hub.Dead then return end
            Config.flush()
        end)
    end

    function Config.set(key, v)
        Cfg[key] = v
        for _, fn in ipairs(watchers[key] or {}) do pcall(fn, v) end
        Config.markDirty()
    end

    Hub.beforeUnload(Config.flush) -- perubahan terakhir tidak hilang saat unload

    --========================================================
    -- PROFIL (file terpisah per nama) + PRESET (dari games.lua)
    --========================================================
    local function safeName(n) return (tostring(n):gsub("[^%w_%-]", "_")) end
    local function profilePath(n) return DIR .. "/" .. safeName(n) .. ".json" end

    function Config.saveProfile(name)
        if not writefile then return false, "writefile tidak didukung" end
        if makefolder and isfolder and not isfolder(DIR) then pcall(makefolder, DIR) end
        local ok, e = pcall(writefile, profilePath(name), encode())
        if ok then return true end
        return false, tostring(e)
    end

    local function applyData(d)
        local n = 0
        for k, v in pairs(d) do
            if k ~= "Ver" and Cfg[k] ~= nil and not volatile[k] then
                local c = coerce(k, v)
                if c ~= nil then
                    Config.set(k, c)
                    n += 1
                end
            end
        end
        return n
    end

    function Config.loadProfile(name)
        if not (readfile and isfile) then return false, "readfile tidak didukung" end
        local path = profilePath(name)
        if not isfile(path) then return false, "profil tidak ada" end
        local ok, raw = pcall(readfile, path)
        local d = ok and decodeJSON(raw)
        if not d then return false, "profil rusak atau dibuat versi yang lebih baru" end
        applyData(d)
        return true
    end

    -- cadangan lewat teks JSON (clipboard)
    function Config.export() return encode() end

    function Config.import(raw)
        local d = decodeJSON(tostring(raw or ""))
        if not d then return false, "data tidak valid atau versi lebih baru" end
        return true, applyData(d)
    end

    function Config.resetAll()
        for k, v in pairs(Default) do
            if not volatile[k] then Config.set(k, v) end
        end
    end

    function Config.listProfiles()
        local out = {}
        if listfiles and isfolder and isfolder(DIR) then
            local ok, files = pcall(listfiles, DIR)
            if ok then
                for _, p in ipairs(files) do
                    local n = p:match("([^/\\]+)%.json$")
                    if n then out[#out + 1] = n end
                end
            end
        end
        table.sort(out)
        return out
    end

    function Config.deleteProfile(name)
        if not (delfile and isfile) then return false end
        local path = profilePath(name)
        if isfile(path) then return pcall(delfile, path) end
        return false
    end

    function Config.presetNames()
        local out = {}
        for n in pairs(Hub.Game.presets or {}) do out[#out + 1] = n end
        table.sort(out)
        return out
    end

    function Config.applyPreset(name)
        local p = Hub.Game.presets and Hub.Game.presets[name]
        if not p then return false end
        for k, v in pairs(p) do
            if Cfg[k] ~= nil then Config.set(k, v) end
        end
        return true
    end
end
