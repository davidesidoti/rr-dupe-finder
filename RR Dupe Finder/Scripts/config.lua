-- RR Dupe Finder — configuration
return {
    Debug            = false,   -- verbose logging (e.g. count of skipped/unreadable cassettes)
    ScanKey          = "F6",    -- resolved in main.lua via Key[ScanKey]
    Modifiers        = {},      -- optional, e.g. { "CONTROL" }, resolved via ModifierKey[name]
    MinCopies        = 2,       -- flag SKUs owned in >= this many copies
    -- v2:
    HighlightEnabled = true,                                    -- false → report only, no tint
    TintColor        = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },  -- INFORMATIONAL ONLY in v2: the
                                                                -- outline shell's colour is fixed by
                                                                -- its material (recon R3; DMIs crash)
    ClearKey         = nil,                                     -- optional key to clear tint; nil = none
}
