-- ui.lua | mesin UI: sidebar + pencarian fitur + kartu kontrol
-- Modul lain menambah halaman lewat:
--   Hub.ui(function(UI)
--       local p = UI.page("Nama Tab", "🙂")   -- ikon opsional
--       p:Section("Judul grup")
--       p:Toggle("Label", "KeyCfg")
--   end)
-- Semua kontrol terikat ke Cfg lewat Config.set / Config.watch, jadi muat profil otomatis memperbarui tampilan.
-- Kontrol yang punya label ikut terindeks untuk pencarian (halaman + judul grup + label).
return function(Hub)
    local UIS = game:GetService("UserInputService")
    local TS = game:GetService("TweenService")
    local Cfg, Config, U = Hub.Cfg, Hub.Config, Hub.util

    Config.declare({ UIAccent = Color3.fromRGB(0, 170, 255) })

    local T = {
        bg = Color3.fromRGB(14, 14, 18),
        side = Color3.fromRGB(20, 20, 26),
        surface = Color3.fromRGB(28, 28, 36),
        raised = Color3.fromRGB(40, 40, 52),
        line = Color3.fromRGB(46, 46, 60),
        text = Color3.fromRGB(238, 238, 244),
        muted = Color3.fromRGB(140, 140, 158),
        danger = Color3.fromRGB(190, 55, 55),
        accent = Cfg.UIAccent,
    }

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
        new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o)
    end
    local function stroke(o, col, tr)
        return new("UIStroke", { Color = col or T.line, Thickness = 1, Transparency = tr or 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
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
    local function tween(o, props, t)
        TS:Create(o, TweenInfo.new(t or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end
    local function isPress(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end

    local drag = {}
    local function startDrag(fn, done) drag.fn, drag.done = fn, done end

    --========================================================
    -- JENDELA
    --========================================================
    local gui, win, float, navSf, pagesHolder, resultsSf, emptyLbl, headerLbl, searchBox, toastLbl
    local resHeaders = {}
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

    --========================================================
    -- PENCARIAN: kontrol yang cocok dipindah sementara ke daftar hasil, lalu dikembalikan
    --========================================================
    local function clearSearch()
        for _, h in ipairs(resHeaders) do pcall(function() h:Destroy() end) end
        resHeaders = {}
        for _, e in ipairs(UI.rows) do
            if e.row.Parent == resultsSf then
                e.row.Parent = e.page.sf
                e.row.LayoutOrder = e.order
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
                    local h = label(resultsSf, key, 11, T.muted, {
                        Size = UDim2.new(1, 0, 0, 18), LayoutOrder = n, Font = Enum.Font.GothamBold,
                    })
                    resHeaders[#resHeaders + 1] = h
                end
                n += 1
                e.row.Parent = resultsSf
                e.row.LayoutOrder = n
            end
        end
        emptyLbl.Visible = (n == 0)
    end

    local function build()
        local vp = workspace.CurrentCamera.ViewportSize
        local W = math.min(560, math.floor(vp.X * 0.94))
        local H = math.min(340, math.floor(vp.Y * 0.88))
        local SBW = (W < 440) and 104 or 134

        gui = new("ScreenGui", {
            Name = "TOFHubUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10000,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        }, Hub.container)

        win = new("Frame", {
            Size = UDim2.fromOffset(W, H),
            Position = UDim2.fromOffset(math.floor((vp.X - W) / 2), math.floor((vp.Y - H) / 2)),
            BackgroundColor3 = T.bg, BorderSizePixel = 0, Active = true, ClipsDescendants = true,
        }, gui)
        corner(win, 12)
        stroke(win, T.line, 0.2)

        -- bar atas (tarik untuk memindahkan)
        local top = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.side, BorderSizePixel = 0 }, win)
        local logo = label(top, "◆  TOF Hub", 14, T.accent, {
            Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -90, 1, 0), Font = Enum.Font.GothamBold,
        })
        UI.accent(function() logo.TextColor3 = T.accent end)
        local function topBtn(text, xOff, color)
            return new("TextButton", {
                Text = text, Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, xOff, 0, 0),
                BackgroundTransparency = 1, TextColor3 = color or T.muted, TextSize = 16, Font = Enum.Font.GothamBold,
            }, top)
        end
        local minBtn = topBtn("–", -60)
        local closeBtn = topBtn("✕", -30, T.danger)

        top.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            local sp, sw = i.Position, win.Position
            startDrag(function(pos)
                local v = workspace.CurrentCamera.ViewportSize
                local x = math.clamp(sw.X.Offset + (pos.X - sp.X), -win.AbsoluteSize.X + 60, v.X - 60)
                local y = math.clamp(sw.Y.Offset + (pos.Y - sp.Y), 0, v.Y - 30)
                win.Position = UDim2.fromOffset(x, y)
            end)
        end)

        local body = new("Frame", {
            Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1,
        }, win)

        ------------------------------------------------------------
        -- SIDEBAR
        ------------------------------------------------------------
        local side = new("Frame", {
            Size = UDim2.new(0, SBW, 1, 0), BackgroundColor3 = T.side, BorderSizePixel = 0,
        }, body)
        new("Frame", {
            Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = T.line, BorderSizePixel = 0,
        }, side)

        local sWrap = new("Frame", {
            Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 30), BackgroundColor3 = T.raised, BorderSizePixel = 0,
        }, side)
        corner(sWrap, 8)
        searchBox = new("TextBox", {
            Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -30, 1, 0), BackgroundTransparency = 1,
            Text = "", PlaceholderText = "🔍 Cari fitur", PlaceholderColor3 = T.muted, TextColor3 = T.text,
            Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
        }, sWrap)
        local clearBtn = new("TextButton", {
            Text = "✕", Size = UDim2.fromOffset(22, 30), Position = UDim2.new(1, -24, 0, 0),
            BackgroundTransparency = 1, TextColor3 = T.muted, TextSize = 12, Font = Enum.Font.GothamBold, Visible = false,
        }, sWrap)
        clearBtn.Activated:Connect(function() searchBox.Text = "" end)

        navSf = new("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -66), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, side)
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, navSf)
        new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2) }, navSf)

        label(side, "modular • v5", 10, T.muted, {
            Position = UDim2.new(0, 12, 1, -18), Size = UDim2.new(1, -24, 0, 14),
        })

        ------------------------------------------------------------
        -- KONTEN
        ------------------------------------------------------------
        local content = new("Frame", {
            Position = UDim2.fromOffset(SBW, 0), Size = UDim2.new(1, -SBW, 1, 0), BackgroundTransparency = 1,
        }, body)
        headerLbl = label(content, "", 16, T.text, {
            Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 26), Font = Enum.Font.GothamBold,
        })
        pagesHolder = new("Frame", {
            Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -50), BackgroundTransparency = 1,
        }, content)
        toastLbl = label(content, "", 11, T.muted, {
            Position = UDim2.new(0, 12, 1, -16), Size = UDim2.new(1, -24, 0, 14),
        })

        resultsSf = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
            ScrollBarImageColor3 = T.raised, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
        }, pagesHolder)
        new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, resultsSf)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        }, resultsSf)
        emptyLbl = label(pagesHolder, "Tidak ada fitur yang cocok", 13, T.muted, {
            Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 20), TextXAlignment = Enum.TextXAlignment.Center,
            Visible = false,
        })

        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            clearBtn.Visible = searchBox.Text ~= ""
            applySearch()
        end)

        ------------------------------------------------------------
        -- TOMBOL MELAYANG (saat diminimalkan)
        ------------------------------------------------------------
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
            p.tab.BackgroundTransparency = on and 0.82 or 1
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

    function UI.page(name, icon)
        if UI.pages[name] then return UI.pages[name] end
        local sf = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = T.raised, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
        }, pagesHolder)
        new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        }, sf)

        local tab = new("TextButton", {
            Text = "", Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.accent, BackgroundTransparency = 1,
            BorderSizePixel = 0, AutoButtonColor = false, LayoutOrder = #UI.order + 1,
        }, navSf)
        corner(tab, 8)
        local bar = new("Frame", {
            Size = UDim2.fromOffset(3, 18), Position = UDim2.new(0, 0, 0.5, -9), BackgroundColor3 = T.accent,
            BorderSizePixel = 0, Visible = false,
        }, tab)
        corner(bar, 2)
        if icon then
            label(tab, icon, 15, T.text, {
                Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(22, 34), TextXAlignment = Enum.TextXAlignment.Center,
            })
        end
        local txt = label(tab, name, 13, T.muted, {
            Position = UDim2.fromOffset(icon and 34 or 12, 0), Size = UDim2.new(1, icon and -38 or -16, 1, 0),
            Font = Enum.Font.GothamMedium, TextTruncate = Enum.TextTruncate.AtEnd,
        })

        local page = setmetatable({ name = name, sf = sf, tab = tab, bar = bar, txt = txt, n = 0, section = "" }, Page)
        UI.pages[name] = page
        UI.order[#UI.order + 1] = page
        tab.Activated:Connect(function() selectPage(page) end)
        return page
    end

    -- kartu dasar; `text` (opsional) membuat kontrol ikut terindeks untuk pencarian
    function Page:row(h, text)
        self.n += 1
        local r = new("Frame", {
            Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = T.surface, BorderSizePixel = 0, LayoutOrder = self.n,
        }, self.sf)
        corner(r, 8)
        stroke(r)
        if text then
            UI.rows[#UI.rows + 1] = { row = r, page = self, section = self.section, text = tostring(text), order = self.n }
        end
        return r
    end

    function Page:Section(text)
        self.n += 1
        self.section = text
        local l = label(self.sf, text:upper(), 11, T.accent, {
            Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBold, LayoutOrder = self.n,
        })
        UI.accent(function() l.TextColor3 = T.accent end)
    end

    function Page:Toggle(text, key)
        local r = self:row(36, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -72, 1, 0) })
        local sw = new("Frame", {
            Size = UDim2.fromOffset(40, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
            BorderSizePixel = 0,
        }, r)
        corner(sw, 11)
        local dot = new("Frame", {
            Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        }, sw)
        corner(dot, 9)
        local first = true
        local function paint()
            local on = Cfg[key] == true
            local col = on and T.accent or T.raised
            local pos = UDim2.fromOffset(on and 20 or 2, 2)
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
        local r = self:row(50, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -100, 0, 18) })
        local chip = new("Frame", {
            Size = UDim2.fromOffset(70, 20), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 5),
            BackgroundColor3 = T.raised, BorderSizePixel = 0,
        }, r)
        corner(chip, 6)
        local vl = label(chip, "", 12, T.text, {
            Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamMedium,
        })
        local track = new("Frame", {
            Position = UDim2.new(0, 12, 0, 36), Size = UDim2.new(1, -24, 0, 6), BackgroundColor3 = T.raised, BorderSizePixel = 0,
        }, r)
        corner(track, 3)
        local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, track)
        corner(fill, 3)
        local knob = new("Frame", {
            Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        }, track)
        corner(knob, 8)

        local function paint()
            local v = tonumber(Cfg[key]) or min
            local a = math.clamp((v - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, -8, 0.5, -8)
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
            Text = "", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 0, 26),
        }, r)
        hit.InputBegan:Connect(function(i)
            if not isPress(i) then return end
            -- pemilik gulir bisa halaman biasa atau daftar hasil pencarian
            local scroller = r:FindFirstAncestorWhichIsA("ScrollingFrame")
            if scroller then scroller.ScrollingEnabled = false end
            setFrom(i.Position.X)
            startDrag(function(pos) setFrom(pos.X) end, function()
                if scroller then scroller.ScrollingEnabled = true end
            end)
        end)
    end

    function Page:Color(text, key)
        local r = self:row(38, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -130, 1, 0) })
        local sw = new("Frame", {
            Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -94, 0.5, 0),
            BorderSizePixel = 0,
        }, r)
        corner(sw, 6)
        stroke(sw, T.text, 0.7)
        local tb = new("TextBox", {
            Size = UDim2.fromOffset(76, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, Font = Enum.Font.Gotham, TextSize = 12,
            ClearTextOnFocus = false, BorderSizePixel = 0, Text = "",
        }, r)
        corner(tb, 6)
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
        local r = self:row(36, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, -12, 1, 0) })
        local b = new("TextButton", {
            Size = UDim2.new(0.5, -22, 0, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, Font = Enum.Font.GothamMedium, TextSize = 12,
            BorderSizePixel = 0, AutoButtonColor = false, Text = "",
        }, r)
        corner(b, 6)
        local function paint() b.Text = tostring(Cfg[key]) .. "  ›" end
        paint()
        Config.watch(key, paint)
        b.Activated:Connect(function()
            local idx = table.find(options, Cfg[key]) or 0
            Config.set(key, options[idx % #options + 1])
        end)
    end

    function Page:Input(text, key, placeholder)
        local r = self:row(36, text)
        label(r, text, 13, T.text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.4, -12, 1, 0) })
        local tb = new("TextBox", {
            Size = UDim2.new(0.6, -22, 0, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            BackgroundColor3 = T.raised, TextColor3 = T.text, PlaceholderColor3 = T.muted, Font = Enum.Font.Gotham,
            TextSize = 12, ClearTextOnFocus = false, BorderSizePixel = 0, Text = "", PlaceholderText = placeholder or "",
        }, r)
        corner(tb, 6)
        local function paint() tb.Text = tostring(Cfg[key]) end
        paint()
        Config.watch(key, paint)
        tb.FocusLost:Connect(function() Config.set(key, tb.Text) end)
    end

    -- teks bisa string atau fungsi (fungsi diperbarui tiap 0.5 detik saat terlihat)
    -- style: true / "danger" = merah, "primary" = warna aksen
    function Page:Button(text, cb, style)
        local initial = type(text) == "function" and select(2, pcall(text)) or text
        local r = self:row(36, initial)
        r.BackgroundTransparency = 1
        for _, c in ipairs(r:GetChildren()) do
            if c:IsA("UIStroke") then c:Destroy() end
        end
        local b = new("TextButton", {
            Size = UDim2.new(1, 0, 1, 0), TextColor3 = T.text, Font = Enum.Font.GothamMedium, TextSize = 13,
            BorderSizePixel = 0, AutoButtonColor = true, Text = "",
        }, r)
        corner(b, 8)
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
        self.n += 1
        local r = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.surface,
            BorderSizePixel = 0, LayoutOrder = self.n,
        }, self.sf)
        corner(r, 8)
        stroke(r)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
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
            if UI.order[1] then selectPage(UI.order[1]) end
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
