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
    "violence_district",
}

-- gagal di salah satu ini = hentikan semuanya
local CRITICAL = { hub = true, games = true, config = true, cats = true }

local EMBEDDED = {}

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
