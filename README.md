# Roblox Script Portfolio

Showcasing some of my scripts that I use in my Roblox games.

Connected Discord-GitHub

- Discord: @deno_fresh
- Roblox: @zxcdead_ghoul
- GitHub: @VofSwords

## Lobby

A reusable lobby class ([Lobby/Classes/Lobby.luau](Lobby/Classes/Lobby.luau)) and two services built on it. The lobby collects players along with a consumer-defined payload, seals the roster, and hands it to a game through `OnStart`; it never reads what it carries, so both the per-player and the lobby-level payload types belong to the consumer. Membership and state changes are published as signals (`OnPlayerAdded`, `OnEmpty`, `OnFull`, `OnStart`, `OnCancelled`, `OnDestroyed`). The class is split into a method prototype and per-instance data, each declared as a type before any implementation exists. The prototype is then checked against that declared contract, so drift between the API and the implementation surfaces where the method is written rather than at a call site.

Two services demonstrate different lifecycles:

- **Game1v1** ([Lobby/Services/Game1v1](Lobby/Services/Game1v1)) — lobbies created on demand by players, many running in parallel. Two seats drive membership: sitting down adds a player carrying their seat name, standing up removes them, and filling both seats seals the lobby and starts a timed round. When the round ends, the lobby with its place is destroyed.

- **GameFFA** ([Lobby/Services/GameFFA](Lobby/Services/GameFFA)) — one reusable lobby cycling between lobby and game. A single 16-player lobby sits behind a force field; touching it joins, and the payload is that player's own `Died`/`CharacterRemoving` connections, so the lobby carries each member's cleanup handles. A countdown starts on the first join, and once the "game" is over the lobby is replaced with a fresh one.

Signals from [SignalPlus](https://github.com/AlexanderLindholt/SignalPlus).

[Demo](https://www.roblox.com/games/87170113326381/Lobby-class-demo)

## KeyboardFloor

A single client script ([KeyboardFloor.client.luau](KeyboardFloor.client.luau)) that turns any tagged part into a large interactive keyboard floor. It subdivides the part's surface into spatial chunks that stream in and out around the player, draws key models from a shared object pool, detects presses with collision-group-filtered spatial queries against the character, and animates them with tweens. Per-chunk random seeds keep letters and colors stable across unload/reload. Written in strict-mode typed Luau.

[Demo](https://www.roblox.com/games/100237147546880/Keyboard-Floor-Demo)

## Pure

A collection of utility functions that I found missing in Roblox's built-in API. Inspired by lodash in JavaScript and functional programming. If I don't find a suitable alternative, I'll release this as a package
