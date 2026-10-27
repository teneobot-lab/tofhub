--========================================================
-- TOF HUB loader
-- Mode "local": baca file dari folder workspace executor (TOFHub/*.lua)
-- Mode "url"  : unduh dari hosting (isi SOURCE.base, pakai commit hash supaya tidak kena cache lama)
-- Bundle      : build.py mengisi EMBEDDED, jadi satu file saja yang perlu dieksekusi
--========================================================
if getgenv and getgenv().TOFHubUnload then pcall(getgenv().TOFHubUnload) end

local SOURCE = {
    mode = "url",
    folder = "TOFHub/",
    base = "https://raw.githubusercontent.com/teneobot-lab/tofhub/main/",
}

-- urutan penting: modul belakang memakai Hub.* dari modul depan
local ORDER = {
    "hub", "games", "config", "cats", "ui", "pool", "index", "roles",
    "esp_players", "esp_objects", "esp_zombies", "world", "ui_tabs",
}
-- gagal di salah satu ini = hentikan semuanya
local CRITICAL = { hub = true, games = true, config = true, cats = true }

local EMBEDDED = {}

EMBEDDED["hub"] = (function()
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
end)()

EMBEDDED["games"] = (function()
-- games.lua | data per game. Tambah game baru: salin blok `default`, ubah isinya, kunci dengan PlaceId.
-- Field yang tidak diisi otomatis diambil dari `default`.
return function(Hub)
    local GAMES = {
        default = {
            name = "Twist of Fate (default)",
            mapName = "Map", -- objek hanya dipindai di dalam workspace.<mapName>
            -- atribut karakter yang menandai role
            roles = {
                killerAttrs = { "TerrorRadius", "IsChasing", "SuspenseRadius" },
                survivorAttrs = { "vaultspeed", "healboost" },
            },
            -- kata kunci nama objek per kategori (bisa diubah user di UI)
            keywords = {
                Gen = "generator", Hook = "hook", Gate = "gate", Pallet = "pallet", Window = "window",
                Zombie = "scp2, zombie",
            },
            hookTag = "Spike", -- hook TANPA tag ini ditandai [TERISI]
            zombieSkip = { Lobby = true, FakeCharacters = true, Clones = true, Terrain = true, Camera = true },
            -- override default config khusus game ini (key = nama di Cfg)
            defaults = {},
            -- preset: kumpulan nilai Cfg yang diterapkan sekaligus
            presets = {
                ["ESP lengkap"] = {
                    ESPKiller = true, ESPSurv = true, ESPZombie = true,
                    ObjGen = true, ObjHook = true, ObjGate = true, ObjPallet = true, ObjWindow = true,
                },
                ["ESP minimal"] = {
                    ESPKiller = true, ESPSurv = false, ESPZombie = false,
                    ObjGen = true, ObjHook = false, ObjGate = false, ObjPallet = false, ObjWindow = false,
                },
                ["Hemat performa"] = {
                    PerfMode = true, PerfShadows = true, PerfEffects = true, PerfQuality = true,
                    PerfTerrain = true, PerfESP = true, PerfUI = true,
                },
                ["Semua mati"] = {
                    ESPKiller = false, ESPSurv = false, ESPZombie = false,
                    ObjGen = false, ObjHook = false, ObjGate = false, ObjPallet = false, ObjWindow = false,
                    Fullbright = false, NoFog = false, PerfMode = false,
                },
            },
        },

        -- contoh game lain:
        -- [1234567890] = {
        --     name = "Game Lain",
        --     keywords = { Gen = "engine", Hook = "cage" },
        --     roles = { killerAttrs = { "IsMonster" } },
        -- },
    }

    local g = GAMES[game.PlaceId] or GAMES.default
    for k, v in pairs(GAMES.default) do
        if g[k] == nil then g[k] = v end
    end
    Hub.Games, Hub.Game = GAMES, g
end
end)()

EMBEDDED["config"] = (function()
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
end)()

EMBEDDED["cats"] = (function()
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
end)()

EMBEDDED["ui"] = (function()
-- ui.lua | mesin UI: sidebar, pencarian, grup lipat, color picker, jendela dapat diubah ukurannya
-- Modul lain menambah halaman lewat:
--   Hub.ui(function(UI)
--       local p = UI.page("Nama Tab", 6)        -- angka = urutan di sidebar
--       p:Section("Judul grup")                  -- grup lipat (tertutup sampai diketuk)
--       p:Toggle("Label", "KeyCfg")
--   end)
-- Kontrol berlabel ikut terindeks untuk pencarian (halaman + judul grup + label).
return function(Hub)
    local UIS = game:GetService("UserInputService")
    local TS = game:GetService("TweenService")
    local Cfg, Config, U = Hub.Cfg, Hub.Config, Hub.util

    Config.declare({ UIAccent = Color3.fromRGB(94, 140, 255), UIW = 0, UIH = 0 })

    local T = {
        bg = Color3.fromRGB(13, 13, 17),
        side = Color3.fromRGB(17, 17, 22),
        surface = Color3.fromRGB(23, 23, 30),
        raised = Color3.fromRGB(34, 34, 45),
        line = Color3.fromRGB(42, 42, 55),
        text = Color3.fromRGB(232, 232, 240),
        muted = Color3.fromRGB(128, 128, 146),
        danger = Color3.fromRGB(214, 76, 76),
        white = Color3.new(1, 1, 1),
        accent = Cfg.UIAccent,
    }

    local MIN_W, MIN_H = 340, 230

    local UI = { pages = {}, order = {}, rows = {}, dyn = {}, accentFns = {}, current = nil, T = T }
    Hub.UI = UI

    local builders = {}
    function Hub.ui(fn) builders[#builders + 1] = fn end

    function UI.accent(fn) UI.accentFns[#UI.accentFns + 1] = fn end
    Config.watch("UIAccent", function(c)
        T.accent = c
        for _, fn in ipairs(UI.accentFns) do pcall(fn) end
    end)

    --========================================================
    -- HELPER
    --========================================================
    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function corner(o, r)
        new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
    end
    local function stroke(o, col, tr, th)
        return new("UIStroke", {
            Color = col or T.line, Thickness = th or 1, Transparency = tr or 0.3,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, o)
    end
    local function label(parent, text, size, color, props)
        local l = new("TextLabel", {
            BackgroundTransparency = 1, Text = text, TextSize = size or 13, Font = Enum.Font.Gotham,
            TextColor3 = color or T.text, TextXAlignment = Enum.TextXAlignment.Left,
        }, parent)
        if props then
            for k, v in pairs(props) do l[k] = v end
        end
        return l
    end
    local function lowFx() return Cfg.PerfMode == true and Cfg.PerfUI == true end
    local function tween(o, props, t)
        if lowFx() then
            for k, v in pairs(props) do o[k] = v end
            return
        end
        TS:Create(o, TweenInfo.new(t or 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end
    local function isPress(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end

    local drag = {}
    local function startDrag(fn, done) drag.fn, drag.done = fn, done end

    --========================================================
    -- JENDELA
    --========================================================
    local gui, win, side, content, float, navSf, pagesHolder, resultsSf, emptyLbl, headerLbl, searchBox
    local toastFrame, toastLbl
    local resHeaders = {}
    local toastToken = 0

    local function screen()
        local s = gui and gui.AbsoluteSize or Vector2.zero
        if s.X < 50 or s.Y < 50 then s = workspace.CurrentCamera.ViewportSize end
        return s
    end

    function UI.toast(text)
        if not toastFrame then return end
        toastToken += 1
        local t = toastToken
        toastLbl.Text = tostring(text)
        toastFrame.Visible = true
        task.delay(2.2, function()
            if t == toastToken and toastFrame and toastFrame.Parent then toastFrame.Visible = false end
        end)
    end

    local function showWin(show)
        if not win then return end
        win.Visible = show
        float.Visible = not show
    end

    local function defaultSize()
        local sc = screen()
        return math.min(600, math.floor(sc.X * 0.94)), math.min(370, math.floor(sc.Y * 0.88))
    end

    function UI.resetWindow()
        local sc = screen()
        local W, H = defaultSize()
        win.Size = UDim2.fromOffset(W, H)
        win.Position = UDim2.fromOffset(math.floor((sc.X - W) / 2), math.floor((sc.Y - H) / 2))
        Config.set("UIW", 0)
        Config.set("UIH", 0)
    end

    --========================================================
    -- PENCARIAN: kontrol yang cocok dipindah sementara ke daftar hasil, lalu dikembalikan
    --========================================================
    local function setCard(e, card)
        e.row.BackgroundTransparency = card and 0 or 1
        e.stroke.Enabled = card
        if e.divider then e.divider.Visible = not card end
    end

    local function clearSearch()
        for _, h in ipairs(resHeaders) do pcall(function() h:Destroy() end) end
        resHeaders = {}
        for _, e in ipairs(UI.rows) do
            if e.row.Parent == resultsSf then
                e.row.Parent = e.parent
                e.row.LayoutOrder = e.order
                setCard(e, e.parent == e.page.sf)
            end
        end
        resultsSf.Visible = false
        emptyLbl.Visible = false
    end

    local function matches(hay, words)
        for _, w in ipairs(words) do
            if not hay:find(w, 1, true) then return false end
        end
        return true
    end

    local restyle -- didefinisikan di bawah

    local function applySearch()
        local q = searchBox.Text:lower()
        clearSearch()
        local words = {}
        for w in q:gmatch("%S+") do words[#words + 1] = w end
        if #words == 0 then
            restyle()
            return
        end
        for _, p in pairs(UI.pages) do p.sf.Visible = false end
        resultsSf.Visible = true
        headerLbl.Text = "Hasil pencarian"
        local n, lastKey = 0, nil
        for _, e in ipairs(UI.rows) do
            local hay = (e.page.name .. " " .. e.section .. " " .. e.text):lower()
            if matches(hay, words) then
                local key = e.page.name .. ((e.section ~= "") and (" / " .. e.section) or "")
                if key ~= lastKey then
                    n += 1
                    lastKey = key
                    resHeaders[#resHeaders + 1] = label(resultsSf, key, 11, T.muted, {
                        Size = UDim2.new(1, 0, 0, 20), LayoutOrder = n, Font = Enum.Font.GothamMedium,
                    })
                end
                n += 1
                e.row.Parent = resultsSf
                e.row.LayoutOrder = n
                setCard(e, true)
            end
        end
        emptyLbl.Visible = (n == 0)
    end

    local function applyLayout()
        if not (win and side and content) then return end
        local sbw = (win.AbsoluteSize.X < 460) and 96 or 140
        side.Size = UDim2.new(0, sbw, 1, 0)
        content.Position = UDim2.fromOffset(sbw, 0)
        content.Size = UDim2.new(1, -sbw, 1, 0)
    end

    local function build()
        gui = new("ScreenGui", {
            Name = "TOFHubUI", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 10000,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        }, Hub.container)

        local sc = screen()
        local dW, dH = defaultSize()
        local W = (Cfg.UIW > 0) and math.clamp(Cfg.UIW, MIN_W, sc.X) or dW
        local H = (Cfg.UIH > 0) and math.clamp(Cfg.UIH, MIN_H, sc.Y) or dH

        win = new("Frame", {
            Size = UDim2.fromOffset(W, H),
            Position = UDim2.fromOffset(math.floor((sc.X - W) / 2), math.floor((sc.Y - H) / 2)),
            BackgroundColor3 = T.bg, BorderSizePixel = 0, Active = true, ClipsDescendants = true,
        }, gui)
        corner(win, 14)
        stroke(win, T.line, 0.1)

        ------------------------------------------------------------
        -- BAR ATAS
        ------------------------------------------------------------
        local top = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.side, BorderSizePixel = 0 }, win)
        local dotMark = new("Frame", {
            Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 14, 0.5, -4), BackgroundColor3 = T.accent, BorderSizePixel = 0,
        }, top)
        corner(dotMark, 4)
        UI.accent(function() dotMark.BackgroundColor3 = T.accent end)
        label(top, "TOF Hub", 13, T.text, {
            Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -110, 1, 0), Font = Enum.Font.GothamBold,
        })
        local function topBtn(text, xOff, color, size)
            return new("TextButton", {
                Text = text, Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, xOff, 0, 0),
                BackgroundTransparency = 1, TextColor3 = color or T.muted, TextSize = size or 18, Font = Enum.Font.GothamMedium,
            }, top)
        end
        local minBtn = topBtn("–", -68)
        local closeBtn = topBtn("×", -34, T.danger, 22)

        top.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            local sp, sw = i.Position, win.Position
            startDrag(function(pos)
                local v = screen()
                local x = math.clamp(sw.X.Offset + (pos.X - sp.X), -win.AbsoluteSize.X + 70, v.X - 70)
                local y = math.clamp(sw.Y.Offset + (pos.Y - sp.Y), 0, v.Y - 34)
                win.Position = UDim2.fromOffset(x, y)
            end)
        end)

        local body = new("Frame", {
            Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1,
        }, win)

        ------------------------------------------------------------
        -- SIDEBAR
        ------------------------------------------------------------
        side = new("Frame", { Size = UDim2.new(0, 140, 1, 0), BackgroundColor3 = T.side, BorderSizePixel = 0 }, body)
        new("Frame", {
            Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = T.line, BorderSizePixel = 0,
        }, side)

        local sWrap = new("Frame", {
            Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 32), BackgroundColor3 = T.raised, BorderSizePixel = 0,
        }, side)
        corner(sWrap, 10)
        -- ikon kaca pembesar (digambar dari frame, tanpa teks)
        local lens = new("Frame", {
            Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(11, 9), BackgroundTransparency = 1,
        }, sWrap)
        corner(lens, 5)
        new("UIStroke", { Color = T.muted, Thickness = 1.5 }, lens)
        new("Frame", {
            Size = UDim2.fromOffset(6, 2), Position = UDim2.fromOffset(19, 22), Rotation = 45,
            BackgroundColor3 = T.muted, BorderSizePixel = 0,
        }, sWrap)
        searchBox = new("TextBox", {
            Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -52, 1, 0), BackgroundTransparency = 1,
            Text = "", TextColor3 = T.text, Font = Enum.Font.Gotham, TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        }, sWrap)
        local clearBtn = new("TextButton", {
            Text = "×", Size = UDim2.fromOffset(22, 32), Position = UDim2.new(1, -24, 0, 0),
            BackgroundTransparency = 1, TextColor3 = T.muted, TextSize = 18, Font = Enum.Font.GothamMedium, Visible = false,
        }, sWrap)
        clearBtn.Activated:Connect(function() searchBox.Text = "" end)

        navSf = new("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -56), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, side)
        new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, navSf)
        new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2) }, navSf)

        ------------------------------------------------------------
        -- KONTEN
        ------------------------------------------------------------
        content = new("Frame", {
            Position = UDim2.fromOffset(140, 0), Size = UDim2.new(1, -140, 1, 0), BackgroundTransparency = 1,
        }, body)
        headerLbl = label(content, "", 17, T.text, {
            Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 26), Font = Enum.Font.GothamBold,
        })
        pagesHolder = new("Frame", {
            Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42), BackgroundTransparency = 1,
        }, content)

        resultsSf = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
            ScrollBarImageColor3 = T.raised, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
        }, pagesHolder)
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, resultsSf)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 28), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        }, resultsSf)
        emptyLbl = label(pagesHolder, "Tidak ada fitur yang cocok", 13, T.muted, {
            Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 24), TextXAlignment = Enum.TextXAlignment.Center,
            Visible = false,
        })

        toastFrame = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(0, 30),
            AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.raised, BorderSizePixel = 0, Visible = false, ZIndex = 20,
        }, content)
        corner(toastFrame, 15)
        stroke(toastFrame, T.line, 0.2)
        new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, toastFrame)
        toastLbl = label(toastFrame, "", 12, T.text, {
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 21,
        })

        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            clearBtn.Visible = searchBox.Text ~= ""
            applySearch()
        end)

        ------------------------------------------------------------
        -- PENGUBAH UKURAN (sudut kanan bawah)
        ------------------------------------------------------------
        local grip = new("TextButton", {
            Text = "", Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1, ZIndex = 30,
        }, win)
        for _, p in ipairs({ { 17, 17 }, { 10, 17 }, { 17, 10 } }) do
            local d = new("Frame", {
                Size = UDim2.fromOffset(3, 3), Position = UDim2.fromOffset(p[1], p[2]), BackgroundColor3 = T.muted,
                BorderSizePixel = 0, ZIndex = 31,
            }, grip)
            corner(d, 2)
        end
        grip.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            local sp, sz = i.Position, win.AbsoluteSize
            startDrag(function(pos)
                local v, pa = screen(), win.AbsolutePosition
                local w = math.clamp(sz.X + (pos.X - sp.X), MIN_W, math.max(MIN_W, v.X - pa.X))
                local h = math.clamp(sz.Y + (pos.Y - sp.Y), MIN_H, math.max(MIN_H, v.Y - pa.Y))
                win.Size = UDim2.fromOffset(w, h)
            end, function()
                Config.set("UIW", math.floor(win.AbsoluteSize.X))
                Config.set("UIH", math.floor(win.AbsoluteSize.Y))
            end)
        end)

        win:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
        applyLayout()

        ------------------------------------------------------------
        -- TOMBOL MELAYANG (saat diminimalkan)
        ------------------------------------------------------------
        float = new("TextButton", {
            Text = "T", Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(12, 90),
            BackgroundColor3 = T.bg, TextColor3 = T.accent, TextSize = 18, Font = Enum.Font.GothamBold,
            Visible = false, AutoButtonColor = false, BorderSizePixel = 0,
        }, gui)
        corner(float, 22)
        local fs = new("UIStroke", { Color = T.accent, Thickness = 2 }, float)
        UI.accent(function()
            float.TextColor3 = T.accent
            fs.Color = T.accent
        end)
        float.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            local sp, sw, moved = i.Position, float.Position, false
            startDrag(function(pos)
                local d = pos - sp
                if d.Magnitude > 6 then moved = true end
                if moved then float.Position = UDim2.fromOffset(sw.X.Offset + d.X, sw.Y.Offset + d.Y) end
            end, function()
                if not moved then showWin(true) end
            end)
        end)

        minBtn.Activated:Connect(function() showWin(false) end)
        closeBtn.Activated:Connect(function() Hub.unload() end)

        Hub.track(UIS.InputBegan:Connect(function(i, gp)
            if gp then return end
            if i.KeyCode == Enum.KeyCode.RightShift then showWin(not win.Visible) end
        end))
        Hub.track(UIS.InputChanged:Connect(function(i)
            if drag.fn and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                pcall(drag.fn, i.Position)
            end
        end))
        Hub.track(UIS.InputEnded:Connect(function(i)
            if drag.fn and isPress(i) then
                local d = drag.done
                drag.fn, drag.done = nil, nil
                if d then pcall(d) end
            end
        end))
    end

    --========================================================
    -- HALAMAN
    --========================================================
    local Page = {}
    Page.__index = Page

    restyle = function()
        local searching = searchBox and searchBox.Text ~= ""
        for _, p in pairs(UI.pages) do
            local on = (p == UI.current)
            p.sf.Visible = on and not searching
            p.tab.BackgroundColor3 = T.accent
            p.tab.BackgroundTransparency = on and 0.85 or 1
            p.bar.Visible = on
            p.bar.BackgroundColor3 = T.accent
            p.txt.TextColor3 = on and T.text or T.muted
        end
        if UI.current and not searching then headerLbl.Text = UI.current.name end
    end

    local function selectPage(page)
        UI.current = page
        if searchBox and searchBox.Text ~= "" then
            searchBox.Text = "" -- memicu applySearch() -> restyle()
        end
        restyle()
    end
    UI.select = selectPage

    function UI.page(name, order)
        if UI.pages[name] then return UI.pages[name] end
        local sf = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = T.raised, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
        }, pagesHolder)
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 28), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        }, sf)

        local ord = order or (100 + #UI.order)
        local tab = new("TextButton", {
            Text = "", Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.accent, BackgroundTransparency = 1,
            BorderSizePixel = 0, AutoButtonColor = false, LayoutOrder = ord,
        }, navSf)
        corner(tab, 9)
        local bar = new("Frame", {
            Size = UDim2.fromOffset(3, 16), Position = UDim2.new(0, 0, 0.5, -8), BackgroundColor3 = T.accent,
            BorderSizePixel = 0, Visible = false,
        }, tab)
        corner(bar, 2)
        local txt = label(tab, name, 13, T.muted, {
            Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -20, 1, 0),
            Font = Enum.Font.GothamMedium, TextTruncate = Enum.TextTruncate.AtEnd,
        })

        local page = setmetatable({
            name = name, sf = sf, tab = tab, bar = bar, txt = txt, ord = ord,
            n = 0, nInner = 0, holder = sf, section = "",
        }, Page)
        UI.pages[name] = page
        UI.order[#UI.order + 1] = page
        tab.Activated:Connect(function() selectPage(page) end)
        return page
    end

    -- kartu / baris dasar. Di luar grup tampil sebagai kartu; di dalam grup tampil datar dengan garis pemisah.
    function Page:row(h, text)
        local inGroup = (self.holder ~= self.sf)
        local order
        if inGroup then
            self.nInner += 1
            order = self.nInner
        else
            self.n += 1
            order = self.n
        end
        local r = new("Frame", {
            Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = T.surface, BackgroundTransparency = inGroup and 1 or 0,
            BorderSizePixel = 0, LayoutOrder = order,
        }, self.holder)
        corner(r, 10)
        local st = stroke(r)
        st.Enabled = not inGroup
        local div
        if inGroup then
            div = new("Frame", {
                Size = UDim2.new(1, -28, 0, 1), Position = UDim2.fromOffset(14, 0), BackgroundColor3 = T.line,
                BorderSizePixel = 0,
            }, r)
        end
        if text then
            UI.rows[#UI.rows + 1] = {
                row = r, page = self, section = self.section, text = tostring(text),
                parent = self.holder, order = order, stroke = st, divider = div,
            }
        end
        return r
    end

    -- grup lipat: tertutup sampai header diketuk
    function Page:Section(text, open)
        self.n += 1
        local grp = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.surface,
            BorderSizePixel = 0, LayoutOrder = self.n,
        }, self.sf)
        corner(grp, 10)
        stroke(grp)
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, grp)
        local head = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = 1,
        }, grp)
        label(head, text, 13, T.text, {
            Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -50, 1, 0), Font = Enum.Font.GothamMedium,
        })
        local chev = label(head, "›", 22, T.muted, {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -20, 0.5, -1), Size = UDim2.fromOffset(20, 24),
            TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamMedium,
        })
        local body = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
            LayoutOrder = 2, Visible = false,
        }, grp)
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, body)

        local isOpen = false
        local function set(o, instant)
            isOpen = o
            body.Visible = o
            chev.TextColor3 = o and T.accent or T.muted
            if instant then
                chev.Rotation = o and 90 or 0
            else
                tween(chev, { Rotation = o and 90 or 0 })
            end
        end
        UI.accent(function() chev.TextColor3 = isOpen and T.accent or T.muted end)
        head.Activated:Connect(function() set(not isOpen) end)
        set(open == true, true)

        self.holder = body
        self.nInner = 0
        self.section = text
    end

    -- kembali ke tingkat halaman (setelah grup)
    function Page:Root()
        self.holder = self.sf
        self.section = ""
    end

    function Page:Toggle(text, key)
        local r = self:row(42, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -76, 1, 0) })
        local sw = new("Frame", {
            Size = UDim2.fromOffset(38, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
            BorderSizePixel = 0,
        }, r)
        corner(sw, 11)
        local dot = new("Frame", {
            Size = UDim2.fromOffset(16, 16), BackgroundColor3 = T.white, BorderSizePixel = 0,
        }, sw)
        corner(dot, 8)
        local first = true
        local function paint()
            local on = Cfg[key] == true
            local col = on and T.accent or T.raised
            local pos = UDim2.fromOffset(on and 19 or 3, 3)
            if first then
                sw.BackgroundColor3, dot.Position = col, pos
                first = false
            else
                tween(sw, { BackgroundColor3 = col })
                tween(dot, { Position = pos })
            end
        end
        paint()
        UI.accent(paint)
        Config.watch(key, paint)
        local hit = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0) }, r)
        hit.Activated:Connect(function() Config.set(key, not Cfg[key]) end)
    end

    function Page:Slider(text, key, min, max, step, suffix)
        local r = self:row(56, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -110, 0, 18) })
        local vl = label(r, "", 12, T.accent, {
            Position = UDim2.new(1, -94, 0, 7), Size = UDim2.fromOffset(80, 18), TextXAlignment = Enum.TextXAlignment.Right,
            Font = Enum.Font.GothamMedium,
        })
        local track = new("Frame", {
            Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -28, 0, 4), BackgroundColor3 = T.raised, BorderSizePixel = 0,
        }, r)
        corner(track, 2)
        local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, track)
        corner(fill, 2)
        local knob = new("Frame", {
            Size = UDim2.fromOffset(14, 14), BackgroundColor3 = T.white, BorderSizePixel = 0,
        }, track)
        corner(knob, 7)

        local function paint()
            local v = tonumber(Cfg[key]) or min
            local a = math.clamp((v - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, -7, 0.5, -7)
            vl.Text = ("%g%s"):format(v, suffix or "")
            fill.BackgroundColor3 = T.accent
            vl.TextColor3 = T.accent
        end
        paint()
        UI.accent(paint)
        Config.watch(key, paint)

        local function setFrom(x)
            local a = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
            local v = min + a * (max - min)
            v = math.floor(v / step + 0.5) * step
            v = math.clamp(tonumber(("%.4f"):format(v)), min, max)
            if v ~= Cfg[key] then Config.set(key, v) end
        end

        local hit = new("TextButton", {
            Text = "", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 30),
        }, r)
        hit.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            local scroller = r:FindFirstAncestorWhichIsA("ScrollingFrame")
            if scroller then scroller.ScrollingEnabled = false end
            setFrom(i.Position.X)
            startDrag(function(pos) setFrom(pos.X) end, function()
                if scroller then scroller.ScrollingEnabled = true end
            end)
        end)
    end

    ----------------------------------------------------------------
    -- COLOR PICKER: ketuk kotak warna untuk membuka palet (saturasi/kecerahan + hue + warna cepat)
    ----------------------------------------------------------------
    local QUICK = {
        Color3.fromRGB(235, 64, 52), Color3.fromRGB(255, 145, 36), Color3.fromRGB(255, 214, 10),
        Color3.fromRGB(52, 199, 89), Color3.fromRGB(50, 200, 220), Color3.fromRGB(10, 132, 255),
        Color3.fromRGB(175, 82, 222), Color3.fromRGB(240, 240, 240),
    }
    local PICK_H = 150

    function Page:Color(text, key)
        local r = self:row(42, text)
        r.ClipsDescendants = true
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -150, 0, 42) })

        local tb = new("TextBox", {
            Size = UDim2.fromOffset(76, 26), Position = UDim2.new(1, -90, 0, 8), BackgroundColor3 = T.raised,
            TextColor3 = T.text, Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false,
            BorderSizePixel = 0, Text = "",
        }, r)
        corner(tb, 7)
        local sw = new("TextButton", {
            Text = "", Size = UDim2.fromOffset(30, 24), Position = UDim2.new(1, -128, 0, 9), BorderSizePixel = 0,
            AutoButtonColor = false,
        }, r)
        corner(sw, 7)
        stroke(sw, T.white, 0.75)

        local base = Cfg[key]
        local h, s, v = 0, 0, 1
        if typeof(base) == "Color3" then h, s, v = base:ToHSV() end

        local svBox, svCur, hueKnob
        local function refreshPicker()
            if svBox then
                svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                svCur.Position = UDim2.new(s, 0, 1 - v, 0)
                hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
            end
        end
        local function paint()
            local c = Cfg[key]
            if typeof(c) ~= "Color3" then return end
            if Color3.fromHSV(h, s, v) ~= c then h, s, v = c:ToHSV() end
            sw.BackgroundColor3 = c
            tb.Text = "#" .. U.hex(c)
            refreshPicker()
        end
        local function push() Config.set(key, Color3.fromHSV(h, s, v)) end
        paint()
        Config.watch(key, paint)

        tb.FocusLost:Connect(function()
            local c = U.parseHex(tb.Text)
            if c then Config.set(key, c) else paint() end
        end)

        local built, open = false, false
        local function buildPicker()
            built = true
            local pk = new("Frame", {
                Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 0, PICK_H - 12), BackgroundTransparency = 1,
            }, r)

            svBox = new("Frame", {
                Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = Color3.fromHSV(h, 1, 1), BorderSizePixel = 0,
                ClipsDescendants = true,
            }, pk)
            corner(svBox, 8)
            local white = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = T.white, BorderSizePixel = 0 }, svBox)
            new("UIGradient", {
                Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
            }, white)
            local black = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, svBox)
            new("UIGradient", {
                Rotation = 90,
                Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
            }, black)
            svCur = new("Frame", {
                Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
            }, svBox)
            corner(svCur, 7)
            new("UIStroke", { Color = T.white, Thickness = 2 }, svCur)

            local hb = new("Frame", {
                Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = T.white, BorderSizePixel = 0,
            }, pk)
            corner(hb, 6)
            local keys = {}
            for k = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 1, 1)) end
            new("UIGradient", { Color = ColorSequence.new(keys) }, hb)
            hueKnob = new("Frame", {
                Size = UDim2.fromOffset(8, 18), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = T.white, BorderSizePixel = 0,
            }, hb)
            corner(hueKnob, 4)
            new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.5 }, hueKnob)

            local quick = new("Frame", {
                Position = UDim2.fromOffset(0, 114), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1,
            }, pk)
            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
            }, quick)
            for n, c in ipairs(QUICK) do
                local q = new("TextButton", {
                    Text = "", Size = UDim2.fromOffset(22, 22), BackgroundColor3 = c, BorderSizePixel = 0,
                    AutoButtonColor = false, LayoutOrder = n,
                }, quick)
                corner(q, 11)
                q.Activated:Connect(function()
                    h, s, v = c:ToHSV()
                    push()
                end)
            end

            local function dragWith(i, apply)
                if not isPress(i) then return end
                local scroller = r:FindFirstAncestorWhichIsA("ScrollingFrame")
                if scroller then scroller.ScrollingEnabled = false end
                apply(i.Position)
                startDrag(apply, function()
                    if scroller then scroller.ScrollingEnabled = true end
                end)
            end
            svBox.InputBegan:Connect(function(i)
                dragWith(i, function(pos)
                    s = math.clamp((pos.X - svBox.AbsolutePosition.X) / math.max(1, svBox.AbsoluteSize.X), 0, 1)
                    v = 1 - math.clamp((pos.Y - svBox.AbsolutePosition.Y) / math.max(1, svBox.AbsoluteSize.Y), 0, 1)
                    push()
                end)
            end)
            hb.InputBegan:Connect(function(i)
                dragWith(i, function(pos)
                    h = math.clamp((pos.X - hb.AbsolutePosition.X) / math.max(1, hb.AbsoluteSize.X), 0, 1)
                    push()
                end)
            end)
            refreshPicker()
        end

        sw.Activated:Connect(function()
            open = not open
            if open and not built then buildPicker() end
            tween(r, { Size = UDim2.new(1, 0, 0, open and (42 + PICK_H) or 42) })
        end)
    end

    function Page:Choice(text, key, options)
        local r = self:row(42, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, -14, 1, 0) })
        local b = new("TextButton", {
            Size = UDim2.new(0.5, -28, 0, 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, Font = Enum.Font.GothamMedium, TextSize = 12,
            BorderSizePixel = 0, AutoButtonColor = false, Text = "",
        }, r)
        corner(b, 8)
        local function paint() b.Text = tostring(Cfg[key]) end
        paint()
        Config.watch(key, paint)
        b.Activated:Connect(function()
            local idx = table.find(options, Cfg[key]) or 0
            Config.set(key, options[idx % #options + 1])
        end)
    end

    function Page:Input(text, key)
        local r = self:row(42, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.4, -14, 1, 0) })
        local tb = new("TextBox", {
            Size = UDim2.new(0.6, -28, 0, 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, Font = Enum.Font.Gotham, TextSize = 12,
            ClearTextOnFocus = false, BorderSizePixel = 0, Text = "",
        }, r)
        corner(tb, 8)
        new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tb)
        local function paint() tb.Text = tostring(Cfg[key]) end
        paint()
        Config.watch(key, paint)
        tb.FocusLost:Connect(function() Config.set(key, tb.Text) end)
    end

    -- teks bisa string atau fungsi (fungsi diperbarui tiap interval UI saat terlihat)
    -- style: true / "danger" = merah, "primary" = warna aksen
    function Page:Button(text, cb, style)
        local initial = text
        if type(text) == "function" then
            local ok, t = pcall(text)
            initial = ok and t or ""
        end
        local r = self:row(48, initial)
        local b = new("TextButton", {
            Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 1, -16), TextColor3 = T.text,
            Font = Enum.Font.GothamMedium, TextSize = 13, BorderSizePixel = 0, AutoButtonColor = true, Text = "",
        }, r)
        corner(b, 9)
        local function color()
            if style == true or style == "danger" then
                b.BackgroundColor3 = T.danger
            elseif style == "primary" then
                b.BackgroundColor3 = T.accent
            else
                b.BackgroundColor3 = T.raised
            end
        end
        color()
        UI.accent(color)
        local function apply()
            if type(text) == "function" then
                local ok, t = pcall(text)
                b.Text = ok and tostring(t) or "error"
            else
                b.Text = text
            end
        end
        apply()
        if type(text) == "function" then UI.dyn[#UI.dyn + 1] = { page = self, apply = apply } end
        b.Activated:Connect(function()
            local ok, e = pcall(cb)
            if not ok then UI.toast("Error: " .. tostring(e)) end
            apply()
        end)
    end

    function Page:Info(fn)
        local r = self:row(0)
        r.AutomaticSize = Enum.AutomaticSize.Y
        new("UIPadding", {
            PaddingTop = UDim.new(0, 11), PaddingBottom = UDim.new(0, 11),
            PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        }, r)
        local l = label(r, "", 12, T.text, {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
        })
        local function apply()
            local ok, t = pcall(fn)
            l.Text = ok and tostring(t) or ("error: " .. tostring(t))
        end
        apply()
        UI.dyn[#UI.dyn + 1] = { page = self, apply = apply }
    end

    --========================================================
    -- FITUR
    --========================================================
    Hub.register({
        id = "ui",
        interval = 0.5,
        init = function()
            build()
            UI.accent(restyle)
            for _, fn in ipairs(builders) do Hub.safe("ui:builder", fn, UI) end
            local first
            for _, p in ipairs(UI.order) do
                if not first or p.ord < first.ord then first = p end
            end
            if first then selectPage(first) end
        end,
        update = function()
            if not (win and win.Visible) then return end
            for _, d in ipairs(UI.dyn) do
                if d.page == UI.current or (resultsSf and resultsSf.Visible) then pcall(d.apply) end
            end
        end,
        cleanup = function()
            if gui then pcall(function() gui:Destroy() end) end
            gui, win = nil, nil
        end,
    })
end
end)()

EMBEDDED["pool"] = (function()
-- pool.lua | daur ulang Highlight + BillboardGui (tidak Destroy/buat ulang tiap update)
-- Hub.Gfx dipakai semua modul ESP. `rec` = tabel milik pemanggil (rec.hl, rec.bb, rec.tl).
return function(Hub)
    local Cfg = Hub.Cfg
    local MAX = 64

    local folder = Instance.new("Folder")
    folder.Name = "TOFESP"
    folder.Parent = Hub.container
    Hub.espFolder = folder

    local hlPool, bbPool = {}, {}

    local function newHL()
        local h = Instance.new("Highlight")
        h.Name = "TOFHL"
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        return h
    end
    local function newBB()
        local bb = Instance.new("BillboardGui")
        bb.Name = "TOFTag"
        bb.AlwaysOnTop = true
        bb.ResetOnSpawn = false
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 1
        tl.Font = Enum.Font.GothamBold
        tl.TextSize = 12
        tl.TextStrokeTransparency = 0.4
        tl.Parent = bb
        return bb, tl
    end

    -- instance yang sudah di-Destroy (mis. part induknya hilang) tidak boleh masuk pool:
    -- set Parent pada instance terkunci melempar error, jadi dites dulu dengan pcall.
    local function release(pool, inst, extra)
        local ok = pcall(function()
            inst.Adornee = nil
            inst.Parent = nil
        end)
        if ok and #pool < MAX then
            pool[#pool + 1] = extra or inst
        else
            pcall(function() inst:Destroy() end)
        end
    end

    local Gfx = {}

    function Gfx.ensureBB(rec, w, h, off)
        if not rec.bb then
            local e = table.remove(bbPool)
            if e then
                rec.bb, rec.tl = e.bb, e.tl
            else
                rec.bb, rec.tl = newBB()
            end
        end
        rec.bb.Size = UDim2.fromOffset(w, h)
        rec.bb.StudsOffset = Vector3.new(0, off, 0)
    end
    function Gfx.placeBB(rec, part)
        rec.bb.Adornee = part
        local want = (Cfg.ESPMode == "Workspace") and part or folder
        if rec.bb.Parent ~= want then rec.bb.Parent = want end
    end
    function Gfx.dropBB(rec)
        if rec.bb then
            local bb, tl = rec.bb, rec.tl
            rec.bb, rec.tl = nil, nil
            release(bbPool, bb, { bb = bb, tl = tl })
        end
    end

    function Gfx.ensureHL(rec)
        if not rec.hl then rec.hl = table.remove(hlPool) or newHL() end
    end
    function Gfx.placeHL(rec, adornee)
        rec.hl.Adornee = adornee
        local want = (Cfg.ESPMode == "Workspace") and adornee or folder
        if rec.hl.Parent ~= want then rec.hl.Parent = want end
    end
    function Gfx.dropHL(rec)
        if rec.hl then
            local h = rec.hl
            rec.hl = nil
            release(hlPool, h)
        end
    end

    function Gfx.dropGui(rec)
        Gfx.dropBB(rec)
        Gfx.dropHL(rec)
    end

    function Gfx.styleLabel(rec, col, text)
        rec.tl.TextColor3 = col
        rec.tl.TextSize = Cfg.TextSize
        rec.tl.Text = text
    end

    Hub.Gfx = Gfx

    Hub.atUnload(function()
        for _, e in ipairs(bbPool) do pcall(function() e.bb:Destroy() end) end
        for _, h in ipairs(hlPool) do pcall(function() h:Destroy() end) end
        bbPool, hlPool = {}, {}
        pcall(function() folder:Destroy() end)
    end)
end
end)()

EMBEDDED["index"] = (function()
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
end)()

EMBEDDED["roles"] = (function()
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
end)()

EMBEDDED["esp_players"] = (function()
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
end)()

EMBEDDED["esp_objects"] = (function()
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
end)()

EMBEDDED["esp_zombies"] = (function()
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
end)()

EMBEDDED["world"] = (function()
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
end)()

EMBEDDED["ui_tabs"] = (function()
-- ui_tabs.lua | isi halaman UI untuk modul inti. Angka kedua di UI.page = urutan di sidebar.
-- Modul lain menambah halaman sendiri lewat Hub.ui(function(UI) ... end) (contoh: world.lua -> "Misc", urutan 6).
return function(Hub)
    local Players, LP = Hub.Players, Hub.LP
    local Cfg, Config = Hub.Cfg, Hub.Config

    Config.declare({ ProfileName = "default" }, { volatile = { "ProfileName" } })

    local function copy(text)
        if setclipboard then
            setclipboard(text)
            return true
        end
        return false
    end

    local function diag()
        local out = { "== TOFHub diagnosis ==", "modul dimuat: " .. table.concat(Hub.loaded or {}, ", ") }
        for k, v in pairs(Hub.failed or {}) do out[#out + 1] = "GAGAL " .. k .. ": " .. tostring(v) end
        for k, v in pairs(Hub.Err) do out[#out + 1] = "ERR " .. k .. ": " .. tostring(v) end
        if Hub.Core then out[#out + 1] = Hub.Core.dump() end
        return table.concat(out, "\n")
    end

    local function catControls(p, c)
        p:Section(c.name)
        p:Toggle("Aktif", c.on)
        p:Toggle("Sorot (chams)", c.chams)
        p:Toggle("Label", c.label)
        p:Slider("Jarak maksimal", c.dist, 50, 5000, 50, " m")
        p:Color("Warna", c.col)
        if c.keyCfg then p:Input("Kata kunci", c.keyCfg) end
    end

    Hub.ui(function(UI)
        ----------------------------------------------------------------
        -- DASHBOARD
        ----------------------------------------------------------------
        local d = UI.page("Dashboard", 1)
        d:Info(function()
            local Core = Hub.Core
            local names = {}
            if Core then
                for _, p in ipairs(Core.killers) do names[#names + 1] = p.DisplayName end
            end
            return "Killer: " .. (#names > 0 and table.concat(names, ", ") or "tidak terdeteksi")
        end)
        d:Info(function()
            local k = Hub.ESP and Hub.ESP.shown or {}
            local objN = 0
            for _, n in pairs(Hub.Obj and Hub.Obj.shown or {}) do objN += n end
            return ("ESP tampil: killer %d  |  survivor %d  |  zombie %d  |  objek %d"):format(
                k.Killer or 0, k.Surv or 0, Hub.Zom and Hub.Zom.shown or 0, objN)
        end)
        d:Info(function()
            local n, first = 0, nil
            for k, v in pairs(Hub.Err) do
                n += 1
                first = first or (k .. ": " .. tostring(v))
            end
            local failed = 0
            for _ in pairs(Hub.failed or {}) do failed += 1 end
            if n == 0 and failed == 0 then return "Status: semua modul normal" end
            return ("Status: %d error, %d modul gagal\n%s"):format(n, failed, first or "")
        end)
        d:Section("Pintasan")
        d:Toggle("ESP Killer", "ESPKiller")
        d:Toggle("ESP Survivor", "ESPSurv")
        d:Toggle("ESP Zombie", "ESPZombie")
        d:Toggle("Full bright", "Fullbright")
        d:Toggle("Mode hemat performa", "PerfMode")

        ----------------------------------------------------------------
        -- ESP
        ----------------------------------------------------------------
        local e = UI.page("ESP", 2)
        e:Section("Tampilan label")
        e:Toggle("Tampilkan nama", "ShowName")
        e:Toggle("Tampilkan jarak", "ShowDist")
        e:Toggle("Tampilkan HP", "ShowHP")
        e:Toggle("Tag killer", "ShowRole")
        e:Slider("Transparansi sorot", "FillT", 0, 100, 5, "%")
        e:Slider("Ukuran teks", "TextSize", 9, 22, 1, "")
        e:Choice("Mode ESP", "ESPMode", { "CoreGui", "Workspace" })
        catControls(e, Hub.CAT.Killer)
        catControls(e, Hub.CAT.Surv)

        ----------------------------------------------------------------
        -- OBJEK
        ----------------------------------------------------------------
        local o = UI.page("Objek", 3)
        for _, g in ipairs(Hub.OBJ_GROUPS) do catControls(o, g) end

        ----------------------------------------------------------------
        -- ZOMBIE
        ----------------------------------------------------------------
        local z = UI.page("Zombie", 4)
        catControls(z, Hub.CAT.Zombie)
        z:Toggle("Semua NPC (abaikan kata kunci)", "ZomAll")

        ----------------------------------------------------------------
        -- ROLE
        ----------------------------------------------------------------
        local r = UI.page("Role", 5)
        r:Info(function()
            local Core = Hub.Core
            if not Core or #Core.info == 0 then return "Belum ada pemain terdeteksi" end
            local lines = {}
            for _, e2 in ipairs(Core.info) do
                lines[#lines + 1] = ("%s  %s   skor %d"):format(e2.killer and "Killer" or "Survivor", e2.p.DisplayName, e2.score)
            end
            return table.concat(lines, "\n")
        end)
        r:Section("Deteksi")
        r:Slider("Jumlah killer", "KillerCount", 1, 4, 1, "")
        r:Button(function()
            return "Killer manual: " .. (Cfg.ManualKiller ~= "" and Cfg.ManualKiller or "Auto")
        end, function()
            local names = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP then names[#names + 1] = p.Name end
            end
            local idx = table.find(names, Cfg.ManualKiller)
            local nxt
            if Cfg.ManualKiller == "" then
                nxt = names[1] or ""
            elseif idx then
                nxt = names[idx + 1] or ""
            else
                nxt = ""
            end
            Config.set("ManualKiller", nxt)
        end)
        r:Button("Deteksi ulang", function()
            if Hub.Core then Hub.Core.dirty = true end
            UI.toast("Deteksi ulang dijadwalkan")
        end)
        r:Button("Salin data pemain", function()
            if Hub.Core and copy(Hub.Core.dump()) then
                UI.toast("Disalin ke clipboard")
            else
                UI.toast("Clipboard tidak didukung")
            end
        end)

        ----------------------------------------------------------------
        -- CONFIG (halaman Misc ada di world.lua, urutan 6)
        ----------------------------------------------------------------
        local c = UI.page("Config", 7)
        c:Section("Profil")
        c:Input("Nama profil", "ProfileName")
        c:Button("Simpan profil", function()
            local ok, err = Config.saveProfile(Cfg.ProfileName)
            UI.toast(ok and "Profil disimpan" or ("Gagal: " .. tostring(err)))
        end, "primary")
        c:Button("Muat profil", function()
            local ok, err = Config.loadProfile(Cfg.ProfileName)
            UI.toast(ok and "Profil dimuat" or ("Gagal: " .. tostring(err)))
        end)
        c:Button("Hapus profil", function()
            Config.deleteProfile(Cfg.ProfileName)
            UI.toast("Profil dihapus")
        end, true)
        c:Info(function()
            local l = Config.listProfiles()
            return "Profil tersimpan: " .. (#l > 0 and table.concat(l, ", ") or "belum ada")
        end)

        c:Section("Preset")
        for _, name in ipairs(Config.presetNames()) do
            c:Button(name, function()
                Config.applyPreset(name)
                UI.toast("Preset diterapkan: " .. name)
            end)
        end

        c:Section("Tampilan")
        c:Color("Warna aksen", "UIAccent")
        c:Button("Reset ukuran jendela", function()
            UI.resetWindow()
            UI.toast("Ukuran jendela direset")
        end)

        c:Section("Sistem")
        c:Button("Salin konfigurasi (JSON)", function()
            UI.toast(copy(Config.export()) and "Konfigurasi disalin" or "Clipboard tidak didukung")
        end)
        c:Button("Salin diagnosis", function()
            UI.toast(copy(diag()) and "Diagnosis disalin" or "Clipboard tidak didukung")
        end)
        c:Button("Reset semua pengaturan", function()
            Config.resetAll()
            UI.toast("Semua pengaturan dikembalikan ke default")
        end, true)
        c:Button("Unload script", function() Hub.unload() end, true)
    end)
end
end)()

local function getModule(name)
    if EMBEDDED[name] then return EMBEDDED[name] end
    local src
    if SOURCE.mode == "url" then
        src = game:HttpGet(SOURCE.base .. name .. ".lua")
    else
        src = readfile(SOURCE.folder .. name .. ".lua")
    end
    local fn, err = loadstring(src, "=" .. name)
    if not fn then error(err, 0) end
    return fn()
end

local Hub = { failed = {}, loaded = {} }
if getgenv then getgenv().TOFHub = Hub end -- tersedia sejak awal untuk debug

for _, name in ipairs(ORDER) do
    local ok, err = pcall(function()
        local init = getModule(name)
        init(Hub)
    end)
    if ok then
        Hub.loaded[#Hub.loaded + 1] = name
    else
        Hub.failed[name] = tostring(err)
        warn("[TOFHub] modul '" .. name .. "' gagal: " .. tostring(err))
        if CRITICAL[name] then
            if Hub.unload then pcall(Hub.unload) end
            return
        end
    end
end

if getgenv then getgenv().TOFHubUnload = Hub.unload end
Hub.start()

local nFail = 0
for _ in pairs(Hub.failed) do nFail += 1 end
print(("[TOFHub] %d modul dimuat, %d gagal"):format(#Hub.loaded, nFail))
