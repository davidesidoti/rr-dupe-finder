# RR Dupe Finder — v1 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a UE4SS Lua mod that, on F6, scans every loaded cassette, groups by SKU, flags 2+ copies, and reports each copy's world coordinates plus a sellable-extras total.

**Architecture:** Five small Lua modules under `RR Dupe Finder/Scripts/` — `config` (settings), `sku` (the reverse-engineered SKU read path), `scan` (UObject enumeration), `report` (pure grouping/formatting), `main` (wiring + keybind). `report` makes zero UE calls so it is unit-testable with a standalone Lua interpreter; the UE-bound modules are verified in-game.

**Tech Stack:** Lua 5.4 (UE4SS runtime), UE4SS v3.0.1 API (`FindAllOf`, `RegisterKeyBind`, `ExecuteInGameThread`, `K2_GetActorLocation`). Standalone Lua 5.4 (via scoop) for `report` tests.

**Spec:** `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v1-design.md` — read it first.

---

## ⚠️ Commit policy (applies to EVERY commit in this plan)

All commits are attributed solely to the user (`hash_developer <sidotidavide@gmail.com>`).
**NEVER add a `Co-Authored-By` trailer.** This overrides the default harness rule.
Git is already configured with the user's identity, so plain `git commit -m "..."` is correct.
Commit directly to `main` (matches the repo's existing history). Push only in Session 4 (or when the user asks).

## How to run each session in a separate Claude Code session

Open Claude Code in `D:\Github\rr-dupe-finder` and prompt:

> Read `CLAUDE.md`, `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v1-design.md`, and
> `docs/superpowers/plans/2026-06-24-rr-dupe-finder-v1.md`. Execute **Session N** of the plan,
> checking off each step. Honor the commit policy: no `Co-Authored-By` trailer.

Each session is self-contained, leaves the mod in a working state, and ends with a commit.

## Verification reality

UE4SS Lua runs **inside the game process**. There is no automated harness for code that
touches UObjects (`sku`, `scan`, `main`). Those are verified by a manual in-game loop:
hot-reload (`Ctrl+R`), press F6, read `...\ue4ss\UE4SS.log`. Only `report.lua` (pure Lua)
gets real automated tests. Do not write fake "tests" for the UE-bound modules.

The in-game log lives at:
`D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log`

---

## File structure (locked decisions)

| File | Responsibility | Created in |
|------|----------------|-----------|
| `RR Dupe Finder/enabled.txt` | empty; presence enables the mod | Session 1 |
| `RR Dupe Finder/Scripts/config.lua` | settings table | Session 1 |
| `RR Dupe Finder/Scripts/main.lua` | wiring + keybind (stub → final) | Session 1, 2, 3 |
| `RR Dupe Finder/Scripts/sku.lua` | `isCartridge`, `read` (SKU struct path) | Session 2 |
| `RR Dupe Finder/Scripts/scan.lua` | `run()` → cassette records | Session 2 |
| `RR Dupe Finder/Scripts/report.lua` | `analyze`, `format` (pure) | Session 3 |
| `tests/report_test.lua` | pure-Lua tests for `report` | Session 3 |

---

# SESSION 1 — Scaffold + config + dev-sync

**Outcome:** the mod loads in-game (banner in the log) and F6 logs a stub line.

### Task 1.1: Create mod folder, enabled.txt, and config.lua

**Files:**
- Create: `RR Dupe Finder/enabled.txt` (empty)
- Create: `RR Dupe Finder/Scripts/config.lua`

- [x] **Step 1: Create the empty `enabled.txt`**

Create `RR Dupe Finder/enabled.txt` with **no content** (zero bytes). Its mere presence enables the mod.

- [x] **Step 2: Create `config.lua`**

Create `RR Dupe Finder/Scripts/config.lua`:

```lua
-- RR Dupe Finder — configuration
return {
    Debug     = false,   -- verbose logging (e.g. count of skipped/unreadable cassettes)
    ScanKey   = "F6",    -- resolved in main.lua via Key[ScanKey]
    Modifiers = {},      -- optional, e.g. { "CONTROL" }, resolved via ModifierKey[name]
    MinCopies = 2,       -- flag SKUs owned in >= this many copies
}
```

### Task 1.2: Create the stub main.lua

**Files:**
- Create: `RR Dupe Finder/Scripts/main.lua`

- [x] **Step 1: Write the scaffold main.lua**

This stub requires ONLY `config` (the other modules don't exist yet, so requiring them would error on load):

```lua
-- RR Dupe Finder — entry point (scaffold)
local Config = require("config")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

local key = Key[Config.ScanKey]
RegisterKeyBind(key, function()
    log("Scan key pressed (stub — scan not implemented yet).")
end)

log("RR Dupe Finder loaded (scaffold). Press " .. Config.ScanKey .. " to test the keybind.")
```

### Task 1.3: Set up the dev-sync junction

**Files:** none (filesystem link outside the repo)

- [x] **Step 1: Verify the link target doesn't already exist in Mods**

Run (PowerShell):
```powershell
Test-Path "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\Mods\RR Dupe Finder"
```
Expected: `False`. If `True`, inspect it — if it's an old copy, the user should remove/rename it before linking.

- [x] **Step 2: Create the junction (no admin needed)**

Run (PowerShell):
```powershell
New-Item -ItemType Junction `
  -Path "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\Mods\RR Dupe Finder" `
  -Target "D:\Github\rr-dupe-finder\RR Dupe Finder"
```
Expected: prints a directory entry for the new junction. Now edits in the repo are live in-game.

- [x] **Step 3: Confirm hot-reload + console settings**

Check `D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS-settings.ini` has:
```ini
EnableHotReloadSystem = 1
GuiConsoleEnabled = 1
```
If not, set them (one-time). Note for the user: these require a game restart to take effect the first time.

### Task 1.4: In-game verification

- [x] **Step 1: Load the mod**

Ask the user to launch the game (or `Ctrl+R` to hot-reload if already running) and load any save.

- [x] **Step 2: Verify the load banner**

Grep the log:
```powershell
Select-String -Path "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log" -Pattern "RR Dupe Finder loaded"
```
Expected: a line `[RR-Dupe] RR Dupe Finder loaded (scaffold). Press F6 to test the keybind.`

- [x] **Step 3: Verify the keybind**

Ask the user to press **F6** in-game, then grep:
```powershell
Select-String -Path "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log" -Pattern "Scan key pressed"
```
Expected: `[RR-Dupe] Scan key pressed (stub — scan not implemented yet).`

If either fails: confirm `enabled.txt` exists, the junction resolves, and `Key.F6` is valid (UE4SS console will log a Lua error otherwise).

### Task 1.5: Commit

- [x] **Step 1: Stage and commit (no co-author trailer)**

```bash
git add "RR Dupe Finder/enabled.txt" "RR Dupe Finder/Scripts/config.lua" "RR Dupe Finder/Scripts/main.lua"
git commit -m "Scaffold RR Dupe Finder mod (config + keybind stub)"
```

- [x] **Step 2: Verify the commit has no co-author**

```bash
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, and the body contains **no** `Co-Authored-By` line.

---

# SESSION 2 — SKU read + scan

**Outcome:** F6 dumps the live cassette count and per-cassette SKU + coordinates (temporary debug output).

### Task 2.1: Implement sku.lua

**Files:**
- Create: `RR Dupe Finder/Scripts/sku.lua`

- [ ] **Step 1: Write sku.lua**

The struct keys are copied verbatim from the working SKU QoL mod — do NOT alter them.

```lua
-- RR Dupe Finder — SKU read path (isolated; the most build-fragile module)
local M = {}

-- GUID-mangled Blueprint struct property names. Verbatim from SKU QoL. Do NOT guess.
local PRODUCT_STRUCTURE_KEY = "Product Structure"
local BASE_STRUCTURE_KEY    = "BaseStructure_2_FBB12C464AE570CAFD12ED8506160683"
local BOX_DATA_KEY          = "BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10"
local SKU_KEY               = "SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876"

-- True only for a real, usable cassette actor (valid + not the class default object).
function M.isCartridge(obj)
    if not obj or not obj:IsValid() then return false end
    if obj:GetFullName():find("Default__") then return false end
    return true
end

-- Returns the integer SKU, or nil if any struct level is missing.
function M.read(cart)
    local ps   = cart[PRODUCT_STRUCTURE_KEY]; if not ps   then return nil end
    local base = ps[BASE_STRUCTURE_KEY];      if not base then return nil end
    local box  = base[BOX_DATA_KEY];          if not box  then return nil end
    return box[SKU_KEY]
end

return M
```

### Task 2.2: Implement scan.lua

**Files:**
- Create: `RR Dupe Finder/Scripts/scan.lua`

- [ ] **Step 1: Write scan.lua**

```lua
-- RR Dupe Finder — cassette enumeration
local sku = require("sku")
local M = {}

-- Returns: array of { sku=<int>, x=, y=, z=, name=<fullname> }
-- Each cassette read is wrapped in pcall so one bad actor never aborts the scan.
function M.run()
    local out = {}
    local carts = FindAllOf("Cartridge_Base_C") or {}
    for _, cart in pairs(carts) do
        pcall(function()
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

### Task 2.3: Wire main.lua to dump scan output (temporary)

**Files:**
- Modify: `RR Dupe Finder/Scripts/main.lua`

- [ ] **Step 1: Replace main.lua with the scan-dump version**

This is a temporary diagnostic so we can confirm `scan`/`sku` work before building `report`. The scan runs inside `ExecuteInGameThread` (UObject reads must be on the game thread).

```lua
-- RR Dupe Finder — entry point (scan-dump diagnostic; report wired in Session 3)
local Config = require("config")
local scan   = require("scan")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

local function dumpScan()
    local records = scan.run()
    log(string.format("Scan found %d readable cassettes.", #records))
    for i, r in ipairs(records) do
        if i > 10 then log("  ... (first 10 shown)"); break end
        log(string.format("  SKU %s  (%.1f, %.1f, %.1f)", tostring(r.sku), r.x, r.y, r.z))
    end
end

local function onScanKey()
    ExecuteInGameThread(function()
        local ok, err = pcall(dumpScan)
        if not ok then log("Scan error: " .. tostring(err)) end
    end)
end

RegisterKeyBind(Key[Config.ScanKey], onScanKey)
log("RR Dupe Finder loaded (scan-dump). Press " .. Config.ScanKey .. " to dump cassettes.")
```

### Task 2.4: In-game verification

- [ ] **Step 1: Hot-reload and scan**

Ask the user to load a save with cassettes on shelves, `Ctrl+R`, then press **F6**.

- [ ] **Step 2: Verify the dump**

```powershell
Select-String -Path "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log" -Pattern "Scan found" | Select-Object -Last 1
```
Expected: `[RR-Dupe] Scan found N readable cassettes.` with N > 0, followed by per-cassette `SKU x (a, b, c)` lines.

- [ ] **Step 3: Cross-check one cassette**

Ask the user to pick one cassette in-game whose SKU they can read via the in-game computer (or UE4SS Live View), and confirm that SKU appears in the dump. This validates `sku.read` against ground truth.

If the dump shows 0 cassettes: confirm a save is loaded with stock present and that `FindAllOf("Cartridge_Base_C")` isn't returning nil (the pcall would otherwise hide a read error — temporarily set `Config.Debug` aside and check the UE4SS console for Lua errors).

### Task 2.5: Commit

- [ ] **Step 1: Stage and commit (no co-author trailer)**

```bash
git add "RR Dupe Finder/Scripts/sku.lua" "RR Dupe Finder/Scripts/scan.lua" "RR Dupe Finder/Scripts/main.lua"
git commit -m "Add SKU read and cassette scan modules"
```

- [ ] **Step 2: Verify no co-author**

```bash
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 3 — Report module + tests + final wiring

**Outcome:** `report.lua` passes pure-Lua tests; F6 prints the full duplicate report in-game.

### Task 3.0: Install a standalone Lua interpreter (for tests)

**Files:** none

- [ ] **Step 1: Install Lua 5.4 via scoop**

Run (PowerShell):
```powershell
scoop install lua
```
Expected: scoop installs Lua and adds `lua` to PATH. Verify:
```powershell
lua -v
```
Expected: `Lua 5.4.x ...`

If the user declines the install, skip the automated test runs below and instead verify
`report` behavior in-game during Task 3.7's verification. The test FILE should still be
written and committed for future use.

### Task 3.1: Write the failing test for report.analyze

**Files:**
- Create: `tests/report_test.lua`

- [ ] **Step 1: Write the test harness + analyze cases**

`report.lua` has no `require` dependencies, so the test loads it with `dofile`. Run from the repo root.

```lua
-- tests/report_test.lua — run from repo root: lua tests/report_test.lua
local report = dofile("RR Dupe Finder/Scripts/report.lua")

local failures = 0
local function check(name, cond)
    if cond then
        print("PASS: " .. name)
    else
        print("FAIL: " .. name)
        failures = failures + 1
    end
end

-- analyze: empty input
do
    local a = report.analyze({}, 2)
    check("empty totalCarts",     a.totalCarts == 0)
    check("empty uniqueSkus",     a.uniqueSkus == 0)
    check("empty no dupes",       #a.dupes == 0)
    check("empty sellable 0",     a.sellableExtras == 0)
end

-- analyze: all unique → no dupes
do
    local recs = {
        { sku = 1, x = 0, y = 0, z = 0 },
        { sku = 2, x = 0, y = 0, z = 0 },
        { sku = 3, x = 0, y = 0, z = 0 },
    }
    local a = report.analyze(recs, 2)
    check("unique totalCarts",    a.totalCarts == 3)
    check("unique uniqueSkus",    a.uniqueSkus == 3)
    check("unique no dupes",      #a.dupes == 0)
    check("unique sellable 0",    a.sellableExtras == 0)
end

-- analyze: 10 x3, 20 x2, 30 x1 → dupes [10(3), 20(2)], sellable 3
do
    local recs = {
        { sku = 30, x = 0, y = 0, z = 0 },
        { sku = 10, x = 1, y = 2, z = 3 },
        { sku = 20, x = 0, y = 0, z = 0 },
        { sku = 10, x = 4, y = 5, z = 6 },
        { sku = 20, x = 0, y = 0, z = 0 },
        { sku = 10, x = 7, y = 8, z = 9 },
    }
    local a = report.analyze(recs, 2)
    check("mix totalCarts",       a.totalCarts == 6)
    check("mix uniqueSkus",       a.uniqueSkus == 3)
    check("mix dupe count",       #a.dupes == 2)
    check("mix sorted first 10",  a.dupes[1].sku == 10 and a.dupes[1].copies == 3)
    check("mix sorted second 20", a.dupes[2].sku == 20 and a.dupes[2].copies == 2)
    check("mix sellable 3",       a.sellableExtras == 3)
    check("mix locs captured",    #a.dupes[1].locs == 3 and a.dupes[1].locs[1].x == 1)
end

-- analyze: MinCopies = 3 → only 10 flagged
do
    local recs = {
        { sku = 10, x = 0, y = 0, z = 0 }, { sku = 10, x = 0, y = 0, z = 0 }, { sku = 10, x = 0, y = 0, z = 0 },
        { sku = 20, x = 0, y = 0, z = 0 }, { sku = 20, x = 0, y = 0, z = 0 },
    }
    local a = report.analyze(recs, 3)
    check("min3 dupe count",      #a.dupes == 1)
    check("min3 only 10",         a.dupes[1].sku == 10)
    check("min3 sellable 2",      a.sellableExtras == 2)
end

-- analyze: tie-break by sku ascending when copies equal
do
    local recs = {
        { sku = 20, x = 0, y = 0, z = 0 }, { sku = 20, x = 0, y = 0, z = 0 },
        { sku = 10, x = 0, y = 0, z = 0 }, { sku = 10, x = 0, y = 0, z = 0 },
    }
    local a = report.analyze(recs, 2)
    check("tie first 10",         a.dupes[1].sku == 10)
    check("tie second 20",        a.dupes[2].sku == 20)
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
os.exit(failures == 0 and 0 or 1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from repo root):
```powershell
lua tests/report_test.lua
```
Expected: an error like `cannot open RR Dupe Finder/Scripts/report.lua` (the module doesn't exist yet). This is the red state.

### Task 3.2: Implement report.analyze to pass the tests

**Files:**
- Create: `RR Dupe Finder/Scripts/report.lua`

- [ ] **Step 1: Write report.lua with `analyze` (and a `format` stub)**

```lua
-- RR Dupe Finder — duplicate grouping + report formatting (pure; no UE calls)
local M = {}

-- records: array of { sku, x, y, z }
-- Returns: { totalCarts, uniqueSkus, dupes = { {sku, copies, locs={{x,y,z},...}} }, sellableExtras }
function M.analyze(records, minCopies)
    minCopies = minCopies or 2
    local bySku, order = {}, {}
    for _, r in ipairs(records) do
        local g = bySku[r.sku]
        if not g then
            g = { sku = r.sku, locs = {} }
            bySku[r.sku] = g
            order[#order + 1] = r.sku
        end
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
        if a.copies ~= b.copies then return a.copies > b.copies end
        return a.sku < b.sku
    end)
    return { totalCarts = #records, uniqueSkus = #order, dupes = dupes, sellableExtras = sellable }
end

-- Placeholder; implemented in Task 3.4.
function M.format(a)
    return {}
end

return M
```

- [ ] **Step 2: Run the test to verify analyze passes**

Run:
```powershell
lua tests/report_test.lua
```
Expected: every `analyze` check prints `PASS`, ending with `ALL PASS` and exit code 0.

### Task 3.3: Write the failing test for report.format

**Files:**
- Modify: `tests/report_test.lua`

- [ ] **Step 1: Append format cases before the final summary lines**

Insert these blocks immediately **before** the `print(string.format("\n%s", ...))` line:

```lua
-- format: empty → single "No cassettes found." line
do
    local lines = report.format(report.analyze({}, 2))
    check("fmt empty single line", #lines == 1)
    check("fmt empty text",        lines[1] == "No cassettes found.")
end

-- format: all unique → header + clean line
do
    local recs = { { sku = 1, x = 0, y = 0, z = 0 }, { sku = 2, x = 0, y = 0, z = 0 } }
    local lines = report.format(report.analyze(recs, 2))
    check("fmt clean header",  lines[1] == "Scan complete: 2 cassettes, 2 unique SKUs, 0 duplicated.")
    check("fmt clean line",    lines[2] == "No duplicates — collection is clean.")
end

-- format: dupes → header, per-SKU blocks, footer
do
    local recs = {
        { sku = 10, x = 1, y = 2, z = 3 },
        { sku = 10, x = 4, y = 5, z = 6 },
        { sku = 20, x = 7, y = 8, z = 9 },
        { sku = 20, x = 1, y = 1, z = 1 },
        { sku = 30, x = 0, y = 0, z = 0 },
    }
    local lines = report.format(report.analyze(recs, 2))
    check("fmt dupe header",  lines[1] == "Scan complete: 5 cassettes, 3 unique SKUs, 2 duplicated.")
    check("fmt dupe sku10",   lines[2] == "SKU 10 — 2 copies:")
    check("fmt dupe sku10 c1",lines[3] == "    #1  (1.0, 2.0, 3.0)")
    check("fmt dupe sku10 c2",lines[4] == "    #2  (4.0, 5.0, 6.0)")
    check("fmt dupe sku20",   lines[5] == "SKU 20 — 2 copies:")
    check("fmt dupe footer",  lines[#lines] == "Total sellable extras: 2   (sum of copies-1 across duplicated SKUs)")
end
```

- [ ] **Step 2: Run the test to verify the format cases fail**

Run:
```powershell
lua tests/report_test.lua
```
Expected: the `fmt ...` checks print `FAIL` (format returns `{}`), ending with a failure count and exit code 1.

### Task 3.4: Implement report.format to pass the tests

**Files:**
- Modify: `RR Dupe Finder/Scripts/report.lua`

- [ ] **Step 1: Replace the `format` placeholder with the real implementation**

```lua
-- Returns: array of strings (no prefix; main.lua adds the "[RR-Dupe] " tag)
function M.format(a)
    local lines = {}
    if a.totalCarts == 0 then
        lines[1] = "No cassettes found."
        return lines
    end
    lines[#lines + 1] = string.format(
        "Scan complete: %d cassettes, %d unique SKUs, %d duplicated.",
        a.totalCarts, a.uniqueSkus, #a.dupes)
    if #a.dupes == 0 then
        lines[#lines + 1] = "No duplicates — collection is clean."
        return lines
    end
    for _, g in ipairs(a.dupes) do
        lines[#lines + 1] = string.format("SKU %s — %d copies:", tostring(g.sku), g.copies)
        for i, p in ipairs(g.locs) do
            lines[#lines + 1] = string.format("    #%d  (%.1f, %.1f, %.1f)", i, p.x, p.y, p.z)
        end
    end
    lines[#lines + 1] = string.format(
        "Total sellable extras: %d   (sum of copies-1 across duplicated SKUs)", a.sellableExtras)
    return lines
end
```

- [ ] **Step 2: Run the full test suite**

Run:
```powershell
lua tests/report_test.lua
```
Expected: every check `PASS`, ending with `ALL PASS` and exit code 0.

### Task 3.5: Wire main.lua to the final scan → analyze → format flow

**Files:**
- Modify: `RR Dupe Finder/Scripts/main.lua`

- [ ] **Step 1: Replace main.lua with the final version**

```lua
-- RR Dupe Finder — entry point
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
    for _, name in ipairs(Config.Modifiers) do mods[#mods + 1] = ModifierKey[name] end
    RegisterKeyBind(key, mods, onScanKey)
else
    RegisterKeyBind(key, onScanKey)
end

log("RR Dupe Finder loaded. Press " .. Config.ScanKey .. " to scan.")
```

### Task 3.6: In-game verification of the full report

- [ ] **Step 1: Hot-reload and scan**

Ask the user to load a save with at least one duplicated SKU, `Ctrl+R`, then press **F6**.

- [ ] **Step 2: Verify the report format**

```powershell
Select-String -Path "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log" -Pattern "Scan complete" | Select-Object -Last 1
```
Expected: `[RR-Dupe] Scan complete: N cassettes, U unique SKUs, D duplicated.` followed by per-SKU blocks and a `Total sellable extras: X` footer.

- [ ] **Step 3: Sanity-check the math**

Confirm `sellable extras == total cassettes − unique SKUs` for the live data (both numbers are in the report). They must match.

### Task 3.7: Commit

- [ ] **Step 1: Stage and commit (no co-author trailer)**

```bash
git add "RR Dupe Finder/Scripts/report.lua" "RR Dupe Finder/Scripts/main.lua" "tests/report_test.lua"
git commit -m "Add dupe grouping/report module with tests"
```

- [ ] **Step 2: Verify no co-author**

```bash
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 4 — Polish + docs + release

**Outcome:** edge cases handled, optional console-command trigger, docs reconciled with reality, pushed to origin.

### Task 4.1: Add a debug "skipped unreadable" tally

**Files:**
- Modify: `RR Dupe Finder/Scripts/scan.lua`
- Modify: `RR Dupe Finder/Scripts/main.lua`

- [ ] **Step 1: Make scan.run also return a skipped count**

Replace the body of `M.run` in `scan.lua` so it counts cassettes whose SKU couldn't be read:

```lua
-- Returns: records (array), skipped (int count of cassettes with unreadable SKU)
function M.run()
    local out, skipped = {}, 0
    local carts = FindAllOf("Cartridge_Base_C") or {}
    for _, cart in pairs(carts) do
        pcall(function()
            if not sku.isCartridge(cart) then return end
            local s = sku.read(cart)
            if not s then skipped = skipped + 1; return end
            local loc = cart:K2_GetActorLocation()
            out[#out + 1] = { sku = s, x = loc.X, y = loc.Y, z = loc.Z, name = cart:GetFullName() }
        end)
    end
    return out, skipped
end
```

- [ ] **Step 2: Log the tally in main.lua when Debug is on**

Update `runScan` in `main.lua`:

```lua
local function runScan()
    local records, skipped = scan.run()
    local analysis = report.analyze(records, Config.MinCopies)
    for _, line in ipairs(report.format(analysis)) do log(line) end
    if Config.Debug and skipped > 0 then
        log(string.format("(debug) skipped %d cassette(s) with unreadable SKU", skipped))
    end
end
```

- [ ] **Step 3: Confirm report tests still pass**

Run:
```powershell
lua tests/report_test.lua
```
Expected: `ALL PASS` (report.lua is unchanged; this just confirms nothing regressed).

### Task 4.2: Add an optional console-command trigger

**Files:**
- Modify: `RR Dupe Finder/Scripts/main.lua`

- [ ] **Step 1: Register a console command alias for the scan**

Add, immediately before the final `log("RR Dupe Finder loaded...")` line in `main.lua`:

```lua
-- Alternate trigger: type "rrdupe" in the UE4SS console.
RegisterConsoleCommandHandler("rrdupe", function(fullCommand, parameters, outputDevice)
    onScanKey()
    return true
end)
```

- [ ] **Step 2: In-game verify the console command**

Ask the user to `Ctrl+R`, open the UE4SS console, type `rrdupe`, and confirm the same report prints as F6 produces.

### Task 4.3: Reconcile the docs with reality

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (only if a claim is now inaccurate)

- [ ] **Step 1: Update CLAUDE.md §10 (Current status)**

The current §10 says the MVP is "implemented as a single `main.lua`." It is now five modules. Replace the §10 body so it reads accurately, e.g.:

```markdown
## 10. Current status

**MVP (detection + report): implemented** as five Lua modules under
`RR Dupe Finder/Scripts/` — `config`, `sku`, `scan`, `report`, `main`.

- Binds **F6** (and a `rrdupe` console command) to a scan.
- `scan.run()` calls `FindAllOf("Cartridge_Base_C")`, skips `Default__`, reads the SKU
  via `sku.read` (verified struct path), and records `K2_GetActorLocation` for each.
- `report.analyze` groups by SKU and flags any with >= `Config.MinCopies` copies;
  `report.format` renders the report. The scan runs inside `ExecuteInGameThread`.
- `report` is pure Lua and unit-tested in `tests/report_test.lua`.

Design spec: `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v1-design.md`.
```

- [ ] **Step 2: Update CLAUDE.md §11 roadmap note**

Under §11, mark v1 done and leave the v2/v3 items; ensure the "Exploration TODO" (title field, mesh, inventory, rented flag) stays listed as the v2 gate.

- [ ] **Step 3: Verify README accuracy**

Read `README.md`. Its Features/Usage already describe F6 + log output, which now matches.
If anything reads as inaccurate (e.g. "single main.lua" wording anywhere), fix only that.
No broad rewrite.

### Task 4.4: Final verification pass

- [ ] **Step 1: Edge case — no duplicates**

Ask the user to test on a save with no dupes (or temporarily set `Config.MinCopies = 99`),
`Ctrl+R`, press F6. Expected in the log: `No duplicates — collection is clean.`

- [ ] **Step 2: Edge case — MinCopies respected**

Set `Config.MinCopies = 3`, `Ctrl+R`, F6. Expected: only SKUs with 3+ copies appear.
Reset to `2` afterward.

- [ ] **Step 3: Confirm tests green**

```powershell
lua tests/report_test.lua
```
Expected: `ALL PASS`.

### Task 4.5: Commit and push

- [ ] **Step 1: Stage and commit (no co-author trailer)**

```bash
git add "RR Dupe Finder/Scripts/scan.lua" "RR Dupe Finder/Scripts/main.lua" CLAUDE.md README.md
git commit -m "Polish report, add console command, reconcile docs"
```

- [ ] **Step 2: Verify no co-author, then push**

```bash
git log -1 --format="%an <%ae>%n%n%B"
git push origin main
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line; push succeeds.

---

## Notes for whoever executes this

- **`CLAUDE.md` is currently untracked.** It will first enter git in Session 4 (Task 4.3's
  commit stages it). If you'd rather track it earlier, stage it in any prior session's commit —
  just keep the no-co-author rule.
- **Don't reorder the struct keys in `sku.lua`.** They are GUID-mangled and build-specific.
- **Don't rely on debug-draw** anywhere — this is a Shipping build; `DrawDebug*` are no-ops.
- If `Key[Config.ScanKey]` is ever `nil` (bad key name), `RegisterKeyBind` will error on load;
  the UE4SS console shows the Lua error. Valid names follow UE4SS's `Key` enum (e.g. `F6`).
