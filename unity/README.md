# Forgotten World — Unity client

The active game client is being rebuilt in Unity 2022.3 LTS. The previous Godot project remains under `game/` as a migration reference.

## Current playable foundation
- Generated side-view world with ground, trees, distant hills and crystal formations.
- Rigidbody-based movement and jumping.
- Forest slimes that wander/chase nearby players, can be hit and award coins and gel.
- Nearby resource gathering from tree trunks and crystal nodes.
- Four distinct pixel-art outfit sprites.
- Friendly forest slimes that can be befriended and follow the player.
- Weapon switching and a swing animation.
- Inventory panel with material counts and outfit selection.
- Local JSON save with periodic autosaving.
- Account sign-in/register panel connected to the existing Flask API.

## Controls
- A/D or arrow keys: move.
- Space/W/Up: jump.
- E: gather a nearby tree or crystal.
- I: open/close inventory.
- U: open/close account panel.

## Account setup
Press U and enter the public Wispbyte server URL, username and password. The URL is saved locally, and the session token is stored in PlayerPrefs. The account client currently reads the profile wallet; online purchases, cosmetics sync, shared worlds and remote player events still need to be ported.

## Current limitations
This is an early Unity migration build, not a finished game. The generated art is a temporary pixel-art foundation; a full sprite-sheet art pass, six biome progression, proper crafting, more enemies, mining/placement, shared worlds, and Discord Rich Presence remain on the roadmap. The Unity Windows build requires a valid Unity license secret in GitHub Actions.
