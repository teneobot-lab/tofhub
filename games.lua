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
