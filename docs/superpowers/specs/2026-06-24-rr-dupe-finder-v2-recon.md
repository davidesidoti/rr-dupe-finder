# rr-dupe-finder — v2 recon findings
**Date:** 2026-06-25 (Session 1 of the v2 plan)

All four facts were resolved via a temporary probe in `main.lua` (now removed) driven by `rr*`
UE4SS console commands. The UE4SS **GUI / Live View never spawned** on this install
(`GuiConsoleEnabled = 1` but `GraphicsAPI = opengl` produced no window), so R1 was obtained by
**UE4SS Lua reflection** (`UStruct:ForEachProperty` + `StructProperty:GetStruct`) rather than
Live View.

---

## R1 — Title field
- **Key (verbatim):** `ProductName_14_055828B1436E5AD27BFA95AF181099DE`
- **Type:** `FText` (returned to Lua as `userdata`)
- **Stringify:** `value:ToString()` — **not** `tostring(value)` (that yields a userdata address).
  Wrap in `pcall`; treat `""` as nil.
- **Path:** `Product Structure` → `BaseStructure_2_FBB12C464AE570CAFD12ED8506160683`
  → `BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10` → `ProductName_14_…` (sibling of `SKU_26_…`).
- **Cross-checked:** field value is the full movie title (e.g. `"The Bun Ignition Point"`); the
  in-game pickup tooltip shows this same ProductName (e.g. `"JUMBO MANHUNT"`).
- **Other `BoxData` siblings (reference):** `SubjectName_15_349EDA35415477D434C88AAB4B5DD9D8`
  (FText, short subject, e.g. `"Bun"`); `SubjectImage_8_…` / `BackgroundImage_10_…` (texture
  names); `Genre_27_…`, `LayoutStyle_24_…`, `LayoutStyleColor_31_…`, `ColorPalette_34_…` (ints);
  `NewToUnlock_38_…` (bool).

## R2 — Mesh component
- **Accessor:** `cart.Mesh` (i.e. `cart["Mesh"]`)
- **UClass:** `StaticMeshComponent`
- **Base material (element 0):** a per-instance `MaterialInstanceDynamic` of
  `/Game/VideoStore/core/shader/VHS/M_VHS_Master-Holographic` (shows as
  `MID_M_VHS_Master-Holographic` under `/Engine/Transient`). The cassette also has a second SMC
  named `ShadowImpostor` — ignore it.
- **Note:** placed cassettes are class `videotape_C` (a subclass of `Cartridge_Base_C`).
  `FindAllOf("Cartridge_Base_C")` returns them; `cart.Mesh` works on all 366.

## R3 — Highlight mechanism  ⚠️ CHANGED FROM THE PLAN'S DEFAULT (`overlay`)
- **Verdict: `marker`** — spawn the game's VHS **outline shell** over each *placed* duplicate.
  - `SetOverlayMaterial` *works* but only as a whole-mesh fill (e.g. solid white with
    `EmissiveMeshMaterial`); the user wanted a coloured **border**.
  - No native post-process outline exists (`SetRenderCustomDepth` produced nothing) and the
    cassette has **no** hidden outline mesh component (only `Mesh` + `ShadowImpostor`).
- **Shell mesh:** `/Game/VideoStore/asset/prop/vhs/LA_VHS_Box_Outline_01.LA_VHS_Box_Outline_01`
- **Material:** `/Game/VideoStore/core/shader/environment/Neon/M_Opaque_Neon_Tintable.M_Opaque_Neon_Tintable`
  — renders a **static amber/gold** outline as a plain `SetMaterial(0, …)`. **User's chosen look.**
- **Scale:** `~1.1` (user preferred slightly larger than the cassette; `1.0` hugs exactly).
- **Colour:** FIXED by the material. `Config.TintColor` is **informational only** in v2.
  An arbitrary colour needs a Dynamic Material Instance, and **`CreateDynamicMaterialInstance`
  HARD-CRASHES the game** through UE4SS here — **do NOT use it.** To offer other colours, swap
  in a different pre-coloured opaque material (static-colour alternatives proven to render:
  `…/Neon/Neon_Offset/MI_Opaque_Neon_Bright` = green, `…/environment/M_Opaque_Emissive` = green,
  `/Engine/EngineMaterials/EmissiveMeshMaterial` = white).

### R3 — proven spawn recipe (use in `highlight.lua`, Session 3)
Libs via `require("UEHelpers")` → `GetWorld()`, `GetGameplayStatics()`, `GetKismetMathLibrary()`.
For each placed-dupe actor `cart`:
```lua
local xform = kml:MakeTransform(cart:K2_GetActorLocation(), cart:K2_GetActorRotation(),
                                { X = 1.1, Y = 1.1, Z = 1.1 })
local a   = gs:BeginDeferredActorSpawnFromClass(world,
              StaticFindObject("/Script/Engine.StaticMeshActor"), xform, 1, nil, 1)  -- 6 in-args
local smc = a.StaticMeshComponent
smc:SetMobility(2)                                    -- Movable (runtime spawn)
smc:SetStaticMesh(StaticFindObject(SHELL_MESH))
gs:FinishSpawningActor(a, xform, 1)                   -- 3 in-args (UE5.4 added scale-method)
smc:SetMaterial(0, StaticFindObject(MAT))            -- AFTER finish (pre-finish set is reset)
pcall(function() smc:SetCollisionEnabled(0) end)     -- NoCollision
-- keep `a` in a table for clear()
```
- `StaticFindObject` needs the full `Package.Object` path (`…/Foo.Foo`), else it throws
  "Name wasn't long".
- Skip backstock: only spawn where the cassette is not at the origin (reuse the
  `(|x|,|y|,|z|) < 0.5` test).

### R3 — clear (hot-reload-proof)
Destroy the tracked spawned set first; then, because a hot-reload/refresh orphans the actors and
loses Lua refs, also sweep: `FindAllOf("StaticMeshActor")` and `K2_DestroyActor()` any whose
`StaticMeshComponent:GetStaticMesh():GetFullName()` contains `LA_VHS_Box_Outline_01`.
**Ownership caveat:** the mesh-match sweep assumes the *game* never places its own
`LA_VHS_Box_Outline_01` `StaticMeshActor`s (held true during recon). Prefer the tracked set;
use mesh-match only as the orphan fallback.

## R4 — Opportunistic (non-blocking)
- **Rented/owned flag:** not in `BoxData` (only the fields under R1). Not chased further. If
  needed later, inspect other props on `videotape_C` / `Cartridge_Base_C`.
- **Inventory array:** not investigated (Live View unavailable; gates nothing in v2).

---

## Tooling notes discovered this session
- **UE4SS GUI / Live View did not spawn** (`GraphicsAPI = opengl`). For struct introspection use
  reflection probes; if Live View is genuinely needed, switch `GraphicsAPI` to `dx11` and restart.
- **`pairs()` cannot iterate a UScriptStruct value** (`table expected, got UScriptStruct`). Use
  `UStruct:ForEachProperty` + `StructProperty:GetStruct()`, walking the class chain via
  `GetSuperStruct()` for inherited properties.
- **`CreateDynamicMaterialInstance` crashes** the process (native) — avoid DMIs in this mod.
- **`FinishSpawningActor` / `BeginDeferredActorSpawnFromClass` need UE5.4 arg counts** (3 / 6
  in-args respectively); a short call throws "UFunction expected N parameters, received M".
