# WildsHUDFork - Monster Hunter Wilds Mod

Shows the HP value of the locked-on large monster as native game text.

Stripped-down fork of **WildsHUD** (original author: [iamwh0iam](https://www.nexusmods.com/profile/iamwh0iam)). Everything except the monster HP value has been removed: no HP bar, monster name, stamina, status effects or player damage.

## Requirements

- Requires [REFramework](https://www.nexusmods.com/monsterhunterwilds/mods/93)

## Features

- HP of the locked-on large monster as a number or percentage
- Native game font
- Configurable position (anchor + offset), scale, font size
- Text alignment: left, center or right of the anchor point

## Installation

- Download from GitHub Releases and ensure `WildsHUDFork.lua` is placed under `reframework/autorun`
- Remove the original `WildsHUD.lua` and the `reframework/autorun/WildsHUD` folder

## Usage

- Open the REFramework menu and configure the mod under `WildsHUDFork`
- Settings are saved automatically to `reframework/data/WildsHUDFork/config.json`
- On first start the settings of the original WildsHUD are taken over
