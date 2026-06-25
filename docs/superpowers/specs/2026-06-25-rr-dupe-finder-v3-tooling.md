# rr-dupe-finder — v3 tooling recon (Session 2)

**Date:** 2026-06-25

Track B's "author → cook → pack → install" pipeline for the layer-3 DUPLICATE sticker. This note is
the contract between the asset pak and `highlight.lua`. Two halves: **Confirmed** (verifiable without
the editor) and **Pending** (gated on the UE 5.4 install in flight).

---

## Confirmed (no editor needed)

- **Pak format honoured by RR:** legacy **`.pak`**, **Zlib**-compressed, `.uasset`/`.uexp`/`.ubulk`
  triplets, **unencrypted** (UnrealPak `-List` read `RRMT_FlyerReSkin_P.pak` with no `-cryptokeys`).
  **Not** IoStore `.utoc/.ucas`. → **Risk R2 resolved: ship an additive loose `_P.pak`.**
- **Mount convention (the key finding):** the reskin pak mounts at **`"../../../"`** and its entries
  begin **`RetroRewind/Content/...`**. The game project is therefore named **`RetroRewind`** (that's
  why `/Game/` → `RetroRewind/Content/`). **So the UE 5.4 modding project must ALSO be named
  `RetroRewind`** — then the cooked tree lands at `…/Cooked/Windows/RetroRewind/Content/RRDupe/…` and
  packs to the correct in-pak path with no path surgery.
  - Example existing entry:
    `RetroRewind/Content/L10N/de/VideoStore/asset/textures/T_Flyer_A_01/T_Flyer_A_01_bc.uasset`
- **Packer:** **`UnrealPak.exe`** ships inside the engine
  (`Engine\Binaries\Win64\UnrealPak.exe`). No `repak`/Rust install needed. (repak remains a fallback.)
- **Inspector:** UnrealPak `-List` covers our needs (mount point + entry paths). FModel not required
  for S2; install later only if deep asset browsing is wanted.
- **Image tooling:** Python **PIL 12.2** present → test + real label art generated programmatically
  (`gen_test_png.py`), no external image editor.
- **Engine version trap (recorded):** only **UE 5.7.4** was installed (`C:\Program Files\Epic
  Games\UE_5.7`, `D:\Epic Games\UE_5.7`). It is **NOT usable** — a UE 5.4 Shipping runtime refuses
  packages cooked by a newer engine (cooked-package version > runtime). Cooking the sticker requires
  **UE 5.4.x** to match the game (CLAUDE.md §2). Installing 5.4.4 via the Epic Launcher.

## Runtime asset-path convention (the Lua contract — locked)

| Asset | Runtime path (StaticFindObject / LoadAsset form) |
|---|---|
| Real material (S4/S5) | `/Game/RRDupe/MI_Duplicate-Sticker.MI_Duplicate-Sticker` |
| Real texture (S4) | `/Game/RRDupe/T_VHS_Duplicate.T_VHS_Duplicate` |
| **Test** material (S2/S3) | `/Game/RRDupe/M_RRDupe_Test.M_RRDupe_Test` |
| **Test** texture (S2/S3) | `/Game/RRDupe/T_RRDupe_Test.T_RRDupe_Test` |

In-pak path for any of them: `RetroRewind/Content/RRDupe/<Name>.uasset` (+ `.uexp`/`.ubulk`).

## Project + pipeline artifacts (outside the repo)

| Artifact | Location |
|---|---|
| Modding project (named `RetroRewind`) | `D:\RRModKit\RetroRewind\RetroRewind.uproject` |
| Test texture (PNG, ready to import) | `D:\RRModKit\T_RRDupe_Test.png` (256² RGBA, "RR DUPE TEST") |
| PNG generator | `D:\RRModKit\gen_test_png.py` |
| Headless asset builder (UE Python) | `D:\RRModKit\make_assets.py` |
| Pipeline driver (scaffold→cook→pack) | `D:\RRModKit\build_test_pak.ps1` |
| Test pak output | `…\RetroRewind\Content\Paks\~mods\RRDupeTest_P.pak` |

## Staged pipeline commands (auto-detect the 5.4 engine; run after install)

```powershell
# one-shot: scaffold the RetroRewind project, import asset, cook Windows, pack RRDupeTest_P.pak into ~mods
powershell -ExecutionPolicy Bypass -File D:\RRModKit\build_test_pak.ps1
# (Session 4 builds the real pak with the same driver:  -Sticker)
```

Internals the driver runs (engine = the detected `UE_5.4` root):

```text
# 1. import + build the Unlit emissive material from the PNG
UnrealEditor-Cmd.exe <proj> -run=pythonscript -script=D:\RRModKit\make_assets.py -unattended -nosplash -nopause -stdout
# 2. cook for Windows (DefaultGame.ini forces +DirectoriesToAlwaysCook=/Game/RRDupe)
UnrealEditor-Cmd.exe <proj> -run=Cook -targetplatform=Windows -unattended -nosplash -nopause -stdout
# 3. pack additive _P.pak; response lines reproduce mount "../../../" + RetroRewind/Content/... entries
UnrealPak.exe <~mods>\RRDupeTest_P.pak -create=D:\RRModKit\pak_response.txt -compress
```

---

## Confirmed (post-install — pipeline proven end-to-end 2026-06-25)

- **Editor:** UE **5.4.4** at `D:\Epic Games\UE_5.4` (UnrealEditor-Cmd + UnrealPak + PythonScriptPlugin
  all present). Launcher-managed.
- **`build_test_pak.ps1` ran clean (exit 0):** import (UE-Python, first try) → cook (**5 files, no engine
  bloat**) → pack. **`RRDupeTest_P.pak` (12.1 KB) installed in `~mods`.** make_assets.py material API was
  correct on the first run.
- **Working pack command (UnrealPak — repak NOT needed):**
  `UnrealPak.exe <out>.pak -create=<response.txt> -compress`, each response line
  `"<cooked disk path>" "../../../RetroRewind/Content/RRDupe/<file>"`.
- **Mount-point gotcha + resolution:** UnrealPak `-create` collapses the common dir, so the pak's entries
  are **bare filenames** under mount `../../../RetroRewind/Content/RRDupe/` (no "mount point" banner in
  `-List`, unlike FlyerReSkin's shallow `../../../`). **Proven equivalent** via
  `UnrealPak <pak> -Extract <dir> -extracttomountpoint` → reconstructs
  `RetroRewind/Content/RRDupe/{M_RRDupe_Test,T_RRDupe_Test}.uasset`, i.e. mount+entry rebuilds the exact
  path the engine asks for (`/Game/RRDupe/...`). So the deep mount loads identically to a shallow one.
  (repak, the plan's alt packer, was blocked by the download policy and proved unnecessary.)
- **Cook detail:** content-only project **named `RetroRewind`**; `DefaultGame.ini`
  `+DirectoriesToAlwaysCook=(Path="/Game/RRDupe")` forces the map-unreferenced assets to cook.
- **Note for S4:** the editor + game on this machine were **5.7** until now; cooking the real sticker must
  use this 5.4.4 — rerun the same driver with `-Sticker` (builds `RRDupeSticker_P.pak`).

## Load spike (R1 / #1101) — Session 3 — VERDICT: **FAIL** (additive new-path assets won't load)

**Date:** 2026-06-25. Probe: a throwaway `rrspike` console command running a control-vs-test
`LoadAsset` + `StaticFindObject` sweep, then a spawn. `RRDupeTest_P.pak` mounted via cold restart.

**Decisive control-vs-test table (read from `UE4SS.log`):**

| Path | before | LoadAsset | after | meaning |
|---|---|---|---|---|
| `/Engine/BasicShapes/Cone.Cone` (engine) | false | ok | **true** | LoadAsset itself works |
| base `/Game/VideoStore/.../LA_VHS_Box_Outline_01` | true | ok | **true** | base-pak `/Game/` resolves |
| `/Game/RRDupe/M_RRDupe_Test` (our material) | false | ok | **false** | additive new path NOT found |
| `/Game/RRDupe/T_RRDupe_Test` (our texture) | false | ok | **false** | additive new path NOT found |

`LoadAsset` returns **without error** on the RRDupe paths yet the object never enters memory, and **no**
engine-side "failed to find package" line is logged — the classic `DoesPackageExist == false` silent
no-op. The base outline shell spawned fine on a cassette; no quad — exactly as predicted.

**Root cause (investigated, not guessed):**
- **Not the pak format.** Base game is a single loose `RetroRewind-Windows.pak`; **no IoStore**
  (`.utoc/.ucas`) anywhere under `Content\Paks`. The plan's "retry as IoStore" mitigation is **moot**.
- **Not the mount-point collapse.** Our pak stores bare entries under a deep mount
  (`../../../RetroRewind/Content/RRDupe/`), but so does the **working** `BlackMarketEveryDay_2301_P.pak`
  (`asset/outside/WeatherSystem.uasset` … under `../../../RetroRewind/Content/`). Deep mounts resolve fine.
- **Not the `LoadAsset` arg form.** Full `Package.Object`, the same form the stock `summon` command
  (`ConsoleCommandsMod/summon_unloaded_assets.lua` → `LoadAsset(Parameters[1])`) uses; controls prove it.
- **The wall is additive vs override.** Every working `~mods` pak here is an **override** of a path that
  already exists in the cooked base registry (FlyerReSkin → L10N textures; BlackMarketEveryDay →
  WeatherSystem/Market/Core_Gamemode). Ours is the only **additive** pak (a brand-new `/Game/RRDupe/`
  path in no registry). The engine won't resolve a package path it never cooked, even from a correctly
  mounted pak. = UE4SS #1101 / Spec R1.

**Mitigations:** IoStore repack → N/A (no IoStore on this title). Shallow-mount repack → not attempted
(BlackMarketEveryDay proves deep mounts load; it would not touch additive resolution). A cooked
AssetRegistry shipped in the pak might register the new path, but that is deep, uncertain Track-B tooling.

**Branch decision (plan S3 → FAIL):** Track B's custom-pak DUPLICATE **texture** sticker (Sessions 4–5)
is **not viable** on this title. Take the **Fallback appendix** — render the label as in-world **3D text**
(`TextRenderComponent` "DUPLICATE"), no custom pak. Track A (rented filter + report buckets, S1) already
shipped and is unaffected; the v2 **outline shell** highlight also still works (F6 outlined 57 placed dupes
in this test) and stays as the across-the-room marker.
