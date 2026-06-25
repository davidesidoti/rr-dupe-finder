-- RR Dupe Finder — configuration
return {
    Debug            = false,   -- verbose logging (e.g. count of skipped/unreadable cassettes)
    ScanKey          = "F6",    -- resolved in main.lua via Key[ScanKey]
    Modifiers        = {},      -- optional, e.g. { "CONTROL" }, resolved via ModifierKey[name]
    MinCopies        = 2,       -- flag SKUs owned in >= this many copies
    ExcludeRented    = true,    -- v3: don't label rented copies (you can't sell them)
    -- v2/v3 in-world markers (HighlightEnabled = master gate; the two sub-toggles pick the style):
    HighlightEnabled = true,                                    -- false → report only, no in-world mark
    OutlineEnabled   = true,                                    -- v2 amber outline shell (spot from afar)
    TextLabelEnabled = false,                                   -- v3 floating red "DUPLICATE" 3D text.
                                                                -- TEMP false: the TextRenderActor spawn
                                                                -- native-crashes (under investigation); the
                                                                -- custom-pak texture sticker also FAILED the
                                                                -- load gate (#1101 — see v3 tooling recon)
    TextColor        = { R = 255, G = 0, B = 0, A = 255 },      -- FColor 0-255 for the 3D text
    TextWorldSize    = 18,                                      -- world height of the text (cm); tune in-game
    TintColor        = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },  -- INFORMATIONAL ONLY: the outline colour is
                                                                -- fixed by its material (recon R3; DMIs crash)
    ClearKey         = nil,                                     -- optional key to clear markers; nil = none
}
