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
