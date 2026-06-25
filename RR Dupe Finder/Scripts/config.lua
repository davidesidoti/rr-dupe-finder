-- RR Dupe Finder — configuration
return {
    Debug            = false,   -- verbose logging (e.g. count of skipped/unreadable cassettes)
    ScanKey          = "F6",    -- resolved in main.lua via Key[ScanKey]
    Modifiers        = {},      -- optional, e.g. { "CONTROL" }, resolved via ModifierKey[name]
    MinCopies        = 2,       -- flag SKUs owned in >= this many copies
    ExcludeRented    = true,    -- v3: don't label rented copies (you can't sell them)
    KeepOneCopy      = true,    -- v3: mark only the EXTRA copies to sell, leaving one copy of each
                                -- movie unmarked as your keeper. false = mark every duplicate copy.

    -- v4 in-world markers. MarkerStyle picks which marker(s) spawn over each sellable dupe:
    --   "outline" → v3 amber box outline only (THE INSTANT REVERT to v3 behaviour).
    --   "beacon"  → only the high-contrast marker floated above the box.
    --   "both"    → outline (good up close) + beacon (visible at distance / when colours clash).
    HighlightEnabled   = true,                          -- false → report only, no in-world mark
    MarkerStyle        = "both",                        -- "outline" | "beacon" | "both"
    BeaconZOffset      = 40,                             -- units the beacon floats above the cassette
    BeaconScale        = 1.3,                            -- beacon mesh scale (reads at distance)
    BeaconAnimate      = false,                          -- DISABLED (crash). LoopAsync runs Lua on a worker
                                                         -- thread; concurrent with game-thread Lua it corrupts
                                                         -- the VM → EXCEPTION_ACCESS_VIOLATION ~40-60s after a
                                                         -- scan (crash dump 2026-06-25 16:59). Keep false unless
                                                         -- a GAME-THREAD-safe animation is proven. See CLAUDE.md.
    BeaconBobAmplitude = 6,                              -- vertical bob, units
    BeaconBobSpeed     = 3.0,                            -- bob rate, radians/sec
    BeaconSpinSpeed    = 90,                             -- spin rate, degrees/sec

    -- v2 outline marker colour is fixed by its material (recon R3; DMIs crash — gotcha 10).
    TintColor          = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },  -- INFORMATIONAL ONLY
    ClearKey           = nil,                            -- optional key to clear markers; nil = none
}
