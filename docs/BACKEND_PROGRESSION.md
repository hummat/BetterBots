# Backend & Progression Architecture

> Research doc — feasibility analysis for local/offline progression in Darktide.
> Not a planned feature of BetterBots. Documented for game preservation context.

## Architecture Overview

Darktide uses a clean two-layer split:

| Layer | Where | What it controls |
|-------|-------|-----------------|
| **Gameplay simulation** | Local (SoloPlay) or dedicated server (AWS GameLift) | Combat, AI, physics, abilities, spawning |
| **Progression backend** | Fatshark/Atoma cloud (`bsp-td-*.atoma.cloud`) | XP, currency, inventory, crafting, contracts, store, mastery |

The backend is a **REST/HAL+JSON** API with ~30 service modules, all routed through a single C++ engine function `Backend.title_request()`. Authentication uses platform OAuth (Steam OpenID -> Fatshark token). A clean `BackendInterface` facade in Lua wraps all game-side calls.

**Hosting**: AWS GameLift with FleetIQ (Spot Instances), FlexMatch for matchmaking, Global Accelerator for latency. Presented at AWS re:Invent 2023 (session GAM305).

**Key URLs** (from decompiled source):
- Auth service: `https://bsp-auth-dev.fatsharkgames.se`
- Title service: `https://bsp-td-dev.fatsharkgames.se` (dev) / `https://bsp-td-{env}.atoma.cloud` (prod)
- Telemetry: `https://telemetry-utvxrq72na-ez.a.run.app/events` (Google Cloud Run)
- Account portal: `https://accounts.atoma.cloud`

## How SoloPlay Interacts with the Backend

SoloPlay **still talks to the backend** — sessions are created, tracked, and reward-capped:

```
GameplaySession.create("singleplayer_" + random(), "localhost")
  -> POST /gameplay/sessions  (creates a real backend session)
  -> session marked as "untrusted" server type

[mission plays locally]

GameplaySession.complete(session_id, participants, mission_result, reward_modifiers)
  -> POST /gameplay/sessions/{id}/complete
  -> backend calculates rewards BUT applies solo reward caps

GameplaySession.remaining_solo_rewards(account_id)
  -> GET /data/{account_id}/account/untrusted/state
  -> returns remaining capped rewards for the period
```

Solo sessions earn *some* rewards — just capped and tagged "untrusted." The backend explicitly tracks and limits these via per-period quotas.

## Backend Service Modules

From `backend_interface.lua` — every module is a separate REST client class:

| Service | What it does | Complexity to replicate |
|---------|-------------|------------------------|
| `gameplay_session` | Mission lifecycle, reward flow | **High** — reward calculation is server-side |
| `progression` | XP tables, level-up | Medium — XP curve data is fetchable |
| `wallet` | Currency balances (credits, plasteel, diamantine, marks, aquilas) | Medium — balance tracking + caps |
| `gear` | Inventory CRUD, paginated | **High** — item generation, UUID management |
| `crafting` | Upgrade rarity, extract/replace traits, reroll perks | **High** — RNG + cost validation + item mutation |
| `mastery` | Weapon mastery tracks, trait tiers | Medium |
| `characters` | Character creation, loadout equipping | Medium |
| `contracts` | Weekly tasks, reroll, completion | Medium |
| `commendations` | Penances/achievements | Medium |
| `store` | Armoury Exchange, cosmetics shop, rotations | **High** — personalized rotations, offer generation |
| `player_rewards` | Mailbox, reward claiming | Low |
| `tracks` / `wintracks` | Seasonal tracks, event tracks | Medium |
| `master_data` | Item templates, definitions | Low (static data) |
| `matchmaker` | Queue tickets (incl. single-player) | Low for solo |
| `mission_board` | Available missions | Low |
| `account` | Account data, settings | Low |
| `social` | Friends, presence | Not needed for solo |
| `havoc` | Seasonal ranking | Not needed for solo |
| Others | `dlc_license`, `hub_session`, `version_check`, etc. | Low / skippable |

## Mission Completion & Reward Flow

```
Mission End (client game_session_manager)
  |
  v
GameplaySession.complete(session_id, participants, mission_result, reward_modifiers)
  | POST /gameplay/sessions/{id}/complete
  v
Backend processes missionResult, calculates rewards
  |
  v
ProgressionManager.fetch_session_report(session_id)
  |
  v
Poll: GameplaySession.poll_for_end_of_round(session_id, participant)
  | GET /gameplay/sessions/{id} (status check, every 2s)
  | GET /gameplay/sessions/{id} -> follow _links.eor (fetch rewards once completed)
  v
Backend returns eor object containing:
  - XP grants (character + account level)
  - Currency rewards (plasteel, diamantine, credits)
  - Item drops (with server-generated stats)
  - Mastery progression
  - Commendation updates
  |
  v
ProgressionManager._parse_report(eor)
  -> Updates local player inventory/progression state
  -> UI displays rewards screen
```

**Participant format**: `{account_id}|{character_id}` — must match session record.

**Reward modifiers sent by client** (per character):
- `xp`, `credits`, `rareLoot`, `gearInsteadOfWeapon`
- `sideMissionXp`, `sideMissionCredit`
- `mission_reward_*_modifier` (hidden challenge multipliers)

Backend uses these as *inputs* to its own reward calculation — the client does not compute final values.

## Currency Systems

Five currencies, all server-authoritative:

| Currency | Scope | Earned from | Spent on | Cap |
|----------|-------|-------------|----------|-----|
| Credits | Character | Missions, contracts, gear deletion | Crafting, store | Backend-set |
| Marks | Character | Contracts, events | Store purchases | Backend-set |
| Plasteel | Character | Missions, events | Weapon/gadget crafting | Backend-set |
| Diamantine | Character | Missions, events, challenges | Rarity upgrades, traits | Backend-set |
| Aquilas | Account | Real money (Steam/PSN/Xbox) | Premium cosmetics | Backend-set |

**Wallet endpoints**:
- Per-character: `GET /data/{account_id}/characters/{character_id}/wallets`
- Per-account: `GET /data/{account_id}/account/wallets`
- Currency config: `GET /store/currencies`
- Balance format: `{ type, amount, lastTransactionId }` per wallet

**Double-spend prevention**: Transaction IDs increment on every successful operation. Backend rejects stale IDs.

**Client-side caching**: Optional (`GameParameters.enable_wallets_cache`). Optimistic update on purchase/craft, invalidated on error.

## Crafting System

All crafting is a single endpoint with operation dispatch:

```
POST /data/{account_id}/account/crafting
Body: { op: "upgradeRarity" | "extractTrait" | "replaceTrait" | "rerollPerk" | "fuseTraits" | "addExpertise" | "extractMastery", gearId, ... }
```

- **Server-rolled**: Final item stats (rarity, traits, perks) generated server-side
- **Costs**: Fetched via `GET /data/account/crafting/costs`
- **Idempotent**: Same request twice = same result (via `lastTransactionId`)
- No item generation code exists in the client

## Inventory / Gear

- **Paginated**: `GET /v2/data/{account_id}/account/gear?limit={size}&slots={slots}`
- **Item format**: `{ uuid, characterId, masterDataInstance: { id }, overrides: { ... } }`
- **Equip**: `PUT /characters/{character_id}/inventory/` with `[{ instanceId, slotId }]`
- **Delete**: `DELETE /account/gear/{gear_id}` — returns currency refund
- **Batch delete**: Up to 40 items per batch
- **Source of truth**: Backend — local cache is read-only projection

## Contracts & Penances

- **Weekly contracts**: `GET /characters/{id}/contracts/current?createIfMissing=true`
- **Reroll task**: `DELETE /characters/{id}/contracts/current/tasks/{task_id}?lastTransactionId={txn}`
- **Complete**: `POST /characters/{id}/contracts/current/complete` -> returns reward
- **Penance tracks**: `GET /data/{account_id}/trackstate/{track_id}`
- **Claim tier**: `POST /tracks/{track_id}/tiers/{tier}`

## Store / Armoury Exchange

- **Per-archetype stores**: Credits, Marks, Cosmetics, Weapon cosmetics (6 archetypes x 4 store types)
- **Endpoint**: `GET /store/storefront/{store_name}?accountId={id}&characterId={char}&personal={bool}`
- **Rotation**: Server-generated personalized offers per account+character, `currentRotationEnd` timestamp
- **Purchase**: POST to offer's purchase link (embedded in HAL response) -> server validates balance, generates item
- **Premium (Aquilas)**: Separate storefront, external payment reconciliation via Steam/PSN/Xbox SDKs

## Authentication & Security Model

### Authentication Flow

```
Steam OpenID -> Backend.authenticate(user_id) -> account { sub: "account_id" }
All subsequent requests: C++ layer injects auth token into HTTP headers
```

Platform-specific:
- Steam: encrypted app ticket
- Xbox/PSN: platform token in `platform-token` header
- Auth methods: `AUTH_METHOD_STEAM`, `AUTH_METHOD_XBOXLIVE`, `AUTH_METHOD_PSN`

### The C++ Boundary

All backend calls funnel through three **native engine functions** (Stingray/Bitsquid binary):

```lua
Backend.initialize(debug_log, auth_url, title_url, telemetry_url)
Backend.authenticate(user_id)
Backend.title_request(path, options)  -- returns promise ID
```

These handle HTTP transport, TLS, and auth token injection. They are **not hookable** from DMF — not Lua functions, but C++ bindings.

### What IS Protected

| Protection | How |
|------------|-----|
| Platform identity | Steam/Xbox/PSN OAuth — proves who you are |
| Auth token injection | C++ layer adds Authorization header — not spoofable from Lua |
| Server-side reward calculation | Backend computes final values, client can't influence |
| Transaction IDs | Prevent double-spend / replay |
| Solo reward caps | `remaining_solo_rewards()` per-period limit for "untrusted" sessions |

### What IS NOT Protected

| Gap | Detail |
|-----|--------|
| No EAC | Removed December 2022 — no kernel-level integrity check |
| No request signing | No HMAC/signature on requests — auth token is the only credential |
| No server validation | Backend accepts any `server_id`/`ip_address` in session creation |
| No mission result signing | Client submits raw `mission_result` — no checksum |
| No per-session cryptographic binding | Session IDs are UUIDs, not cryptographically tied to server identity |

## Server-Only Logic (Not in Client)

These computations exist only on Fatshark's backend — the decompiled Lua shows API calls but not the formulas:

1. **Reward calculation**: mission difficulty x modifiers x performance -> XP/credits/materials
2. **Item generation**: rarity rolls, trait selection, perk rolls, stat distribution
3. **Loot tables**: drop rates, rarity weights, mission-tier scaling
4. **Crafting RNG**: trait/perk reroll outcomes
5. **Store rotation algorithm**: personalized per-account/character offer generation
6. **Solo reward caps**: per-period quotas for "untrusted" sessions

## Traffic Redirection Options

Since `Backend.title_request()` is a C++ function, redirecting traffic requires operating below the Lua mod layer:

| Approach | How | Difficulty | Notes |
|----------|-----|-----------|-------|
| DNS redirect | `/etc/hosts`: point `bsp-td-*.atoma.cloud` -> `127.0.0.1` | Easy | Needs matching TLS cert or cert validation bypass |
| Local HTTPS proxy | mitmproxy/Charles with custom CA cert | Medium | Game may pin certs |
| Binary patching | Modify hardcoded URLs in Stingray binary | Hard | Breaks on every game update |
| Xbox backend config | Code shows Xbox reads `backend_config.json` for URL overrides | Unknown | Unclear if exploitable on PC |
| Lua-layer interception | Hook the Lua callers above `Backend.title_request()` | Possible | Can intercept/modify requests but not redirect transport |

## Implementation Paths

### Path A: Full Local Backend Emulator

Build a local HTTP server implementing all ~30 service endpoints (~50-80 total routes):

```
localhost:8443
  /gameplay/sessions/*       -> session lifecycle + reward calc
  /data/{id}/account/gear    -> SQLite-backed inventory
  /account/crafting          -> crafting logic + RNG
  /store/storefront/*        -> static or randomized store
  /data/experience-table/*   -> hardcoded XP curves
  /characters/*              -> character management
  ...
```

**Requirements**: HTTP server + SQLite/similar, HAL+JSON responses, reverse-engineered reward/loot/crafting formulas, traffic redirect, initial state seeded from real account.

**Gets you**: Full offline progression, crafting, leveling, contracts. Complete game loop without internet. Game preservation when servers shut down.

**Loses**: Multiplayer, accurate loot/crafting odds (unless reverse-engineered), store rotations (unless built), zero sync with real account.

**Effort**: Months of dedicated work.

### Path B: Backend Proxy / Interceptor

Local HTTPS proxy intercepts specific calls, forwards everything else to real backend:

```
Game -> mitmproxy (localhost) -> Fatshark backend
               | (intercept)
       Override solo reward caps
       Modify reward_modifiers before forwarding
       Inject additional rewards in EOR response
```

**Gets you**: Real progression on real account, most systems unmodified.

**Loses**: Depends on servers being online. **High ban risk** — manipulating reward data on a live account. Explicitly violates ToS.

**Effort**: Weeks.

### Path C: Offline Tracker Mod

DMF mod that locally records what *would have* been earned. No actual progression — just bookkeeping.

**Effort**: Days. **Value**: Minimal (a spreadsheet).

## Existing Community Efforts

**None.** No private server emulator exists for Darktide or Vermintide 2.

- **DarktideLocalServer** (Nexus #211, [GitHub](https://github.com/ronvoluted/darktide-local-server)): Just a localhost image server for UI mods. Not a backend emulator.
- **Armoury Exchange** ([GitHub](https://github.com/danreeves/dt-exchange)): Browser extension accessing store API via Steam auth. Proves API is accessible to third-party tools but doesn't modify progression.
- **Vermintide 2**: Same architecture (P2P hosting, server-authoritative progression). Split into Official Realm (progression) and Modded Realm (no progression). No private server in 8+ years.

## Fatshark's Position

From the [official modding policy](https://forums.fatsharkgames.com/t/darktide-modding-policy/75407):

> "Mods will have access to the same authentication level as the regular game, which means mods are perfectly capable of managing inventories, currencies, and characters."

Explicitly banned: "Bypassing progression, penances, or contracts; unlocking premium cosmetics/currencies."

Enforcement: "Players found using banned mods in a way that affects other unmodded players will be subject to a prompt warning and possible ban."

## Official Solo Mode Status

- Announced November 2022, described as "in final testing stages"
- As of March 2026: **still not released** — community thread: "Solo Mode: A Three Year Lie?"
- Would be locally hosted but still require internet for backend authentication
- No indication it would include unrestricted progression

## Game Preservation Angle

The strongest ethical case for a local backend. When Fatshark eventually shuts down servers:
- The gameplay simulation works offline (SoloPlay proves this)
- All progression stops — characters frozen, no crafting, no leveling
- A local backend emulator is the only path to a complete game loop
- The EU's "Stop Killing Games" campaign (which Darktide players have specifically cited) may eventually provide legal framework

The full API surface is documented in the decompiled Lua source — future preservation efforts have a detailed blueprint to work from.

## API Endpoint Summary

| System | Read | Write |
|--------|------|-------|
| Sessions | `GET /gameplay/sessions/{id}` | `POST /complete`, `/update`, `/events` |
| Wallets | `GET /store/currencies`, `/{account}/wallets` | (read-only — modified via rewards/purchases) |
| Gear | `GET /v2/{account}/account/gear?limit=&slots=` | `POST /account/gear`, `DELETE /{id}`, `PATCH` |
| Crafting | `GET /crafting/{id}/meta`, `/crafting/costs/*` | `POST /account/crafting` |
| Contracts | `GET /characters/{id}/contracts/current` | `POST /complete`, `DELETE /tasks/{id}` |
| Progression | `GET /experience-table/{type}`, `/progression/{type}/{id}` | `PUT /{type}/{id}/level/{num}` |
| Mastery | `GET /trackstate/{id}` | `POST /tracks/{id}/tiers/{tier}` |
| Store | `GET /store/storefront/{name}` | (purchase via offer HAL link) |
| Characters | `GET /characters/{id}` | `PUT /characters/{id}/inventory/` |
| Account | `GET /account/*` | `PUT /account/data/{section}` |
| Solo caps | `GET /{account}/account/untrusted/state` | (server-managed) |

## Key Source Files

| Area | File | What it contains |
|------|------|-----------------|
| Backend facade | `scripts/backend/backend_interface.lua` | All 30 service module instantiation |
| Backend HTTP | `scripts/foundation/managers/backend/backend_manager.lua` | HTTP transport, retry, auth |
| Session lifecycle | `scripts/backend/gameplay_session.lua` | Mission create/update/complete/poll |
| Reward parsing | `scripts/managers/progression/progression_manager.lua` | EOR fetch + parse |
| Singleplayer connection | `scripts/multiplayer/connection/connection_singleplayer.lua` | Local-only session |
| Matchmaker | `scripts/backend/matchmaker.lua` | Queue ticket types incl. single-player |
| Wallets | `scripts/backend/wallet.lua` | Currency fetch/config |
| Crafting | `scripts/backend/crafting.lua` | All crafting operations |
| Gear/inventory | `scripts/backend/gear.lua` | CRUD + pagination |
| Contracts | `scripts/backend/contracts.lua` | Weekly tasks |
| Mastery | `scripts/backend/mastery.lua` | Trait tiers |
| Store | `scripts/backend/store.lua` | Storefront + offers |
| EAC | `scripts/managers/eac/eac_client_manager.lua` | Anti-cheat integration |
| Account auth | `scripts/managers/account/account_manager_steam.lua` | Steam OpenID flow |
| gRPC/party | `scripts/managers/grpc/grpc_manager.lua` | Party management, presence |
