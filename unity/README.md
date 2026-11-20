# Forgotten World — Unity client

The game client is being rebuilt in Unity 2022.3 LTS. The previous Godot project is retained in `game/` as a migration reference; new gameplay work belongs in `unity/`.

## Current playable foundation
- Side-view 2D world with generated terrain, trees and crystal props.
- Rigidbody-based movement and jumping.
- Weapon switching with four distinct weapon appearances and a swing action.
- Four outfit/skin choices with visible character tint changes.
- Material gathering, inventory panel and local JSON save/autosave.

## Controls
- A/D or arrow keys: move
- Space/W/Up: jump
- J: swing equipped weapon
- E: gather materials
- I: open/close inventory
- 1–4: equip weapon

This is the migration foundation, not a finished content-complete RPG. Multiplayer, account sync, full crafting, enemy combat, proper sprite sheets and Discord Rich Presence still need to be ported and tested.
