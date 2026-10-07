# Signal Smoke (batman_SignalSmoke)

Project Zomboid Build 42.21 mod: colored smoke grenades, road flares, chemlights, improvised smoke bombs, sandbox options, and a small library for other mods (colored smoke, flares and chemlight glows placed by the server, seen by every player, restored after loading, with events for dependent mods).

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

`kind = "chemlight"` places a small colored light with no smoke and no sound (`lightRadius` 1 to 20).

### Events

Listen to signals on the server or in singleplayer (a listener added on a multiplayer client is never called):

```lua
local function onSignal(event)
    -- event.type: "started", "stopped" or "expired"
    -- event.id, event.entry (registry entry, read-only), event.source ("grenade", "flare", "chemlight", "script")
    -- event.username: account of the player who threw or placed it, when known (singleplayer: character name).
    --   Kept on the server only, never in the registry sent to clients: unknown for signals started before the last load.
    -- event.player: IsoPlayer, "started" only, when known
    -- event.reason: "stopped" only, "script" or "pickedUp"; event.replaced: "started" replaced an entry with the same id
end
SignalSmoke.onSignal(onSignal)               -- true if added (no duplicates)
SignalSmoke.removeSignalListener(onSignal)   -- true if removed
```

Register the listener when a server-side file loads (`shared` or `server`). Each listener runs in its own `pcall`: an error is written to the log and does not stop the other listeners. A homemade smoke bomb that fizzles starts no signal.

`SignalSmoke.start{ ..., source = "mymod", player = player }` passes a source and a player to the listeners; `SignalSmoke.stop(id, reason)` passes a reason.

Options, registry format and events: header of `Contents/mods/batman_SignalSmoke/42.21/media/lua/shared/SignalSmoke/SignalSmoke.lua`.

## Checks

```
python tests/run_tests.py
```

Pure Lua tests (lupa), translation keys, Steam descriptions (size, BBCode, links) and luacheck.

## License

MIT, see [LICENSE](LICENSE).
