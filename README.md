# Untitled Brewing Game

A browser puzzle game for **GitHub Game Off 2026** (theme: **SHIFT**), made in Godot 4.7.

You run a brewing shop. Add Ingredients to a Brew to move its 3 Parameters through looping States, use the Shifter to switch an Ingredient into its Shifted Form, and serve Clients' Requests for Gold Coins. The game is played with the mouse and a playthrough takes about 10 minutes.

## Requirements

- Godot **4.7** (standard build, not .NET). The project uses the GL Compatibility renderer, which the web export requires.
- Godot **Web export templates**, for exporting only (Editor → Manage Export Templates).
- Python 3, for the data export tool and to serve the web build locally.

## Folder layout

```
scenes/          .tscn files. main.tscn is the main scene; ui/ holds reusable UI pieces
scripts/
  logic/         Pure game rules: RefCounted classes with no Node dependencies, testable headless
  ui/            Views: they listen to signals from logic/ and call its methods, and hold no rules
data/            JSON generated from the Data Sheet by tools/export_data.py. Do not edit by hand
assets/
  art/           Images, named exactly as in the Asset List (ing_01.png, ing_01_shifted.png, …)
  audio/         Music (.ogg) and sound effects (.wav), named exactly as in the Asset List
tests/           Headless test scripts (extend SceneTree, exit with code 1 on failure)
tools/           Scripts that run outside Godot, such as export_data.py
build/           Export output. Git-ignored, and hidden from Godot by build/.gdignore
```

Empty folders hold a `.gitkeep` so Git tracks them. Delete it once the folder has real files.

## Naming convention

- snake_case for files and folders
- PascalCase with class_name for classes
- IDs that match data sheet and Asset List exactly 
- script's file name match its class 
- a script and its scene share a name
- test_ prefix for test files
- commit .uid files and move or rename scripts and scenes only in the editor
- any art or audio file that isn't in Asset List yet gets added to the Asset List first, so it stays the only place that defines names

## Running

Open the project in Godot and press **F5**, or from a terminal:

```bash
godot --path .
```

`godot` stands for the Godot executable. On macOS it is inside the app bundle, e.g. `/Applications/Godot.app/Contents/MacOS/Godot`.

## Testing

Each test is a script in `tests/` that runs headless and prints PASS or FAIL:

```bash
godot --headless --path . -s tests/test_effects.gd
```

A non-zero exit code means at least one check failed.

## Updating game data

All values (Ingredient effects, supply, Requests, Characters, Parameters) live in the design team's Data Sheet, not in code. After the sheet changes, regenerate `data/`:

```bash
python3 -I tools/export_data.py
```

## Web export

1. Make sure `build/.gdignore` exists. `build/` is git-ignored, so a fresh clone does not have it, and without it the editor imports the exported files:

   ```bash
   mkdir -p build && touch build/.gdignore
   ```

2. Export with the "Web" preset (threads off; output goes to `build/web/`):

   ```bash
   godot --headless --path . --export-release "Web" build/web/index.html
   ```

3. Serve it locally and open http://localhost:8000:

   ```bash
   python3 -m http.server 8000 -d build/web
   ```

   Opening `index.html` straight from disk does not work: browsers block the WebAssembly load on `file://` URLs.
