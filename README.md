# Roblox Script Portfolio

Showcasing some of my scripts that I use in my Roblox games.

Connected Discord-GitHub

- Discord: @deno_fresh
- Roblox: @zxcdead_ghoul
- GitHub: @VofSwords

## KeyboardFloor

A single client script ([KeyboardFloor.client.luau](KeyboardFloor.client.luau)) that turns any tagged part into a large interactive keyboard floor. It subdivides the part's surface into spatial chunks that stream in and out around the player, draws key models from a shared object pool, detects presses with collision-group-filtered spatial queries against the character, and animates them with tweens. Per-chunk random seeds keep letters and colors stable across unload/reload. Written in strict-mode typed Luau.

[Demo](https://www.roblox.com/games/100237147546880/Keyboard-Floor-Demo)

## Pure

A collection of utility functions that I found missing in Roblox's built-in API. Inspired by lodash in JavaScript and functional programming. If I don't find a suitable alternative, I'll release this as a package
