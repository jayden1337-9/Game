# Forgotten World

A 2D medieval-fantasy sandbox RPG being rebuilt in **Unity 2022.3 LTS**, with a Flask account/world service.

## Repository
- `unity/`: new Unity client and Windows build project.
- `game/`: archived Godot prototype retained as a migration reference only.
- `server/`: Flask API, SQLite/PostgreSQL persistence and automated tests.
- `.github/workflows/windows-build.yml`: Unity Windows build and ZIP packaging.
- `.github/workflows/ci.yml`: backend regression tests.

## Unity migration status

The Unity project is the active client. The current foundation includes:
- A generated side-view world with ground, trees, distant hills and crystal formations.
- Rigidbody-based movement and jumping.
- Weapon switching, visible weapon variants and a swing action.
- Four selectable outfit appearances.
- Material gathering, inventory UI and local JSON autosaving.

This is an early playable foundation, not a finished port. The previous Godot prototype had more systems than have been migrated so far. Multiplayer, account integration, full crafting, enemy AI/combat, complete biome generation and Discord Rich Presence still require implementation and testing. The old Godot workflows are no longer used for releases.

## Controls
- A/D or arrow keys: move.
- Space/W/Up: jump.
- J: swing equipped weapon.
- E: gather materials.
- I: inventory.
- 1–4: switch weapon.

## Build requirements

The GitHub Actions Unity workflow uses Unity 2022.3.50f1. Repository maintainers must add a valid Unity license as the `UNITY_LICENSE` Actions secret before the hosted build can run. A successful run publishes one `ForgottenWorld-Windows-ZIP` artifact containing the Windows player and server source.

## Run the account server

Local development:
```bash
cd server
python -m pip install -r requirements.txt
python app.py
```

Wispbyte startup command:
```bash
pip install -U --prefix .local -r server/requirements.txt
/usr/local/bin/python /home/container/server/app.py
```

Set `PORT`, `SECRET_KEY`, and `DATABASE_URL` in the Wispbyte environment panel. The server binds to `0.0.0.0`. For production, use PostgreSQL and a long random secret key.

To bootstrap the administrator account, set `ADMIN_USERNAME=admin1337` and choose `ADMIN_PASSWORD` in the private environment settings. The password is hashed before storage; never commit it to GitHub.

## Existing backend capabilities

The Flask service currently supports:
- Account registration and login.
- Persistent wallet, cosmetic ownership and equipment.
- Daily currency claims and capped, duplicate-protected gameplay rewards.
- World creation, invite codes, shared saves and event relay.
- Admin-only developer grants.

The Unity client has not yet been connected to all of these endpoints.

## Discord Rich Presence

The previous Discord RPC integration is part of the archived Godot client and is **not yet ported to Unity**. The Unity implementation will need a Windows desktop IPC integration and configured Discord application assets. Do not assume Rich Presence is active in the Unity build yet.

## Quality and release notes

The backend tests run on pushes and pull requests. The Unity Windows workflow requires the `UNITY_LICENSE` secret. A release is ready only after the workflow succeeds and the packaged game has been tested on Windows.
