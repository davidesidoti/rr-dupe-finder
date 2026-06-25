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
    -- The beacon is ONE static high-contrast pointer (an arrow aimed DOWN) floated above each
    -- duplicated movie's cluster of sellable copies (not one per cassette). Animation was removed: a
    -- LoopAsync loop hard-crashed the game (async-thread Lua corrupts the VM; crash dump 2026-06-25
    -- 16:59). Do NOT reintroduce an async animation loop. See CLAUDE.md + highlight.lua.
    BeaconZOffset       = 20,                            -- units the pointer floats above the cluster's top copy
    BeaconScale         = 0.08,                           -- pointer mesh scale (SM_3DWidget_Arrow is large)
    BeaconPitch         = 180,                            -- flip the (native-up) arrow to point DOWN at the shelf
    BeaconYaw           = 0,
    BeaconRoll          = 0,
    BeaconClusterRadius = 100,                            -- merge arrows whose copies are within this XY radius
                                                          -- into one (declutters the sell bin / display cabinet)

    -- v2 outline marker colour is fixed by its material (recon R3; DMIs crash — gotcha 10).
    TintColor          = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },  -- INFORMATIONAL ONLY
    ClearKey           = nil,                            -- optional key to clear markers; nil = none
}
