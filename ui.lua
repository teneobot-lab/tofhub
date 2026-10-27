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
