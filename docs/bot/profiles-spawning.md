# Bot Profiles, Spawning, and Group Coordination

Comprehensive reference for how Darktide bots are configured, spawned, coordinated, and synchronized. Based on decompiled source (v1.10.7).

---

## 1. Bot Profile System

### 1.1 Profile Structure

Every bot profile is a Lua table with these fields:

```lua
{
    archetype = "veteran",          -- class: veteran/zealot/psyker/ogryn/adamant/broker
    current_level = 1,              -- always 1, not used for scaling
    gender = "male",                -- male/female
    name_list_id = "male_names_1",  -- for random name generation (optional)
    planet = "option_1",            -- backstory planet (optional)
    display_name = "Zola",          -- fixed display name (optional, tutorial only)
    selected_voice = "veteran_male_a",
    loadout = {
        slot_primary = "...",       -- melee weapon (bot-specific template)
        slot_secondary = "...",     -- ranged weapon (bot-specific template)
        slot_gear_head = "...",     -- cosmetic slots (many)
        slot_gear_upperbody = "...",
        slot_gear_lowerbody = "...",
        slot_body_* = "...",        -- body customization (face, hair, scars, etc.)
    },
    bot_gestalts = {                -- behavior style hints
        melee = behavior_gestalts.linesman,
        ranged = behavior_gestalts.killshot,
    },
    talents = {},                   -- ALWAYS EMPTY TABLE
    personal = {                    -- optional
        character_height = 1.075,   -- visual height variation
    },
}
```

**Source:** `scripts/settings/bot_profiles/ingame_bot_profiles.lua`

### 1.2 Talents

Bots have **no talents**. Every profile sets `talents = {}`. This is a hard constraint -- bots never receive talent nodes, which means:

- No passive abilities from talent tree
- No class ability modifications (e.g., Veteran's "Executioner's Stance" variants)
- The `archetype` field determines which ability template is available, but talent-gated ability modifications never apply

### 1.3 Behavior Gestalts

Defined in `scripts/settings/bot/bot_settings.lua`:

```lua
behavior_gestalts = table.enum("none", "killshot", "linesman")
```

Every ingame bot profile uses `melee = linesman, ranged = killshot`. These values are written to the blackboard's `behavior` component (`melee_gestalt`, `ranged_gestalt`) and influence the BT's melee/ranged action selection. There is no variation -- all bots fight the same way.

### 1.4 Profile Categories

Profiles are organized across four source files, all merged into a single lookup table:

| Source File | Profiles | Purpose |
|---|---|---|
| `ingame_bot_profiles.lua` | `bot_1`..`bot_6`, `low_bot_1`..`low_bot_6`, `medium_bot_1`..`medium_bot_6`, `high_bot_1`..`high_bot_6`, `bot_adamant_*` (6), `bot_broker_*` (6) | Normal gameplay |
| `misc_bot_profiles.lua` | `darktide_seven_01`..`darktide_seven_07` | Cinematic/promo characters |
| `training_ground_bot_profiles.lua` | `bot_training_grounds` | Training grounds |
| `tutorial_bot_profiles.lua` | `tutorial_guide` (Zola), `tutorial_guide_zealot`, `tutorial_guide_ogryn` | Tutorial |

**Source:** `scripts/settings/bot_character_profiles.lua` (lines 11-38)

### 1.5 Profile Loading Pipeline

```
bot_character_profiles.lua
  -> requires all 4 profile source files
  -> each source populates all_profiles table
  -> for each profile:
       MasterItems.get_item_or_fallback(item_id, slot_name, item_definitions)
       LocalProfileBackendParser.parse_profile(profile, profile_name)
  -> cached by item_definitions (singleton per item catalog)
```

`ProfileUtils.get_bot_profile(identifier)` retrieves a shallow copy of the cached profile by name.

**Source:** `scripts/utilities/profile_utils.lua` (line 613)

---

## 2. Ingame Bot Profiles (Detail)

### 2.1 Difficulty Tiers

The ingame profiles are split into four tiers based on naming convention:

| Tier | Profile Pattern | Archetype | Cosmetics | Weapons | Buff |
|---|---|---|---|---|---|
| Default | `bot_1`..`bot_6` | veteran | prisoner clothes | standard bot weapons | none |
| Low | `low_bot_1`..`low_bot_6` | veteran | prisoner clothes | standard bot weapons | none |
| Medium | `medium_bot_1`..`medium_bot_6` | veteran | career gear (lvl 1) | standard bot weapons | `bot_medium_buff` |
| High | `high_bot_1`..`high_bot_6` | veteran | career gear (lvl 2-3) | **high** bot weapons | `bot_high_buff` |

**Every ingame bot is a Veteran.** No zealot, psyker, or ogryn bots exist in normal gameplay.

Tier selection (from `bot_spawning.lua:60-70`):

```lua
BotSpawning.get_bot_config_identifier = function ()
    local challenge = Managers.state.difficulty:get_challenge()
    if challenge >= 5 then
        return "high"   -- Difficulty 5 (Heresy/Damnation)
    elseif challenge == 3 or challenge == 4 then
        return "medium" -- Difficulty 3-4 (Malice/Heresy)
    else
        return "low"    -- Difficulty 1-2 (Sedition/Uprising)
    end
end
```

Profile name is constructed as: `<tier>_bot_<1-6>` (e.g., `medium_bot_3`, `high_bot_5`).

For medium/high difficulty, bots receive stat buffs at spawn via:

```lua
-- game_mode_coop_complete_objective.lua:306-312
buff_extension:add_internally_controlled_buff("bot_" .. bot_config_identifier .. "_buff", t)
```

### 2.2 New Archetypes (Adamant / Broker)

The file also defines 12 profiles for two new archetypes:

| Archetype | Profiles | Count |
|---|---|---|
| `adamant` | `bot_adamant_ma`, `bot_adamant_mb`, `bot_adamant_mc`, `bot_adamant_fa`, `bot_adamant_fb`, `bot_adamant_fc` | 6 |
| `broker` | `bot_broker_ma`, `bot_broker_mb`, `bot_broker_mc`, `bot_broker_fa`, `bot_broker_fb`, `bot_broker_fc` | 6 |

These use the same weapon pool and `linesman/killshot` gestalts as veteran bots. The naming convention (`ma`=male_a, `fb`=female_b, etc.) replaces the numbered scheme. These are likely Arbites and Hive Scum respectively -- not yet exposed through the difficulty-tier spawning system.

### 2.3 Misc Profiles (Darktide Seven)

Seven pre-built characters for cinematic/promotional use:

| Profile | Archetype | Melee | Ranged |
|---|---|---|---|
| `darktide_seven_01` | veteran (M) | chainsword_p1_m1 | bot_lasgun_killshot |
| `darktide_seven_02` | ogryn (M) | ogryn_combatblade_p1_m1 | ogryn_rippergun_p1_m1 |
| `darktide_seven_03` | zealot (F) | thunderhammer_2h_p1_m1 | autogun_p1_m1 |
| `darktide_seven_04` | psyker (M) | forcesword_p1_m1 | forcestaff_p1_m1 |
| `darktide_seven_05` | veteran (F) | powersword_p1_m1 | bot_lasgun_killshot |
| `darktide_seven_06` | zealot (M) | thunderhammer_2h_p1_m1 | autogun_p1_m1 |
| `darktide_seven_07` | psyker (F) | forcesword_p1_m1 | forcestaff_p1_m1 |

These use a mix of regular player weapons and bot-specific weapons. They also have `talents = {}` and no `bot_gestalts` field (darktide_seven_01 has gestalts, the rest do not).

### 2.4 Tutorial Profiles

| Profile | Archetype | Display Name |
|---|---|---|
| `tutorial_guide` | veteran (F) | Zola |
| `tutorial_guide_zealot` | zealot (F) | Jilande |
| `tutorial_guide_ogryn` | ogryn (M) | Kreft |

---

## 3. Bot Weapons

### 3.1 Bot-Specific Weapon Templates

Bots use dedicated weapon templates located in `scripts/settings/equipment/weapon_templates/bot_weapons/`:

| Template | Type | Base Weapon |
|---|---|---|
| `bot_lasgun_killshot` | ranged | Lasgun (killshot variant) |
| `bot_autogun_killshot` | ranged | Autogun (killshot variant) |
| `bot_laspistol_killshot` | ranged | Laspistol (killshot variant) |
| `bot_zola_laspistol` | ranged | Laspistol (tutorial Zola) |
| `high_bot_lasgun_killshot` | ranged | Lasgun (higher difficulty) |
| `high_bot_autogun_killshot` | ranged | Autogun (higher difficulty) |
| `bot_combatsword_linesman_p1` | melee | Combat Sword pattern 1 |
| `bot_combatsword_linesman_p2` | melee | Combat Sword pattern 2 |
| `bot_combataxe_linesman` | melee | Combat Axe |

### 3.2 How Bot Weapons Differ from Player Weapons

Bot weapon templates are **full weapon templates** with identical structure to player weapons. Key differences:

- **`attack_meta_data`**: Bot ranged weapons include this field, which tells the BT how to use them:
  ```lua
  -- bot_lasgun_killshot.lua:732-737
  weapon_template.attack_meta_data = {
      aim_action_name = "action_zoom",
      aim_fire_action_name = "action_shoot_zoomed",
      fire_action_name = "action_shoot_hip",
      unaim_action_name = "action_unzoom",
  }
  ```
- **Stamina template**: Bot melee weapons use `bot_linesman` stamina template instead of player defaults.
- **No trait randomization**: Bots get `traits = {}` -- no random blessings.
- **Tuned damage profiles**: The `high_*` variants likely have adjusted damage values for higher difficulty scaling.

### 3.3 Weapon Distribution Across Profiles

Each set of 6 profiles varies weapons across three melee and three ranged options:

| Bot # | Melee | Ranged |
|---|---|---|
| 1 | bot_combatsword_linesman_p1 | bot_lasgun_killshot |
| 2 | bot_combatsword_linesman_p1 | bot_autogun_killshot |
| 3 | bot_combatsword_linesman_p2 | bot_autogun_killshot |
| 4 | bot_combatsword_linesman_p2 | bot_laspistol_killshot |
| 5 | bot_combataxe_linesman | bot_laspistol_killshot |
| 6 | bot_combataxe_linesman | bot_lasgun_killshot |

High-tier bots replace `bot_lasgun_killshot` with `high_bot_lasgun_killshot` and `bot_autogun_killshot` with `high_bot_autogun_killshot`.

---

## 4. Spawning Flow

### 4.1 When Bots Spawn

Bots spawn in two scenarios:

1. **Initial mission start**: Fill to 4 players. `PlayerUnitSpawnManager._handle_initial_bot_spawning()` shuffles bot IDs 1-6 and spawns enough to fill `max_players - num_humans`.
2. **Player disconnect**: `PlayerUnitSpawnManager._on_client_left()` queues replacement bots (up to available slots).

### 4.2 Spawning Sequence

```
PlayerUnitSpawnManager
  -> _handle_bot_spawning() / _handle_initial_bot_spawning()
    -> BotSpawning.get_bot_config_identifier()   -- "low"/"medium"/"high"
    -> profile_name = config .. "_bot_" .. id     -- e.g. "medium_bot_3"
    -> BotSpawning.spawn_bot_character(profile_name)
      -> ProfileUtils.get_bot_profile(profile_name)
      -> bot_synchronizer_host:add_bot(local_player_id, profile)
        -> BotSynchronizerHost.add_bot() adds to spawn_group
        -> BotSynchronizerHost.update():
           1. profile_synchronizer_host:add_bot() -- sync profile to clients
           2. player_manager:add_bot_player(BotPlayer, ...) -- create BotPlayer
           3. package_synchronizer_host:add_bot() -- sync packages
           4. Wait for profiles_synced
           5. RPC.rpc_add_bot_player() to all clients
  -> BotGameplay.update():
    -> Wait for package_synchronizer_host:bot_synced_by_all()
    -> player_spawner_system:next_free_spawn_point("bots")
    -> player_unit_spawn_manager:spawn_player() -- creates the unit
```

**Source:** `scripts/managers/player/player_unit_spawn_manager.lua` (lines 441-498), `scripts/bot/bot_synchronizer_host.lua`, `scripts/managers/player/player_game_states/bot_gameplay.lua`

### 4.3 Profile Selection Logic

```lua
-- player_unit_spawn_manager.lua:441-462
local initial_bot_id_table = {1, 2, 3, 4, 5, 6}
table.shuffle(initial_bot_id_table)

while self._queued_bots_n > 0 do
    local bot_id = initial_bot_id_table[1]
    local bot_config_identifier = BotSpawning.get_bot_config_identifier()
    local profile_name = bot_config_identifier .. "_bot_" .. bot_id
    BotSpawning.spawn_bot_character(profile_name)
    table.remove(initial_bot_id_table, 1)
    self._queued_bots_n = self._queued_bots_n - 1
end
```

For subsequent spawns (mid-mission), existing bot profile identifiers are excluded to avoid duplicates:

```lua
-- player_unit_spawn_manager.lua:467-497
for _, player in pairs(players) do
    if not player:is_human_controlled() then
        local profile = player:profile()
        local key = table.find(BOT_PROFILE_NAME_TABLE, profile.identifier)
        if key then
            table.remove(BOT_PROFILE_NAME_TABLE, key)
        end
    end
end
```

### 4.4 Bot Slot Limits

```lua
-- default_game_parameters.lua:19
DefaultGameParameters.max_players = 4

-- game_mode_settings_coop_complete_objective.lua:9
max_bots = 3

-- player_unit_spawn_manager.lua:413-425
local max_bots = bot_backfilling_allowed and settings.max_bots or 0
local desired_bot_count = max_players - num_players
desired_bot_count = math.clamp(desired_bot_count, 0, max_bots)
```

- **Max players**: 4 (hardcoded)
- **Max bots**: 3 (per game mode, both `coop_complete_objective` and `survival`)
- **Bot backfilling**: Only allowed in `coop_complete_objective` and `survival` game modes
- **Training grounds, hub, prologue**: No bots (`bot_backfilling_allowed = false`)

### 4.5 Bot Despawning

```lua
BotSpawning.despawn_bot_character(local_player_id, despawn_safe)
BotSpawning.despawn_best_bot(despawn_safe)
```

`despawn_safe` marks the unit for deletion and queues removal for next frame; `despawn` removes immediately. Called when a human player joins (pushing a bot out).

---

## 5. Bot Manager

`BotManager` (`scripts/managers/bot/bot_manager.lua`) is a thin wrapper around the synchronizer objects:

- **`create_synchronizer_host()`**: Creates `BotSynchronizerHost` (server-side bot lifecycle)
- **`create_synchronizer_client()`**: Creates `BotSynchronizerClient` (client-side bot representation)
- **`update(dt)`**: Calls `bot_synchronizer_host:update(dt)` to process spawn groups
- **`post_update(dt, t)`**: Calls `handle_queued_bot_removals()` for safe despawns

The actual spawning decisions live in `PlayerUnitSpawnManager`, not `BotManager`.

---

## 6. BotPlayer Object

`BotPlayer` (`scripts/managers/player/bot_player.lua`) extends `HumanPlayer`:

```lua
BotPlayer.is_human_controlled = function (self)
    return false  -- THE key gate for bot vs human behavior
end

BotPlayer.wanted_spawn_point = function (self)
    return "bots"  -- separate spawn point category
end

BotPlayer.name = function (self)
    return self._profile.display_name or self._profile.name or self._debug_name
end
```

This class is what `player:is_human_controlled()` checks against throughout the codebase. The `BotBehaviorExtension` and `BotUnitInput` are attached only when `is_human_controlled() == false`.

---

## 7. Group Coordination (BotGroup)

### 7.1 Overview

`BotGroup` (`scripts/extension_systems/group/bot_group.lua`) manages all bots on a side as a coordinated squad. One `BotGroup` instance per side.

### 7.2 Per-Bot Data

When a bot joins, `BotGroup.add_bot_unit()` creates a data entry:

```lua
data = {
    ammo_pickup_order_unit = nil,
    follow_position = nil,           -- where to go
    follow_unit = nil,               -- who to follow
    nav_point_utility = {},          -- pathfinding utility scores
    aoe_threat = { expires, escape_direction },
    pickup_orders = {},              -- player-ordered pickups
    behavior_component = ...,        -- blackboard write access
    perception_component = ...,
    pickup_component = ...,
    behavior_extension = ...,
    navigation_extension = ...,
    character_state_component = ...,
}
```

### 7.3 Move Target Selection

The core coordination logic. Called every frame via `BotGroup.update()`:

```
_update_move_targets(bot_data, num_bots, nav_world, side)
```

**Algorithm by player count:**

| Human Players | Bot Behavior |
|---|---|
| 0 (all disabled) | Bots follow disabled humans |
| 1 | Bots cluster around closest human |
| 2 (in carry event, 2 bots) | Each bot follows one human |
| 2 (normal) | Bots follow closest human (averaged bot position) |
| 3+ | Bots follow **least lonely** human (closest to other players) |
| 3+ (carry event) | Bots follow **most lonely** human (furthest from others) |

**Key constants:**
- `LONELINESS_PREVIOUS_TARGET_STICKINESS = 25` -- keeps following same target
- `CLOSEST_TARGET_PREVIOUS_TARGET_STICKINESS = 3` -- bias toward current target
- `DESTINATION_POINTS_SPACE_PER_PLAYER = 1` -- meters between follow positions
- `DESTINATION_POINTS_RANGE = 3` -- max spread range

### 7.4 Formation / Destination Points

Bots don't stand on top of their follow target. `_find_destination_points()` raycasts left and right of the follow target's velocity direction to find valid nav mesh positions:

1. Determine cluster position (ahead of player in movement direction)
2. Raycast in fan pattern (left/right vectors at pi/8 intervals)
3. Generate points along each ray at 1m intervals
4. Assign bots to points via utility optimization (permutation search minimizing distance)

If the follow target is in a disallowed nav tag volume, bots find positions outside it instead.

### 7.5 Hold Position

Bots can be held in place (`bot_behavior_extension._hold_position`), which overrides follow behavior. The hold position has a max distance radius -- bots stay within that radius even when asked to override for cover or melee engagement.

### 7.6 Priority Targets

`_update_priority_targets()` tracks enemies that have pounced allies. Bots coordinate to rescue pounced players -- the closest bot gets priority (with stickiness to avoid thrashing).

### 7.7 Ally Aid Priority

`register_ally_needs_aid_priority()` / `is_prioritized_ally()` ensures only one bot goes to revive a downed ally. The closest bot claims priority with a stickiness distance of 3 meters.

### 7.8 Pickup Coordination

`_update_pickups()` runs every 0.15-0.25s, scanning a broadphase around each player unit for:

- **Ammo pickups**: Assigned to nearest bot within 5m (or 15m of follow position). Uses stickiness of 2.5m.
- **Health deployables** (medical crates): Within 10m of bot or 15m of follow position.
- **Mule pickups**: Bots carry objective items (grimoires, etc.) -- tracked in `_available_mule_pickups`.
- **Health pickups**: Distributed via utility optimization (permutation search considering HP and distance).

### 7.9 AOE Threat Response

`aoe_threat_created()` broadcasts area threats (OOBB, cylinder, sphere shapes) to all bots. Each bot calculates an escape direction and queues a dodge at a random time (0-0.5s delay).

### 7.10 Cover Coordination

`set_in_cover()` / `in_cover()` tracks which bot is using which cover position (by hash), preventing multiple bots from claiming the same cover.

---

## 8. Bot Orders

### 8.1 Available Orders

From `scripts/utilities/bot_order.lua` and `NetworkLookup.bot_orders`:

| Order | Function | Description |
|---|---|---|
| `pickup` | `BotOrder.pickup(bot_unit, pickup_unit, ordering_player)` | Order bot to pick up an item |
| `drop` | `BotOrder.drop(bot_unit, pickup_name, ordering_player)` | Order bot to drop a carried item |

Only two order types exist. There is no "hold position" or "attack target" player-issued order in vanilla.

### 8.2 Pickup Order Flow

1. Player tags a pickup while looking at a bot
2. Server: Sets `bot_group_data.pickup_orders[slot_name]` with `{unit, pickup_name}`
3. Existing orders for same slot on other bots are cleared (reassignment)
4. Bot's `follow_component.needs_destination_refresh = true` triggers pathfinding update
5. Client: Sends `rpc_bot_unit_order` to server which calls `BotOrder.pickup()`

### 8.3 Ammo Pickup Order

Handled separately from slot-based pickups. Sets `pickup_component.ammo_pickup` with a 5-second validity window. Checks `Ammo.reserve_ammo_is_full()` first -- full ammo bots ignore the order.

---

## 9. Bot Synchronization

### 9.1 Host-Side (BotSynchronizerHost)

**Source:** `scripts/bot/bot_synchronizer_host.lua`

Manages the authoritative bot state:

- **Spawn states**: `spawn` -> `syncing_profile` -> (synced, remove from spawn_group)
- **`add_bot(local_player_id, profile)`**: Queues bot in spawn group
- **`update()`**: Processes spawn group:
  1. `profile_synchronizer_host:add_bot()` -- push profile to all clients
  2. `player_manager:add_bot_player(BotPlayer, ...)` -- create player object
  3. `package_synchronizer_host:add_bot()` -- sync asset packages
  4. Wait for `profile_synchronizer_host:peer_profiles_synced()`
  5. `RPC.rpc_add_bot_player()` to all connected peers
- **`remove_bot()`**: Removes bot from all systems, sends `rpc_remove_bot_player` to clients
- **`remove_bot_safe()`**: Marks unit for deletion first, queues removal for next frame

### 9.2 Client-Side (BotSynchronizerClient)

**Source:** `scripts/bot/bot_synchronizer_client.lua`

Listens for RPCs from host:

- **`rpc_add_bot_player(channel_id, local_player_id, slot)`**: Creates `RemotePlayer` (not `BotPlayer`) from synced profile JSON. Client bots run no BT -- they're just synced visual representations.
- **`rpc_remove_bot_player(channel_id, local_player_id)`**: Removes the remote player.

Key difference: On clients, bots are `RemotePlayer` with `human_controlled = false`, not `BotPlayer`. The AI brain only runs on the host.

### 9.3 Peer Management

```lua
BotSynchronizerHost.add_peer(channel_id)   -- new client connected
BotSynchronizerHost.remove_peer(channel_id) -- client disconnected
```

When a new peer connects, existing bots are communicated via profile sync. The `rpc_add_bot_player` RPC tells each client to create the bot's player object.

---

## 10. Relevance to BetterBots

### 10.1 Profile Constraints on Abilities

Since all ingame bots are `archetype = "veteran"`, the ability system only loads Veteran ability templates. The `can_activate_ability` condition reads the archetype from the profile to determine which abilities are available.

**Implications:**
- BetterBots currently only needs to handle Veteran abilities in vanilla (Stealth, Focus, Gunlugger/Broker variants)
- The `adamant` and `broker` profiles are defined but not yet accessible through the standard spawning path
- To test non-veteran abilities, you need either:
  - The Tertium4Or5 mod (which replaces profiles with real player profiles of various archetypes)
  - Direct spawning of misc/tutorial profiles (which include zealot, ogryn, psyker)

### 10.2 Tertium4Or5 Interaction

Tertium4Or5 replaces bot profiles with the player's actual character profiles (fetched via `fetch_all_profiles`). This means:
- Bots can be any archetype the player has characters for
- Bots inherit the player's equipped weapons (real weapon templates, not bot-specific ones)
- Bots still get `talents = {}` (Tertium4Or5 doesn't inject talents)
- The `bot_gestalts` field may be missing (since real profiles don't have it)

BetterBots must handle:
- Any archetype (not just veteran)
- Real weapon templates that may lack `attack_meta_data` or `ability_meta_data`
- Missing `bot_gestalts` (the BT has fallback behavior for `"none"` gestalt)

### 10.3 Weapon Template Constraints

Bot-specific weapons include `attack_meta_data` which the BT uses for ranged combat decisions. Player weapons pulled in by Tertium4Or5 may not have this field, causing bots to fall back to hip-fire only.

Similarly, `ability_meta_data` is what BetterBots injects for Tier 2 abilities. The BT node `bt_bot_activate_ability_action` reads this metadata to determine what inputs to queue.

### 10.4 Spawning Path for Testing

To test BetterBots with non-veteran bots:
- **With Tertium4Or5**: Bots spawn as player's characters (zealot, psyker, ogryn, etc.)
- **Without Tertium4Or5**: All bots are veteran -- only veteran abilities can be tested
- **Direct spawn**: `BotSpawning.spawn_bot_character("darktide_seven_02")` would spawn an ogryn bot, but this requires console/mod access

### 10.5 Profile Selection Has No Class Diversity

The spawning system always selects from `<tier>_bot_<1-6>`, which are all veteran. There is no logic to pick different classes based on party composition. This is a fundamental limitation that mods like Tertium4Or5 address.

---

## Source File Reference

| File | Path (relative to Darktide-Source-Code/) |
|---|---|
| Bot character profiles | `scripts/settings/bot_character_profiles.lua` |
| Ingame profiles | `scripts/settings/bot_profiles/ingame_bot_profiles.lua` |
| Misc profiles | `scripts/settings/bot_profiles/misc_bot_profiles.lua` |
| Training profiles | `scripts/settings/bot_profiles/training_ground_bot_profiles.lua` |
| Tutorial profiles | `scripts/settings/bot_profiles/tutorial_bot_profiles.lua` |
| Bot settings | `scripts/settings/bot/bot_settings.lua` |
| Bot manager | `scripts/managers/bot/bot_manager.lua` |
| Bot spawning | `scripts/managers/bot/bot_spawning.lua` |
| Player unit spawn manager | `scripts/managers/player/player_unit_spawn_manager.lua` |
| BotPlayer class | `scripts/managers/player/bot_player.lua` |
| Bot gameplay state | `scripts/managers/player/player_game_states/bot_gameplay.lua` |
| Bot group | `scripts/extension_systems/group/bot_group.lua` |
| Bot orders | `scripts/utilities/bot_order.lua` |
| Synchronizer (host) | `scripts/bot/bot_synchronizer_host.lua` |
| Synchronizer (client) | `scripts/bot/bot_synchronizer_client.lua` |
| Profile utils | `scripts/utilities/profile_utils.lua` |
| Game mode settings | `scripts/settings/game_mode/game_mode_settings_coop_complete_objective.lua` |
| Game parameters | `scripts/foundation/utilities/parameters/default_game_parameters.lua` |
| Dev parameters (max_bots) | `scripts/foundation/utilities/parameters/default_dev_parameters.lua` |
| Bot weapons dir | `scripts/settings/equipment/weapon_templates/bot_weapons/` |
| Network lookup | `scripts/network_lookup/network_lookup.lua` |
