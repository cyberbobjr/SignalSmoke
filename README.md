# Signal Smoke (batman_SignalSmoke)

Project Zomboid Build 42.21 mod: colored smoke grenades, road flares, and a small library for other mods (colored smoke and flares placed by the server, seen by every player, restored after loading).

- Steam Workshop: [3811010882](https://steamcommunity.com/sharedfiles/filedetails/?id=3811010882) — Mod ID `batman_SignalSmoke`.
- Mod: `Contents/mods/batman_SignalSmoke` (`42.21/mod.info`).
- Workshop descriptions: `README.steam` (English, mirrored in `workshop.txt`) and `README.steam.<lang>`.
- Changes: [CHANGELOG.md](CHANGELOG.md). Design and research notes (French): `docs/`.
- 3D models and icons: `source/items/build_items.py` (headless Blender recipe).

## Using the library

Add `require=\batman_SignalSmoke` to your `mod.info`, then on the server or in singleplayer:

```lua
local SignalSmoke = require "SignalSmoke/SignalSmoke"
local id = SignalSmoke.start{ x = 100, y = 200, z = 0, color = "green", minutes = 30 }
SignalSmoke.stop(id)
```

Options and registry format: header of `Contents/mods/batman_SignalSmoke/42.21/media/lua/shared/SignalSmoke/SignalSmoke.lua`.

## Checks

```
python tests/run_tests.py
```

Pure Lua tests (lupa), translation keys, Steam descriptions (size, BBCode, links) and luacheck.

## License

MIT, see [LICENSE](LICENSE).
