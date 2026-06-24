# rr-dupe-finder — v2 design (titles + in-world highlight)

**Date:** 2026-06-24
**Status:** Approved (brainstorm), ready for implementation planning
**Scope:** Full v2 — movie titles in the report **and** in-world tinting of placed
duplicates, as one milestone. v3 (per-SKU colour, rented filter, UMG list, nearest
pointer) is out of scope, outlined at the end.

Builds directly on the shipped v1 MVP. Read `CLAUDE.md` (game data model, UE4SS API,
gotchas) and the v1 spec (`2026-06-24-rr-dupe-finder-v1-design.md`) first — this spec
assumes both.

---

## 1. Goal

On the scan key (F6), in addition to the v1 detect-and-report behaviour:

1. **Name duplicates** — show each duplicated movie's **title** instead of a bare SKU
   integer (SKU shown as a fallback when a title can't be read).
2. **Locate duplicates in-world** — **tint** every *placed* duplicate cassette a single
   bright colour so the player can spot them on the shelf and walk over to sell the
   extras. Pressing F6 again refreshes; a clear trigger removes the tint.

Still read-only with respect to save data. The tint is a runtime material change on
loaded actors; it never persists to disk.

---

## 2. The recon gate (why this is a two-phase milestone)

Both features depend on facts that **cannot be derived from the repo** — they exist
only in the running game and must be read via the **UE4SS Live View**. The build is
therefore gated behind a **recon spike** (Session 1 of the plan). Guessing is
explicitly forbidden (CLAUDE.md gotcha 4: GUID-mangled struct keys are not
human-guessable).

### Recon deliverables (acceptance criteria for Session 1)

A short findings doc — `docs/superpowers/specs/2026-06-24-rr-dupe-finder-v2-recon.md` —
that records, each with the verbatim string / value observed in Live View:

- **R1 — Title field key.** The GUID-mangled property name of the movie title, a
  sibling of `SKU_26_...` inside `BoxData_25_...`. Plus its Lua type (FString/FText/
  FName) so we know how to stringify it.
- **R2 — Mesh component.** The cassette's renderable mesh component: its UClass
  (almost certainly `StaticMeshComponent`) and its property/accessor name on
  `Cartridge_Base_C`, so `highlight.lua` can reach the material.
- **R3 — Tint mechanism + feasibility verdict.** Confirm **one** workable, restorable
  way to recolour the mesh in this Shipping build, in preference order:
  1. **`SetOverlayMaterial`** (UE 5.4 has it) with a sourced translucent coloured
     material — *non-destructive, trivial restore* (set overlay → nil). **Preferred.**
  2. **Dynamic Material Instance** — only if the base material exposes a colour/tint
     scalar/vector parameter (record the parameter name).
  3. **`SetMaterial(index, mat)` swap** to a sourced bright material — restore by
     swapping back.
  - **R3a — Source a highlight asset.** A usable coloured/translucent **material**
    (for tint) reachable via `StaticFindObject`/load — and, while there, a usable
    bright **mesh** asset (for the marker fallback). Record full object paths.
  - If *none* of 1–3 works, the verdict is "tint infeasible" → build the **marker
    fallback** (§8.3) instead. This branch is decided by recon, not at runtime.
- **R4 — Opportunistic (non-blocking).** While in Live View, note (a) any central
  **player-inventory** array pairing SKU↔title (possible cleaner data source, deferred
  to v3) and (b) any **rented/owned flag** on the cartridge (v3 filter). Record or mark
  "not found"; do **not** spend the session chasing these.

Session 1 ends with the findings doc committed. Sessions 2+ consume R1–R3 as named
constants and the confirmed mechanism. **No build code is written before R1–R3 land.**

---

## 3. Design principles (carried from v1)

- **Modular, one job per unit**; keep `report.lua` free of UE calls so its branching
  logic stays unit-testable outside the game.
- **Reuse what's verified** — same struct walk, `FindAllOf`, `pcall`-per-actor,
  `ExecuteInGameThread`, `RegisterKeyBind`/`RegisterConsoleCommandHandler` as v1.
- **YAGNI** — uniform tint colour (not per-SKU), no rented filter, no UMG, no nearest
  pointer. Those are v3.
- **Non-destructive & robust restore** — prefer a tint mechanism whose clear path works
  even after a hot-reload has wiped Lua state (see §8.2).

---

## 4. Modules

Extends v1's five modules; adds one (`highlight.lua`). The pure/UE-bound boundary is
preserved: `report.lua` still makes zero UE calls and stays unit-tested.

| Module | v2 responsibility | Depends on | UE calls? |
|--------|-------------------|-----------|-----------|
| `config.lua` | + `TintColor`, `HighlightEnabled`, optional `ClearKey` | — | no |
| `sku.lua` | + `readTitle(cart)`; owns the **full product-struct read path** | — | yes |
| `scan.lua` | records gain `title` + live `actor` ref | `sku` | yes |
| `report.lua` | groups carry `title`; per-copy `placed` flag; titled format | — | **no** |
| `highlight.lua` | **new** — `apply(actors, colour)` / `clear()` | `config` | yes |
| `main.lua` | clear→scan→report→tint flow; clear trigger | all | yes |

**Why title goes in `sku.lua`, not a new `title.lua`** (the v1 spec floated a separate
file): the title is another GUID-mangled key reached by the **same** `ps → base → box`
navigation as the SKU. A separate module would duplicate that fragile walk. Keeping
both reads in the one isolated module means a future game update still touches exactly
one small file — which was the original reason `sku.lua` was split out. The module name
stays `sku.lua` to avoid churn; conceptually it is the product-struct reader.

### 4.1 `config.lua` (additions)

```lua
return {
    Debug           = false,
    ScanKey         = "F6",
    Modifiers       = {},
    MinCopies       = 2,
    -- v2:
    HighlightEnabled = true,                       -- false → report only, no tinting
    TintColor        = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },  -- uniform dupe colour
    ClearKey         = nil,                         -- optional key to clear tint; nil = none
}
```

### 4.2 `sku.lua` (add title read)

```lua
-- GUID-mangled keys. SKU verbatim from SKU QoL; TITLE_KEY from recon deliverable R1.
local PRODUCT_STRUCTURE_KEY = "Product Structure"
local BASE_STRUCTURE_KEY    = "BaseStructure_2_FBB12C464AE570CAFD12ED8506160683"
local BOX_DATA_KEY          = "BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10"
local SKU_KEY               = "SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876"
local TITLE_KEY             = nil  -- ← R1 supplies the exact literal; isolated to this line

-- shared navigation to the BoxData struct
local function box(cart)
    local ps   = cart[PRODUCT_STRUCTURE_KEY]; if not ps   then return nil end
    local base = ps[BASE_STRUCTURE_KEY];      if not base then return nil end
    return base[BOX_DATA_KEY]
end

function M.read(cart)       local b = box(cart); return b and b[SKU_KEY]   or nil end
function M.readTitle(cart)  local b = box(cart); return b and b[TITLE_KEY] or nil end
```

`readTitle` returns the title stringified per R1's type (e.g. `:ToString()` for FText).
The exact stringify call is fixed once R1 reports the field type; the rest is stable.

### 4.3 `scan.lua` (carry title + actor)

Records become `{ sku, title, x, y, z, name, actor }`. The `actor` ref lets
`highlight.lua` tint placed dupes from the same single enumeration (no second
`FindAllOf`). `title` may be `nil` — that's the fallback case, handled in `report`.

```lua
out[#out + 1] = {
    sku = s, title = sku.readTitle(cart),
    x = loc.X, y = loc.Y, z = loc.Z,
    name = cart:GetFullName(), actor = cart,
}
```

`skipped` (unreadable SKU) is retained from v1. A cassette with a readable SKU but
`nil` title is **not** skipped — it lists under its SKU.

### 4.4 `report.lua` (titles + placed flag — still pure, still tested)

`analyze` gains two pure additions; it never touches `actor` beyond passing it through
as an opaque value:

- Each group carries `title` (first non-nil title seen for that SKU).
- Each copy carries `placed` = `not isOrigin(x, y, z)`, where `isOrigin` treats
  coords within an epsilon of (0,0,0) as backstock (the §5 quirk). Group also exposes
  `placedCopies` count.

`format` renders a titled header and marks backstock:

```
Scan complete: 7 cassettes, 4 unique SKUs, 2 duplicated.
"Blade Runner" (SKU 10293) — 3 copies (2 placed, 1 backstock):
    #1  (1203.4, -882.1, 95.0)
    #2  (1530.0, -640.2, 95.0)
    #3  backstock (unplaced)
"The Thing" (SKU 55012) — 2 copies:
    #1  (300.1, 88.0, 110.0)
    #2  (412.9, 90.3, 110.0)
Total sellable extras: 3   (sum of copies-1 across duplicated SKUs)
```

Header rule: `title` present → `"<title>" (SKU <n>)`; absent → `SKU <n>`. The
"(… placed, … backstock)" suffix appears only when at least one copy is backstock.

### 4.5 `highlight.lua` (new — UE-bound, recon-gated internals)

Interface is fixed now; internals finalised by R3.

```lua
local M = {}
-- apply(actors, colour): tint each actor's cassette mesh `colour` (uniform).
--   Records nothing it can't re-derive — see clear().
-- clear(): remove the tint from ALL Cartridge_Base_C, not just a remembered set,
--   so an orphaned tint (e.g. left by a pre-hot-reload run) is always recoverable.
function M.apply(actors, colour) end
function M.clear() end
return M
```

**Preferred mechanism (R3 option 1):** `SetOverlayMaterial`. `apply` sets a translucent
coloured overlay material (sourced per R3a; tinted to `colour` via a DMI on the overlay
if it exposes a colour param) on each actor's mesh component. `clear` enumerates every
cassette and calls `SetOverlayMaterial(nil)`. This makes restore **stateless and
hot-reload-proof** — the key robustness win (§8.2). DMI-swap and material-swap
mechanisms (R3 options 2/3) require capturing originals and are the fallbacks.

---

## 5. Carried-over reality: the (0,0,0) backstock quirk

Most loaded cassettes report `K2_GetActorLocation() == (0,0,0)` — backstock/unplaced
stock you cannot walk to. Confirmed in the v1 Session-2 scan (366 readable, only
shelf-placed ones had real coords). Consequences for v2:

- **Detection/titles** cover *all* cassettes (count + group + name are position-free).
- **Tinting** targets only *placed* copies (`placed == true`). Tinting a backstock
  actor is pointless (and it may not be rendered anyway).
- The report still lists backstock copies, marked `backstock (unplaced)`, so the count
  and sellable-extras math stay complete and honest.

`isOrigin` uses a small epsilon (e.g. `abs < 0.5` on each axis) rather than exact `== 0`,
to be robust to float noise while still catching the origin cluster.

---

## 6. Data flow

```
F6 ─▶ ExecuteInGameThread ─▶ highlight.clear()          (drop any prior tint)
                          ─▶ scan.run() ─▶ records (sku, title, x,y,z, actor)
                          ─▶ report.analyze(records, MinCopies)
                          ─▶ report.format(analysis) ─▶ print() per line
                          ─▶ if HighlightEnabled:
                                 actors = placed-dupe actors from analysis
                                 highlight.apply(actors, Config.TintColor)
```

`main.lua` collects tint targets from the analysis (every `placed` copy of every dupe
group → its `actor`), so the tinted set is exactly the placed duplicates the report
lists. All of it runs on the game thread (UObject reads *and* material writes).

---

## 7. Trigger / UX (F6 as refresh)

- **F6 (scan key):** `clear → scan → report → tint`. Always a fresh refresh, so moving
  cassettes and re-pressing F6 re-tints correctly with no stale colours.
- **Clear without scanning:** `rrdupe clear` console subcommand, and the optional
  `Config.ClearKey` if set. Both call `highlight.clear()` only.
- **`rrdupe` console command:** same as F6 (full refresh).
- **`HighlightEnabled = false`:** F6 still scans + reports (with titles); no tinting.

The final report line summarises the tint, e.g.
`Tinted 4 placed duplicate cassette(s). Press F6 to refresh or 'rrdupe clear' to clear.`

---

## 8. Error handling & edge cases

### 8.1 Reuse v1 safety
`FindAllOf` nil → empty. Per-actor `pcall`. Whole run `pcall`'d → errors log, never
crash. CDO filtered in `sku.isCartridge`. Unreadable SKU → skipped + Debug tally.

### 8.2 Restore robustness (the main new risk)
A material change that can't be undone would leave cassettes permanently recoloured.
Mitigations, in order:

- **Stateless clear (preferred, via `SetOverlayMaterial`):** `clear()` re-enumerates all
  cassettes and removes the overlay — no saved state, so a tint left dangling by a
  previous run or a hot-reload is still fully clearable by pressing clear/F6.
- **If a stateful mechanism is forced (DMI/material swap):** capture each actor's
  original material in `apply`; `clear()` restores from that map. Because hot-reload
  wipes the map, **also** support restoring to the known **base cassette material**
  (R3a) as a stateless fallback so orphaned tints remain recoverable.
- `apply`/`clear` wrap each actor in `pcall`; one bad actor never aborts the batch.

### 8.3 Marker fallback (if R3 verdict = tint infeasible)
Spawn a bright `StaticMeshComponent`/actor (mesh from R3a) above each placed dupe;
track spawned markers in a table; `clear()` destroys them. Same `apply`/`clear`
interface, so `main.lua` and the report are unchanged. Decided at recon time, not at
runtime.

### 8.4 Title edge cases
`nil`/empty title → fall back to `SKU <n>` (no quotes). Non-ASCII titles render as
mojibake in the on-disk `UE4SS.log` (gotcha 9) but are fine in the GUI console; this is
display-only and does not affect grouping or tinting.

---

## 9. Testing strategy

- **`report.lua` (pure) — extend `tests/report_test.lua`:**
  - title carried onto the group; header uses `"title" (SKU n)` when present,
    `SKU n` when title is `nil`.
  - `placed` flag: origin-coord copy flagged backstock; non-origin flagged placed;
    epsilon boundary case.
  - `placedCopies` count and the "(N placed, M backstock)" suffix logic.
  - all v1 cases (grouping, sort, sellable math, MinCopies, tie-break) still green.
  - `actor` field threaded through untouched (pass a stub value, assert identity).
- **`sku.lua` / `scan.lua` / `highlight.lua` (need the game):** verified in-game —
  cross-check a known cassette's title against the in-game computer; confirm placed
  dupes visibly tint and that `clear`/F6-refresh fully restores them (including after a
  hot-reload, per §8.2). No fake "tests" for UE-bound modules (v1 rule).

---

## 10. Session breakdown (recon-gated)

Each session ends working + committed. **Commit policy unchanged: attributed solely to
the user (hash_developer / sidotidavide@gmail.com), NO `Co-Authored-By` trailer.**
Commit `docs/` changes by path (the `docs/` ignore rule blocks `git add` of new files).

1. **Recon spike.** Live View: resolve R1 (title key+type), R2 (mesh component), R3
   (tint mechanism + feasibility) incl. R3a (source a material + a mesh asset); note R4
   opportunistically. Write + commit the recon findings doc. *No build code.* This
   session gates everything after it — if R3 = infeasible, Session 3 switches to the
   marker fallback.
2. **Titles.** Add `sku.readTitle` (R1), thread `title` through `scan`; extend
   `report.analyze`/`format` + tests for titles and the `placed`/backstock flagging;
   wire `main` to print titled output. *Verify:* report shows titles, fallback works,
   tests green. *Commit.* (Fully buildable from R1 alone — independent of tint.)
3. **Highlight.** Implement `highlight.lua` per R2/R3 (or the marker fallback); add
   `actor` ref to scan records; collect placed-dupe actors in `main`; tint on F6, clear
   on `rrdupe clear`/`ClearKey`; add `TintColor`/`HighlightEnabled` to config. *Verify
   in-game:* placed dupes tint, refresh re-tints, clear restores (incl. post-hot-reload).
   *Commit.*
4. **Polish + docs + release.** `HighlightEnabled=false` path, edge cases, tint summary
   line; reconcile `CLAUDE.md` §10/§11 and README (v2 done, unknowns resolved). Final
   verification pass. *Commit + push* (fetch/rebase first, per CLAUDE.md §9).

Session 2 (titles) depends only on R1, so it can proceed even if R3 is still being
nailed down. Session 3 (highlight) is the recon-gated one.

---

## 11. Out of scope (v3 — outlined, not designed)

- **Per-SKU tint colours** (matching copies share a colour) — palette collisions with
  many dupes; deferred deliberately.
- **Rented-cassette filter** — needs R4's rented/owned flag.
- **UMG on-screen list** with distance/direction; **nearest-duplicate pointer.**
- **Inventory-array data source** — if R4 finds a central SKU↔title array, it may
  replace actor enumeration for the *report* (not the tint, which needs live actors).
- **Expanded config** — keybind/threshold/colour UI.

---

## 12. Open items resolved by recon (not unknowns at build time)

These are *inputs the recon spike produces*, listed so the plan can treat them as a
checklist — none is a runtime unknown once Session 1 lands:

1. **R1** — title field key + type (→ `sku.lua`).
2. **R2** — mesh component class + accessor (→ `highlight.lua`).
3. **R3 / R3a** — confirmed tint mechanism + sourced material (and fallback mesh) asset
   paths, or the "tint infeasible → marker" verdict.
4. **R4** — inventory array / rented flag presence (informational; gates nothing in v2).
