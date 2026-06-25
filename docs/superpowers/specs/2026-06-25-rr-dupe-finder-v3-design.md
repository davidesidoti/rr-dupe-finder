# rr-dupe-finder — v3 design: "DUPLICATE" sticker + rented filter

**Date:** 2026-06-25
**Status:** design approved in brainstorm; ready for implementation plan.
**Predecessors:** v1 (report), v2 (titles + outline-shell highlight). See `…-v2-design.md`, `…-v2-recon.md`.

---

## 1. Goal

Replace v2's spawned outline-shell highlight with a **real in-world "DUPLICATE" sticker**
stuck to each duplicate cassette, in the spirit of the game's existing **NEW** badge. Additionally,
**exclude rented cassettes** from the duplicate flagging, since they can't be sold.

The user's ask, intent: a label *attached to the cassette* (like the in-game **NEW** badge), reading
**DUPLICATE** — not floating text hovering over the box. **Shape is flexible** — it does *not* have to
be star-shaped; whatever is easiest (a plain rectangle) is fine.

---

## 2. Recon findings (completed this session)

Done via a temporary component-enumeration probe (`probe.lua`, now removed) driven by an `rrprobe`
console command. Read-only reflection over `FindAllOf("Cartridge_Base_C")` → per-actor component
lists (`BlueprintCreatedComponents` + `K2_GetComponentsByClass(SceneComponent)`).

**Component inventory of a placed cassette (`videotape_C`, 366 in the test store):**

| Component (class :: name) | Count | Visible | Meaning |
|---|---|---|---|
| `StaticMeshComponent :: Mesh` | 366 | — | the VHS box (cover = one MID `M_VHS_Master-Holographic`) |
| `StaticMeshComponent :: ShadowImpostor` | 366 | — | fake shadow; ignore |
| `StaticMeshComponent :: NODE_AddStaticMeshComponent-4` | 30 | 30 | **the NEW badge** (see below) |
| `StaticMeshComponent :: NODE_AddStaticMeshComponent-0` | 7 | 7 | **the RESERVED sticker** (see below) |
| `TextRenderComponent :: TextRender` | 366 | 155 | the movie **title** in 3D (font `MI_Font_EBGaramond`) |
| `WidgetComponent :: Widget` | 366 | 22 | the look-at detail popup (`UI_Player_LookAtDetail_3D_C`); **not** a badge |
| `AC_Border_C :: AC_Border` | 366 | — | custom "Border" actor-component; purpose unknown — **parked** (possible native outline for a future highlight) |
| `TimelineComponent` ×3, `AC_PhysicsSound_C`, `SceneComponent::DefaultSceneRoot` | 366 | — | animation/sound/root; irrelevant |

**Key assets (verbatim full paths):**

- **NEW badge** = construction-script-added static mesh
  `StaticMesh /Game/VideoStore/asset/prop/vhs/SM_VHS_NewRelease-Sticker.SM_VHS_NewRelease-Sticker`
  with a per-instance dynamic material named `NewReleaseSticker` (the game itself makes a DMI here).
  Attached at `RelLoc (0,0,0)` — the mesh geometry is pre-offset to the box corner, so spawning a mesh
  at the cassette's actor transform reproduces that placement.
- **RESERVED sticker** = `StaticMesh /Game/VideoStore/asset/prop/vhs/SM_VHS_Reserved-Sticker_01.SM_VHS_Reserved-Sticker_01`
  with material `MaterialInstanceConstant /Game/VideoStore/asset/prop/vhs/MI_Reserved-Sticker_01.MI_Reserved-Sticker_01`.
  Present (visible) only on cassettes that are reserved/rented → **this is the rented indicator**
  that v2 recon R4 could not find in `BoxData`.

**Conclusions:**

1. The badge's text is **baked into the sticker art** — the box cover is a single material, the badge
   is a discrete mesh+texture. There is **no "DUPLICATE" sticker** in the game. So a literal
   "DUPLICATE" label requires a **custom cooked texture+material → layer-3 asset PAK**. (This is the
   decision driver; see §3.)
2. The art only needs a **texture+material** — no 3D modelling. Because shape is flexible, we can paint
   the label onto a simple flat quad (trivial UVs) rather than UV-matching the game's star mesh.
3. Rented cassettes are detectable by the presence of a visible `SM_VHS_Reserved-Sticker_01`
   component (enables the rented filter without a hidden bool).

---

## 3. Decisions taken in the brainstorm

| Decision | Choice | Rationale |
|---|---|---|
| Label fidelity | **Layer-3 custom "DUPLICATE" sticker** (shape flexible, e.g. a rectangle) | User wants a real badge with the word; text is baked art, so layer-1 can't spell it. |
| Tooling | **No editor yet → tooling setup is Phase 0** | User has no UE5.4 editor / packer installed; none ships with the game. |
| Sequencing | **Straight to layer-3, no layer-1 interim** | The P1 load-spike is an early kill-switch, so risk is contained without throwaway interim work. |
| Rented filter | **In scope for v3** | Cheap (layer-1), the Reserved sticker makes it detectable, and it directly serves the goal (don't flag what you can't sell). |

---

## 4. Architecture

### 4.1 Lua side (low risk — primitives already proven in v2/recon)

- **Spawn:** reuse the v2 R3 recipe — for each sellable duplicate, spawn a `StaticMeshActor` at the
  cassette's transform and `SetMaterial(0, <our custom DUPLICATE material>)`. **Shape is flexible**, so
  default to a simple flat **quad** (`/Engine/BasicShapes/Plane`): trivial 0–1 UVs mean the label
  texture maps directly with no star-mesh UV matching. (Reusing the game's star mesh
  `SM_VHS_NewRelease-Sticker` is an optional aesthetic upgrade, not required.) DMIs **crash** via UE4SS
  (gotcha 10), so the colour/text is fixed by the authored material, applied with a plain `SetMaterial`.
- **Rented detection:** in `scan`, for each cassette, check whether it carries a *visible* component
  whose `.StaticMesh` is `SM_VHS_Reserved-Sticker_01` (read via the `.StaticMesh` property —
  `GetStaticMesh()` is not exposed, gotcha 12). Record `rented = true/false` per copy.
- **Report:** carry `rented` into the per-copy model. Each copy falls in exactly one **bucket**, by
  precedence: **rented** (has a visible Reserved sticker) → **backstock** (at origin `(0,0,0)`) →
  **sellable** (placed, real coords, not rented). Group format gains the breakdown, e.g.
  `"Title" (SKU n) — 3 copies (1 sellable, 1 backstock, 1 rented):`. `report` stays pure-Lua and
  unit-tested.
- **Highlight/label:** label only **sellable** copies (you can only walk to, and only sell, those).
  `clear` adapts the v2 stateless sweep: destroy the tracked spawned actors, then a
  `FindAllOf("StaticMeshActor")` orphan fallback that matches our **unique DUPLICATE material** on
  element 0 (not the mesh). Because that material is our own asset the game never uses, the sweep can't
  catch game actors, and it stays correct whatever quad/mesh we spawn. Prefer the tracked set; use the
  material-match only for hot-reload orphans.
- **Module impact:** `scan` (add rented detection + keep live actor), `report` (rented in model +
  format), `highlight` (spawn quad + custom material instead of outline shell; clear),
  `config` (new keys), `main` (unchanged wiring). All existing modules; no new module strictly
  required, though a small `assets.lua` holding the verbatim asset paths is optional tidiness.

### 4.2 Asset side (the new, uncertain part)

- Author `T_VHS_Duplicate` (texture) + `MI_Duplicate-Sticker` (material) for a **flat quad** — a simple
  rectangular "DUPLICATE" label on a 0–1 UV plane, so no star-UV matching is needed. Distinct, readable
  look (e.g. bold red); exact art settled in P2. (A star-shaped variant matching NEW is an optional
  upgrade, not in the baseline.)
- Cook for Windows and pack into `Content/Paks/~mods/RRDupeSticker_P.pak` (the `_P` suffix gives load
  priority; this is the same install path the game's existing `~mods` asset PAKs use).
- The asset is **additive** (a brand-new asset, not an override of a base asset) so it must be
  *loadable at runtime* from the mod pak — see Risk R1.

### 4.3 Config additions

```lua
StickerEnabled = true,   -- v3 layer-3 DUPLICATE sticker (supersedes the v2 outline shell)
KeepOutlineShell = false,-- also spawn the v2 outline shell (for across-the-room spotting)
ExcludeRented = true,    -- don't label rented copies; report them separately
```

Existing keys retained: `ScanKey`, `Modifiers`, `MinCopies`, `ClearKey`, `Debug`, `HighlightEnabled`
(master on/off for any in-world marking). `TintColor` stays informational (colour is fixed by the
authored material).

---

## 5. Risks & mitigations

- **R1 — custom-pak asset loading (make-or-break).** UE4SS [#1101] reports `LoadAsset` failing for
  brand-new assets in a custom pak (works for base-pak assets). **Mitigation:** Phase 1 is a load
  spike that *proves* a trivial custom texture loads + renders before any real art is made. Secondary
  mitigations if it fails: (a) the `IoStoreLoaderMod` C++ approach to mount the pak into the asset
  registry; (b) the **fallback** in §6.
- **R2 — UE5.4 IoStore format.** UE5.4 Shipping uses IoStore (`.utoc/.ucas`); yet the game honours
  loose `.pak` overrides (existing `RRMT_FlyerReSkin_P.pak` works). Whether *additive* assets need
  `.utoc/.ucas` vs `.pak` is part of the P1 spike.
- **R3 — UV/texture matching (largely retired).** With a flat quad (`/Engine/BasicShapes/Plane`,
  trivial 0–1 UVs) the label texture maps directly, so no star-UV matching is needed. Only relevant if
  we later opt for the star mesh as an aesthetic upgrade.
- **R4 — clear-sweep ownership.** The orphan fallback matches our **unique DUPLICATE material** (our
  own asset, never used by the game), so it can't catch game actors — robust regardless of the spawned
  shape (see §4.1).
- **R5 — rented proxy.** Using the Reserved-sticker *component* as the rented signal is a visual
  proxy; if a cleaner bool exists it's a P4 nicety, not a blocker.

[#1101]: https://github.com/UE4SS-RE/RE-UE4SS/issues/1101

---

## 6. Fallback (if the P1 spike fails)

Ship **layer-1 in-world "DUPLICATE" text**: spawn/attach a `TextRenderComponent`-style 3D text reading
"DUPLICATE" stamped flat on the box (reusing the game's own text-render tech, font material
`MI_Font_EBGaramond` or similar), styled to read as a label. No tooling, lesser look, still ships the
feature and the rented filter. This is a documented downgrade, decided only if R1 is unsolvable.

---

## 7. Phased plan (detail belongs in the implementation plan)

- **P0 — Tooling setup:** install UE5.4 editor (Epic Launcher) + an unpacker/packer (UnrealPak or
  repak); stand up a minimal UE5.4 content project that can cook+pack a `_P.pak`. Optionally extract
  the NEW sticker texture as a *style* reference. Look for a lighter community shortcut (Nexus tools)
  but don't depend on one.
- **P1 — Load spike 🚦 RISK GATE:** pack a trivial custom texture+material; prove UE4SS `LoadAsset` +
  `SetMaterial` renders it on a spawned `StaticMeshActor` (a plain quad) in-game. Pass → continue;
  fail → §6 fallback.
- **P2 — Author art:** the real DUPLICATE label texture+material (rectangular quad, distinct colour),
  cook, pack.
- **P3 — Lua integration:** `highlight` spawns the quad sticker on sellable dupes; `clear`;
  config toggles; supersede the outline shell (config can keep it).
- **P4 — Rented filter:** `scan` records rented per copy; `report` breaks down sellable/backstock/rented;
  labels skip rented. (Optional: hunt for a cleaner rented bool than the sticker-component proxy.)
- **P5 — Polish, tests, docs (CLAUDE.md + README), commit.**

P4's Lua-only pieces (rented detection, report breakdown) are independent of the asset pipeline and
could land even while P0–P2 tooling is in flight.

---

## 8. Out of scope (→ v4)

Arbitrary highlight colour at runtime (still blocked by the DMI crash, gotcha 10); central inventory
array as a cleaner SKU↔title source; nearest-duplicate pointer; on-screen UMG list; investigating
`AC_Border_C` as a native outline system; a star-shaped sticker variant matching NEW.

---

## 9. Testing

- `report` stays pure-Lua, unit-tested in `tests/report_test.lua`; add v3 cases for the
  sellable/backstock/rented breakdown and the rented-exclusion in labeling.
- Asset/Lua-in-game behaviour is verified the established way: hot-reload, trigger scan, read
  `UE4SS.log` for `[RR-Dupe]` lines; the P1 spike has its own in-game pass/fail check.
