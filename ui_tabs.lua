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
