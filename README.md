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
- **Highlights every placed duplicate in-world** with a bright outline so you can spot it on the shelf; backstock copies (not physically placed) are listed but not highlighted.
- Reports the world coordinates of every placed copy so you can track them down.
- Tells you how many extra copies you could sell in total.
- Read-only: never touches or modifies your save data.

## Roadmap

- [x] Show movie titles instead of raw SKU numbers.
- [x] Highlight duplicate cassettes in-world (outline shell) so you can spot them at a glance.
- [ ] On-screen list with direction and distance to each duplicate.
- [ ] Config file: minimum copy threshold, highlight color, custom keybind.
- [ ] Optional filter to exclude cassettes currently rented out by customers.

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
2. Press **F6** to scan. Every placed duplicate is highlighted in-world with a bright outline; press **F6** again to refresh, or type `rrdupe clear` in the UE4SS console to remove the highlights.
3. Read the report.

The report lists each duplicated movie by title (or its SKU if the title can't be read), its copy count, how many copies are placed on shelves versus held in backstock, and the world coordinates of every placed copy — followed by a total of how many extra copies you can sell. You can also trigger a scan by typing `rrdupe` in the UE4SS console.

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

Each movie cassette is the Blueprint actor `Cartridge_Base_C`, with its SKU and title stored in a nested Blueprint struct. The mod uses UE4SS's `FindAllOf` to grab every loaded cassette, reads each SKU and movie title, groups them, and reports any SKU that appears more than once along with each actor's location. For duplicates that are physically placed on a shelf, it spawns a bright outline shell over the cassette so you can find it at a glance.

Detection covers every cassette currently loaded in the level. A copy that is off the premises (for example, rented out by a customer) will not appear, which is intended since you cannot sell those anyway.

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
