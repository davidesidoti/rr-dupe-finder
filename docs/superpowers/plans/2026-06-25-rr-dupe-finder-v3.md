# RR Dupe Finder — v3 Implementation Plan ("DUPLICATE" sticker + rented filter)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stick a real in-world **"DUPLICATE"** label (a custom cooked texture on a flat quad, shipped in a `_P.pak`) onto every *sellable* duplicate cassette, and **exclude rented copies** (detected via the game's Reserved sticker) from the dupe flagging.

**Architecture:** Two independent tracks. **Track A (Sessions 1)** is pure-Lua + scan: the rented filter and the sellable/backstock/rented report breakdown — fully TDD'd in `report.lua`, ships value with zero new tooling. **Track B (Sessions 2–5)** is the layer-3 asset pipeline: install UE5.4 + a packer (S2), a **load-spike risk gate** that proves UE4SS can load a custom-pak asset (S3 — fail here ⇒ Fallback appendix), author the DUPLICATE art (S4), then swap `highlight.lua` from the v2 outline shell to the spawned quad sticker (S5). Session 6 polishes, reconciles docs, and pushes. The pure/UE-bound split is preserved: `report.lua` stays UE-free and unit-tested.

**Tech Stack:** Lua 5.4 (UE4SS v3.0.1) — `FindAllOf`, `StaticFindObject`, **`LoadAsset`**, `K2_GetComponentsByClass`, `SetMaterial`, `BeginDeferredActorSpawnFromClass`/`FinishSpawningActor`, `ExecuteInGameThread`. Standalone Lua (scoop) for `report` tests. **New:** UE5.4 editor (Epic Launcher) + a UE pak tool (`repak` or UnrealPak) + `FModel` for pak inspection.

**Spec:** `docs/superpowers/specs/2026-06-25-rr-dupe-finder-v3-design.md` — read it first.

---

## ⚠️ Commit policy (applies to EVERY commit in this plan)

All commits are attributed solely to the user (`hash_developer <sidotidavide@gmail.com>`).
**NEVER add a `Co-Authored-By` trailer.** This overrides the default harness rule. Plain
`git commit -m "..."`, committed directly to `main`.

**`docs/` files are gitignored** (CLAUDE.md §9). New docs files (this plan, any recon doc) need
`git add -f` to stage past the ignore; *tracked* docs files are committed **by path**
(`git commit -m "..." -- "docs/..."`). Source under `RR Dupe Finder/` and `tests/` stage
normally. **The `.pak` and any UE project go OUTSIDE the repo** (the pak lives in the game's
`~mods` folder; see §"Asset artifacts" below) — they are not committed. Push only in Session 6:
`git fetch && git rebase origin/main` first (the remote can diverge; CLAUDE.md §9).

After each commit, verify:
```bash
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, **no** `Co-Authored-By` line.

## How to run each session in a separate Claude Code session

Open Claude Code in `D:\Github\rr-dupe-finder` and prompt:

> Read `CLAUDE.md`, `docs/superpowers/specs/2026-06-25-rr-dupe-finder-v3-design.md`, and
> `docs/superpowers/plans/2026-06-25-rr-dupe-finder-v3.md`. Execute **Session N**, checking off
> each step. Honor the commit policy: no `Co-Authored-By` trailer.

## Verification reality

UE4SS Lua runs **inside the game process**. Only `report.lua` (pure) has automated tests. `scan`,
`highlight`, `main` are verified by the manual in-game loop: hot-reload (`Ctrl+R`), press **F6** (or
type `rrdupe`), read `UE4SS.log`. The GUI console does **not** spawn here (opengl — gotcha 11), so
read the log from disk. The running process keeps the **old** script until `Ctrl+R`; key off the log
**timestamp**. **Grep the log with ASCII patterns** — em-dashes are mojibake on disk (gotcha 9).

Set `$log` first in PowerShell:
```powershell
$log = "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\UE4SS.log"
```

## Asset artifacts (Track B — live outside the repo)

| Artifact | Location | Committed? |
|---|---|---|
| UE5.4 modding project | `D:\RRModKit\` (or anywhere outside the repo) | No |
| Final mod pak | `…\RetroRewind\Content\Paks\~mods\RRDupeSticker_P.pak` | No |
| Runtime asset path (in pak) | `/Game/RRDupe/MI_Duplicate-Sticker` + `/Game/RRDupe/T_VHS_Duplicate` | n/a |

The Lua only references the **runtime asset path**; that string is the contract between Track B's pak
and `highlight.lua`. Pick it in S2 Step "asset path convention" and use it verbatim thereafter.

---

## File structure (v3 deltas)

| File | v3 change | Touched in |
|------|-----------|-----------|
| `RR Dupe Finder/Scripts/scan.lua` | records gain `rented` (component scan for Reserved sticker) | Session 1 |
| `RR Dupe Finder/Scripts/report.lua` | per-copy `rented`; group `sellable/backstock/rented` counts; new suffix + per-copy lines; rented-aware `sellableExtras` | Session 1 |
| `tests/report_test.lua` | v3 cases; v2 suffix strings updated to the new wording | Session 1 |
| `RR Dupe Finder/Scripts/main.lua` | collect **sellable** (placed ∧ not rented) actors for labeling | Sessions 1, 5 |
| `RR Dupe Finder/Scripts/config.lua` | + `ExcludeRented` (S1); + `StickerEnabled`, `KeepOutlineShell` (S5) | Sessions 1, 5 |
| `RR Dupe Finder/Scripts/highlight.lua` | swap outline shell → spawned quad + custom material; material-match clear | Session 5 |
| `CLAUDE.md`, `README.md` | reconcile to v3-done | Session 6 |

---

# SESSION 1 — Rented filter + report buckets (pure Lua, TDD)

**Outcome:** the report classifies each copy as **sellable / backstock / rented**, rented copies are
excluded from labeling and from the "sellable extras" tally, and the existing v2 outline-shell
highlight now skips rented cassettes. **No new tooling. Ships independently of Track B.**

### Task 1.1: Extend `report.lua` (rented buckets) — TDD

**Files:**
- Modify: `tests/report_test.lua`
- Modify: `RR Dupe Finder/Scripts/report.lua`

- [x] **Step 1: Update the two v2 suffix expectations to the new bucket wording**

The suffix changes from `(p placed, b backstock)` to a non-zero-bucket list `(s sellable, b backstock,
r rented)`. In `tests/report_test.lua`, change the two existing v2 expectations:

```lua
    check("v2 suffix header",    lines[2] == '"Alien" (SKU 50) — 2 copies (1 sellable, 1 backstock):')
```
(the `"Akira"` all-placed case still expects **no** suffix: `'"Akira" (SKU 60) — 2 copies:'` — leave it.)

- [x] **Step 2: Write the failing v3 cases**

Insert immediately before the final summary `print(...)` line in `tests/report_test.lua`:

```lua
-- v3: rented copy is bucketed rented (precedence over backstock/sellable) and excluded from extras
do
    local recs = {
        { sku = 80, title = "Jaws", x = 10, y = 10, z = 10, rented = false }, -- sellable
        { sku = 80, title = "Jaws", x = 20, y = 20, z = 20, rented = true  }, -- rented (placed but reserved)
        { sku = 80, title = "Jaws", x = 0,  y = 0,  z = 0,  rented = false }, -- backstock
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v3 copies==3",         g.copies == 3)
    check("v3 sellableCopies==1", g.sellableCopies == 1)
    check("v3 backstockCopies==1",g.backstockCopies == 1)
    check("v3 rentedCopies==1",   g.rentedCopies == 1)
    check("v3 loc rented flag",   g.locs[2].rented == true)
end

-- v3: full three-bucket suffix + per-copy lines
do
    local recs = {
        { sku = 81, title = "Saw", x = 1, y = 1, z = 1, rented = false }, -- sellable
        { sku = 81, title = "Saw", x = 0, y = 0, z = 0, rented = false }, -- backstock
        { sku = 81, title = "Saw", x = 5, y = 6, z = 7, rented = true  }, -- rented
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v3 3-bucket suffix", lines[2] == '"Saw" (SKU 81) — 3 copies (1 sellable, 1 backstock, 1 rented):')
    check("v3 sellable line",   lines[3] == "    #1  (1.0, 1.0, 1.0)")
    check("v3 backstock line",  lines[4] == "    #2  backstock (unplaced)")
    check("v3 rented line",     lines[5] == "    #3  rented (can't sell)")
end

-- v3: rented subtracted from sellable extras ((copies - rented) - 1)
do
    local recs = {
        { sku = 82, title = "Cube", x = 1, y = 1, z = 1, rented = false },
        { sku = 82, title = "Cube", x = 2, y = 2, z = 2, rented = false },
        { sku = 82, title = "Cube", x = 3, y = 3, z = 3, rented = true  },
    }
    check("v3 extras excl rented", report.analyze(recs, 2).sellableExtras == 1)  -- (3-1)-1 = 1
end

-- v3: back-compat — no `rented` field behaves exactly like v2 (rented treated false)
do
    local recs = {
        { sku = 83, title = "Tron", x = 1, y = 1, z = 1 },
        { sku = 83, title = "Tron", x = 2, y = 2, z = 2 },
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v3 nil rented == sellable", g.sellableCopies == 2 and g.rentedCopies == 0)
    check("v3 extras back-compat",     report.analyze(recs, 2).sellableExtras == 1)
end
```

- [x] **Step 3: Run tests — verify the v3 cases (and the two edited v2 strings) fail**

```powershell
lua tests/report_test.lua
```
Expected: `v3 …` checks FAIL plus the edited `v2 suffix header` FAILS (still says "placed"); ends with
a failure count, exit 1.

- [x] **Step 4: Replace `analyze` and `format` in `report.lua`**

Replace both functions (keep `local M = {}` / `return M` and `isOrigin`):

```lua
local function isOrigin(x, y, z)
    return math.abs(x) < 0.5 and math.abs(y) < 0.5 and math.abs(z) < 0.5
end

-- records: array of { sku, title?, x, y, z, actor?, rented? }
-- Each copy buckets by precedence: rented → backstock(origin) → sellable.
-- Returns: { totalCarts, uniqueSkus, sellableExtras,
--            dupes = { { sku, title, copies, placedCopies,
--                        sellableCopies, backstockCopies, rentedCopies,
--                        locs = { { x, y, z, actor, placed, rented }, ... } } } }
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
            x = r.x, y = r.y, z = r.z, actor = r.actor,
            placed = not isOrigin(r.x, r.y, r.z),
            rented = r.rented == true,
        }
    end
    local dupes, sellableExtras = {}, 0
    for _, s in ipairs(order) do
        local g = bySku[s]
        g.copies, g.placedCopies = #g.locs, 0
        g.sellableCopies, g.backstockCopies, g.rentedCopies = 0, 0, 0
        for _, p in ipairs(g.locs) do
            if p.placed then g.placedCopies = g.placedCopies + 1 end
            if p.rented then
                g.rentedCopies = g.rentedCopies + 1
            elseif not p.placed then
                g.backstockCopies = g.backstockCopies + 1
            else
                g.sellableCopies = g.sellableCopies + 1
            end
        end
        if g.copies >= minCopies then
            dupes[#dupes + 1] = g
            sellableExtras = sellableExtras + math.max(0, (g.copies - g.rentedCopies) - 1)
        end
    end
    table.sort(dupes, function(a, b)
        if a.copies ~= b.copies then return a.copies > b.copies end   -- most-duplicated first
        return a.sku < b.sku                                          -- tie-break by SKU asc
    end)
    return { totalCarts = #records, uniqueSkus = #order, dupes = dupes, sellableExtras = sellableExtras }
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
        -- suffix = non-zero buckets, omitted entirely when everything is sellable
        if g.backstockCopies > 0 or g.rentedCopies > 0 then
            local parts = {}
            if g.sellableCopies  > 0 then parts[#parts + 1] = g.sellableCopies  .. " sellable"  end
            if g.backstockCopies > 0 then parts[#parts + 1] = g.backstockCopies .. " backstock" end
            if g.rentedCopies    > 0 then parts[#parts + 1] = g.rentedCopies    .. " rented"     end
            head = head .. " (" .. table.concat(parts, ", ") .. ")"
        end
        lines[#lines + 1] = head .. ":"
        for i, p in ipairs(g.locs) do
            if p.rented then
                lines[#lines + 1] = string.format("    #%d  rented (can't sell)", i)
            elseif p.placed then
                lines[#lines + 1] = string.format("    #%d  (%.1f, %.1f, %.1f)", i, p.x, p.y, p.z)
            else
                lines[#lines + 1] = string.format("    #%d  backstock (unplaced)", i)
            end
        end
    end
    lines[#lines + 1] = string.format(
        "Total sellable extras: %d   (copies minus rented, minus one to keep, per duplicated SKU)",
        a.sellableExtras)
    return lines
end
```

- [x] **Step 5: Run the full suite — verify all pass**

```powershell
lua tests/report_test.lua
```
Expected: every check PASS (v1 + v2 + v3), ending `ALL PASS`, exit 0.

### Task 1.2: Rented detection in `scan.lua`

**Files:**
- Modify: `RR Dupe Finder/Scripts/scan.lua`

- [x] **Step 1: Add an `isRented` helper + thread `rented` onto each record**

Add near the top of `scan.lua` (after the `require`s):

```lua
-- A cassette is rented iff it carries a VISIBLE Reserved-sticker mesh component
-- (recon: SM_VHS_Reserved-Sticker_01 on NODE_AddStaticMeshComponent-0). Read .StaticMesh
-- (GetStaticMesh() not exposed — gotcha 12). Fully pcall-guarded; defaults false.
local RESERVED_MESH = "SM_VHS_Reserved-Sticker_01"
local function isRented(cart)
    local rented = false
    pcall(function()
        local smcClass = StaticFindObject("/Script/Engine.StaticMeshComponent")
        if not smcClass then return end
        local comps = cart:K2_GetComponentsByClass(smcClass)
        if not comps then return end
        comps:ForEach(function(_, e)
            local c = e:get()
            if rented or not c then return end
            local sm = c.StaticMesh
            if sm and sm:GetFullName():find(RESERVED_MESH) then
                local vis = false; pcall(function() vis = c:IsVisible() end)
                if vis then rented = true end
            end
        end)
    end)
    return rented
end
```

Then in `M.run`, add `rented = isRented(cart)` to the record table (keep the v2/v3 fields):

```lua
            out[#out + 1] = {
                sku = s, title = sku.readTitle(cart),
                x = loc.X, y = loc.Y, z = loc.Z, name = cart:GetFullName(),
                actor = cart, rented = isRented(cart),
            }
```

- [x] **Step 2: Syntax check**

```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/scan.lua'))" ; if ($?) { "syntax ok" }
```
Expected: `syntax ok`.

### Task 1.3: Make labeling rented-aware in `main.lua` + `config.lua`

**Files:**
- Modify: `RR Dupe Finder/Scripts/config.lua`
- Modify: `RR Dupe Finder/Scripts/main.lua`

- [x] **Step 1: Add `ExcludeRented` to `config.lua`**

Insert into the returned table (after `MinCopies`):

```lua
    ExcludeRented    = true,    -- v3: don't label rented copies (you can't sell them)
```

- [x] **Step 2: Collect *sellable* actors in `main.lua`**

Replace `placedDupeActors` with a rented-aware collector and update its one call site:

```lua
-- Live actors of every copy eligible for an in-world label: placed, and (unless the player
-- opts out) not rented. Rented copies can't be sold, so by default they're skipped.
local function sellableDupeActors(analysis)
    local actors = {}
    for _, g in ipairs(analysis.dupes) do
        for _, p in ipairs(g.locs) do
            local skip = p.rented and Config.ExcludeRented
            if p.placed and not skip and p.actor then actors[#actors + 1] = p.actor end
        end
    end
    return actors
end
```

In `runScan`, change `local actors = placedDupeActors(analysis)` to
`local actors = sellableDupeActors(analysis)`. (The summary log line text is unchanged for now;
Session 5 rewords it for the sticker.)

- [x] **Step 3: Syntax check both**

```powershell
lua -e "assert(dofile('RR Dupe Finder/Scripts/config.lua'))" ; if ($?) { "config ok" }
lua -e "assert(loadfile('RR Dupe Finder/Scripts/main.lua'))" ; if ($?) { "main ok" }
```
Expected: `config ok` then `main ok`.

### Task 1.4: In-game verification

- [x] **Step 1: Hot-reload and scan**

Ask the user to load a save that has at least one **rented/reserved** cassette among a duplicated
SKU, `Ctrl+R`, press **F6**.

- [x] **Step 2: Verify the breakdown + rented exclusion**

```powershell
Select-String -Path $log -Pattern "copies" | Select-Object -Last 10
Select-String -Path $log -Pattern "rented" | Select-Object -Last 10
```
Expected: a dupe header shows `(… sellable, … rented)` and rented copies render as
`#n  rented (can't sell)`. The v2 outline shell (still active) must **not** appear on the rented
cassette — confirm visually with the user. (If a known-rented cassette reads as sellable, re-check the
Reserved-sticker mesh name against a fresh component probe before proceeding.)

### Task 1.5: Commit

- [x] **Step 1: Stage source + tests and commit (no co-author)**

```bash
git add "RR Dupe Finder/Scripts/scan.lua" "RR Dupe Finder/Scripts/report.lua" "RR Dupe Finder/Scripts/config.lua" "RR Dupe Finder/Scripts/main.lua" "tests/report_test.lua"
git commit -m "Add rented-cassette filter and sellable/backstock/rented report breakdown"
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 2 — Asset tooling setup (Track B foundation)

**Outcome:** a working **author → cook → pack → install** pipeline that can put a trivial custom asset
into the game's `~mods`, plus the confirmed pack command and runtime asset-path convention. **This is
an investigation/setup session, not TDD.** It produces a short recon note, not build code.

> Mirrors v2's Session 1 in spirit: discover concrete facts, record them, gate later sessions. No
> code in the repo changes here.

### Task 2.1: Install the editor + tools

**Files:** none in the repo.

- [x] **Step 1: Install UE5.4 + a packer + an inspector**

- Epic Games Launcher → **Unreal Engine 5.4.x** (match the game's engine, CLAUDE.md §2).
- A UE pak tool: **`repak`** (https://github.com/trumank/repak — prebuilt release or `cargo install
  repak_cli`) **or** UnrealPak (ships in the engine at `Engine/Binaries/Win64/UnrealPak.exe`).
- **`FModel`** (https://fmodel.app) to browse the game's paks.

Record exact versions/paths in the recon note (Task 2.4).

- [x] **Step 2: Verify each tool launches**

```powershell
# adjust paths to where you installed them
repak --version        # or: & "<engine>\Engine\Binaries\Win64\UnrealPak.exe" 2>&1 | Select-Object -First 1
```
Expected: a version/usage banner (proves the packer runs).

### Task 2.2: Learn the real `~mods` format from an existing reskin

- [x] **Step 1: Inspect `RRMT_FlyerReSkin_P.pak` in FModel**

Open `…\RetroRewind\Content\Paks\RRMT_FlyerReSkin_P.pak` (and the base `RetroRewind-Windows.pak` for
the AES key if prompted — RR paks are typically unencrypted; note if a key is needed). Confirm:
- the internal mount path of an overridden asset (e.g. `RetroRewind/Content/...`),
- whether the existing mods are `.pak` (loose) vs `.utoc/.ucas` (IoStore) — drives Risk R2.

Record both in the recon note.

- [ ] **Step 2: Extract the NEW sticker texture (style reference, optional)**

In FModel, export the texture used by `SM_VHS_NewRelease-Sticker` /
`/Game/VideoStore/asset/prop/vhs/` as PNG. This is only a visual reference for the DUPLICATE art —
not strictly required, but handy in S4.

### Task 2.3: Stand up a minimal mod project + prove a trivial pak builds

**Files:** outside the repo (e.g. `D:\RRModKit\`).

- [x] **Step 1: Create a UE5.4 Blank project and one throwaway asset**

New **Blank** C++-free project (UE 5.4). In the Content Browser create a folder matching the **runtime
asset-path convention**: `/Game/RRDupe/`. Add one trivial `Texture2D` named `T_RRDupe_Test` (import any
small PNG) and one **Unlit** material `M_RRDupe_Test` sampling it (Material Domain = Surface, Shading
Model = Unlit, Emissive = the texture). Save.

- [x] **Step 2: Cook + pack into `~mods`**

Cook for Windows (Platforms → Windows → Cook Content), then pack the cooked
`…/Saved/Cooked/Windows/<Project>/Content/RRDupe/` tree into a pak whose internal paths begin
`RetroRewind/Content/RRDupe/...`. Candidate command (confirm/adjust per the tool chosen in 2.1):

```powershell
# repak: response file lists "<diskpath>" "<mountpath>" pairs, or pack a prepared folder mirror
repak pack "D:\RRModKit\packroot" "D:\SteamLibrary\steamapps\common\RetroRewind\RetroRewind\Content\Paks\~mods\RRDupeTest_P.pak"
```
Record the **exact working command** in the recon note (S3/S4 reuse it verbatim).

- [x] **Step 3: Decide and record the runtime asset-path convention**

Lock the strings the Lua will load (the contract in §"Asset artifacts"):
`/Game/RRDupe/MI_Duplicate-Sticker.MI_Duplicate-Sticker` (material) — `StaticFindObject`/`LoadAsset`
need the full `Package.Object` form. Record this.

### Task 2.4: Write + commit the tooling recon note

**Files:**
- Create: `docs/superpowers/specs/2026-06-25-rr-dupe-finder-v3-tooling.md`

- [x] **Step 1: Record the pipeline facts**

```markdown
# rr-dupe-finder — v3 tooling recon
**Date:** <fill>

- Editor: UE `<5.4.x>` at `<path>`
- Packer: `<repak <ver> | UnrealPak>` — working pack command:
  `<exact command>`
- Pak format honoured by RR: `<.pak loose | .utoc/.ucas IoStore>`  (AES key needed: `<yes/no, key>`)
- Existing-mod mount path example: `RetroRewind/Content/<...>`
- Runtime asset-path convention (the Lua contract): `/Game/RRDupe/MI_Duplicate-Sticker.MI_Duplicate-Sticker`
- Project location: `<D:\RRModKit\...>`
```

- [x] **Step 2: Commit (force-add new doc; no co-author)**

```bash
git add -f "docs/superpowers/specs/2026-06-25-rr-dupe-finder-v3-tooling.md"
git commit -m "Add v3 tooling recon (editor + packer + asset-path convention)"
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 3 — Load spike 🚦 RISK GATE

**Outcome:** a yes/no answer to the make-or-break question — *can UE4SS Lua load a brand-new asset
from our custom `_P.pak` and render it in-game?* (Spec R1 / UE4SS #1101.) **Pass → Sessions 4–5
proceed. Fail → the Fallback appendix.** No committed repo code (uses a throwaway probe).

### Task 3.1: Probe the load + render

**Files:**
- Create (temporary, deleted in Step 4): `RR Dupe Finder/Scripts/probe.lua`
- Modify (temporary): `RR Dupe Finder/Scripts/main.lua` (one `pcall(require, "probe")` line)

- [ ] **Step 1: Confirm the test pak from S2 is installed**

`RRDupeTest_P.pak` (from S2 Task 2.3) is in `…\Content\Paks\~mods\`. Restart the game so the pak mounts
(new paks need a cold start, not just `Ctrl+R`).

- [ ] **Step 2: Add a throwaway load+spawn probe**

Create `RR Dupe Finder/Scripts/probe.lua` (substitute `<MATPATH>` from the S2 asset-path convention):

```lua
-- TEMPORARY v3 load spike. DELETE after recon. Trigger: `rrspike` in the console.
local P = "[RR-Spike] "
local function log(m) print(P .. tostring(m) .. "\n") end
local MATPATH = "<MATPATH>"   -- e.g. /Game/RRDupe/M_RRDupe_Test.M_RRDupe_Test

local function run()
    log("LoadAsset " .. MATPATH)
    pcall(function() LoadAsset(MATPATH) end)           -- must run on game thread (we are, via ExecuteInGameThread)
    local mat = StaticFindObject(MATPATH)
    log("found after load: " .. tostring(mat ~= nil and mat:IsValid()))
    if not mat or not mat:IsValid() then log("FAIL: custom-pak asset did not load (#1101)"); return end

    -- spawn a plane quad at a placed cassette and paint our material on it
    local UEHelpers = require("UEHelpers")
    local gs  = UEHelpers.GetGameplayStatics()
    local kml = UEHelpers.GetKismetMathLibrary()
    local world = UEHelpers.GetWorld()
    local plane = StaticFindObject("/Engine/BasicShapes/Plane.Plane")
    local smClass = StaticFindObject("/Script/Engine.StaticMeshActor")
    local cart
    for _, c in pairs(FindAllOf("Cartridge_Base_C") or {}) do
        if c and c:IsValid() and not c:GetFullName():find("Default__") then
            local l = c:K2_GetActorLocation()
            if not (math.abs(l.X) < 0.5 and math.abs(l.Y) < 0.5 and math.abs(l.Z) < 0.5) then cart = c; break end
        end
    end
    if not cart then log("no placed cassette to test on"); return end
    local xform = kml:MakeTransform(cart:K2_GetActorLocation(), cart:K2_GetActorRotation(),
                                    { X = 0.3, Y = 0.3, Z = 0.3 })
    local a = gs:BeginDeferredActorSpawnFromClass(world, smClass, xform, 1, nil, 1)
    local smc = a.StaticMeshComponent
    smc:SetMobility(2)
    smc:SetStaticMesh(plane)
    gs:FinishSpawningActor(a, xform, 1)
    smc:SetMaterial(0, mat)
    pcall(function() smc:SetCollisionEnabled(0) end)
    log("PASS: spawned quad with custom material — confirm it is visible in-game")
end

RegisterConsoleCommandHandler("rrspike", function()
    ExecuteInGameThread(function() local ok,e = pcall(run); if not ok then log("error " .. tostring(e)) end end)
    return true
end)
log("v3 load spike loaded — type 'rrspike'")
```

Add to the end of `main.lua` (temporary):
```lua
pcall(require, "probe")   -- TEMP v3 spike; remove with probe.lua
```

- [ ] **Step 3: Run the spike and read the verdict**

`Ctrl+R`, type `rrspike` in the console, then:
```powershell
Select-String -Path $log -SimpleMatch -Pattern "[RR-Spike]" | Select-Object -Last 10 | ForEach-Object { $_.Line }
```
Ask the user whether a small textured quad appeared on a cassette.
- **PASS** = `found after load: true` **and** the user sees the quad → custom-pak loading works.
- **FAIL** = `found after load: false` (or no quad) → asset didn't load.

- [ ] **Step 4: Remove the probe**

Delete `RR Dupe Finder/Scripts/probe.lua` and the `pcall(require, "probe")` line. Confirm:
```bash
git status --porcelain "RR Dupe Finder/Scripts/main.lua"
```
Expected: empty (main.lua back to its Session-1 committed state; probe.lua was never tracked).

### Task 3.2: Record the verdict + branch

- [ ] **Step 1: Append the verdict to the tooling recon note**

Add to `…-v3-tooling.md`:
```markdown
## Load spike (R1 / #1101)
- Verdict: `<PASS | FAIL>`
- If FAIL, mitigation tried: `<IoStore .utoc/.ucas repack | AES | none>` → `<result>`
```
Commit by path:
```bash
git commit -m "Record v3 load-spike verdict" -- "docs/superpowers/specs/2026-06-25-rr-dupe-finder-v3-tooling.md"
```

- [ ] **Step 2: Branch**

- **PASS** → continue to Session 4.
- **FAIL** → first retry once by repacking as IoStore (`.utoc/.ucas`) if the tool supports it (Risk R2);
  if still FAIL, **stop Track B and execute the Fallback appendix** instead of Sessions 4–5. Track A
  (Session 1) already shipped, so the rented filter stands regardless.

---

# SESSION 4 — Author the DUPLICATE art

**Outcome:** `RRDupeSticker_P.pak` in `~mods` containing the real `T_VHS_Duplicate` +
`MI_Duplicate-Sticker` at the runtime path. **Gated on S3 = PASS.** Setup/art session, not TDD.

### Task 4.1: Make the texture + material

**Files:** outside the repo (the UE project from S2).

- [ ] **Step 1: Author the label texture**

In any image editor make a square (e.g. 512×512) **"DUPLICATE"** label — bold white text on a solid/
high-contrast fill (e.g. red), transparent outside the badge so it reads as a sticker on the box.
Export PNG; import into the UE project as `T_VHS_Duplicate` under `/Game/RRDupe/`.

- [ ] **Step 2: Author the material**

Create `MI_Duplicate-Sticker` (or a base `M_` + instance) under `/Game/RRDupe/`: **Unlit**, Blend Mode
**Masked** or **Translucent**, Emissive = `T_VHS_Duplicate` RGB, Opacity/Mask = its alpha. Two-sided on.
This is the unique material the clear-sweep keys on (Spec R4), so the path must match the convention.

- [ ] **Step 3: Cook + pack into the final pak**

Cook for Windows; pack with the **exact command recorded in S2 Task 2.3**, output
`…\Content\Paks\~mods\RRDupeSticker_P.pak`. Remove the throwaway `RRDupeTest_P.pak`.

- [ ] **Step 4: Verify the asset loads in-game**

Restart the game (mount the new pak). Reuse the S3 spike *mentally*: there's no probe now, so just
confirm via S5's integration. (If unsure, temporarily re-add the S3 probe pointing at
`/Game/RRDupe/MI_Duplicate-Sticker…` and confirm `found after load: true`, then remove it again.)

---

# SESSION 5 — Lua integration: spawn the quad sticker

**Outcome:** F6 sticks the DUPLICATE quad on every sellable duplicate; `rrdupe clear` removes it
(robust across hot-reload via material-match); config gates it. **Gated on S4.** Supersedes the v2
outline shell.

### Task 5.1: Add sticker settings to `config.lua`

**Files:**
- Modify: `RR Dupe Finder/Scripts/config.lua`

- [ ] **Step 1: Append the sticker keys**

```lua
    -- v3:
    StickerEnabled   = true,    -- spawn the DUPLICATE quad sticker (supersedes the v2 outline shell)
    KeepOutlineShell = false,   -- also spawn the v2 outline shell (across-the-room spotting)
```

- [ ] **Step 2: Syntax check**

```powershell
lua -e "assert(dofile('RR Dupe Finder/Scripts/config.lua'))" ; if ($?) { "config ok" }
```
Expected: `config ok`.

### Task 5.2: Rewrite `highlight.lua` to spawn the quad sticker

**Files:**
- Modify: `RR Dupe Finder/Scripts/highlight.lua`

- [ ] **Step 1: Replace the body with the quad-sticker apply/clear**

Substitute `MAT_PATH` with the S2 convention. Keeps the v2 outline-shell spawn available behind
`KeepOutlineShell` (reuse the existing shell mesh constant from the current file).

```lua
-- RR Dupe Finder — in-world DUPLICATE label (v3): spawn a flat quad with our custom material
-- over each sellable duplicate. Clear is stateless (tracked set + material-match orphan sweep).
local M = {}
local UEHelpers = require("UEHelpers")

local MAT_PATH    = "/Game/RRDupe/MI_Duplicate-Sticker.MI_Duplicate-Sticker"  -- S2 convention; in RRDupeSticker_P.pak
local PLANE_MESH  = "/Engine/BasicShapes/Plane.Plane"
local SMA_CLASS   = "/Script/Engine.StaticMeshActor"
local SHELL_MESH  = "/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01"  -- v2 outline (optional)
local SHELL_MAT   = "/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable"
local SCALE       = 0.3
local spawned     = {}

local function findMat()
    local m = StaticFindObject(MAT_PATH)
    if (not m or not m:IsValid()) then pcall(function() LoadAsset(MAT_PATH) end); m = StaticFindObject(MAT_PATH) end
    if m and m:IsValid() then return m end
    return nil
end

local function spawnMeshAt(cart, meshPath, matObj, scale)
    local gs  = UEHelpers.GetGameplayStatics()
    local kml = UEHelpers.GetKismetMathLibrary()
    local world = UEHelpers.GetWorld()
    local mesh  = StaticFindObject(meshPath); if not mesh or not mesh:IsValid() then return end
    local cls   = StaticFindObject(SMA_CLASS)
    local xform = kml:MakeTransform(cart:K2_GetActorLocation(), cart:K2_GetActorRotation(),
                                    { X = scale, Y = scale, Z = scale })
    local a = gs:BeginDeferredActorSpawnFromClass(world, cls, xform, 1, nil, 1)
    if not a then return end
    local smc = a.StaticMeshComponent
    smc:SetMobility(2)
    smc:SetStaticMesh(mesh)
    gs:FinishSpawningActor(a, xform, 1)
    if matObj then smc:SetMaterial(0, matObj) end
    pcall(function() smc:SetCollisionEnabled(0) end)
    spawned[#spawned + 1] = a
end

-- apply(actors, _colour): label each sellable dupe. Returns count labelled.
function M.apply(actors, _colour)
    local Config = require("config")
    local mat = findMat()
    local shellMat = StaticFindObject(SHELL_MAT)
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not cart or not cart:IsValid() then return end
            if Config.StickerEnabled ~= false and mat then spawnMeshAt(cart, PLANE_MESH, mat, SCALE) end
            if Config.KeepOutlineShell == true then spawnMeshAt(cart, SHELL_MESH, shellMat, 1.1) end
            n = n + 1
        end)
    end
    return n
end

-- clear(): destroy tracked spawns, then sweep StaticMeshActors whose element-0 material is OUR
-- unique DUPLICATE material (orphan-safe across hot-reload; the game never uses that material).
function M.clear()
    for _, a in pairs(spawned) do
        pcall(function() if a and a:IsValid() then a:K2_DestroyActor() end end)
    end
    spawned = {}
    pcall(function()
        for _, a in pairs(FindAllOf("StaticMeshActor") or {}) do
            pcall(function()
                if not a or not a:IsValid() then return end
                local smc = a.StaticMeshComponent; if not smc then return end
                local m = smc:GetMaterial(0)
                if m and m:GetFullName():find("MI_Duplicate-Sticker") then a:K2_DestroyActor() end
            end)
        end
    end)
end

return M
```

- [ ] **Step 2: Syntax check**

```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/highlight.lua'))" ; if ($?) { "syntax ok" }
```
Expected: `syntax ok`.

### Task 5.3: Update the summary wording in `main.lua`

**Files:**
- Modify: `RR Dupe Finder/Scripts/main.lua`

- [ ] **Step 1: Reword the highlight summary line**

In `runScan`, replace the `Tinted %d …` log line with sticker wording:

```lua
        log(string.format("Labelled %d sellable duplicate cassette(s). Press %s to refresh or 'rrdupe clear' to clear.",
            n, Config.ScanKey))
```

- [ ] **Step 2: Syntax check**

```powershell
lua -e "assert(loadfile('RR Dupe Finder/Scripts/main.lua'))" ; if ($?) { "main ok" }
```
Expected: `main ok`.

### Task 5.4: In-game verification

- [ ] **Step 1: Label appears on sellable dupes only**

`Ctrl+R`, F6 on a save with sellable + rented + backstock dupes. Confirm: a DUPLICATE quad sits on each
**sellable** placed dupe; **none** on rented or backstock copies; log line `Labelled N …` with N =
sum of sellable copies across dupe groups.

```powershell
Select-String -Path $log -Pattern "Labelled" | Select-Object -Last 1
```

- [ ] **Step 2: Clear + refresh + hot-reload robustness**

`rrdupe clear` → all quads gone (`Cleared duplicate tint.`). F6 → reappear. With quads showing,
`Ctrl+R` then `rrdupe clear` → still clears (material-match orphan sweep proven).

- [ ] **Step 3: Config toggles**

`StickerEnabled = false`, `Ctrl+R`, F6 → report prints, no quads. `KeepOutlineShell = true` → outline
shell returns alongside (or instead of) the quad. Reset to defaults.

### Task 5.5: Commit

- [ ] **Step 1: Stage and commit (no co-author)**

```bash
git add "RR Dupe Finder/Scripts/config.lua" "RR Dupe Finder/Scripts/highlight.lua" "RR Dupe Finder/Scripts/main.lua"
git commit -m "Replace outline highlight with spawned DUPLICATE quad sticker"
git log -1 --format="%an <%ae>%n%n%B"
```
Expected: author `hash_developer <sidotidavide@gmail.com>`, no `Co-Authored-By` line.

---

# SESSION 6 — Polish + docs + release

**Outcome:** edge cases confirmed, docs reconciled to v3-done, pushed to origin.

### Task 6.1: Edge-case pass

- [ ] **Step 1: No duplicates**

`Config.MinCopies = 99`, `Ctrl+R`, F6 → `No duplicates — collection is clean.`, no quads, `Labelled 0`
acceptable but confirm nothing mislabelled. Reset `MinCopies = 2`.

- [ ] **Step 2: All-rented duplicate**

A duplicated SKU whose extra copies are all rented → header shows `(… rented)`, **zero** quads spawned
for it, and `Total sellable extras` excludes them.
```powershell
Select-String -Path $log -Pattern "rented" | Select-Object -Last 5
```

- [ ] **Step 3: Tests still green**

```powershell
lua tests/report_test.lua
```
Expected: `ALL PASS`.

### Task 6.2: Reconcile docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (only if a claim is now inaccurate)

- [ ] **Step 1: Update CLAUDE.md §10 (Current status)**

Add a v3 line: rented cassettes (detected via a visible `SM_VHS_Reserved-Sticker_01` component) are
excluded from labeling; the report breaks copies into sellable/backstock/rented; the in-world mark is
now a spawned **flat quad** carrying a custom `MI_Duplicate-Sticker` material shipped in
`~mods\RRDupeSticker_P.pak` (the mod's first **layer-3** asset). `highlight.clear` keys on that unique
material. Note the pak is **not** in the repo.

- [ ] **Step 2: Update CLAUDE.md §5 + §11 + add a gotcha**

§5: record the Reserved-sticker rented signal (resolves the R4 rented-flag TODO) and the NEW-badge
finding (`SM_VHS_NewRelease-Sticker`). §11: mark **v3 done**; move remaining ideas to v4. Add a gotcha:
*custom-pak asset loading* — whether `LoadAsset` works for additive mod assets (record the S3 verdict)
and that the asset/pak lives outside the repo.

- [ ] **Step 3: Update §12 + README**

Note `RRDupeSticker_P.pak` as a layer-3 artifact. Read `README.md`; update Features/Usage to mention the
DUPLICATE label, the rented filter, and that a pak must be installed in `~mods`. Fix only inaccurate
claims; no broad rewrite.

### Task 6.3: Final verification + push

- [ ] **Step 1: Full smoke test**

`Ctrl+R`, F6 on a save with sellable + backstock + rented dupes: titled report, three-bucket breakdown,
DUPLICATE quads on sellable only, `rrdupe clear` clears, tests green.

- [ ] **Step 2: Commit docs (README tracked; CLAUDE.md is gitignored — leave it) — no co-author**

```bash
git commit -m "Reconcile README for v3 (DUPLICATE label + rented filter)" -- README.md 2>/dev/null || echo "no README change"
git log -1 --format="%an <%ae>%n%n%B"
```
> `CLAUDE.md` is gitignored/untracked (CLAUDE.md §9) — do **not** `git add` it; edit it in place and
> leave it local.

- [ ] **Step 3: Check off this plan's sessions + commit by path**

```bash
sed -i '/^# SESSION 1 /,$ s/- \[ \]/- [x]/' "docs/superpowers/plans/2026-06-25-rr-dupe-finder-v3.md"
git commit -m "Check off v3 plan sessions" -- "docs/superpowers/plans/2026-06-25-rr-dupe-finder-v3.md"
```
> The last session has no trailing `# SESSION` header, so the range ends at `$` (CLAUDE.md §9). The
> `## Notes` tail has no `- [ ]` checkboxes, so it's safe.

- [ ] **Step 4: Rebase + push**

```bash
git fetch && git rebase origin/main
git push origin main
```
Expected: rebase clean; push succeeds; author check still shows no `Co-Authored-By`.

---

# FALLBACK APPENDIX — layer-1 "DUPLICATE" text (only if Session 3 = FAIL)

If the load spike proves custom-pak assets won't load, ship the label as **in-world 3D text** instead
of a custom-pak sticker. Replace Sessions 4–5 with this single session; Sessions 1 and 6 are unchanged
(6's docs note the fallback was taken).

### Task F.1: Spawn a `TextRenderComponent` "DUPLICATE" per sellable dupe

**Files:**
- Modify: `RR Dupe Finder/Scripts/highlight.lua`

- [ ] **Step 1: Replace apply/clear to attach 3D text**

Spawn a `StaticMeshActor` (or empty actor) at the cassette, add a `TextRenderComponent`, set its text
and a font material that already exists in-game (recon: `MI_Font_EBGaramond`). Track spawned actors;
clear destroys the tracked set (these carry no unique material, so rely on the tracked set + a name
tag, not a material sweep).

```lua
local M = {}
local UEHelpers = require("UEHelpers")
local FONT_MAT = "/Game/VideoStore/core/shader/font/MI_Font_EBGaramond.MI_Font_EBGaramond"
local SMA_CLASS = "/Script/Engine.StaticMeshActor"
local TRC_CLASS = "/Script/Engine.TextRenderComponent"
local spawned = {}

function M.apply(actors, _c)
    local gs  = UEHelpers.GetGameplayStatics()
    local kml = UEHelpers.GetKismetMathLibrary()
    local world = UEHelpers.GetWorld()
    local n = 0
    for _, cart in pairs(actors or {}) do
        pcall(function()
            if not cart or not cart:IsValid() then return end
            local xform = kml:MakeTransform(cart:K2_GetActorLocation(), cart:K2_GetActorRotation(),
                                            { X = 1, Y = 1, Z = 1 })
            local a = gs:BeginDeferredActorSpawnFromClass(world, StaticFindObject(SMA_CLASS), xform, 1, nil, 1)
            gs:FinishSpawningActor(a, xform, 1)
            local trc = a:AddComponentByClass(StaticFindObject(TRC_CLASS), false, xform, false)
            if trc then
                pcall(function() trc:SetText({ ["SourceString"] = "DUPLICATE" }) end)
                pcall(function() trc:SetTextRenderColor({ R = 255, G = 0, B = 0, A = 255 }) end)
            end
            spawned[#spawned + 1] = a
            n = n + 1
        end)
    end
    return n
end

function M.clear()
    for _, a in pairs(spawned) do pcall(function() if a and a:IsValid() then a:K2_DestroyActor() end end) end
    spawned = {}
end

return M
```

- [ ] **Step 2: Syntax check, in-game verify, commit**

`lua -e "assert(loadfile('RR Dupe Finder/Scripts/highlight.lua'))"`; then the S5 Task 5.4 in-game checks
(text reads "DUPLICATE" on sellable dupes; clear works); commit:
```bash
git add "RR Dupe Finder/Scripts/highlight.lua"
git commit -m "Fallback: in-world DUPLICATE text label (custom-pak load unavailable)"
```

---

## Notes for whoever executes this

- **Session 1 ships on its own.** The rented filter + report buckets are pure-Lua/scan and need no
  tooling. Do it first; it de-risks and delivers value even if Track B stalls.
- **Session 3 is the gate.** Do not author art (S4) or integrate (S5) until the load spike PASSES.
  On FAIL, take the Fallback appendix — don't sink time into art that can't load.
- **`report.lua` stays UE-free.** It threads `actor` opaquely and reads only plain fields
  (`rented`, `x/y/z`). All UObject work is in `scan`/`highlight`/`main`, on the game thread.
- **Don't guess asset paths.** `MI_Duplicate-Sticker` / `T_VHS_Duplicate` and the pack command come
  from the S2 tooling note; the Reserved-sticker mesh name is from the committed v3 recon (spec §2).
- **The pak and UE project live outside the repo** and are never committed; the Lua references only the
  runtime path string (the contract in §"Asset artifacts").
- **DMIs crash** via UE4SS here (gotcha 10) — the sticker colour is fixed by the authored material,
  applied with a plain `SetMaterial`. **`GetStaticMesh()` is not exposed** (gotcha 12) — read
  `.StaticMesh`. **Em-dashes** are mojibake in the on-disk log (gotcha 9) — grep ASCII.
