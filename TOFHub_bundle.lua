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
    "esp_players", "esp_objects", "esp_zombies", "ui_tabs",
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
                ["ESP saja"] = {
                    Aimlock = false, Silent = false, KAim = false, KSilent = false,
                    Speed = false, Fly = false, Noclip = false,
                    ESPKiller = true, ESPSurv = true,
                },
                ["Semua mati"] = {
                    Aimlock = false, Silent = false, KAim = false, KSilent = false,
                    Speed = false, Fly = false, Noclip = false, Fullbright = false,
                    ESPKiller = false, ESPSurv = false, ESPZombie = false,
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

    function Config.loadProfile(name)
        if not (readfile and isfile) then return false, "readfile tidak didukung" end
        local path = profilePath(name)
        if not isfile(path) then return false, "profil tidak ada" end
        local ok, raw = pcall(readfile, path)
        local d = ok and decodeJSON(raw)
        if not d then return false, "profil rusak atau dibuat versi yang lebih baru" end
        for k, v in pairs(d) do
            if k ~= "Ver" and Cfg[k] ~= nil and not volatile[k] then
                local c = coerce(k, v)
                if c ~= nil then Config.set(k, c) end
            end
        end
        return true
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
-- ui.lua | mesin UI: jendela, tab, dan kontrol (Toggle, Slider, Color, Choice, Input, Button, Info)
-- Modul lain menambah halaman lewat:
--   Hub.ui(function(UI)
--       local p = UI.page("Nama Tab")
--       p:Toggle("Label", "KeyCfg")
--   end)
-- Semua kontrol terikat ke Cfg lewat Config.set / Config.watch, jadi muat profil otomatis memperbarui tampilan.
return function(Hub)
    local UIS = game:GetService("UserInputService")
    local Players = Hub.Players
    local Cfg, Config, U = Hub.Cfg, Hub.Config, Hub.util

    Config.declare({ UIAccent = Color3.fromRGB(0, 170, 255) })

    local T = {
        bg = Color3.fromRGB(16, 16, 20),
        surface = Color3.fromRGB(26, 26, 32),
        raised = Color3.fromRGB(42, 42, 52),
        text = Color3.fromRGB(235, 235, 240),
        muted = Color3.fromRGB(150, 150, 165),
        danger = Color3.fromRGB(190, 55, 55),
        accent = Cfg.UIAccent,
    }

    local UI = { pages = {}, order = {}, dyn = {}, accentFns = {}, current = nil, T = T }
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
        new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o)
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
    local function isPress(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end

    -- satu mekanisme drag untuk slider, jendela, dan tombol melayang
    local drag = {}
    local function startDrag(fn, done) drag.fn, drag.done = fn, done end

    --========================================================
    -- JENDELA
    --========================================================
    local gui, win, float, content, tabsBar, toastLbl
    local toastToken = 0

    function UI.toast(text)
        if not toastLbl then return end
        toastToken += 1
        local t = toastToken
        toastLbl.Text = tostring(text)
        task.delay(2.5, function()
            if t == toastToken and toastLbl and toastLbl.Parent then toastLbl.Text = "" end
        end)
    end

    local function showWin(show)
        if not win then return end
        win.Visible = show
        float.Visible = not show
    end

    local function build()
        local vp = workspace.CurrentCamera.ViewportSize
        local W = math.min(480, math.floor(vp.X * 0.92))
        local H = math.min(330, math.floor(vp.Y * 0.8))

        gui = new("ScreenGui", {
            Name = "TOFHubUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10000,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        }, Hub.container)

        win = new("Frame", {
            Size = UDim2.fromOffset(W, H),
            Position = UDim2.fromOffset(math.floor((vp.X - W) / 2), math.floor((vp.Y - H) / 2)),
            BackgroundColor3 = T.bg, BorderSizePixel = 0, Active = true, ClipsDescendants = true,
        }, gui)
        corner(win, 10)
        new("UIStroke", { Color = T.raised, Thickness = 1 }, win)

        -- bar judul
        local title = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.surface, BorderSizePixel = 0 }, win)
        label(title, "TOF Hub", 14, T.text, {
            Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -90, 1, 0), Font = Enum.Font.GothamBold,
        })
        local function titleBtn(text, xOff, color)
            local b = new("TextButton", {
                Text = text, Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, xOff, 0, 0),
                BackgroundTransparency = 1, TextColor3 = color or T.muted, TextSize = 16, Font = Enum.Font.GothamBold,
            }, title)
            return b
        end
        local minBtn = titleBtn("–", -64)
        local closeBtn = titleBtn("✕", -32, T.danger)

        title.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            local sp, sw = i.Position, win.Position
            startDrag(function(pos)
                local v = workspace.CurrentCamera.ViewportSize
                local x = math.clamp(sw.X.Offset + (pos.X - sp.X), -win.AbsoluteSize.X + 60, v.X - 60)
                local y = math.clamp(sw.Y.Offset + (pos.Y - sp.Y), 0, v.Y - 30)
                win.Position = UDim2.fromOffset(x, y)
            end)
        end)

        -- bar tab
        tabsBar = new("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.bg,
            BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
        }, win)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
            VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
        }, tabsBar)
        new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, tabsBar)

        -- isi halaman + toast
        content = new("Frame", {
            Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -82),
            BackgroundTransparency = 1, BorderSizePixel = 0,
        }, win)
        toastLbl = label(win, "", 12, T.muted, {
            Position = UDim2.new(0, 10, 1, -18), Size = UDim2.new(1, -20, 0, 18),
        })

        -- tombol melayang saat diminimalkan
        float = new("TextButton", {
            Text = "T", Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(12, 90),
            BackgroundColor3 = T.bg, TextColor3 = T.accent, TextSize = 20, Font = Enum.Font.GothamBold,
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
    -- HALAMAN + KONTROL
    --========================================================
    local Page = {}
    Page.__index = Page

    local function selectPage(page)
        UI.current = page
        for _, p in pairs(UI.pages) do
            local on = (p == page)
            p.sf.Visible = on
            p.tab.BackgroundColor3 = on and T.accent or T.raised
            p.tab.TextColor3 = on and Color3.new(1, 1, 1) or T.muted
        end
    end
    UI.select = selectPage

    function UI.page(name)
        if UI.pages[name] then return UI.pages[name] end
        local sf = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
        }, content)
        new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        }, sf)

        local tab = new("TextButton", {
            Text = name, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = T.raised, TextColor3 = T.muted, TextSize = 12, Font = Enum.Font.GothamBold,
            BorderSizePixel = 0, AutoButtonColor = false, LayoutOrder = #UI.order + 1,
        }, tabsBar)
        corner(tab, 6)
        new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, tab)

        local page = setmetatable({ name = name, sf = sf, tab = tab, n = 0 }, Page)
        UI.pages[name] = page
        UI.order[#UI.order + 1] = page
        tab.Activated:Connect(function() selectPage(page) end)
        return page
    end

    function Page:row(h)
        self.n += 1
        local r = new("Frame", {
            Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = T.surface, BorderSizePixel = 0, LayoutOrder = self.n,
        }, self.sf)
        corner(r, 6)
        return r
    end

    function Page:Section(text)
        self.n += 1
        local l = label(self.sf, text, 13, T.accent, {
            Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.GothamBold, LayoutOrder = self.n,
        })
        UI.accent(function() l.TextColor3 = T.accent end)
    end

    function Page:Toggle(text, key)
        local r = self:row(34)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -70, 1, 0) })
        local sw = new("Frame", {
            Size = UDim2.fromOffset(42, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            BorderSizePixel = 0,
        }, r)
        corner(sw, 11)
        local dot = new("Frame", {
            Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        }, sw)
        corner(dot, 9)
        local function paint()
            local on = Cfg[key] == true
            sw.BackgroundColor3 = on and T.accent or T.raised
            dot.Position = UDim2.fromOffset(on and 22 or 2, 2)
        end
        paint()
        UI.accent(paint)
        Config.watch(key, paint)
        local hit = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0) }, r)
        hit.Activated:Connect(function() Config.set(key, not Cfg[key]) end)
    end

    function Page:Slider(text, key, min, max, step, suffix)
        local r = self:row(46)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -100, 0, 18) })
        local vl = label(r, "", 13, T.muted, {
            Position = UDim2.new(1, -90, 0, 4), Size = UDim2.fromOffset(80, 18), TextXAlignment = Enum.TextXAlignment.Right,
        })
        local track = new("Frame", {
            Position = UDim2.new(0, 10, 0, 30), Size = UDim2.new(1, -20, 0, 6),
            BackgroundColor3 = T.raised, BorderSizePixel = 0,
        }, r)
        corner(track, 3)
        local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, track)
        corner(fill, 3)
        local knob = new("Frame", {
            Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        }, track)
        corner(knob, 7)

        local function paint()
            local v = tonumber(Cfg[key]) or min
            local a = math.clamp((v - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, -7, 0.5, -7)
            vl.Text = ("%g%s"):format(v, suffix or "")
            fill.BackgroundColor3 = T.accent
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
            Text = "", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(1, 0, 0, 26),
        }, r)
        local sf = self.sf
        hit.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            sf.ScrollingEnabled = false -- cegah halaman ikut bergulir saat menggeser slider
            setFrom(i.Position.X)
            startDrag(function(pos) setFrom(pos.X) end, function() sf.ScrollingEnabled = true end)
        end)
    end

    function Page:Color(text, key)
        local r = self:row(36)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -130, 1, 0) })
        local sw = new("Frame", {
            Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -92, 0.5, 0),
            BorderSizePixel = 0,
        }, r)
        corner(sw, 5)
        local tb = new("TextBox", {
            Size = UDim2.fromOffset(76, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, Font = Enum.Font.Gotham, TextSize = 12,
            ClearTextOnFocus = false, BorderSizePixel = 0, Text = "",
        }, r)
        corner(tb, 5)
        local function paint()
            local c = Cfg[key]
            if typeof(c) == "Color3" then
                sw.BackgroundColor3 = c
                tb.Text = "#" .. U.hex(c)
            end
        end
        paint()
        Config.watch(key, paint)
        tb.FocusLost:Connect(function()
            local c = U.parseHex(tb.Text)
            if c then Config.set(key, c) else paint() end
        end)
    end

    function Page:Choice(text, key, options)
        local r = self:row(34)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.5, -10, 1, 0) })
        local b = new("TextButton", {
            Size = UDim2.new(0.5, -20, 0, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, Font = Enum.Font.Gotham, TextSize = 12,
            BorderSizePixel = 0, AutoButtonColor = false, Text = "",
        }, r)
        corner(b, 5)
        local function paint() b.Text = tostring(Cfg[key]) end
        paint()
        Config.watch(key, paint)
        b.Activated:Connect(function()
            local idx = table.find(options, Cfg[key]) or 0
            Config.set(key, options[idx % #options + 1])
        end)
    end

    function Page:Input(text, key, placeholder)
        local r = self:row(34)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.4, -10, 1, 0) })
        local tb = new("TextBox", {
            Size = UDim2.new(0.6, -20, 0, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, PlaceholderColor3 = T.muted, Font = Enum.Font.Gotham,
            TextSize = 12, ClearTextOnFocus = false, BorderSizePixel = 0, Text = "", PlaceholderText = placeholder or "",
        }, r)
        corner(tb, 5)
        local function paint() tb.Text = tostring(Cfg[key]) end
        paint()
        Config.watch(key, paint)
        tb.FocusLost:Connect(function() Config.set(key, tb.Text) end)
    end

    -- teks bisa string atau fungsi (fungsi diperbarui tiap 0.5 detik saat halaman terlihat)
    function Page:Button(text, cb, danger)
        self.n += 1
        local b = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = danger and T.danger or T.raised, TextColor3 = T.text,
            Font = Enum.Font.GothamBold, TextSize = 13, BorderSizePixel = 0, AutoButtonColor = true,
            LayoutOrder = self.n, Text = "",
        }, self.sf)
        corner(b, 6)
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
        self.n += 1
        local r = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.surface,
            BorderSizePixel = 0, LayoutOrder = self.n,
        }, self.sf)
        corner(r, 6)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
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
            UI.accent(function() if UI.current then selectPage(UI.current) end end)
            for _, fn in ipairs(builders) do Hub.safe("ui:builder", fn, UI) end
            if UI.order[1] then selectPage(UI.order[1]) end
        end,
        update = function()
            if not (win and win.Visible) then return end
            for _, d in ipairs(UI.dyn) do
                if d.page == UI.current then pcall(d.apply) end
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
        for _, g in ipairs(OBJ_GROUPS) do shown[g.id] = 0 end
        for _, rec in ipairs(list) do
            local g = rec.g
            local ok = pcall(function()
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
                if Cfg[g.chams] and hlCount < 16 then
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
                if Cfg[cat.chams] and i <= 8 then
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

EMBEDDED["ui_tabs"] = (function()
-- ui_tabs.lua | isi halaman UI untuk modul yang sudah ada.
-- Modul baru (Aim, World, Move, ...) cukup memanggil Hub.ui(function(UI) ... end) di file-nya sendiri.
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
        p:Toggle("Chams (sorot)", c.chams)
        p:Toggle("Label", c.label)
        p:Slider("Jarak maksimal", c.dist, 50, 5000, 50, " m")
        p:Color("Warna", c.col)
        if c.keyCfg then p:Input("Kata kunci", c.keyCfg, "pisahkan dengan koma") end
    end

    Hub.ui(function(UI)
        ----------------------------------------------------------------
        -- DASHBOARD
        ----------------------------------------------------------------
        local d = UI.page("Dashboard")
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
            return ("ESP tampil: killer %d | survivor %d | zombie %d | objek %d"):format(
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

        ----------------------------------------------------------------
        -- ESP (umum + Killer + Survivor)
        ----------------------------------------------------------------
        local e = UI.page("ESP")
        e:Section("Tampilan label")
        e:Toggle("Tampilkan nama", "ShowName")
        e:Toggle("Tampilkan jarak", "ShowDist")
        e:Toggle("Tampilkan HP", "ShowHP")
        e:Toggle("Tag [KILLER]", "ShowRole")
        e:Slider("Transparansi sorot", "FillT", 0, 100, 5, "%")
        e:Slider("Ukuran teks", "TextSize", 9, 22, 1, "")
        e:Choice("Mode ESP", "ESPMode", { "CoreGui", "Workspace" })
        catControls(e, Hub.CAT.Killer)
        catControls(e, Hub.CAT.Surv)

        ----------------------------------------------------------------
        -- OBJEK
        ----------------------------------------------------------------
        local o = UI.page("Objek")
        for _, g in ipairs(Hub.OBJ_GROUPS) do catControls(o, g) end

        ----------------------------------------------------------------
        -- ZOMBIE
        ----------------------------------------------------------------
        local z = UI.page("Zombie")
        catControls(z, Hub.CAT.Zombie)
        z:Toggle("Semua NPC (abaikan kata kunci)", "ZomAll")

        ----------------------------------------------------------------
        -- ROLE
        ----------------------------------------------------------------
        local r = UI.page("Role")
        r:Info(function()
            local Core = Hub.Core
            if not Core or #Core.info == 0 then return "Belum ada pemain terdeteksi" end
            local lines = {}
            for _, e2 in ipairs(Core.info) do
                lines[#lines + 1] = ("%s %s  skor %d"):format(e2.killer and "[K]" or "[S]", e2.p.DisplayName, e2.score)
            end
            return table.concat(lines, "\n")
        end)
        r:Slider("Jumlah killer", "KillerCount", 1, 4, 1, "")
        r:Button(function()
            return "Killer manual: " .. (Cfg.ManualKiller ~= "" and Cfg.ManualKiller or "Auto") .. "  (tap ganti)"
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
        r:Button("Salin data pemain (debug)", function()
            if Hub.Core and copy(Hub.Core.dump()) then
                UI.toast("Disalin ke clipboard")
            else
                UI.toast("Clipboard tidak didukung")
            end
        end)

        ----------------------------------------------------------------
        -- PENGATURAN
        ----------------------------------------------------------------
        local s = UI.page("Pengaturan")
        s:Section("Tampilan")
        s:Color("Warna aksen", "UIAccent")
        s:Section("Profil")
        s:Input("Nama profil", "ProfileName", "mis. harian")
        s:Button("Simpan profil", function()
            local ok, err = Config.saveProfile(Cfg.ProfileName)
            UI.toast(ok and "Profil disimpan" or ("Gagal: " .. tostring(err)))
        end)
        s:Button("Muat profil", function()
            local ok, err = Config.loadProfile(Cfg.ProfileName)
            UI.toast(ok and "Profil dimuat" or ("Gagal: " .. tostring(err)))
        end)
        s:Button("Hapus profil", function()
            Config.deleteProfile(Cfg.ProfileName)
            UI.toast("Profil dihapus (jika ada)")
        end, true)
        s:Info(function()
            local l = Config.listProfiles()
            return "Profil tersimpan: " .. (#l > 0 and table.concat(l, ", ") or "(kosong)")
        end)
        s:Section("Preset")
        for _, name in ipairs(Config.presetNames()) do
            s:Button("Preset: " .. name, function()
                Config.applyPreset(name)
                UI.toast("Preset diterapkan: " .. name)
            end)
        end
        s:Section("Lainnya")
        s:Button("Salin diagnosis", function()
            UI.toast(copy(diag()) and "Diagnosis disalin" or "Clipboard tidak didukung")
        end)
        s:Button("Unload script", function() Hub.unload() end, true)
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
