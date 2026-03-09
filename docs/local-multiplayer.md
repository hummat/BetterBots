# Local Multiplayer Feasibility

> Research doc — feasibility analysis for local co-op (VT2-style) in Darktide.
> Not a planned feature of BetterBots. Documented for game preservation context.
> See also: `docs/backend-progression.md` for the progression/economy side.

## VT2 vs Darktide Hosting

| | VT2 | Darktide |
|--|-----|----------|
| Default hosting | P2P (any player hosts) | Dedicated server only (AWS GameLift) |
| Local play | Built-in, 1–4 players | SoloPlay mod, 1 player + 3 bots |
| P2P network code | Active, production path | Present in engine, dormant |
| Host migration | None (host quits = game over) | N/A (server doesn't quit) |
| Mod realm | Official (progression) vs Modded (no progression) | No split — all mods are "modded" |
| Dedicated server tool | Promised, cancelled | Built-in (not player-accessible) |

Darktide deliberately moved from VT2's P2P model to dedicated-server-only. But the engine still has LAN and Steam P2P networking code compiled in — just not wired into the game's session flow.

## How SoloPlay Works

`ConnectionSingleplayer` (`scripts/multiplayer/connection/connection_singleplayer.lua`) is a deliberate stub:

- `max_members()` returns **1** — hardcoded, no slots for other players
- Zero networking — no lobby, no channels, no RPC dispatch
- All methods (`disconnect`, `kick`, `update`, `next_event`) are no-ops
- `allocation_state()` returns 1 (fully allocated, no vacancies)
- Host type: `HOST_TYPES.singleplay` or `HOST_TYPES.singleplay_backend_session`
- The entire game simulation runs locally — AI, physics, abilities, everything on the player's machine

The SoloPlay mod (Nexus #176) hooks session boot to call `boot_singleplayer_session()` in `multiplayer_session_manager.lua`, creating a `SingleplayerSessionBoot` → `ConnectionSingleplayer`. Still requires internet for initial backend auth and character loading.

## Network Platform Modes

The engine supports multiple networking backends (`connection_manager.lua` lines 33–78):

```lua
"lan"          → Network.init_lan_client(config, port)    -- exists, unused in production
"wan_server"   → Network.init_wan_server(config, ...)     -- dedicated servers use this
"wan_client"   → Network.init_wan_client(config, ...)     -- players use this
"steam"        → Network.init_steam_client(config)        -- exists, unused in production
"steam_server" → Network.init_steam_server(port, ...)     -- exists, unused in production
```

The `lan` and `steam` paths are compiled into the Stingray binary but the game's `_connection_options()` only initializes `wan_server` or `wan_client`. The other paths are never reached.

The WAN path internally reuses LAN lobby APIs: joining a dedicated server calls `Network.join_lan_lobby(lobby_id)`. The engine's lobby abstraction is generic across transport types.

## Host Types

From `matchmaking_constants.lua`:

```lua
HOST_TYPES = table.enum(
    "player",                       -- listen server (player hosts) — never used
    "mission_server",               -- dedicated mission server
    "hub_server",                   -- dedicated social hub
    "party",                        -- party/squad host
    "singleplay",                   -- solo play (local, no network)
    "singleplay_backend_session"    -- solo with backend tracking (Psykhanium)
)
```

The `"player"` host type exists in the enum but is never assigned in production — evidence the engine supports player-hosted games even though Darktide doesn't use it.

## Multiplayer Connection Handshake

When a client joins a dedicated server, it goes through a 16-stage state machine (`connection_local_state_machine.lua`):

1. `LocalConnectChannelState` — establish engine lobby channel
2. `LocalVersionCheckState` — verify game version hash
3. `LocalAwaitConnectionBootedState` — wait for server ready signal
4. `LocalMasterItemsCheckState` — validate item definitions
5. `LocalRequestHostTypeState` — retrieve host type
6. `LocalMechanismVerificationState` — verify game mechanism (mission definition)
7. `LocalSlotReserveState` — request player slots from backend (optional)
8. `LocalWaitForClaimState` — wait for backend slot confirmation (optional)
9. `LocalSlotClaimState` — claim local player slot (1–4)
10. `LocalPlayersSyncState` — sync player data (profiles, account IDs, session IDs)
11. `LocalTickRateSyncState` — sync server tick rate
12. `LocalEacCheckState` — EAC verification
13. `LocalProfilesSyncState` — download full player profiles
14. `LocalDLCVerificationState` — verify DLC ownership
15. `LocalDataSyncState` — sync game-specific data
16. `LocalSyncStatsState` — sync stats/telemetry IDs

After completion, server broadcasts `rpc_sync_host_local_players` to all clients.

For local multiplayer, stages 7–8 (backend slot reservation), 12 (EAC — removed anyway), and 14 (DLC verification) could be skipped.

## Entity Replication

The engine handles entity replication natively:

- `Network.create_game_session()` manages game objects identified by `game_object_id`
- Server spawns units, engine auto-replicates to all clients via `game_object_created` events
- Ownership tracked per unit: server owns enemies, each client owns their player unit
- Clients receive `game_object_created`, `game_object_destroyed`, `game_object_migrated_to_me` events
- Hot join support: host sends all current game state to new client

**Input replication** uses deterministic lockstep:
- Host sends `rpc_player_input_array(channel_id, frame_index, input_buffer)` to all clients
- Clients replay identical inputs for bit-exact state match
- Network tick rate: ~20 Hz for authority updates, local physics at 60 Hz
- No client-side prediction (the game doesn't use it even in normal multiplayer)

## Bot Backfill

Bot slot management is automatic (`player_unit_spawn_manager.lua`):

```lua
desired_bot_count = max_players - num_players  -- 4 minus human count
```

When a human joins:
- `_on_client_joined()` despawns excess bots
- `PlayerManager.claim_slot()` assigns the new player slot 1–4
- `PlayerUnitSpawnManager` spawns their unit

When a human leaves:
- `PlayerManager.release_slot()` frees the slot
- A bot automatically spawns to fill it

This works for any mix of N humans + (4–N) bots. No changes needed.

## What a Local Multiplayer Mod Would Need

### Layer 1: Network Listener (Hard)

The host must accept incoming connections. Requires calling engine-level C++ functions:

| Approach | Function | Notes |
|----------|----------|-------|
| Steam P2P | `Network.init_steam_client()` | Steam handles NAT traversal, no port forwarding |
| LAN direct | `Network.init_lan_client(config, port)` | Both players must be on same network |
| WAN direct | `Network.init_wan_server(config, port, oodle, cert, key)` | Needs UDP cert/key, port forwarding |

These are C++ engine bindings, not Lua functions. Whether DMF can call them is the key unknown — they exist in the binary's Lua binding table but may require specific initialization state.

### Layer 2: Lobby Creation (Hard)

The host needs a discoverable lobby:

- `Network.create_lan_lobby()` — for LAN play
- Steam lobby creation for Steam P2P
- The engine uses a `LanClient.create_lobby_browser()` API internally

Friends would need to either:
- Browse LAN lobbies (if on same network)
- Join via Steam friend invite (if Steam P2P works)
- Direct connect by IP:port (if WAN/LAN)

### Layer 3: Connection Handshake (Medium-Hard)

Replace `ConnectionSingleplayer` with a minimal multiplayer handler (~500 LOC):

```lua
ConnectionLocalMultiplayer = class("ConnectionLocalMultiplayer")
ConnectionLocalMultiplayer.max_members = function() return 4 end
ConnectionLocalMultiplayer.allocation_state = function() return 4 end
-- + channel management, peer tracking, event dispatch
-- + simplified handshake (skip backend/EAC/DLC stages)
```

Must implement:
- Channel management for connected peers
- Version hash check (prevent mismatched clients)
- Player sync data exchange
- Tick rate negotiation
- Game object sync readiness signaling

### Layer 4: Profile/Character Data (Medium)

Joining players need character profiles (class, loadout, talents, cosmetics). Options:

| Source | When | Complexity |
|--------|------|-----------|
| Real backend | Both players online, authenticated | Low — use existing profile fetch |
| Cached profile | Previously logged in, now offline | Medium — need profile serialization |
| Default loadout | Fully offline | Low — like vanilla bot profiles |

Simplest path: both players logged into Darktide normally, one creates SoloPlay session, other joins over LAN/Steam.

### Layer 5: Unit Spawning & Replication (Free)

Once a peer is connected and synced, everything works automatically:
- `PlayerManager.claim_slot()` assigns slot
- `PlayerUnitSpawnManager` spawns player unit
- Engine replicates entity to all peers
- Bot is despawned to make room
- Combat, abilities, AI — all functional

## Difficulty Summary

| Component | Difficulty | Notes |
|-----------|-----------|-------|
| Network listener startup | **Hard** | C++ engine calls, below mod layer |
| Lobby creation / discovery | **Hard** | Steam or LAN lobby APIs |
| Simplified handshake | **Medium-Hard** | ~500 LOC, must match engine expectations |
| Player slot management | **Free** | Already handles N humans + (4–N) bots |
| Unit spawning | **Free** | Automatic once peer registered |
| Entity replication | **Free** | Engine-native |
| Profile sync (online) | **Low** | Use existing backend fetch |
| Profile sync (offline) | **Medium** | Need cached/default profiles |
| Bot backfill | **Free** | `4 - num_players` already works |
| Progression/rewards | **Separate problem** | See `docs/backend-progression.md` |

## The Core Blocker

Same as the backend problem: the **C++ engine boundary**. `Network.init_steam_client()`, `Network.init_lan_client()`, `Network.create_lan_lobby()` — these functions exist in the Stingray binary but aren't exposed to the Lua mod layer in a documented or tested way.

If the engine networking functions are callable from Lua (big if): **weeks of work**.
If they're not (likely): requires binary modding or a custom launcher — **months**.

## Existing Community Efforts

**None.** No mods, no community projects, no proof-of-concept for local multiplayer.

- **SoloPlay** (Nexus #176): Solo only, max_members=1, no networking
- **Many More Try** (Nexus #175): Joins expired mission board entries for pseudo-private matches — still uses dedicated servers
- **DarktideLocalServer** (Nexus #211): Localhost image server for UI mods, unrelated to gameplay networking

## Game Preservation Implications

When Fatshark shuts down dedicated servers:
- SoloPlay continues to work (local simulation, no server dependency for gameplay)
- Multiplayer dies entirely — no P2P fallback, no LAN mode
- A local multiplayer mod + local backend emulator would be the only path to co-op play
- The engine has the networking infrastructure — it just needs to be activated

## Key Source Files

| Area | File |
|------|------|
| SoloPlay connection | `scripts/multiplayer/connection/connection_singleplayer.lua` |
| Client connection | `scripts/multiplayer/connection/connection_client.lua` |
| Handshake state machine | `scripts/multiplayer/connection/connection_local_state_machine.lua` |
| Connection manager | `scripts/managers/multiplayer/connection_manager.lua` |
| Session management | `scripts/managers/multiplayer/multiplayer_session.lua` |
| Player slot management | `scripts/managers/player/player_manager.lua` |
| Player spawning | `scripts/managers/player/player_unit_spawn_manager.lua` |
| Game session (network) | `scripts/managers/multiplayer/game_session_manager.lua` |
| Mission boot (multiplayer) | `scripts/multiplayer/session/party_immaterium_mission_session_boot.lua` |
| Host types / constants | `scripts/settings/network/matchmaking_constants.lua` |
| Game parameters | `scripts/settings/default_game_parameters.lua` (`max_players = 4`) |
