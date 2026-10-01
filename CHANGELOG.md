# Changelog

## 0.2.0 — 2026-10-01

### New
- **Chemlights** in four colors (green, red, blue, yellow): right-click, **Activate and place on the ground**. A small colored glow with no smoke and no sound, for 8 hours of game time. Pick it up and drop it elsewhere: it keeps glowing until it runs out, then becomes a used chemlight. Found in army storage and surplus stores, police and fire lockers, camping and survival gear.
- **Improvised smoke bombs**: recipe **Make Improvised Smoke Bomb** (Cooking 2), with an empty can, sugar, a cold pack or fertilizer, paint in the color you want (green, red, yellow or purple) and a fuse (twine or a fabric strip). Shorter smoke than a grenade, and 1 in 5 is a dud.
- **Sandbox options**: grenade smoke, road flare and chemlight durations, improvised smoke duration and dud chance, loot multiplier, road flares in police car trunks.
- Road flares can now be found in police car trunks.

### For modders
- **Events**: `SignalSmoke.onSignal(fn)` and `SignalSmoke.removeSignalListener(fn)`. Your function is called on the server (or in singleplayer) when a grenade, flare, chemlight or script signal starts, stops or expires, with its type, id, registry entry, source and the player's username when known. Each listener is isolated: an error in one is logged and doesn't stop the others.
- `SignalSmoke.start{ kind = "chemlight", ... }` places a chemlight glow by script. The existing API is unchanged.

## 0.1.0 — 2026-09-30

First release on the Steam Workshop (Build 42.21).

### Added
- Four colored smoke grenades (green, red, yellow, purple): thrown like the vanilla smoke bomb, colored smoke for about a minute and a half, glowing in its color at night. Zombies in the smoke lose sight of their target. No grey smoke, no fire, no damage.
- Road flares: right-click, **Light and place on the ground**; red flickering light, a little red smoke and a crackling sound for about one in-game hour. Pick it up to put it out.
- Loot: grenades in army storage, army surplus and police lockers; flares in gas station emergency supplies, car supply tools, fire department and police lockers.
- Multiplayer: the server keeps active smokes and flares and sends them to every client, including late joiners; they are restored after loading a save.
- Library for other mods: `SignalSmoke.start{...}` and `SignalSmoke.stop(id)` place colored smoke or flares by script (server or singleplayer).
- Original 3D models, textures and icons, poster and mod icon.
- Translations: English, French, German, Spanish, Portuguese, Brazilian Portuguese, Russian, Simplified Chinese, Japanese and Korean.
