# MonsterHuntCounterFork - Monster Hunter Wilds Mod

Shows how often you have hunted each large monster directly on the monster icons in the quest list.

Fork of **Monster Hunt Counter v1.0.1** (original author: [combolee](https://www.nexusmods.com/profile/combolee?gameId=6993)). The original draws the numbers as an overlay with reframework-d2d; this fork renders them as native game text inside the quest list UI.

## Requirements

- Requires [REFramework](https://www.nexusmods.com/monsterhunterwilds/mods/93)
- reframework-d2d is **not** required

## Features

- Hunt count (`xN`) at the bottom right of each large monster icon in the quest list
- Uses the game's own font; the numbers move, scroll and fade with the quest cards
- Counts are read once when the quest list opens (or the category changes)
- Labels are only shown when the monster behind an icon is verified; unknown targets stay empty
- Configurable font size (small / normal / large) and X/Y offset

## Changes compared to the original

- Native game text instead of a reframework-d2d overlay
- No 16:9 / 21:9 layout option needed anymore
- Settings file renamed; settings of the original mod are taken over on first start

## Installation

- Download from GitHub Releases and ensure `MonsterHuntCounterFork.lua` is placed under `reframework/autorun`
- Remove the original `Monster_Hunt_Counter_v1.0.1.lua` so the counts are not shown twice

## Usage

- Open the REFramework menu and configure the mod under `MonsterHuntCounterFork`
- Settings are saved automatically to `reframework/data/MonsterHuntCounterFork.json`
