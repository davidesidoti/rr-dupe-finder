# rr-dupe-finder — v1 MVP design

**Date:** 2026-06-24
**Status:** Approved, ready for implementation planning
**Scope:** v1 MVP only (detect + report). v2/v3 outlined at the end, not designed here.

---

## 1. Goal

A UE4SS Lua mod for *Retro Rewind: Video Store Simulator* that, on a keypress,
scans every loaded cassette in the store, groups them by SKU, flags any SKU owned
in 2+ copies, and reports each copy's world coordinates plus a total of sellable
extras. Read-only; never modifies save data.

This is genuine new work: the repo currently contains only `README.md`, `CLAUDE.md`,
`LICENSE`, `.gitignore`. No mod code exists yet, despite README/CLAUDE.md §10
describing an "implemented" MVP.

See `CLAUDE.md` for the full reverse-engineered game data model, UE4SS API surface,
and gotchas. This spec assumes that context.

---

## 2. Design principles

- **Modular**: small units, one job each, explicit dependencies, the logic-heavy
  unit (`report.lua`) kept free of UE calls so it is testable outside the game.
- **Reuse what's verified**: the SKU struct path, `FindAllOf`, `pcall`-per-actor,
  and the `require("config")` pattern all come straight from the working **SKU QoL**
  reference mod (`...\ue4ss\Mods\SKU QoL\Scripts\main.lua`).
- **YAGNI**: no game-event hooks in v1 (the scan is on-demand via keybind, so no
  `NotifyOnNewObject`/`RegisterHook` machinery is needed). No rented-filter, no
  highlight, no titles — those are v2/v3.

---

## 3. Repo & mod layout

The shippable mod folder lives inside the repo (matches README's "copy the
`RR Dupe Finder` folder into your mods directory"):

```
rr-dupe-finder/                  (repo root)
├── RR Dupe Finder/              ← shippable mod
│   ├── enabled.txt              (empty file; presence = mod enabled)
│   └── Scripts/
│       ├── main.lua             entry: wiring + keybind
│       ├── config.lua           settings table
│       ├── sku.lua              reverse-engineered SKU read path (isolated)
│       ├── scan.lua             enumerate cassettes → records
│       └── report.lua           group + format (UE-free, unit-testable)
├── tests/
│   └── report_test.lua          pure-Lua tests for report.lua
├── docs/superpowers/specs/      this spec + future specs
├── README.md  CLAUDE.md  LICENSE  .gitignore
```

---

## 4. Modules

Five units. `report.lua` makes **zero UE calls** — that is deliberate, so its
grouping/sorting/sellable-math (the only real branching logic) is testable with a
standalone Lua interpreter.

| Module | Responsibility | Depends on | UE calls? |
|--------|----------------|-----------|-----------|
| `config.lua` | settings table | — | no |
| `sku.lua` | `isCartridge(obj)`, `read(cart)` → SKU int; isolates the GUID-mangled struct keys | — | yes |
| `scan.lua` | `run()` → array of cassette records | `sku` | yes |
| `report.lua` | `analyze(records, minCopies)`, `format(analysis)` | — | **no** |
| `main.lua` | require all, resolve key, bind it, run scan→analyze→format on game thread | all | yes |

`sku.lua` is split out (rather than folded into `scan.lua`) because the
GUID-suffixed struct path is the single most build-fragile thing in the codebase —
a future game update should touch exactly one small file.

### 4.1 `config.lua`

```lua
return {
    Debug     = false,   -- verbose logging (e.g. count of skipped/unreadable cassettes)
    ScanKey   = "F6",    -- resolved in main via Key[ScanKey]
    Modifiers = {},      -- optional, e.g. { "CONTROL" }, resolved via ModifierKey[name]
    MinCopies = 2,       -- flag SKUs owned in >= this many copies
}
```

### 4.2 `sku.lua`

```lua
local M = {}

-- GUID-mangled Blueprint struct property names. Verbatim from SKU QoL. Do NOT guess.
local PRODUCT_STRUCTURE_KEY = "Product Structure"
local BASE_STRUCTURE_KEY    = "BaseStructure_2_FBB12C464AE570CAFD12ED8506160683"
local BOX_DATA_KEY          = "BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10"
local SKU_KEY               = "SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876"

function M.isCartridge(obj)
    if not obj or not obj:IsValid() then return false end
    if obj:GetFullName():find("Default__") then return false end   -- skip CDO
    return true
end

function M.read(cart)
    local ps   = cart[PRODUCT_STRUCTURE_KEY]; if not ps   then return nil end
    local base = ps[BASE_STRUCTURE_KEY];      if not base then return nil end
    local box  = base[BOX_DATA_KEY];          if not box  then return nil end
    return box[SKU_KEY]
end

return M
```

### 4.3 `scan.lua`

```lua
local sku = require("sku")
local M = {}

-- Returns: array of { sku=<int>, x=, y=, z=, name=<fullname> }
function M.run()
    local out = {}
    local carts = FindAllOf("Cartridge_Base_C") or {}
    for _, cart in pairs(carts) do
        pcall(function()                       -- one bad actor never aborts the scan
            if not sku.isCartridge(cart) then return end
            local s = sku.read(cart); if not s then return end
            local loc = cart:K2_GetActorLocation()
            out[#out + 1] = { sku = s, x = loc.X, y = loc.Y, z = loc.Z, name = cart:GetFullName() }
        end)
    end
    return out
end

return M
```

### 4.4 `report.lua` (pure — no UE calls)

```lua
local M = {}

-- records: array of { sku, x, y, z }
-- Returns: { totalCarts, uniqueSkus, dupes = { {sku, copies, locs={{x,y,z},...}} }, sellableExtras }
function M.analyze(records, minCopies)
    minCopies = minCopies or 2
    local bySku, order = {}, {}
    for _, r in ipairs(records) do
        local g = bySku[r.sku]
        if not g then g = { sku = r.sku, locs = {} }; bySku[r.sku] = g; order[#order+1] = r.sku end
        g.locs[#g.locs + 1] = { x = r.x, y = r.y, z = r.z }
    end
    local dupes, sellable = {}, 0
    for _, s in ipairs(order) do
        local g = bySku[s]
        g.copies = #g.locs
        if g.copies >= minCopies then
            dupes[#dupes + 1] = g
            sellable = sellable + (g.copies - 1)
        end
    end
    table.sort(dupes, function(a, b)
        if a.copies ~= b.copies then return a.copies > b.copies end   -- most-duplicated first
        return a.sku < b.sku                                          -- tie-break by SKU asc
    end)
    return { totalCarts = #records, uniqueSkus = #order, dupes = dupes, sellableExtras = sellable }
end

-- Returns: array of strings (no prefix; main adds the "[RR-Dupe] " tag)
function M.format(a)
    local lines = {}
    if a.totalCarts == 0 then lines[1] = "No cassettes found."; return lines end
    lines[#lines+1] = string.format("Scan complete: %d cassettes, %d unique SKUs, %d duplicated.",
        a.totalCarts, a.uniqueSkus, #a.dupes)
    if #a.dupes == 0 then lines[#lines+1] = "No duplicates — collection is clean."; return lines end
    for _, g in ipairs(a.dupes) do
        lines[#lines+1] = string.format("SKU %s — %d copies:", tostring(g.sku), g.copies)
        for i, p in ipairs(g.locs) do
            lines[#lines+1] = string.format("    #%d  (%.1f, %.1f, %.1f)", i, p.x, p.y, p.z)
        end
    end
    lines[#lines+1] = string.format(
        "Total sellable extras: %d   (sum of copies-1 across duplicated SKUs)", a.sellableExtras)
    return lines
end

return M
```

### 4.5 `main.lua`

```lua
local Config = require("config")
local scan   = require("scan")
local report = require("report")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

local function runScan()
    local records  = scan.run()
    local analysis = report.analyze(records, Config.MinCopies)
    for _, line in ipairs(report.format(analysis)) do log(line) end
end

local function onScanKey()
    ExecuteInGameThread(function()                 -- UObject reads must be on the game thread
        local ok, err = pcall(runScan)
        if not ok then log("Scan error: " .. tostring(err)) end
    end)
end

local key = Key[Config.ScanKey]
if Config.Modifiers and #Config.Modifiers > 0 then
    local mods = {}
    for _, name in ipairs(Config.Modifiers) do mods[#mods+1] = ModifierKey[name] end
    RegisterKeyBind(key, mods, onScanKey)
else
    RegisterKeyBind(key, onScanKey)
end

log("RR Dupe Finder loaded. Press " .. Config.ScanKey .. " to scan.")
```

The snippets above are the reference target for implementation; sessions may refine
naming/formatting but must preserve the module boundaries and interfaces.

---

## 5. Data flow

```
F6 ─▶ ExecuteInGameThread ─▶ scan.run() ─▶ records
                                              │
                                  report.analyze(records, MinCopies)
                                              │
                                  report.format(analysis) ─▶ lines
                                              │
                                     print() per line ─▶ UE4SS.log / GUI console
```

---

## 6. Report format

```
[RR-Dupe] Scan complete: 7 cassettes, 4 unique SKUs, 2 duplicated.
[RR-Dupe] SKU 10293 — 3 copies:
[RR-Dupe]     #1  (1203.4, -882.1, 95.0)
[RR-Dupe]     #2  (1530.0, -640.2, 95.0)
[RR-Dupe]     #3  (980.7, -1200.5, 95.0)
[RR-Dupe] SKU 55012 — 2 copies:
[RR-Dupe]     #1  (300.1, 88.0, 110.0)
[RR-Dupe]     #2  (412.9, 90.3, 110.0)
[RR-Dupe] Total sellable extras: 3   (sum of copies-1 across duplicated SKUs)
```

(7 cassettes − 4 unique SKUs = 3 extra copies; the two remaining unique SKUs are
single copies, not shown since only duplicates are listed.)

Empty/clean cases: `"No cassettes found."` and `"No duplicates — collection is clean."`

---

## 7. Error handling & edge cases

- `FindAllOf` returns `nil` → treat as empty → "No cassettes found."
- Each cassette read wrapped in `pcall` — one bad actor never aborts the scan.
- `sku.read` returns `nil` → skip that cassette; if `Debug`, log a "skipped N unreadable" tally.
- CDO (`Default__Cartridge_Base_C`) filtered in `sku.isCartridge`.
- Whole `runScan` wrapped in `pcall`; failure logs an error line, not a silent death.
- SKUs used as table keys directly (integers); displayed via `tostring`.

---

## 8. Dev-sync workflow

Source of truth is the repo. Make the game see live edits via a Windows directory
junction (no admin required):

```
mklink /J "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\Mods\RR Dupe Finder" "D:\Github\rr-dupe-finder\RR Dupe Finder"
```

Iterate: edit in repo → `Ctrl+R` in game (hot reload) → press `F6` → read output in
the GUI console or `...\ue4ss\UE4SS.log`. Fallback if you'd rather not junction: copy
the `RR Dupe Finder` folder into `Mods\` after each change.

Enable in `UE4SS-settings.ini` for the loop: `EnableHotReloadSystem = 1`,
`GuiConsoleEnabled = 1`.

---

## 9. Testing strategy

- **`report.lua`** (pure): `tests/report_test.lua`, run with a standalone Lua 5.4
  interpreter (`lua54 tests/report_test.lua`), loading the module via
  `dofile("RR Dupe Finder/Scripts/report.lua")` (it has no `require` deps). Cases:
  - empty records → "No cassettes found."
  - all-unique records → "No duplicates — collection is clean.", `sellableExtras == 0`
  - SKU A ×3, SKU B ×2 → dupes sorted [A(3), B(2)], `sellableExtras == 3`
  - `MinCopies = 3` → only A flagged
  - tie-break: two SKUs each ×2 → ordered by SKU ascending
  - *If no Lua interpreter is available, these become in-game sanity checks instead.*
- **`scan.lua` / `sku.lua`** (need the game): verified in-game by pressing `F6` and
  cross-checking the count/coords against a known cassette via UE4SS Live View.

---

## 10. Session breakdown

Four sessions, each runnable in a fresh Claude Code session, each ending working +
committed. **Commit policy: all commits/pushes attributed solely to the user
(hash_developer / sidotidavide@gmail.com), with NO `Co-Authored-By` trailer.**

1. **Scaffold + config + dev-sync.** Create `RR Dupe Finder/`, `enabled.txt`, stub
   modules, real `config.lua`; set up the junction. *Verify:* load banner in
   `UE4SS.log`, `F6` bound and logs a stub line. *Commit.*
2. **SKU read + scan.** Implement `sku.lua` + `scan.lua`; `F6` temporarily dumps
   record count + first few records. *Verify in-game:* F6 logs N cassettes with SKUs
   + coords, cross-checked against a known cassette. *Commit.*
3. **Report + tests.** Implement `report.lua`; wire `main.lua` fully; add
   `tests/report_test.lua`. *Verify:* full report prints; sellable math checks out;
   tests pass (or in-game sanity checks). *Commit.*
4. **Polish + docs + release.** Edge cases, `MinCopies` honored, optional console
   command alias (`RegisterConsoleCommandHandler`); reconcile `CLAUDE.md` §10/§11 and
   README with reality (now modular, MVP genuinely done). *Final verification pass.
   Commit + push.*

(Sessions 1+2 may merge into three sessions if preferred.)

---

## 11. Roadmap beyond v1 (outline only — not designed here)

- **v2 — titles + in-world highlight.** Needs Live View exploration first (gated):
  find the **title field** (sibling of SKU in `BoxData`) and the cassette **mesh
  component** (for tinting). Highlight via mesh tint or spawned marker — **debug-draw
  is out** (Shipping build no-ops it). New module candidates: `title.lua` (alongside
  `sku.lua`), `highlight.lua`.
- **v3 — polish.** On-screen UMG list with distance/direction; expand `config.lua`
  (color, thresholds); toggle on/off; optional rented-cassette filter (needs a
  rented/owned flag on the cartridge — also a Live View discovery).

---

## 12. Known unknowns / Live View TODOs (block v2, not v1)

1. Movie **title** field name inside `BoxData_25_...`.
2. Cassette **mesh component** type + name (for the v2 tint/marker decision).
3. Whether a central **player-inventory** array exists (possible cleaner data source).
4. A **rented vs owned** flag on the cartridge (for the v3 filter).
