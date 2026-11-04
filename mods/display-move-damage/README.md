# Display Move Damage - Monster Hunter Wilds Mod

Shows how much damage your moves deal while you hunt. The top row shows the current move, the bottom row the move before it, each with name, damage and hit count.

## Requirements

- Requires [REFramework](https://www.nexusmods.com/monsterhunterwilds/mods/93)

## Features

- Move names as shown in the game's action guide, in the game language
- Projectiles and delayed hits (arrows, ammo, Helm Breaker, ...) count for the move that launched them
- Bowgun hits are named after the ammo, bow hits show the coating
- Kinsect and slinger hits are shown separately
- Hits of the same move within a configurable merge window are added up
- Native game panel (copy of the training area combo display)
- Only your own hits are counted

## Installation

- Download from GitHub Releases and ensure `display_move_damage.lua` is placed under `reframework/autorun`

## Usage

- Open the REFramework menu and configure the mod under `DisplayMoveDamage`
- Options: enable, large monsters only, hit count, training area, merge window, auto-hide, position and scale
- Use `Preview` to position the panel without fighting
- Settings are saved automatically to `reframework/data/DisplayMoveDamage/config.json`

## Credits

- Move detection and naming is based on [My Hunt Report](https://www.nexusmods.com/monsterhunterwilds/mods/4949) by JCubic
- The native panel follows the player damage element of [Wilds HUD](https://www.nexusmods.com/monsterhunterwilds/mods/5209) by iamwh0iam
