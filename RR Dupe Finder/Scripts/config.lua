-- RR Dupe Finder — configuration
return {
    Debug            = false,   -- verbose logging (e.g. count of skipped/unreadable cassettes)
    ScanKey          = "F6",    -- resolved in main.lua via Key[ScanKey]
    Modifiers        = {},      -- optional, e.g. { "CONTROL" }, resolved via ModifierKey[name]
    MinCopies        = 2,       -- flag SKUs owned in >= this many copies
    ExcludeRented    = true,    -- v3: don't label rented copies (you can't sell them)
    -- v2 in-world marker = the amber outline shell over each sellable duplicate. (v3 tried a custom
    -- "DUPLICATE" sticker and 3D text; both proved unviable on this title — see CLAUDE.md §10/gotchas.)
    HighlightEnabled = true,                                    -- false → report only, no in-world mark
    TintColor        = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },  -- INFORMATIONAL ONLY: the outline colour is
                                                                -- fixed by its material (recon R3; DMIs crash)
    ClearKey         = nil,                                     -- optional key to clear markers; nil = none
}
