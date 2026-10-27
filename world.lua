-- world.lua | halaman Misc: pencahayaan (Full bright, kabut) dan mode hemat performa untuk perangkat low-end.
-- Semua perubahan dicatat dan dikembalikan saat dimatikan / unload. Nilai yang sudah diubah game sendiri tidak ditimpa.
return function(Hub)
    local Lighting = game:GetService("Lighting")
    local Cfg, Config = Hub.Cfg, Hub.Config

    Config.declare({
        Fullbright = false, FBBright = 2, NoFog = false,
        PerfMode = false, PerfShadows = true, PerfEffects = true, PerfQuality = true,
        PerfTerrain = true, PerfESP = true, PerfUI = true,
    })

    --========================================================
    -- Pengelola perubahan properti (simpan nilai asli, pulihkan hanya jika belum diubah pihak lain)
    --========================================================
    local function same(a, b)
        if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-3 end
        return a == b
    end

    local function setProp(rec, inst, prop, value)
        local s = rec.saved[inst]
        if not s then
            s = {}
            rec.saved[inst] = s
        end
        local e = s[prop]
        if not e then
            e = { orig = inst[prop] }
            s[prop] = e
        end
        e.set = value
        if not same(inst[prop], value) then inst[prop] = value end
    end

    local function restoreAll(rec)
        for inst, props in pairs(rec.saved) do
            for prop, e in pairs(props) do
                pcall(function()
                    if same(inst[prop], e.set) then inst[prop] = e.orig end
                end)
            end
        end
        rec.saved = {}
    end

    local function postEffects(rec)
        local function scan(parent)
            if not parent then return end
            for _, c in ipairs(parent:GetChildren()) do
                if c:IsA("PostEffect") and not c:IsA("ColorCorrectionEffect") then
                    setProp(rec, c, "Enabled", false)
                end
            end
        end
        scan(Lighting)
        scan(workspace.CurrentCamera)
    end

    --========================================================
    -- Daftar efek: want() = apakah aktif, tick(rec) = terapkan (dipanggil berulang agar tahan terhadap reset oleh game)
    --========================================================
    local effects = {
        {
            id = "fullbright",
            want = function() return Cfg.Fullbright end,
            tick = function(rec)
                setProp(rec, Lighting, "Brightness", Cfg.FBBright)
                setProp(rec, Lighting, "Ambient", Color3.new(1, 1, 1))
                setProp(rec, Lighting, "OutdoorAmbient", Color3.new(1, 1, 1))
            end,
        },
        {
            id = "nofog",
            want = function() return Cfg.NoFog end,
            tick = function(rec)
                setProp(rec, Lighting, "FogEnd", 1000000)
                local atm = Lighting:FindFirstChildOfClass("Atmosphere")
                if atm then
                    setProp(rec, atm, "Density", 0)
                    setProp(rec, atm, "Haze", 0)
                end
            end,
        },
        {
            id = "perf_shadows",
            want = function() return Cfg.PerfMode and Cfg.PerfShadows end,
            tick = function(rec) setProp(rec, Lighting, "GlobalShadows", false) end,
        },
        {
            id = "perf_effects",
            want = function() return Cfg.PerfMode and Cfg.PerfEffects end,
            tick = postEffects,
        },
        {
            id = "perf_quality",
            want = function() return Cfg.PerfMode and Cfg.PerfQuality end,
            tick = function(rec) setProp(rec, settings().Rendering, "QualityLevel", Enum.QualityLevel.Level01) end,
        },
        {
            id = "perf_terrain",
            want = function() return Cfg.PerfMode and Cfg.PerfTerrain end,
            tick = function(rec)
                local t = workspace.Terrain
                setProp(rec, t, "Decoration", false)
                setProp(rec, t, "WaterWaveSize", 0)
                setProp(rec, t, "WaterWaveSpeed", 0)
                setProp(rec, t, "WaterReflectance", 0)
            end,
        },
    }

    local recs = {}
    for _, e in ipairs(effects) do recs[e.id] = { saved = {}, on = false } end

    -- interval pembaruan fitur lain (ESP, UI) diperlambat saat mode hemat aktif
    local scaled = {
        { id = "esp_players", slow = 0.45, flag = "PerfESP" },
        { id = "esp_objects", slow = 0.45, flag = "PerfESP" },
        { id = "esp_zombies", slow = 0.45, flag = "PerfESP" },
        { id = "ui", slow = 1, flag = "PerfUI" },
    }
    local function applyIntervals(forceBase)
        for _, s in ipairs(scaled) do
            local f = Hub.byId[s.id]
            if f then
                f._base = f._base or f.interval or 0
                local slow = (not forceBase) and Cfg.PerfMode and Cfg[s.flag]
                f.interval = slow and s.slow or f._base
            end
        end
    end

    local function step()
        for _, e in ipairs(effects) do
            local rec = recs[e.id]
            if e.want() then
                rec.on = true
                Hub.safe("world:" .. e.id, e.tick, rec)
            elseif rec.on then
                rec.on = false
                restoreAll(rec)
            end
        end
        applyIntervals(false)
    end

    Hub.register({
        id = "world",
        interval = 0.3,
        update = step,
        cleanup = function()
            for _, e in ipairs(effects) do restoreAll(recs[e.id]) end
            applyIntervals(true)
        end,
    })

    --========================================================
    -- UI: halaman Misc
    --========================================================
    Hub.ui(function(UI)
        local p = UI.page("Misc", 6)
        p:Section("Pencahayaan")
        p:Toggle("Full bright", "Fullbright")
        p:Slider("Tingkat kecerahan", "FBBright", 0, 6, 0.5, "")
        p:Toggle("Hilangkan kabut", "NoFog")
        p:Section("Performa")
        p:Toggle("Mode hemat performa", "PerfMode")
        p:Toggle("Matikan bayangan", "PerfShadows")
        p:Toggle("Matikan efek visual", "PerfEffects")
        p:Toggle("Kualitas grafis minimum", "PerfQuality")
        p:Toggle("Air dan dekorasi minimal", "PerfTerrain")
        p:Toggle("ESP hemat (update lebih jarang)", "PerfESP")
        p:Toggle("UI hemat (tanpa animasi)", "PerfUI")
    end)
end
