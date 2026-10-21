# Developer API

Signal Smoke is a library: your mod can place colored smoke, flares and chemlight glows that every player sees, restored after loading, and listen to signals started by players or by other mods. Full contract (French): [specifications-techniques.md](../../specifications-techniques.md#api-publique-lua).

## Setup

```
# mod.info of your mod
require=\batman_SignalSmoke
```

```lua
local SignalSmoke = require "SignalSmoke/SignalSmoke"
```

The module is a `shared` file, so it is available whatever the mod order. **Writes and events work only on the authority** (dedicated server, host, or singleplayer: `not isClient()`). Reads work everywhere.

## Start and stop a signal

```lua
local id, err = SignalSmoke.start{
    x = 100, y = 200, z = 0,        -- integers, x and y required
    color = "green",                -- name from SignalSmoke.COLORS or { r = 0.2, g = 0.8, b = 1 }
    kind = "smoke",                 -- "smoke" (default), "flare" or "chemlight"
    minutes = 30,                   -- game minutes (default 30); or realSeconds = 90; or untilH = <world hours>
    radius = 1,                     -- smoke tiles, 0 to 2 (1 = cross of 5 tiles)
    light = true,                   -- smoke: at night only; flare and chemlight: always
    id = "mymod:zone1",             -- optional; the same id replaces the entry
    owner = "MyMod",                -- optional, to recognize your entries
}
if not id then print("[MyMod] Signal Smoke refused: " .. tostring(err)) end

SignalSmoke.stop(id)                -- true if it existed
```

| Function | Side | Returns |
|---|---|---|
| `start(opts)` | authority | id, or `nil, "server only"` on an MP client, or `nil, message` for invalid options |
| `stop(id, reason)` | authority | `true` / `false`; `nil, "server only"` on an MP client |
| `isActive(id)` | anywhere | `true` while the entry exists and has not run out |
| `list()` | anywhere | `{ [id] = entry }` of active entries (read only) |
| `onSignal(fn)` / `removeSignalListener(fn)` | authority | `true` if added / removed |

Other options of `start`: `lightRadius` (1–20), `smoke = false`, `sound` (looped sound name, heard within 40 tiles), `itemId` (a placed item to follow: the signal stops if it is picked up, and the item is removed at the end), `spentType` (item type placed instead at the end), `source`, `player` (`IsoPlayer`) or `username`.

Colors: `green`, `red`, `yellow`, `purple`, `orange`, `blue`, `white`.

On an MP client, `list()` and `isActive()` read the copy received from the server: empty until it arrives after joining.

## Listen to signals

```lua
local function onSignal(event)
    -- event.type: "started", "stopped" or "expired"
    -- event.id, event.entry (read only), event.source ("grenade", "flare", "chemlight", "script"...)
    -- event.username: account of the player at the origin, when known (singleplayer: character name)
    -- event.player: IsoPlayer, "started" only, when known
    -- event.reason: "stopped" only ("script", "pickedUp"); event.replaced: "started" only
end
SignalSmoke.onSignal(onSignal)
```

Register the listener when a `shared` or `server` file loads. Each listener runs in its own `pcall`: an error is logged and does not stop the others. A dud improvised bomb starts no signal. The username is kept in server memory only: it is unknown for signals started before the last load.

To find the color name of a signal, use `SignalSmoke.colorNameOf(event.entry)` (API 3): it returns `entry.colorName` (set when the color was given by name) or the nearest name of `SignalSmoke.COLORS`. Check `(SignalSmoke.API_VERSION or 1) >= 3` before using it.

To place a lit road flare from a script (server or singleplayer), call `SignalSmoke.placeFlare{ x = 100, y = 200, z = 0, color = "green", minutes = 20, id = "mymod:flare", owner = "MyMod" }` (API 3): it puts a lit flare on the loaded tile, protects it from ground clean-up and registers it; it returns `id, item` or `nil, error`. A picked-up flare keeps burning down without light and relights when placed back.

`SignalSmoke.API_VERSION`: 1 (0.1.0), 2 (events and chemlights, 0.2.0), 3 (`colorName`, `colorNameOf`, `placeFlare`). Missing means 1 or 2: test the functions you need.

## Tips

- Use your own `id` and refresh the signal before it ends (compare `list()[id].untilH` with `getGameTime():getWorldAgeHours()`), rather than starting a new one each time.
- Keep smoke durations in minutes rather than hours: smoke is a local object of each client.
- Replacing an entry with the same `id` does not remove the item followed by the old entry.
