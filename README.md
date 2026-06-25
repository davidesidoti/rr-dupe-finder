# rr-dupe-finder

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod for **Retro Rewind: Video Store Simulator** that finds and locates duplicate movies in your store, so you can sell the extras and keep a clean, unique collection.

The in-game computer only tells you how many copies of one SKU you own at a time, and only if you type the code in by hand. This mod scans your whole store at once and tells you exactly what is duplicated and where each copy is.

> **Game:** Retro Rewind: Video Store Simulator (Unreal Engine 5.4)
> **Framework:** UE4SS v3.0.1

---

## Features

- Scans every cassette in the store with a single keypress.
- Groups them by SKU and flags anything you own 2 or more of.
- Shows the **movie title** of each duplicated cassette (falls back to the raw SKU if a title can't be read).
- **Marks only the *extra* copies to sell** — a downward **arrow** hovers over each pile of duplicates (and/or an outline on each box; configurable via `MarkerStyle`), leaving one copy of each movie unmarked as your keeper, so you can sell everything marked and still keep a complete, unique collection. Backstock and rented copies are listed but never marked.
- **One marker per pile** (nearby copies are grouped), plus a hotkey (**F7**) to clear all markers.
- Breaks every duplicated movie into **sellable / backstock / rented** so you know exactly what you can move.
- Reports the world coordinates of every sellable copy so you can track them down.
- Tells you how many extra copies you could sell in total (rented copies excluded — you can't sell those).
- Read-only: never touches or modifies your save data.

## Roadmap

- [x] Show movie titles instead of raw SKU numbers.
- [x] Highlight duplicate cassettes in-world — a downward **arrow** over each pile (and/or a box outline), one marker per shelf.
- [x] Exclude cassettes currently rented out by customers (you can't sell those).
- [x] Config file: copy threshold, marker style, and a clear keybind (**F7**).
- [ ] On-screen list with direction and distance to each duplicate.

---

## Requirements

- **UE4SS v3.0.1** must be installed first. Follow the install instructions on the [UE4SS Nexus page](https://www.nexusmods.com/retrorewindvideostoresimulator/mods/52).

## Installation

1. Make sure UE4SS is installed and working.
2. Copy the `RR Dupe Finder` folder into your mods directory:
   ```
   <SteamLibrary>\steamapps\common\RetroRewind\RetroRewind\Binaries\Win64\ue4ss\Mods\
   ```
   The folder must contain an empty `enabled.txt` and a `Scripts\main.lua`.
3. Launch the game and load your save.

## Usage

1. Load a save with your store stocked.
2. Press **F6** to scan. Each *extra* duplicate is marked in-world — by default a downward **arrow** hovers over each pile of duplicates, leaving one copy of each movie unmarked as your keeper, so you can sell everything marked and keep a complete, unique collection. Press **F6** again to refresh, or **F7** (or `rrdupe clear` in the UE4SS console) to remove all markers.
3. Read the report.

The report lists each duplicated movie by title (or its SKU if the title can't be read), its copy count, a breakdown of how many copies are sellable / in backstock / currently rented out, and the world coordinates of every sellable copy — with one copy of each marked `<- KEEP this one` (your keeper) and the rest being the extras to sell. It finishes with a total of how many extra copies you can sell (rented copies excluded). You can also trigger a scan by typing `rrdupe` in the UE4SS console.

### Configuration

Options live in `RR Dupe Finder\Scripts\config.lua`:
- `MarkerStyle` — `"both"` (default), `"outline"` (box only), or `"beacon"` (arrow only).
- `MinCopies` — how many copies counts as a duplicate (default 2).
- `ScanKey` / `ClearKey` — scan (**F6**) and clear (**F7**) keys.
- `BeaconScale` / `BeaconZOffset` / `BeaconClusterRadius` — arrow size, hover height, and how aggressively nearby copies merge into one marker.

### Seeing the output

All output is written to the UE4SS log at:
```
...\Binaries\Win64\ue4ss\UE4SS.log
```

To read the report live in-game instead, enable the console overlay in `UE4SS-settings.ini`:
```ini
[Debug]
GuiConsoleEnabled = 1
```

---

## How it works

Each movie cassette is the Blueprint actor `Cartridge_Base_C`, with its SKU and title stored in a nested Blueprint struct. The mod uses UE4SS's `FindAllOf` to grab every loaded cassette, reads each SKU and movie title, groups them, and reports any SKU that appears more than once along with each actor's location. For duplicates physically placed on a shelf, it spawns a downward **arrow** above each pile (nearby copies are grouped into one marker) and/or a bright outline over each box — your choice via `MarkerStyle` — so you can find them at a glance.

Detection covers every cassette currently loaded in the level. Copies still in the store but reserved for a customer are detected (via their in-game Reserved sticker) and flagged as **rented**, so they're listed for reference but never highlighted or counted toward your sellable total — you can't sell those.

---

## Compatibility

- Does not modify save data.
- Pure read-and-report; does not change game systems.
- Should not conflict with other UE4SS Lua mods.

## Development

See [`CLAUDE.md`](./CLAUDE.md) for the full technical context: the game's data model, the UE4SS API surface used, known gotchas, and the dev/test loop.

## Credits

- **UE4SS-RE** for the scripting framework.
- The **SKU QoL** mod, which the cassette SKU read path was derived from.
- The **LineTraceMod** reference for UE4SS camera and Kismet library usage.

## License

MIT. See [`LICENSE`](./LICENSE). (Swap this out if you prefer something else.)
