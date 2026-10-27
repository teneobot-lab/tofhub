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
