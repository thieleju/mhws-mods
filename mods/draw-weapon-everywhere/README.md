# Draw Weapon Everywhere - Monster Hunter Wilds Mod

Lets you draw your weapon, attack and use items in rest areas: the Grand Hub, villages and base camps. Toggle it in game with a controller or keyboard shortcut (default L3 + R3).

## Requirements

- Requires [REFramework](https://www.nexusmods.com/monsterhunterwilds/mods/93)

## Features

- Draw your weapon, attack and use items (e.g. bombs) in rest areas
- Toggle in game with a shortcut, with a chat message
- Separate controller and keyboard shortcuts, set up in the REFramework menu
- Global enable/disable switch
- Optionally only in the Grand Hub
- Only affects your own hunter, no damage to other players

## Installation

- Download from GitHub Releases and ensure `draw_weapon_everywhere.lua` is placed under `reframework/autorun`

## Usage

- Press the shortcut (default L3 + R3) to toggle; the current state is shown in the REFramework menu under `Draw Weapon Everywhere`
- Options: enabled, active on game start, Grand Hub only, chat message
- When `Enabled` is off, the mod does nothing and its other options are hidden
- Shortcuts: click `Set` next to Controller or Keyboard, press the combination and release it; `Clear` removes it. Every shortcut that is set is active
- Settings are saved automatically to `reframework/data/DrawWeaponEverywhere/config.json`
- Other players in an online lobby can see your attacks; test in a private lobby first

## How it works

While your hunter is in a rest area, the game's life area component (`app.mcHunterLifeArea.updateMain`) sets per-frame flags that block combat and items. While the mod is active, that update is skipped for your own hunter.

## Credits

- Inspired by [Wilds PvP - Draw Weapons in Hub](https://www.nexusmods.com/monsterhunterwilds/mods/3711) by kassent
