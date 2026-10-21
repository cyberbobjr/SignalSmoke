# Multiplayer

- Every player nearby sees the smoke and the glows and hears the sounds, including players who join while a signal is active.
- The server decides everything: durations, duds, when a flare is picked up, when a chemlight runs out.
- The list of active signals sent to players does not say who threw or placed each one (since 0.2.3).
- Split screen: sounds play when any local player is close; chemlights are found around every local player.
- Signals survive a server restart. Far from every player (area not loaded), nothing is drawn, but signals keep running and end on time.

## For server admins

- Add `batman_SignalSmoke` to `Mods=` and `3811010882` to `WorkshopItems=`.
- No admin command, no file to configure: only the [sandbox options](04-sandbox-options.md).
- Each client draws at most 40 smoke tiles of the mod at once, to leave room for real fires (the game has a cap of 75 fires and smokes).
