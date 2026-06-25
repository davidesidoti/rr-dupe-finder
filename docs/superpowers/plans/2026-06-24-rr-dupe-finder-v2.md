# RR Dupe Finder — v2 Implementation Plan (titles + in-world highlight)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the shipped v1 mod so F6 shows each duplicated movie's **title** (SKU fallback) and **tints every placed duplicate cassette** a uniform bright colour in-world, with a clear/refresh trigger — all read-only with respect to save data.

**Architecture:** Recon-gated. **Session 1 is a UE4SS Live View spike** that resolves four facts (title field key, mesh component, a restorable tint mechanism + a sourced material, and opportunistic inventory/rented notes) into a committed findings doc. Sessions 2–4 then build: titles (pure `report.lua` logic, fully TDD'd, fed by a one-line `sku.lua` title read), then the UE-bound `highlight.lua` tinting, then polish + release. The pure/UE-bound split from v1 is preserved — `report.lua` stays UE-free and unit-tested.

**Tech Stack:** Lua 5.4 (UE4SS v3.0.1 runtime) — `FindAllOf`, `StaticFindObject`, `K2_GetActorLocation`, `SetOverlayMaterial`, `RegisterKeyBind`, `RegisterConsoleCommandHandler`, `ExecuteInGameThread`. Standalone Lua (scoop, currently 5.5.0) for `report` tests. UE4SS **Live View** for recon.

**Spec:** `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v2-design.md` — read it first.

---

## ⚠️ Commit policy (applies to EVERY commit in this plan)

All commits are attributed solely to the user (`hash_developer <sidotidavide@gmail.com>`).
**NEVER add a `Co-Authored-By` trailer.** This overrides the default harness rule.
Plain `git commit -m "..."`, committed directly to `main`.

**`docs/` files are gitignored** (CLAUDE.md §9). New docs files (the recon doc, this plan)
need `git add -f` to stage past the ignore; *tracked* docs files are committed **by path**
(`git commit -m "..." -- "docs/..."`). Source files under `RR Dupe Finder/` and `tests/`
stage normally. Push only in Session 4 — `git fetch && git rebase origin/main` first (the
remote can diverge; CLAUDE.md §9).

After each commit, verify:
```bash
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, **no** `Co-Authored-By` line.

## How to run each session in a separate Claude Code session

Open Claude Code in `D:\Github\rr-dupe-finder` and prompt:

> Read `CLAUDE.md`, `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v2-design.md`, and
> `docs/superpowers/plans/2026-06-24-rr-dupe-finder-v2.md`. Execute **Session N**, checking
> off each step. Honor the commit policy: no `Co-Authored-By` trailer.

## Verification reality

UE4SS Lua runs **inside the game process**. Only `report.lua` (pure) has automated tests.
`sku`, `scan`, `highlight`, `main` are verified by a manual in-game loop: hot-reload
(`Ctrl+R`), press F6 (or type `rrdupe`), read the GUI console or
`D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log`.
Do not write fake "tests" for UE-bound modules. The running process keeps the **old** script
until `Ctrl+R`; key off the log **timestamp** (the load banner text is stable now) or trigger
via the `rrdupe` console command. **Grep the log with ASCII patterns** — em-dashes render as
mojibake on disk (gotcha 9).

Throughout, set `$log` first in PowerShell:
```powershell
$log = "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log"
```

---

## File structure (v2 deltas)

| File | v2 change | Touched in |
|------|-----------|-----------|
| `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v2-recon.md` | **new** — recon findings (R1–R4) | Session 1 |
| `RR Dupe Finder/Scripts/sku.lua` | add `readTitle`; shared `box()` nav | Session 2 |
| `RR Dupe Finder/Scripts/scan.lua` | records gain `title` (S2), `actor` (S3) | Sessions 2, 3 |
| `RR Dupe Finder/Scripts/report.lua` | title on group; `placed`/`placedCopies`; titled format; opaque `actor` thread | Session 2 |
| `tests/report_test.lua` | + title / fallback / placed / suffix / actor cases | Session 2 |
| `RR Dupe Finder/Scripts/config.lua` | + `HighlightEnabled`, `TintColor`, `ClearKey` | Session 3 |
| `RR Dupe Finder/Scripts/highlight.lua` | **new** — `apply` / `clear` | Session 3 |
| `RR Dupe Finder/Scripts/main.lua` | clear→scan→report→tint; clear trigger | Session 3 |
| `CLAUDE.md`, `README.md` | reconcile to v2-done | Session 4 |

---

# SESSION 1 — Recon spike (Live View)

**Outcome:** a committed `…-v2-recon.md` recording R1–R4. **No build code.** This session
gates Sessions 2–3 (Session 2 needs R1; Session 3 needs R2/R3).

> This session is an **investigation**, not TDD. It needs the game running with a save
> loaded and the UE4SS GUI console / Live View available (`GuiConsoleEnabled = 1`, already
> set). Some steps are driven by the user in Live View; one step uses a throwaway probe
> script whose output Claude reads from the log. Record every finding verbatim.

### Task 1.1: R1 — the movie title field

**Files:** none yet (findings recorded in Task 1.5).

- [ ] **Step 1: Open Live View on a known cassette**

Ask the user to: open the UE4SS GUI console → **Live View** → search `Cartridge_Base_C` →
pick a non-`Default__` instance that is **placed on a shelf** and whose movie title they can
read in-game. Expand `Product Structure` → `BaseStructure_2_FBB12C464AE570CAFD12ED8506160683`
→ `BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10`.

- [ ] **Step 2: Identify the title property**

In `BoxData`, the SKU sits at `SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876`. List **all** sibling
properties; the title is the `FString`/`FText`/`FName` one whose value matches the movie the
user sees. Record its **full GUID-mangled name** and its **type**.

- [ ] **Step 3: Cross-check the value**

Confirm the property's value equals the in-game title of that exact cassette. If several
text fields exist (e.g. title vs. studio vs. genre), pick the one matching the on-screen
movie name. Note the others in case they're useful later.

### Task 1.2: R2 — the mesh component

- [ ] **Step 1: Find the renderable mesh component**

In the same Live View instance, locate the cassette's mesh component (almost certainly a
`StaticMeshComponent`). Record its **component name**, its **UClass**, and **how it's reached
from the actor** — either a named property (`cart.<Name>` / `cart["<Name>"]`) or via the
components list. This is what `highlight.lua` will tint.

- [ ] **Step 2: Note the current material**

Record the material currently on element 0 (its full name via the material's row in Live
View). This documents the "base" material for the stateless-restore fallback (§8.2 of the spec).

### Task 1.3: R3 — confirm a restorable tint mechanism + source an asset

> The crux feasibility step. Goal: prove **one** way to recolour the mesh that we can also
> fully undo, and capture the asset path it needs. Preference: `SetOverlayMaterial` > DMI >
> material swap; if none works → marker fallback.

- [ ] **Step 1: Find a usable highlight material (and a fallback mesh)**

Add a throwaway probe to `main.lua` (remove before committing) that lists candidate assets to
the log so Claude can read them:

```lua
-- TEMP recon probe — delete before commit
RegisterConsoleCommandHandler("rrprobe", function()
    ExecuteInGameThread(function()
        local function dump(cls, max)
            local arr = FindAllOf(cls) or {}
            local n = 0
            for _, o in pairs(arr) do
                if o and o:IsValid() and not o:GetFullName():find("Default__") then
                    print("[RR-Probe] " .. cls .. " :: " .. o:GetFullName() .. "\n")
                    n = n + 1; if n >= (max or 25) then break end
                end
            end
            print(string.format("[RR-Probe] %s total ~%d (showing %d)\n", cls, #arr, n))
        end
        dump("MaterialInstanceConstant", 25)
        dump("Material", 25)
        dump("StaticMesh", 25)
    end)
    return true
end)
```

Hot-reload, run `rrprobe` in the console, then read candidates:
```powershell
Select-String -Path $log -Pattern "\[RR-Probe\]" | Select-Object -Last 80
```
Pick (a) a coloured/translucent **material** to use as the overlay/swap tint and (b) a small
bright **static mesh** for the marker fallback. Record both **full object paths** (the string
after `::`). Note whether the chosen material exposes a colour parameter (check it in Live View).

- [ ] **Step 2: Prove the tint applies and clears**

Extend the probe to actually tint one placed cassette via the preferred mechanism, using the
mesh accessor from R2 and the material path from Step 1 (substitute the real strings):

```lua
-- TEMP recon probe 2 — delete before commit. Replace <MESH> and <MATPATH>.
RegisterConsoleCommandHandler("rrtint", function(_, params)
    ExecuteInGameThread(function()
        local mat = StaticFindObject("<MATPATH>")
        if not mat or not mat:IsValid() then print("[RR-Probe] material not found\n"); return end
        local carts = FindAllOf("Cartridge_Base_C") or {}
        local clearing = params and params[1] and tostring(params[1]):lower() == "off"
        local n = 0
        for _, c in pairs(carts) do
            pcall(function()
                if not c or not c:IsValid() or c:GetFullName():find("Default__") then return end
                local loc = c:K2_GetActorLocation()
                if math.abs(loc.X) < 0.5 and math.abs(loc.Y) < 0.5 and math.abs(loc.Z) < 0.5 then return end
                local mesh = c.<MESH>; if not mesh or not mesh:IsValid() then return end
                mesh:SetOverlayMaterial(clearing and nil or mat)   -- preferred mechanism
                n = n + 1
            end)
        end
        print(string.format("[RR-Probe] %s %d placed cassette(s)\n", clearing and "cleared" or "tinted", n))
    end)
    return true
end)
```

Run `rrtint` → ask the user to confirm placed cassettes visibly change colour. Run
`rrtint off` → confirm they return to normal. This proves **R3 = SetOverlayMaterial feasible**.

- [ ] **Step 3: Record the verdict (and fallbacks if needed)**

- If Step 2 tinted **and** cleared visibly → verdict **"overlay"** (the happy path).
- If `SetOverlayMaterial` errored or did nothing → retry the probe swapping the body for a
  **DMI** path (`mesh:CreateDynamicMaterialInstance(0)` then `SetVectorParameterValue` if the
  material has a colour param) or a **`SetMaterial(0, mat)` swap** (capture/restore element 0).
  Record which worked → verdict **"dmi"** or **"swap"**.
- If **none** tints → verdict **"marker"**; Session 3 builds the spawned-marker fallback using
  the mesh asset from Step 1.

- [ ] **Step 4: Remove the probe**

Delete the `rrprobe`/`rrtint` handlers from `main.lua`. Confirm `git diff "RR Dupe Finder/Scripts/main.lua"` is empty (main.lua is back to its committed v1 state).

### Task 1.4: R4 — opportunistic notes (non-blocking)

- [ ] **Step 1: Glance for an inventory array and a rented flag**

While in Live View: (a) check whether a player/store object exposes a central array pairing
SKU↔title (note its path if so — a possible v3 data source); (b) check a cassette for a
boolean/enum that flags **rented vs owned** (note its property name). If not quickly found,
record "not found" and move on — **do not** spend time hunting; these gate nothing in v2.

### Task 1.5: Write + commit the recon doc

**Files:**
- Create: `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v2-recon.md`

- [ ] **Step 1: Record all findings**

Write the doc with these exact fields filled from Tasks 1.1–1.4:

```markdown
# rr-dupe-finder — v2 recon findings
**Date:** 2026-06-24

## R1 — Title field
- Key (verbatim): `<…>`
- Type: `<FString|FText|FName>`
- Stringify call: `<e.g. value:ToString() | tostring(value)>`
- Cross-checked against in-game title: `<movie name>` on cassette `<fullname>`

## R2 — Mesh component
- Accessor: `<e.g. cart.StaticMeshComponent | cart["Mesh"]>`
- UClass: `<…>`
- Base material (element 0): `<full path>`

## R3 — Tint mechanism
- Verdict: `<overlay | dmi | swap | marker>`
- Material asset (full path): `<…>`
- Colour parameter name (DMI only): `<… | none>`
- Marker mesh asset (fallback, full path): `<…>`
- Notes: `<what worked / errors seen>`

## R4 — Opportunistic
- Inventory array: `<path | not found>`
- Rented/owned flag: `<property | not found>`
```

- [ ] **Step 2: Commit (force-add; no co-author)**

```bash
git add -f "docs/superpowers/specs/2026-06-24-rr-dupe-finder-v2-recon.md"
git commit -m "Add v2 recon findings (title field, mesh, tint mechanism)"
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 2 — Titles

**Outcome:** F6's report shows `"Title" (SKU n)` for duplicates (bare `SKU n` fallback) and
marks backstock copies. Pure `report.lua` logic is fully unit-tested. **Needs R1 only.**

> Prerequisite: `…-v2-recon.md` exists with **R1** filled. Substitute the R1 key/stringify
> into the two marked spots below.

### Task 2.1: Add the title read to `sku.lua`

**Files:**
- Modify: `RR Dupe Finder/Scripts/sku.lua`

- [x] **Step 1: Refactor to a shared `box()` nav and add `readTitle`**

Replace the body of `sku.lua` (keep the SKU key verbatim; fill `TITLE_KEY` + the stringify
from R1):

```lua
-- RR Dupe Finder — product-struct read path (isolated; most build-fragile module)
local M = {}

-- GUID-mangled keys. SKU verbatim from SKU QoL. TITLE_KEY from v2 recon R1. Do NOT guess.
local PRODUCT_STRUCTURE_KEY = "Product Structure"
local BASE_STRUCTURE_KEY    = "BaseStructure_2_FBB12C464AE570CAFD12ED8506160683"
local BOX_DATA_KEY          = "BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10"
local SKU_KEY               = "SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876"
local TITLE_KEY             = "<R1 KEY>"   -- ← paste verbatim from the recon doc

function M.isCartridge(obj)
    if not obj or not obj:IsValid() then return false end
    if obj:GetFullName():find("Default__") then return false end   -- skip CDO
    return true
end

local function box(cart)
    local ps   = cart[PRODUCT_STRUCTURE_KEY]; if not ps   then return nil end
    local base = ps[BASE_STRUCTURE_KEY];      if not base then return nil end
    return base[BOX_DATA_KEY]
end

function M.read(cart)
    local b = box(cart); if not b then return nil end
    return b[SKU_KEY]
end

-- Returns a Lua string title, or nil. Stringify per R1's field type.
function M.readTitle(cart)
    local b = box(cart); if not b then return nil end
    local t = b[TITLE_KEY]; if t == nil then return nil end
    -- <R1 STRINGIFY>: if FText/FName → return t:ToString(); if FString → return t
    return tostring(t)
end

return M
```

- [x] **Step 2: Sanity-load standalone (syntax check only)**

`sku.lua` calls UE globals, so it won't *run* standalone, but a syntax error would break the
mod silently. Quick parse check:
```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/sku.lua'))" ; if ($?) { "syntax ok" }
```
Expected: `syntax ok`.

### Task 2.2: Thread `title` through `scan.lua`

**Files:**
- Modify: `RR Dupe Finder/Scripts/scan.lua`

- [x] **Step 1: Add `title` to each record**

In `M.run`, change the record-building line to capture the title (everything else unchanged):

```lua
            local loc = cart:K2_GetActorLocation()
            out[#out + 1] = {
                sku = s, title = sku.readTitle(cart),
                x = loc.X, y = loc.Y, z = loc.Z, name = cart:GetFullName(),
            }
```

A readable SKU with `nil` title is **not** skipped (it lists under its SKU). `skipped` still
counts only unreadable-SKU cassettes.

- [x] **Step 2: Syntax check**

```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/scan.lua'))" ; if ($?) { "syntax ok" }
```
Expected: `syntax ok`.

### Task 2.3: Extend `report.lua` (titles + placed flag) — TDD

**Files:**
- Modify: `tests/report_test.lua`
- Modify: `RR Dupe Finder/Scripts/report.lua`

- [x] **Step 1: Write the failing v2 cases**

Insert these blocks in `tests/report_test.lua` **immediately before** the final
`print(string.format("\n%s", ...))` summary line:

```lua
-- v2: title carried onto group + titled header
do
    local recs = {
        { sku = 10, title = "Blade Runner", x = 1, y = 2, z = 3, actor = "A1" },
        { sku = 10, title = "Blade Runner", x = 4, y = 5, z = 6, actor = "A2" },
    }
    local a = report.analyze(recs, 2)
    check("v2 title on group",   a.dupes[1].title == "Blade Runner")
    local lines = report.format(a)
    check("v2 titled header",    lines[2] == '"Blade Runner" (SKU 10) — 2 copies:')
end

-- v2: nil title → bare SKU header (back-compat with v1 records)
do
    local recs = {
        { sku = 20, x = 1, y = 1, z = 1 }, { sku = 20, x = 2, y = 2, z = 2 },
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v2 untitled header",  lines[2] == "SKU 20 — 2 copies:")
end

-- v2: first non-nil title wins even if a later copy lacks one
do
    local recs = {
        { sku = 30, title = nil,         x = 1, y = 1, z = 1 },
        { sku = 30, title = "The Thing", x = 2, y = 2, z = 2 },
    }
    check("v2 first non-nil title", report.analyze(recs, 2).dupes[1].title == "The Thing")
end

-- v2: placed vs backstock flag + epsilon boundary
do
    local recs = {
        { sku = 40, title = "X", x = 0,   y = 0,    z = 0 },  -- origin → backstock
        { sku = 40, title = "X", x = 0.3, y = -0.2, z = 0.1 },-- within eps → backstock
        { sku = 40, title = "X", x = 0.6, y = 0,    z = 0 },  -- outside eps → placed
        { sku = 40, title = "X", x = 100, y = 200,  z = 5 },  -- clearly placed
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v2 copies==4",        g.copies == 4)
    check("v2 placedCopies==2",  g.placedCopies == 2)
    check("v2 loc1 backstock",   g.locs[1].placed == false)
    check("v2 loc2 eps backstk", g.locs[2].placed == false)
    check("v2 loc3 eps placed",  g.locs[3].placed == true)
    check("v2 loc4 placed",      g.locs[4].placed == true)
end

-- v2: backstock suffix + per-copy lines
do
    local recs = {
        { sku = 50, title = "Alien", x = 10, y = 20, z = 30 }, -- placed
        { sku = 50, title = "Alien", x = 0,  y = 0,  z = 0 },  -- backstock
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v2 suffix header",    lines[2] == '"Alien" (SKU 50) — 2 copies (1 placed, 1 backstock):')
    check("v2 placed line",      lines[3] == "    #1  (10.0, 20.0, 30.0)")
    check("v2 backstock line",   lines[4] == "    #2  backstock (unplaced)")
end

-- v2: all-placed dupe → no suffix
do
    local recs = {
        { sku = 60, title = "Akira", x = 1, y = 1, z = 1 },
        { sku = 60, title = "Akira", x = 2, y = 2, z = 2 },
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v2 no suffix",        lines[2] == '"Akira" (SKU 60) — 2 copies:')
end

-- v2: actor ref threaded through opaquely (for Session 3's tinting)
do
    local recs = {
        { sku = 70, title = "Heat", x = 1, y = 1, z = 1, actor = "ACT-1" },
        { sku = 70, title = "Heat", x = 2, y = 2, z = 2, actor = "ACT-2" },
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v2 actor1 carried",   g.locs[1].actor == "ACT-1")
    check("v2 actor2 carried",   g.locs[2].actor == "ACT-2")
end
```

- [x] **Step 2: Run tests — verify the v2 cases fail**

```powershell
lua tests/report_test.lua
```
Expected: the `v2 …` checks `FAIL` (title/placed/actor not implemented), ending with a failure
count and exit 1. The v1 checks still `PASS`.

- [x] **Step 3: Replace `analyze` and `format` in `report.lua`**

Replace both functions (the rest of the file — `local M = {}` / `return M` — stays):

```lua
local function isOrigin(x, y, z)
    return math.abs(x) < 0.5 and math.abs(y) < 0.5 and math.abs(z) < 0.5
end

-- records: array of { sku, title?, x, y, z, actor? }
-- Returns: { totalCarts, uniqueSkus, sellableExtras,
--            dupes = { { sku, title, copies, placedCopies,
--                        locs = { { x, y, z, actor, placed }, ... } } } }
function M.analyze(records, minCopies)
    minCopies = minCopies or 2
    local bySku, order = {}, {}
    for _, r in ipairs(records) do
        local g = bySku[r.sku]
        if not g then
            g = { sku = r.sku, title = nil, locs = {} }
            bySku[r.sku] = g
            order[#order + 1] = r.sku
        end
        if g.title == nil and r.title ~= nil and r.title ~= "" then g.title = r.title end
        g.locs[#g.locs + 1] = {
            x = r.x, y = r.y, z = r.z, actor = r.actor, placed = not isOrigin(r.x, r.y, r.z),
        }
    end
    local dupes, sellable = {}, 0
    for _, s in ipairs(order) do
        local g = bySku[s]
        g.copies, g.placedCopies = #g.locs, 0
        for _, p in ipairs(g.locs) do if p.placed then g.placedCopies = g.placedCopies + 1 end end
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
    lines[#lines + 1] = string.format("Scan complete: %d cassettes, %d unique SKUs, %d duplicated.",
        a.totalCarts, a.uniqueSkus, #a.dupes)
    if #a.dupes == 0 then lines[#lines + 1] = "No duplicates — collection is clean."; return lines end
    for _, g in ipairs(a.dupes) do
        local head
        if g.title and g.title ~= "" then
            head = string.format('"%s" (SKU %s) — %d copies', g.title, tostring(g.sku), g.copies)
        else
            head = string.format("SKU %s — %d copies", tostring(g.sku), g.copies)
        end
        local backstock = g.copies - g.placedCopies
        if backstock > 0 then
            head = head .. string.format(" (%d placed, %d backstock)", g.placedCopies, backstock)
        end
        lines[#lines + 1] = head .. ":"
        for i, p in ipairs(g.locs) do
            if p.placed then
                lines[#lines + 1] = string.format("    #%d  (%.1f, %.1f, %.1f)", i, p.x, p.y, p.z)
            else
                lines[#lines + 1] = string.format("    #%d  backstock (unplaced)", i)
            end
        end
    end
    lines[#lines + 1] = string.format(
        "Total sellable extras: %d   (sum of copies-1 across duplicated SKUs)", a.sellableExtras)
    return lines
end
```

- [x] **Step 4: Run the full suite — verify all pass**

```powershell
lua tests/report_test.lua
```
Expected: every check `PASS` (v1 + v2), ending `ALL PASS`, exit 0.

### Task 2.4: In-game verification of titles

- [x] **Step 1: Hot-reload and scan**

Ask the user to load a save with a known duplicated movie, `Ctrl+R`, press **F6**. (`main.lua`
is unchanged — titles flow through the existing format loop.)

- [x] **Step 2: Verify titled output**

```powershell
Select-String -Path $log -Pattern "Scan complete" | Select-Object -Last 1
Select-String -Path $log -Pattern "copies:" | Select-Object -Last 10
```
Expected: dupe headers read `"<title>" (SKU n) — k copies[ (p placed, b backstock)]:`. Confirm
one title against the in-game movie name. Any cassette with an unreadable title should appear
as a bare `SKU n — …` line (fallback working).

### Task 2.5: Commit

- [x] **Step 1: Stage source + tests and commit (no co-author)**

```bash
git add "RR Dupe Finder/Scripts/sku.lua" "RR Dupe Finder/Scripts/scan.lua" "RR Dupe Finder/Scripts/report.lua" "tests/report_test.lua"
git commit -m "Add movie titles + placed/backstock flags to report"
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 3 — In-world highlight (tint)

**Outcome:** F6 tints placed duplicates a uniform colour and refreshes; `rrdupe clear` (and an
optional key) removes the tint, robust even after a hot-reload. **Needs R2 + R3.**

> Prerequisite: `…-v2-recon.md` with **R2** (mesh accessor) and **R3** (verdict + asset path)
> filled. Pick the `highlight.lua` variant in Task 3.4 matching the R3 verdict.

### Task 3.1: Add highlight settings to `config.lua`

**Files:**
- Modify: `RR Dupe Finder/Scripts/config.lua`

- [ ] **Step 1: Append the v2 keys**

```lua
return {
    Debug            = false,
    ScanKey          = "F6",
    Modifiers        = {},
    MinCopies        = 2,
    -- v2:
    HighlightEnabled = true,                                    -- false → report only
    TintColor        = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },  -- honoured only if the
                                                                -- overlay material has a colour param (R3)
    ClearKey         = nil,                                     -- optional key to clear tint; nil = none
}
```

- [ ] **Step 2: Syntax check**

```powershell
lua -e "assert(dofile('RR Dupe Finder/Scripts/config.lua'))" ; if ($?) { "config ok" }
```
Expected: `config ok` (config is pure data, so `dofile` works standalone).

### Task 3.2: Add the live `actor` ref to scan records

**Files:**
- Modify: `RR Dupe Finder/Scripts/scan.lua`

- [ ] **Step 1: Add `actor = cart` to the record**

Update the record line from Session 2 to also carry the live actor (so `highlight` can tint
placed dupes from this same enumeration):

```lua
            out[#out + 1] = {
                sku = s, title = sku.readTitle(cart),
                x = loc.X, y = loc.Y, z = loc.Z, name = cart:GetFullName(),
                actor = cart,
            }
```

`report.analyze` already threads `actor` through (Session 2, Task 2.3) and tests cover it — no
`report.lua` change here.

- [ ] **Step 2: Syntax check**

```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/scan.lua'))" ; if ($?) { "syntax ok" }
```
Expected: `syntax ok`.

### Task 3.3: Create `highlight.lua`

**Files:**
- Create: `RR Dupe Finder/Scripts/highlight.lua`

- [ ] **Step 1 (verdict = overlay — the preferred path): write the overlay implementation**

Substitute `<MESH>` (R2 accessor, e.g. `StaticMeshComponent`) and `<MATPATH>` (R3 material):

```lua
-- RR Dupe Finder — in-world tint of duplicate cassettes (UE-bound)
local M = {}

local MAT_PATH = "<MATPATH>"   -- ← R3 overlay material full path

local cached = nil
local function tintMaterial()
    if cached and cached:IsValid() then return cached end
    cached = StaticFindObject(MAT_PATH)
    if cached and cached:IsValid() then return cached end
    cached = nil; return nil
end

local function meshOf(cart)            -- R2 accessor
    return cart.<MESH>
end

-- apply(actors, colour): overlay-tint each actor's mesh. Returns count tinted.
-- `colour` is currently informational (the overlay material carries the colour); kept for
-- the DMI variant. Stateless restore (clear) means we store nothing here.
function M.apply(actors, colour)
    local mat = tintMaterial(); if not mat then return 0 end
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not cart or not cart:IsValid() then return end
            local mesh = meshOf(cart); if not mesh or not mesh:IsValid() then return end
            mesh:SetOverlayMaterial(mat)
            n = n + 1
        end)
    end
    return n
end

-- clear(): remove the overlay from ALL cassettes (not just a remembered set), so a tint
-- orphaned by a prior run or a hot-reload is always recoverable.
function M.clear()
    local carts = FindAllOf("Cartridge_Base_C") or {}
    for _, cart in pairs(carts) do
        pcall(function()
            if not cart or not cart:IsValid() then return end
            if cart:GetFullName():find("Default__") then return end
            local mesh = meshOf(cart)
            if mesh and mesh:IsValid() then mesh:SetOverlayMaterial(nil) end
        end)
    end
end

return M
```

- [ ] **Step 1-alt (verdict = dmi or swap): stateful-tint variant**

If R3 chose DMI or material-swap instead, use this `apply`/`clear` pair (rest of the file
identical). It captures element-0's original material so `clear` can restore it, **and** falls
back to the recorded base material (R2 Step 2) when the capture map was wiped by a hot-reload:

```lua
local BASE_MAT_PATH = "<R2 base material full path>"
local original = {}   -- [actor fullname] = UMaterialInterface

function M.apply(actors, colour)
    local mat = tintMaterial(); if not mat then return 0 end
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not cart or not cart:IsValid() then return end
            local mesh = meshOf(cart); if not mesh or not mesh:IsValid() then return end
            local fn = cart:GetFullName()
            if original[fn] == nil then original[fn] = mesh:GetMaterial(0) end
            mesh:SetMaterial(0, mat)   -- (DMI: mesh:CreateDynamicMaterialInstance(0) then SetVectorParameterValue)
            n = n + 1
        end)
    end
    return n
end

function M.clear()
    local base = StaticFindObject(BASE_MAT_PATH)
    local carts = FindAllOf("Cartridge_Base_C") or {}
    for _, cart in pairs(carts) do
        pcall(function()
            if not cart or not cart:IsValid() or cart:GetFullName():find("Default__") then return end
            local mesh = meshOf(cart); if not mesh or not mesh:IsValid() then return end
            local restore = original[cart:GetFullName()] or base
            if restore and restore:IsValid() then mesh:SetMaterial(0, restore) end
        end)
    end
    original = {}
end
```

- [ ] **Step 1-fallback (verdict = marker): spawned-marker variant**

If no tint mechanism worked, spawn a bright mesh above each placed dupe. Substitute
`<MARKERMESH>` (R3 mesh path). Spawning uses the Kismet/UEHelpers pattern — mirror
`LineTraceMod`/`shared\UEHelpers` for `GetWorld`/spawn specifics:

```lua
local MARKER_MESH = "<MARKERMESH>"
local Z_OFFSET    = 40.0
local spawned     = {}

function M.apply(actors, colour)
    local mesh = StaticFindObject(MARKER_MESH); if not mesh or not mesh:IsValid() then return 0 end
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not cart or not cart:IsValid() then return end
            local loc = cart:K2_GetActorLocation()
            -- Spawn a StaticMeshActor at (loc.X, loc.Y, loc.Z + Z_OFFSET); set its mesh to `mesh`.
            -- Use UEHelpers.GetWorld() + the Kismet spawn pattern from LineTraceMod; keep the
            -- returned actor in `spawned`. (Exact spawn call recorded with R3 if this branch is taken.)
            spawned[#spawned + 1] = nil   -- ← replace with the spawned actor handle
            n = n + 1
        end)
    end
    return n
end

function M.clear()
    for _, m in pairs(spawned) do
        pcall(function() if m and m:IsValid() then m:K2_DestroyActor() end end)
    end
    spawned = {}
end

return M
```

- [ ] **Step 2: Syntax check the chosen variant**

```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/highlight.lua'))" ; if ($?) { "syntax ok" }
```
Expected: `syntax ok`. (It references UE globals, so it only *loads* standalone; behaviour is
verified in-game in Task 3.5.)

### Task 3.4: Wire `main.lua` to the clear→scan→report→tint flow

**Files:**
- Modify: `RR Dupe Finder/Scripts/main.lua`

- [ ] **Step 1: Replace `main.lua` with the v2 version**

```lua
-- RR Dupe Finder — entry point (v2: report + in-world tint)
local Config    = require("config")
local scan      = require("scan")
local report    = require("report")
local highlight = require("highlight")

local P = "[RR-Dupe] "
local function log(m) print(P .. m .. "\n") end

-- Collect the live actors of every PLACED copy of every duplicated SKU.
local function placedDupeActors(analysis)
    local actors = {}
    for _, g in ipairs(analysis.dupes) do
        for _, p in ipairs(g.locs) do
            if p.placed and p.actor then actors[#actors + 1] = p.actor end
        end
    end
    return actors
end

local function runScan()
    highlight.clear()                                   -- drop any prior tint (refresh)
    local records, skipped = scan.run()
    local analysis = report.analyze(records, Config.MinCopies)
    for _, line in ipairs(report.format(analysis)) do log(line) end
    if Config.Debug and skipped > 0 then
        log(string.format("(debug) skipped %d cassette(s) with unreadable SKU", skipped))
    end
    if Config.HighlightEnabled then
        local actors = placedDupeActors(analysis)
        local n = highlight.apply(actors, Config.TintColor) or #actors
        log(string.format("Tinted %d placed duplicate cassette(s). Press %s to refresh or 'rrdupe clear' to clear.",
            n, Config.ScanKey))
    end
end

local function onScanKey()
    ExecuteInGameThread(function()                      -- UObject reads + material writes on the game thread
        local ok, err = pcall(runScan)
        if not ok then log("Scan error: " .. tostring(err)) end
    end)
end

local function onClear()
    ExecuteInGameThread(function()
        local ok, err = pcall(function() highlight.clear() end)
        if ok then log("Cleared duplicate tint.") else log("Clear error: " .. tostring(err)) end
    end)
end

-- scan keybind (+ optional modifiers)
local key = Key[Config.ScanKey]
if Config.Modifiers and #Config.Modifiers > 0 then
    local mods = {}
    for _, name in ipairs(Config.Modifiers) do mods[#mods + 1] = ModifierKey[name] end
    RegisterKeyBind(key, mods, onScanKey)
else
    RegisterKeyBind(key, onScanKey)
end

-- optional dedicated clear key
if Config.ClearKey then RegisterKeyBind(Key[Config.ClearKey], onClear) end

-- console: "rrdupe" = scan/refresh, "rrdupe clear" = clear only
RegisterConsoleCommandHandler("rrdupe", function(fullCommand, parameters, outputDevice)
    if parameters and parameters[1] and tostring(parameters[1]):lower() == "clear" then
        onClear()
    else
        onScanKey()
    end
    return true
end)

log("RR Dupe Finder loaded. Press " .. Config.ScanKey .. " to scan.")
```

- [ ] **Step 2: Syntax check**

```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/main.lua'))" ; if ($?) { "syntax ok" }
```
Expected: `syntax ok`.

### Task 3.5: In-game verification of the tint

- [ ] **Step 1: Hot-reload, scan, observe**

Ask the user to load a save with placed duplicates, `Ctrl+R`, press **F6**. Confirm: placed
duplicate cassettes visibly take the tint colour; the report's `Tinted N …` line shows N equal
to the placed-dupe count in the report.

- [ ] **Step 2: Verify the tint summary line**

```powershell
Select-String -Path $log -Pattern "Tinted" | Select-Object -Last 1
```
Expected: `[RR-Dupe] Tinted N placed duplicate cassette(s). …` with N matching the sum of
placed copies across dupe groups.

- [ ] **Step 3: Verify clear + refresh + hot-reload robustness**

- Type `rrdupe clear` → confirm all tints disappear (log: `Cleared duplicate tint.`).
- Press F6 again → tints reappear (refresh works).
- With tints showing, press `Ctrl+R` (hot-reload wipes Lua state), then `rrdupe clear` →
  confirm tints still clear (stateless-clear / base-material restore proven, spec §8.2).

- [ ] **Step 4: Verify the disable switch**

Set `Config.HighlightEnabled = false`, `Ctrl+R`, F6 → report still prints with titles, **no**
tinting, no `Tinted …` line. Reset to `true` afterward.

### Task 3.6: Commit

- [ ] **Step 1: Stage and commit (no co-author)**

```bash
git add "RR Dupe Finder/Scripts/config.lua" "RR Dupe Finder/Scripts/scan.lua" "RR Dupe Finder/Scripts/highlight.lua" "RR Dupe Finder/Scripts/main.lua"
git commit -m "Add in-world tint of placed duplicate cassettes"
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 4 — Polish + docs + release

**Outcome:** edge cases confirmed, docs reconciled to v2-done, pushed to origin.

### Task 4.1: Edge-case pass

- [ ] **Step 1: No duplicates**

Save with no dupes (or set `Config.MinCopies = 99`), `Ctrl+R`, F6. Expected in log:
`No duplicates — collection is clean.` and **no** `Tinted …` line (no placed dupes → 0 tinted;
the line may print `Tinted 0 …` — acceptable, but confirm nothing is mis-tinted). Reset
`MinCopies = 2`.

- [ ] **Step 2: All-backstock duplicate**

If a duplicated SKU has only `(0,0,0)` copies, confirm the report shows it with
`(0 placed, k backstock)` and that **nothing** is tinted for it (placed filter holds). Verify
via:
```powershell
Select-String -Path $log -Pattern "backstock" | Select-Object -Last 5
```

- [ ] **Step 3: Tests still green**

```powershell
lua tests/report_test.lua
```
Expected: `ALL PASS` (report.lua unchanged since Session 2; confirms no regression).

### Task 4.2: Reconcile docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (only if a claim is now inaccurate)

- [ ] **Step 1: Update CLAUDE.md §10 (Current status)**

Add a v2 line: the mod now reads the movie **title** (via `sku.readTitle`, recon key R1),
reports `"Title" (SKU n)` with backstock flagged, and tints placed duplicates via
`highlight.lua` (record the R3 mechanism used). Note `highlight.clear()` is stateless so tints
survive/recover across hot-reload.

- [ ] **Step 2: Update CLAUDE.md §5 + §11**

In §5 "Still unknown / TODO", strike the items the recon doc resolved (title field; mesh
component) and cite `…-v2-recon.md`. In §11, mark **v2 done**; move any unrun R4 items
(inventory array, rented flag) into the v3 bullets. Update §11's "Exploration TODO" to reflect
what recon answered.

- [ ] **Step 3: Update §12 reference + README**

Add `highlight.lua` to CLAUDE.md §12 / the module list if such a list exists. Read `README.md`;
if it describes only SKU output or "v1", update the Features/Usage to mention titles + tint and
the `rrdupe clear` command. No broad rewrite — fix only inaccurate claims.

### Task 4.3: Final verification + push

- [ ] **Step 1: Full smoke test**

`Ctrl+R`, F6 on a save with placed + backstock duplicates. Confirm in one pass: titled report,
backstock marked, placed dupes tinted, `rrdupe clear` clears, tests green.

- [ ] **Step 2: Commit (docs by path / force-add new) — no co-author**

```bash
git add "RR Dupe Finder/Scripts" "tests/report_test.lua"
git commit -m "Reconcile docs and README for v2 (titles + tint)" -- CLAUDE.md README.md 2>/dev/null || git commit -m "v2 polish"
```
> Note: `CLAUDE.md` is gitignored/untracked (CLAUDE.md §9) — do **not** `git add` it; leave it
> local. `README.md` is tracked and stages normally. Adjust the commit to whatever is actually
> tracked + changed; the point is one clean commit with no co-author trailer.

- [ ] **Step 3: Verify no co-author, rebase, push**

```bash
git log -1 --format="%an <%ae>%n%n%B"
git fetch && git rebase origin/main
git push origin main
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line; rebase
clean; push succeeds.

---

## Notes for whoever executes this

- **Session 1 gates everything.** Do not start Session 2 without R1, or Session 3 without
  R2/R3, filled in `…-v2-recon.md`. Sessions 2 and 3 are independent given recon — Session 2
  (titles) needs only R1, so it can land while R3 is still being settled.
- **Don't guess GUID-mangled keys or asset paths** — every `<…>` placeholder in Sessions 2–3
  is filled from the committed recon doc, never invented (CLAUDE.md gotcha 4).
- **`report.lua` stays UE-free.** It threads `actor` as an opaque value; never call a method on
  it inside `report`. All UObject work happens in `scan`/`highlight`/`main` on the game thread.
- **Tinting writes to UObjects** — it must run inside `ExecuteInGameThread` (it does, via
  `onScanKey`/`onClear`). Never tint from a raw keybind callback.
- **Prefer the stateless `clear`.** The overlay variant needs no per-actor state, which is why
  it's first choice; the stateful variant must keep the base-material fallback so a
  hot-reload-orphaned tint stays clearable.
- **Em-dashes** in report strings are mojibake in the on-disk log but fine in the GUI console;
  grep the log with ASCII patterns (gotcha 9). Tests compare `—` literally and both files are
  UTF-8, so they match.
