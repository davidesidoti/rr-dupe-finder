-- RR Dupe Finder — configuration
return {
    Debug     = false,   -- verbose logging (e.g. count of skipped/unreadable cassettes)
    ScanKey   = "F6",    -- resolved in main.lua via Key[ScanKey]
    Modifiers = {},      -- optional, e.g. { "CONTROL" }, resolved via ModifierKey[name]
    MinCopies = 2,       -- flag SKUs owned in >= this many copies
}
