# Vanilla Bot Capabilities Reference

What Darktide bots can and cannot do out of the box (v1.10, Feb 2026). Source-verified against decompiled code with community observations for context.

---

## Quick Reference

| Capability | Status | Summary |
|---|---|---|
| Light melee attacks | Full | Always available via `DEFAULT_ATTACK_META_DATA` fallback |
| Heavy/charged melee attacks | **No** | Bot melee weapons lack `attack_meta_data` entries for heavies |
| Weapon special actions | **No** | No BT node or input for weapon specials (bayonet, flashlight, etc.) |
| Push (shove) | Partial | Works, but only when outnumbered (>1 enemy) + target pushable + stamina |
| Block | Full | Active when `num_melee_attackers > 0` |
| Dodge (melee) | Partial | Random direction, cooldown-gated, only when melee attackers present |
| Dodge (AoE) | Full | Escape direction broadcast via bot group, randomized timing |
| Hip-fire shooting | Full | All bot ranged weapons support hip-fire |
| ADS / zoomed shooting | Full | Bot profiles set `ranged_gestalt = killshot` → `_should_aim` returns true |
| Charged shots | Full | Against armored targets, out-of-range targets, or flagged weapons |
| Reload | Full | Triggered when clip empty + reserve exists + not in melee |
| Overheat venting | Partial | Queues `reload` input when overheat in 50-99% range |
| Warp charge venting | **No** | No BT node; passive auto-vent only (3s delay) |
| Combat abilities | Minimal | Whitelist allows only `veteran_combat_ability` (works vs elites/specials) — all others blocked |
| Grenades / blitz | **No** | BT node exists but all templates have `template_name == "none"` |
| Revive downed allies | Full | High priority (BT position 2), but interrupted by nearby enemies |
| Rescue from disablers | Partial | Net/hound/trapper — deprioritized if enemies targeting bot |
| Ledge rescue | Partial | Only if no threats targeting bot (unless `force_aid` set) |
| Health station use | Full | Navigates to stations, uses when damaged above threshold |
| Health item pickup | Partial | Picks up deployables, but no healing item use on self/allies |
| Ammo pickup | Full | When ammo % below threshold and player has more |
| Mule item carry | **No** | Architecture exists but `bots_mule_pickup` never set on any pickup template |
| Weapon switching | Full | Auto-switches melee/ranged based on target type |
| Sprinting | **No** | `BotUnitInput` never sets sprint input — bots walk everywhere |
| Navigation / following | Full | GwNav A* pathfinding, fan formation, teleport at 40m |
| Cover seeking | Partial | Seeks cover from ranged enemies within 40m LoS |
| Tagging / pinging | **No** | No BT logic; responds to player tags for targeting only |
| Bot orders | Minimal | `pickup` and `drop` only — no "attack", "hold", "follow" |
| Coherency aura | Full | Provides Veteran Survivalist aura (ammo on elite kill) |

---

## Detailed Breakdown

### 1. Class and Equipment

**All vanilla bots are Veterans** — level 1 equivalent, zero talent nodes, no keystones, no curio bonuses. Weapons are fixed bot-specific templates (green-tier equivalent):

| Slot | Weapon templates | Notes |
|---|---|---|
| Melee | `bot_combataxe_linesman`, `bot_combatsword_linesman_p1/p2` | No `attack_meta_data` → light attacks only |
| Ranged (normal) | `bot_lasgun_killshot`, `bot_autogun_killshot`, `bot_laspistol_killshot` | Have `attack_meta_data` for aim/fire |
| Ranged (high-tier) | `high_bot_lasgun_killshot`, `high_bot_autogun_killshot` | Better stats, same actions |
| Ranged (Zola) | `bot_zola_laspistol` | DLC bot variant |

Since Patch #11 (Oct 2023), bots scale with difficulty: higher-tier cosmetics, increased health, more wounds. A stat bonus bug (bots not receiving wound scaling) was fixed in 1.10.0 (Feb 2026).

**Source:** `scripts/settings/equipment/weapon_templates/bot_weapons/`, `scripts/extension_systems/behavior/bot_profiles/`

**With mods:** Tertium 5/6 replaces bot profiles with player characters (all 6 classes, full talent trees, player-chosen weapons). BetterBots does not change equipment.

---

### 2. Melee Combat

#### What works

**Light attacks** — the only melee attack type. Bot melee weapons have no `attack_meta_data`, so `BtBotMeleeAction._choose_attack` falls back to:

```lua
DEFAULT_ATTACK_META_DATA = {
    light_attack = {
        arc = 0, penetrating = false, max_range = 2.5,
        action_inputs = {
            { action_input = "start_attack", timing = 0 },
            { action_input = "light_attack", timing = 0 },
        },
    },
}
```

The scoring system (`_choose_attack`) evaluates `arc` (sweep), `penetrating` (armor), `no_damage` (stagger-only), and `outnumbered` state — but with only one entry in the fallback table, the decision is trivial.

**Blocking** — active when `num_melee_attackers() > 0`. Uses `DEFAULT_DEFENSE_META_DATA`:
- `start_action_input = "block"`, `stop_action_input = "block_release"`
- `push = "heavy"` (can push even armored enemies)
- `push_action_input = "push"`

**Pushing** — conditional on: in melee range + outnumbered (>1 enemy) + target pushable + sufficient stamina. Monsters and armored enemies (unless `push_type == "heavy"`) are NOT pushable. Bots use heavy push by default, so armored enemies ARE pushable.

**Dodging** — `_update_dodge` triggers when `num_melee_attackers > 0`. Direction is random (50% away from target, 50% left/right). Validated against navmesh (2.25m raycast). Cooldown-gated with randomized intervals.

Full verified execution chain:
1. `bt_bot_melee_action._update_dodge` writes `escape_direction` + `dodge_t` to `bot_group_data.aoe_threat` (lines 568-572)
2. `bot_unit_input._update_movement` polls `aoe_threat` every frame (line 261): when `t > dodge_t && t < expires`, calls `self:dodge()` and applies escape direction to movement vector
3. `BotUnitInput.dodge()` sets `self._dodge = true` (line 131)
4. Next frame, `_update_actions()` queues `input.dodge = true` (line 74-77)
5. `Dodge.check()` validates: cooldown, weapon sticky state, move direction constraints (lines 24-97)
6. If valid → character executes dodge (same system as player dodge)

This is the same mechanism used for poxwalker bomber AoE escape (`BotGroup.aoe_threat_created()`) — melee dodge and AoE dodge share the infrastructure and compete for the single `aoe_threat` slot per bot.

**Community perception:** "Bots block excessively, sometimes circling poxwalkers while holding block." Shove is described as "rare." Dodge is "inconsistent." All accurate based on the cooldown gating and randomization.

#### What doesn't work

| Missing capability | Why | Source |
|---|---|---|
| Heavy/charged attacks | Bot melee weapons have no `attack_meta_data` entries for heavies | `bot_combataxe_linesman.lua` — no `attack_meta_data` field |
| Weapon special actions | No BT input for specials (bayonet, flashlight, etc.) | No `special_action` in bot action inputs |
| Armor-type adaptation | Only one attack available, no armor-specific selection | `DEFAULT_ATTACK_META_DATA` has single entry |
| Push-attack combos | Push and attack are separate decisions, no chaining | `_should_push` returns independently of attack |
| Bulwark flanking | No shield-side detection; bots attack shield face | No angle-aware targeting in melee action |

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action.lua`

**With mods:** The melee action node's `_choose_attack` scoring is fully capable — it handles arc, penetrating, outnumbered, armor-type. But no player melee weapon has `attack_meta_data` either (only bot weapons do), so Tertium 5/6 bots wielding player weapons also fall back to light-only. Fixing this requires `attack_meta_data` injection for each player melee weapon template — same pattern as `ability_meta_data` injection in BetterBots.

---

### 3. Ranged Combat

#### What works

**Hip-fire** — all bot ranged weapons support `shoot_pressed` → `action_shoot_hip`. Default gesture is `"none"` (hip-fire).

**ADS / zoomed shooting — works in vanilla.** All bot profiles set `bot_gestalts.ranged = behavior_gestalts.killshot` (`ingame_bot_profiles.lua:33-35`). This gestalt is passed through the spawn chain (`unit_templates.lua:579` → `BotBehaviorExtension._init_blackboard_components` → `behavior_component.ranged_gestalt`). The shoot action's `_should_aim()` reads this gestalt, looks up `gestalt_behaviors["killshot"]` which has `wants_aim = true`, and triggers the aim/zoom sequence. Bot ranged weapons have full `action_zoom` → `action_shoot_zoomed` → `action_unzoom` chains.

Community claims bots "hip-fire only" — **this is incorrect for vanilla bots**. Vanilla bot profiles explicitly enable ADS. However, Tertium 5/6 custom profiles may lack `bot_gestalts`, causing fallback to `NO_GESTALTS` (`ranged = behavior_gestalts.none`), which disables ADS for modded bots.

**Charged shots** — `_should_charge()` returns true when:
- `can_charge_shot` in weapon's `attack_meta_data`
- Target in charged range but not normal range
- Target armored AND `charge_against_armored_enemy` flag set
- OR `always_charge_before_firing` flag

**Accuracy** — pseudo-random with radius thresholds:
- Min radius: ~2.5° → always fires (guaranteed hit within this cone)
- Max radius: ~11.25° → never fires (too inaccurate)
- Between: linear interpolation, accuracy accumulates over aim time
- Minimum `aim_done` duration: 0.2s before first shot

**Aim speed** scales with difficulty: `{10, 10, 12, 20, 20}` (difficulty 1-5).

**Obstruction detection** — raycast from camera along aim direction. Ignores allies and ragdolls. Checks every 0.2-0.3s. If target obstructed for >3s, bot disengages.

**Reload** — triggered when clip empty + reserve ammo exists + not in melee range.

**Overheat venting** — condition `should_vent_overheat` checks overheat % in range [0.5, 0.99]. Action queues `"reload"` input (context-switches to vent behavior). BT arranges weapon switch before venting.

#### What doesn't work

| Missing capability | Why | Source |
|---|---|---|
| ADS for Tertium 5/6 bots | Custom profiles may lack `bot_gestalts` → fallback to `none` → no ADS | `bot_behavior_extension.lua:91` — falls back to `NO_GESTALTS` when nil |
| Player weapon compatibility | No player weapon has `attack_meta_data` — bots fall back to hardcoded names | See "Player weapon `attack_meta_data` gap" section below |
| Warp charge venting | BT vent node sends wrong action_input (`reload` vs `vent`) | Issue #30 |
| Sustained-fire execution | Vanilla queues the fire action but never mirrors the required raw hold input back through `BotUnitInput`, so stream/full-auto paths collapse into taps. BetterBots `#87` now bridges held inputs for an allowlist of sustained-fire templates without changing path selection policy. | `bot_unit_input.lua`, `player_unit_action_input_extension.lua`, `bt_bot_shoot_action.lua` |
| Suppressive fire | No concept of suppression output | No suppression scoring |
| Target leading (projectile) | Ballistic prediction exists but limited | `_ballistic_shoot_angle` only for gravity projectiles |
| Ammo conservation | Bots pick up ammo they don't need (infinite effective ammo) | `can_loot` checks ammo %, but bot ammo rarely depletes |
| Weakspot / headshot aim | Vanilla bots aim `j_spine` (chest) for every shot, so finesse stats and weakspot blessings/perks/talents are wasted. BetterBots `#91` partially overrides this for lasguns, autoguns, bolters, and stub revolvers by injecting `{ "j_head", "j_spine" }` into `attack_meta_data.aim_at_node` when unset. BetterBots `#92` then corrects the known edge cases on target acquisition: Scab Mauler is pinned to `j_spine`, Bulwark is pinned to `j_head` only when the shield is open or the bot is outside the 70° block cone, and Crusher is **provisionally** pinned to `j_head` only from the rear arc as a stand-in for the claimed back-of-head weakspot. The Crusher path is explicitly assumption, not rig-verified fact. | `bt_bot_shoot_action.lua:53,282-285`. Issues #91 and #92. |

**Note on "infinite ammo":** Community claims bots have infinite ammo. **Verified false.** Bots consume ammo per shot through the identical `ActionShoot._spend_ammunition()` path as players (`action_shoot.lua:469-553`). No `is_human_controlled` exemption exists anywhere in the ammo deduction chain. The only infinite ammo flag (`infinite_ammo_reserve`) is exclusive to prologue missions (`prologue_mission_templates.lua:18`). Bots appear to have infinite ammo because: (a) conservative firing behavior with accuracy gating, (b) ammo pickup priority when below threshold, (c) high reserve on bot weapons.

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action.lua`, `bot_actions.lua`

**With mods:** BetterBots adds warp weapon peril block (≥97% → block weapon attacks). Issue #30 tracks proper vent support.

#### Player weapon `attack_meta_data` gap

**Only 4 bot-specific ranged weapons have `attack_meta_data`.** Zero player weapons do — not lasguns, autoguns, plasma guns, bolters, flamers, or anything else. When Tertium 5/6 gives bots player weapons, the shoot action falls back through hardcoded names:

```lua
-- bt_bot_shoot_action.lua:34-80 fallback chain
attack_meta_data = weapon_template.attack_meta_data or EMPTY_TABLE   -- always EMPTY_TABLE for player weapons
fire_action_input  = meta.fire_action_input     or attack_action.start_input or "shoot"
aim_action_input   = meta.aim_action_input      or aim_action.start_input    or "zoom"
aim_fire_action_input = meta.aim_fire_action_input or aim_attack_action.start_input or "zoom_shoot"
charge_action_input = meta.charge_action_input  or "brace"
can_charge_shot    = meta.can_charge_shot       -- nil → never charges
always_charge_before_firing = meta.always_charge_before_firing  -- nil → doesn't know it must charge
```

These fallbacks (`"shoot"`, `"zoom"`, `"zoom_shoot"`, `"brace"`) happen to match bot weapon templates (which were designed for them), but player weapons use diverse naming conventions:

| Weapon family | Hip-fire input | ADS input | Charge | Bot compatible? |
|---|---|---|---|---|
| Bot lasgun/autogun | `shoot_pressed` → `action_shoot_hip` | `zoom` → `zoom_shoot` | N/A | **Yes** (designed for bots) |
| Player lasgun | `shoot_pressed` → `action_shoot_hip` | `zoom` → `zoom_shoot` | N/A | **Likely yes** (names match) |
| Plasma gun | `shoot_charge` → `action_charge_direct` (auto-fires) | `brace` → `shoot_braced` | Built into fire path | **No** — fallback `"shoot"` doesn't exist |
| Flamer | `shoot_pressed` (hold) | — | N/A | **Probably** (name matches) |
| Bolter | `shoot_pressed` | `zoom` → `zoom_shoot` | N/A | **Probably** (names match) |

**Plasma gun failure case (verified):** The plasma gun requires charging for every shot. Its fire path is: `shoot_charge` → `action_charge_direct` (kind: `overload_charge`) → auto-charges → `running_action_state_to_action_input.fully_charged` auto-injects `charged_enough` → transitions to `action_shoot` (fires projectile). `action_shoot` has `start_input = nil` — it's unreachable except via the charge state machine. The bot's fallback `"shoot"` doesn't exist in the plasma gun's `action_inputs`, so the parser silently drops the request. **The bot never fires.**

**Fix approach:** Inject `attack_meta_data` per player weapon family, same pattern as `ability_meta_data` injection. Example for plasma:

```lua
plasmagun_p1_m1.attack_meta_data = {
    fire_action_input = "shoot_charge",           -- queue this; weapon auto-charges then auto-fires
    fire_action_name = "action_charge_direct",     -- the "fire" action is the charge start
    aim_action_name = "action_charge",             -- ADS charge (brace path)
    aim_fire_action_name = "action_shoot_charged", -- ADS fire
    aim_action_input = "brace",
    aim_fire_action_input = "shoot_braced",
    unaim_action_input = "brace_release",
}
```

The same `attack_meta_data` gap exists for melee: no player melee weapon has it either. Bot melee weapons lack it too (only bot ranged weapons have it). The melee action falls back to `DEFAULT_ATTACK_META_DATA` (light attack only) for ALL weapons without metadata — both bot and player.

**Impact:** This is a cross-cutting issue affecting all player weapons when used by bots via Tertium 5/6. Weapons whose action input names happen to match the hardcoded fallbacks work by coincidence; others (plasma, potentially others) silently break.

---

### 4. Combat Abilities (Ultimates)

#### Status: Blocked

The full activation infrastructure exists:

1. BT node `activate_combat_ability` (priority 8 in selector)
2. Condition `can_activate_ability` reads template, validates metadata, checks action input validity
3. `BtBotActivateAbilityAction` queues inputs via `action_input_extension:bot_queue_action_input()`
4. `ActionInputParser` drains queue → ability fires

**The block:** `bt_bot_conditions.can_activate_ability` has a hardcoded whitelist at line 98 that returns `false` for everything except `zealot_relic` and `veteran_combat_ability`. Of these two, `veteran_combat_ability` is still active — three veteran abilities inherit from it (`veteran_combat_ability_stance`, `veteran_combat_ability_stance_improved`, `veteran_combat_ability_shout`), and the condition function `_can_activate_veteran_ranger_ability` works correctly (checks for elite/special targets). However, `zealot_relic` is now a Tier 3 item ability (no `ability_template` field), so that branch is effectively dead.

**Additional blockers:**
- Many templates lack `ability_meta_data` (Tier 2 problem)
- Item-based abilities have no `ability_template` field at all (Tier 3 problem)
- No per-ability decision logic — vanilla only checks `enemies_in_proximity > 0`
- The whitelist blocks ALL abilities except the two listed — so even abilities with full infrastructure (metadata, inputs, actions) are gated out

**Community note:** A Nov 2025 forum post suggests bots "used to" activate abilities more broadly. The narrow whitelist supports this interpretation — the BT infrastructure handles arbitrary templates, but the condition guard artificially limits activation to two.

**Source:** `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua:59-100`

**With mods:** BetterBots removes the whitelist, injects missing `ability_meta_data`, adds 18 per-template heuristic functions, and implements a Tier 3 item-based fallback system. See CLAUDE.md tier table for full status.

---

### 5. Grenades / Blitz

#### Status: Not implemented

BT node `activate_grenade_ability` exists (priority 9) and uses the same `can_activate_ability` gate. Even if the condition were bypassed, all 19 grenade/blitz templates have `template_name == "none"` — there is no `ability_template` to read metadata from, and `ActionInputParser` cannot process the request.

The one exception is `adamant_whistle` (Ogryn rock throw), which has an `ability_template` field — but it's still blocked by the whitelist.

**Source:** `docs/classes/grenade-inventory.md` for full template inventory

**With mods:** BetterBots issue #4 tracks grenade support. Requires item-based fallback similar to Tier 3 abilities.

---

### 6. Revive and Rescue

#### What works

**Revive** (BT priority 2 — very high):
- Condition `can_revive`: ally exists + need_type `knocked_down` + reached aid destination
- Action: `BtBotInteractAction` with interaction_type `"revive"`, aiming at `j_head`

**Net removal** (priority 3): need_type `netted`

**Ledge rescue** (priority 4): need_type `ledge` — **additional check**: `_is_there_threat_to_aid` blocks rescue if enemies target the bot (unless `force_aid`)

**Hogtied rescue** (priority 5): need_type `hogtied`

**Ally aid navigation** — destination computed by `_refresh_destination` in `BotBehaviorExtension`, stored in `behavior.target_ally_aid_destination`. Flat distance + z-offset thresholds for "reached" check.

**BotGroup coordination** — tracks per-ally stickiness to prevent all bots from competing for the same revive. `is_prioritized_ally(unit, target_ally)` assigns one bot per downed ally.

#### Known issues

| Problem | Cause | Source |
|---|---|---|
| Start-stop revive loop | Enemies interrupt → bot breaks off → re-evaluates → restarts | Community reports (Steam, Oct 2023) |
| No blocking during revive | Revive is an interaction, not a combat action — no defense | `BtBotInteractAction` has no block logic |
| Chain-death cascade | All bots hard-focus first downed ally | BotGroup prioritization doesn't prevent simultaneous attempts well enough |
| Poor disabler rescue | Trash mobs draw melee action over rescue | Melee action priority can override rescue when enemies nearby |

**Patch history:**
- 1.0.25 (Feb 2024): Bots no longer prioritize reviving knocked bots when too many enemies nearby
- Bound by Duty (Sep 2024): Improved bot code for rescue during melee

**Source:** `scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua`, `bt_bot_interact_action.lua`

**With mods:** BetterBots adds revive protection (#20) — blocks ability activation when `current_interaction_unit ~= nil`, preventing abilities from interrupting ongoing revives.

---

### 7. Navigation and Movement

#### What works

**Pathfinding** — GwNav A* with live path updates. NavTag layers support doors, jumps, drops, ladders, damage_drops, leap_of_faith. Fatal drops prevented (calculates fall damage vs health).

**Follow behavior** — destination refresh every 1.0-1.5s (randomized). Fan formation 3m from follow point, 1m spacing per bot. Cluster position calculated ahead of player velocity.

**Destination priority** (highest to lowest):
1. Revive with urgent target
2. Priority target enemy
3. Urgent/priority target enemy
4. Ally needing aid
5. Mule pickup (dead code — no pickup templates set `bots_mule_pickup`)
6. Health station
7. Health deployable
8. Ammo pickup
9. Follow position

**Teleportation** — two triggers:
- `is_too_far_from_ally`: ≥40m from ally + no aid needed + not ahead
- `cant_reach_ally`: >1 failed paths (behind) or >5 (elsewhere) + >5s since success

**Obstacle handling** — lower box test (jump if clear above), upper box test (crouch if clear below). Movement speed smoothly decelerates near goal.

**Transitions** — player-generated (jump/fall recorded, transition created on landing) + level-placed (`BotJumpAssist` components). Ladder: bidirectional traversal. Timeout: 10s general, force-teleport 5s for jumps/drops/leaps.

#### Known issues

| Problem | Cause | Community source |
|---|---|---|
| Stuck on terrain | Ledges, elevators, shuttles, cramped areas | Steam forums (Dec 2022) |
| Stuck in crouch | Crouch state not cleared | Steam forums (Dec 2022) |
| Stand in fire/AoE | AoE dodge is for discrete threats, not persistent ground effects | Steam forums (Jul 2025) |
| Stand in open during gunfire | Cover seeking limited to nav spawn points | Fatshark forums (Nov 2025) |

**Patch history:**
- Patch #4 (Jun 2023): Fixed multiple stuck spots across maps
- Patch #11 (Oct 2023): Fixed ledge walk-off near cargo elevator
- Traitor Curse Part II (Jun 2024): Improved navigation around destructible props
- Traitor Curse Anniversary (Sep 2024): Fixed areas where bots couldn't path to players

**Source:** `scripts/extension_systems/behavior/bot_behavior_extension.lua`, `scripts/extension_systems/behavior/utilities/bot_navigation.lua`

**With mods:** BetterBots charge/dash abilities move bots off navmesh temporarily; live path recalculates on next frame. No navigation changes otherwise.

---

### 8. Dodge and Block (Detail)

#### Melee dodge

Triggered by `BtBotMeleeAction._update_dodge` when:
1. Not prioritizing ally rescue
2. No active AoE threat (avoids conflicting escape directions)
3. Random cooldown has elapsed
4. `num_enemies_in_proximity > 0`
5. `num_melee_attackers() > 0`

Direction: 50% chance away from target, 50% chance left or right (random). Validated via navmesh raycast (2.25m). If valid: writes to `bot_group_data.aoe_threat` with randomized `dodge_t` (0-0.5s). If invalid: 0.1s cooldown before next check.

The dodge is further gated by `cant_push` state — if the bot can't push (low stamina, unpushable target), dodge frequency increases via `CANT_PUSH_DODGE_CHECK_RANDOM_RANGE`.

**Key insight:** Melee dodge piggybacks on the AoE threat infrastructure. The actual dodge input is queued by `BotBehaviorExtension` when `aoe_threat.dodge_t` is reached, not by the melee action directly. This means only one dodge direction can be active at a time (AoE and melee compete).

#### AoE dodge

Triggered externally by the bot group when an AoE threat is detected. Escape direction is broadcast to affected bots. Dodge input queued at randomized time (0-0.5s delay). Single threat tracked per bot — later threats overwrite earlier ones.

#### Block

Active during the melee action's defense state machine:
1. If `should_defend` AND not defending → start block
2. If defending → update (push or release)
3. If attacking → continue attack
4. If in range → start attack
5. If in engage range → wants engage
6. Else → may disengage

Block is continuous while `num_melee_attackers > 0`. Release when no attackers OR when push conditions met.

**Source:** `scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_melee_action.lua:504-581`

**With mods:** BetterBots adds ability suppression (#11) — blocks ability activation when bot is dodging, falling, lunging, jumping, on ladder, or on moving platform.

---

### 9. Perception and Target Selection

#### How bots select targets

Reevaluation timer: 0.3s (rescores valid targets periodically, rescores current between).

**Valid targets:** in `aggroed_minion_target_units` (alerted enemies) or player breed.

**Scoring system** — dual-scored for melee and ranged:

| Weight | Category | Value |
|---|---|---|
| **Common** | | |
| 1.0 | Opportunity (special/player) | Flat bonus |
| 4.0 | Priority (disabling ally) | Ramps over 2s |
| 2.0 | Monster (monster tag + no proximity enemies) | Flat bonus |
| 0.2 | Current target (stickiness) | Prevents flip-flopping |
| **Melee-specific** | | |
| 5.0 | Gestalt weight (breed-specific) | Higher = more desirable |
| 1.0 | Slot targeting (targeting bot) | 0.8 if targeting ally |
| 3.0 | Distance (max at 3m, zero at 8m) | Closer = higher |
| **Ranged-specific** | | |
| 5.0 | Gestalt weight (breed-specific) | Higher = more desirable |
| 1.0 | Distance (max at 6m, zero at 4m) | Closer = higher |
| 1.0 | Line of sight | 1.0 if LoS, 0 if blocked |

Melee and ranged scores computed independently; higher wins and determines target type (`"melee"` or `"ranged"`), which drives weapon switching.

#### Proximity detection

- 5m broadphase radius, max 10 enemies
- Update every 0.5-1.0s (randomized)
- Tracks: `challenge_rating_sum`, `num_enemies_in_proximity`
- Used by: threat assessment, heuristic triggers, melee engage decisions

#### Player tag response

When a player tags an enemy, it becomes a priority/opportunity target. Bots will snipe tagged specials/elites with near-perfect aim — widely considered their strongest cooperative feature.

**Source:** `scripts/extension_systems/behavior/utilities/perception/bot_target_selection.lua`

**With mods:** BetterBots reads perception fields for heuristic triggers (target distance, enemy counts, challenge rating). Does not modify perception.

---

### 10. Items and Resources

#### What works

| Item type | Can pick up | Can use | Notes |
|---|---|---|---|
| Ammo | Yes | Auto (reload) | Threshold: combat 50-80%, peacetime 100% |
| Health deployable | Yes | Auto | Only if `allowed_to_take_health_pickup` |
| Health station (Medicae) | N/A | Yes | Navigates to station, uses when damaged above threshold |
| Mule items (scripture/grimoire) | **No** | **No** | Dead code: `bots_mule_pickup` never set on any pickup template |
| Healing items (stim, medkit) | **No** | **No** | No BT node for pocketable item use |
| Grenades | **No** | **No** | No pickup or throw logic |
| Pocketable items | **No** | **No** | No `pocketable_ability_action` in BT |

**Mule items (scriptures/grimoires) — DEAD CODE.** `BotGroup` initializes `_available_mule_pickups` by scanning all pickup templates for `bots_mule_pickup == true` (`bot_group.lua:22-30`). **No pickup template sets this flag** — `grimoire_pickup.lua` and `tome_pickup.lua` define `interaction_type = "pocketable"` with no `bots_mule_pickup` field. The full chain exists (perception → destination priority 5 → `can_loot` condition → interaction), but it never activates because the candidate pool is permanently empty.

**Medicae controversy:** Bots use Medicae stations and can drain charges before players heal. Especially problematic with grimoire corruption (continuous health drain → repeated Medicae use). Since Bound by Duty (Sep 2024), bots no longer use Medicae in Mortis Trials.

**Poxburster interaction:** Since Bound by Duty, bot ranged fire no longer targets Poxbursters (prevents accidental detonation). Community reports this as a regression — bots now ignore Poxbursters entirely rather than shooting them at safe distance.

**Source:** `bt_bot_conditions.can_loot`, `bt_bot_interact_action.lua`

**With mods:** BetterBots now activates side-mission book mule pickup (tomes/scriptures always, grimoires opt-in) by patching the dead vanilla metadata path, and still adds weapon switch lock during Tier 3 item-ability sequences.

---

### 11. Communication and Social

| Feature | Status | Notes |
|---|---|---|
| Tag/ping enemies | **No** | No BT logic for tagging |
| Respond to player tags | **Yes** | Tagged enemy becomes priority target |
| Voice commands | **No** | No VO generation for bots |
| Emotes | **No** | No emote logic |
| Call for help | **No** | No distress signals |
| Bot orders | **Minimal** | Only `pickup` and `drop` — no attack/hold/follow |

**Group coordination** is entirely automatic and invisible:
- BotGroup manages follow target, formation points, priority ally tracking, pickup orders, AoE threat sharing
- No visible communication to the player

**Source:** `scripts/extension_systems/behavior/utilities/bot_group.lua`

**With mods:** BetterBots does not add communication. Issue #16 tracks bot pinging.

---

### 12. Special Behaviors

#### Coherency aura

Bots count toward the coherency system, providing toughness regeneration. Since all vanilla bots are Veterans, they provide the Survivalist aura (ammo on elite kill). Auras don't stack — 3 Veteran bots give the same aura as 1.

#### Cover seeking

When in line of fire from ranged enemies (40m range check), bots seek cover at nav spawn points. Tracks `in_cover` per bot to avoid stacking at the same cover point. Limited by available spawn points — open areas have no cover.

#### Hold position / stay near

Can be set programmatically via `bot_behavior_extension:set_hold_position()` and `set_stay_near_player()` (5m default). Not player-accessible in vanilla — no UI or command for this.

#### Engagement spacing

Bots distribute around targets during boss fights (flanking if breed has `bots_should_flank`). Melee engage range: 6-12m depending on context (`math.huge` for priority targets).

**Source:** `scripts/extension_systems/behavior/bot_behavior_extension.lua`

---

### 13. Difficulty Viability

**Community consensus:**

| Difficulty | Viability | Notes |
|---|---|---|
| Sedition (1) | Fully viable | Bots handle well |
| Uprising (2) | Fully viable | Minor issues |
| Malice (3) | Viable with babysitting | Player must compensate for bot limitations |
| Heresy (4) | Marginal | Bots frequently go down; "practically suicidal" |
| Damnation (5) | Not viable | Bots die too fast, can't handle threat density |

**Root causes of high-difficulty failure:**
1. Light attacks only → poor damage output against armored/tough enemies
2. No abilities → missing damage spikes, crowd control, survival tools
3. No grenades → can't stagger hordes or burst specials
4. Green-tier weapons → insufficient damage scaling
5. Zero talents → no keystones, no defensive passives
6. Stand in AoE → persistent damage accumulates
7. Chain-death → one bot down cascades to team wipe

---

### 14. Comparison: Vermintide 2 vs Darktide Bots

| Feature | VT2 | Darktide | Notes |
|---|---|---|---|
| Class variety | All classes | Veteran only | VT2 bots use player roster |
| Equipment | Player gear + talents | Fixed green-tier, zero talents | Major disparity |
| Combat abilities | Use active abilities | `veteran_combat_ability` only (vs elites/specials) | VT2 had working ability triggers for all classes |
| Heavy attacks | Available with mods | **No** (weapon metadata missing) | VT2 modders solved this |
| Item carrying | Tomes + grimoires | **Cannot** (dead code) | VT2 bots carry; Darktide architecture exists but unpopulated |
| Healing items | Pick up and use | **Cannot** | VT2 bots managed potions/healing |
| Tagging | With mods | **No** | VT2 "Bot Improvements" mod |
| Difficulty ceiling | Legend/Cataclysm (with mods) | Malice (vanilla) | VT2 bots far more capable |
| Community sentiment | "Better than 80% of players" | "Completely useless placeholder" | Stark contrast |

**VT2 "Bot Improvements - Combat" mod** addressed: better melee choices, ping elites, healing threshold control, stop chasing distant specials, ignore line of fire, stop focusing bosses, improved revive, improved ability usage. This mod is the spiritual predecessor to BetterBots and other Darktide bot mods.

---

### 15. Fatshark Bot Patch History

| Patch | Date | Changes |
|---|---|---|
| #4 (Blessings of the Omnissiah) | Jun 2023 | Fixed stuck spots on multiple maps; bots follow correctly |
| #11 | Oct 2023 | Difficulty scaling (cosmetics, health, wounds); fixed ledge walk-off |
| 1.0.22 | Dec 2023 | Fixed crash when bot revives another bot |
| 1.0.25 | Feb 2024 | Bots don't prioritize reviving knocked bots when many enemies nearby |
| Traitor Curse Part II | Jun 2024 | Improved navigation around destructible props |
| Traitor Curse Anniversary (#15) | Sep 2024 | Fixed area where bots couldn't path to players |
| Bound by Duty | Sep 2024 | No Medicae in Mortis Trials; no targeting Poxbursters; ignore explosive barrels; improved melee rescue code |
| 1.10.0 (No Man's Land) | Feb 2026 | Fixed missing stat bonuses (wound scaling) |

**Developer philosophy (Fatshark):** Bots are designed as "placeholders for teammates," not full AI companions. A developer stated: "Any dev can make a bot that shreds enemies, but it's harder getting them into the ideal 'less than ideal but not harrowingly bad' state." Bot AI is not a development priority — focus is on cooperative multiplayer.

---

### 16. Why the Ability Infrastructure Was Built but Never Activated

The surprising finding from decompiling Darktide's source is how much bot ability infrastructure Fatshark built and never turned on. The BT nodes, action queuing, ability extension — all work end-to-end. Only a hardcoded whitelist in `can_activate_ability` and missing metadata on some templates prevent bots from using abilities. There is no single explanation for this gap; five factors converged.

#### 1. Vermintide 2 codebase inheritance

Both games run on the same Stingray engine (heavily modified in-house). Vermintide 2 bots use career abilities — support was added post-launch and [documented in a Dec 2018 dev blog](https://www.vermintide.com/news/2018/12/17/dev-blog-how-bots-work-in-vermintide-2). The BT node pattern (`BtBotActivateAbilityAction`), the action input queue, and the condition-guard architecture are standard engine infrastructure that carried over. A Fatshark developer confirmed on Discord that Darktide uses "an upgraded version of the same engine," though "nothing lifted from Vermintide will work on it without significant rewriting." The architecture transferred; the ability-specific logic needed rewriting that was never completed.

#### 2. The catastrophic launch forced triage (Nov 2022 – late 2023)

Darktide launched in a widely criticized unfinished state. In January 2023, CEO Martin Wahlund issued a [public apology](https://www.shacknews.com/article/133824/warhammer-40000-darktide-launch-apology), pausing all new content to focus on the crafting system, progression loop, and stability. Seasonal content was scrapped, the Xbox release delayed indefinitely, and cosmetic releases suspended. Solo mode — described as being in "final stages of testing" 10 days before launch — was deprioritized to "not a priority" by March 2023. Bot abilities are solo-mode infrastructure, so they were shelved along with it.

#### 3. The ability system was a moving target

The [Class Overhaul (Patch 13, Oct 2023)](https://www.playdarktide.com/news/dev-blog-class-overhaul) completely redesigned abilities, adding talent trees with 3 blitz abilities, 3 combat abilities, and 3 keystones per class. This overhaul was reportedly in development since before launch. Writing bot heuristics for the old ability system would have been discarded. After the overhaul, new classes kept arriving (Arbites in 2025, Hive Scum as DLC), each requiring new bot profiles. The ability template landscape never stabilized enough to justify bot ability work.

#### 4. Intentional design philosophy: bots as placeholders

This is the only area with direct developer statements:

> "Verm bots aren't designed to be team mates but placeholders for team mates. It's easy to make great bots that can carry. It's hard to make average ones. But average is the goal."
> — Hedge (Fatshark CM), [Steam forums](https://steamcommunity.com/app/1361210/discussions/0/5792223132453708488/)

> "We don't spend a great deal of time with bot AI, our main focus is coop over anything else. [...] It's harder getting them in to the ideal 'less than ideal but not harrowingly bad' state honestly."
> — Fatshark developer, [Steam forums](https://steamcommunity.com/app/1361210/discussions/0/3737376536261988606/)

Community members report that bots are "intentionally weak as to not create incentive to forgo the random matchmaking." The whitelist is not a forgotten TODO — it is a deliberate gate that says "these abilities are safe for bots; the rest we haven't QA'd and don't want to risk."

#### 5. Dedicated server architecture complications

Vermintide 2 used peer-to-peer networking — the host ran bots locally using the host's characters. Darktide runs on dedicated servers, raising the question of whose equipment the bots use and where the AI computation runs. Fatshark acknowledged that solo mode would require "hosting locally your own instance with bots" which "will increase performance cost." Running bot AI server-side for a single player is not cost-effective; running it client-side requires architectural changes that were never prioritized.

#### Synthesis

The infrastructure exists because it is standard engine engineering. When you build a behavior tree with ability activation nodes, you build them generically — `BtBotActivateAbilityAction` works for any ability template. The condition guard is just a lookup table. Building the scaffolding is cheap; populating it for each ability with QA'd heuristics and metadata is expensive.

It was never activated because everything conspired against it: a launch crisis that deprioritized solo-mode features, an ability system redesigned 11 months post-launch, a design philosophy that actively resists capable bots, and a server architecture that made solo play harder than in VT2. The three unused difficulty tiers in bot code (`low_bot`/`medium_bot`/`high_bot`) and the dead mule-item pickup system (section 10) suggest even more ambitious plans that were similarly abandoned.

**What Fatshark has never addressed:** No developer has directly explained why `can_activate_ability` has a whitelist that only allows two templates, acknowledged the built-but-unused infrastructure publicly, or published any technical documentation about the bot BT architecture. Solo mode remains undelivered as of early 2026, over three years after being promised at launch.

---

### 17. What BetterBots Changes (Summary)

For context, here is what BetterBots modifies relative to vanilla:

| Area | Vanilla | BetterBots |
|---|---|---|
| Combat abilities | 0 working (whitelist blocks all) | 15+ abilities across 5 classes |
| Decision logic | `enemies_in_proximity > 0` | 18 per-template heuristic functions |
| Item abilities | Not possible | Tier 3 wield/use/unwield state machine |
| Revive protection | Abilities can interrupt revives | Blocked during interactions (#20) |
| Ability suppression | N/A | Blocked during dodge/fall/lunge/jump (#11) |
| Warp weapon safety | Bots can explode at 100% peril | Blocked at ≥97% peril (#27) |
| Event logging | None | JSONL event stream for telemetry |

**Unchanged:** melee combat, ranged combat, navigation, weapon switching, perception, revive mechanics, item pickup, group coordination.

---

## Moddability Assessment

What a DMF mod can and cannot fix. DMF hooks can replace/wrap any Lua function and mutate any `require()` singleton table. They cannot modify C++ engine code, add new animations, change ECS component schemas, or alter navmesh data.

### Key modding primitive

`action_input_extension:bot_queue_action_input(component_id, action_input, raw_input)` — queues ANY action input for bots through the same `ActionInputParser` ring buffer that handles player inputs. This is the same mechanism BetterBots uses for Tier 2 abilities and Tier 3 item fallback. If the target weapon/ability template defines the action input and the current weapon state allows chaining to it, the input fires.

**Critical detail:** For bots, the parser calls `_update_bot_action_input_requests` (line 647) which bypasses the human input sequence system entirely — no button holds, no duration checks, no `auto_complete`. It directly queues the named action input via `_queue_action_input`. This means bots don't need to "hold" buttons for charged/heavy attacks; they just queue the discrete input name with appropriate timing delays between sequential inputs.

### Moddability by capability

| # | Missing capability | Moddable? | Confidence | Approach | Blockers |
|---|---|---|---|---|---|
| 1 | **ADS for Tertium 5/6 bots** | **Yes** | High | Tertium 5/6 custom profiles may lack `bot_gestalts`, causing `ranged_gestalt = none` (no ADS). Fix by injecting `bot_gestalts.ranged = "killshot"` into custom profiles, or hook `_init_blackboard_components` to force the gestalt. Vanilla bots already ADS — this is only needed for modded profiles. | None — decision logic already exists in vanilla shoot action |
| 2 | **Mule items (scriptures/grimoires)** | **Yes** | Medium-High | Set `bots_mule_pickup = true` on pickup templates, fix field name mismatch (`bot_group.lua:26` reads `pickup_settings.slot_name` but pickup templates use `inventory_slot_name`), and backfill `_available_mule_pickups[slot_name]` because vanilla `BotGroup.init` iterates `pairs(Pickups)` over the registry wrapper instead of individual pickup definitions. BetterBots now ships this via template mutation, init/live-sync cache backfill, and a grimoire opt-in toggle. | Vanilla init path leaves mule slot caches empty unless a mod repairs them |
| 3 | **Heavy melee attacks** | **Yes** | High | Inject `attack_meta_data` with heavy/charged entries into bot melee weapon templates via `require()` mutation. Bot melee weapons (e.g. `bot_combatsword_linesman_p1`) already have full `action_left_heavy` action definitions and `heavy_attack` chain entries — only the metadata table that drives `_choose_attack` scoring is missing. | Need to map correct `action_inputs` timings per weapon; scoring utility already handles arc/penetrating/outnumbered |
| 4 | **Weapon specials** | **Yes** | Medium-High | Queue `bot_queue_action_input("weapon_action", "special_action", nil)`. Bot melee weapons have `special_action` → `action_parry_special` with chain entries from most melee states (idle, after light, during block). | Decision logic needed (when to parry vs block vs attack); `action_input_is_currently_valid` gates on current weapon state; not all bot weapons may have useful specials |
| 5 | **Healing item self-use** | **Partial** | Medium | Syringe pocketables have full action templates: `use_self` → `action_use_self` (kind `"use_syringe"`, 1.9s). Same wield → use → unwield pattern as Tier 3 item fallback. Could queue via `bot_queue_action_input`. | **Inventory gate**: bots never pick up pocketables. Requires either (a) new pickup BT logic, (b) inventory injection at spawn, or (c) player order → forced pickup. Also needs health threshold decision logic. |
| 6 | **Healing item give-to-ally** | **Partial** | Medium | Syringe template has `aim` → `use_ally` path. Bot would need to aim at target ally, then queue `use_ally`. Smart targeting validation (`validate_target_func`) checks target is alive + not disabled. | Same inventory gate as #5, plus target selection/aiming complexity |
| 7 | **Bot tagging/pinging** | **Partial** | Medium | `SmartTagSystem` processes tags via RPC (`rpc_request_set_smart_tag`). In solo play the player IS the server, so the mod could call the system directly. Would need to hook BT evaluation to inject tag requests when bots detect priority targets. | RPC layer may reject bot-originated requests; no `smart_tag_extension` on bot units; would need careful integration with perception scoring |
| 8 | **Poxburster targeting** | **Yes** | High | `chaos_poxwalker_bomber_breed.lua:39` sets `not_bot_target = true`, checked by `bot_target_selection_template.lua:185` and `bot_perception_extension.lua:170,258`. Hook the breed template to conditionally remove the flag, or hook perception to override the filter at safe range (>8m shoot, <5m suppress). See #34. | None — exclusion mechanism identified |
| 9 | **Bot class variety** | **Yes** | High | Hook bot profile selection to inject non-Veteran profiles. Already done by Tertium 5/6 mods — proven approach. | Profiles need valid archetype/weapon/talent data; crash risk with incomplete profiles (Tertium 5 crash on Arbites/Hive Scum archetypes documented) |
| 10 | **Player weapon `attack_meta_data`** | **Yes** | High | Inject `attack_meta_data` into player weapon templates via `require()` mutation (same pattern as `ability_meta_data`). Maps correct action input names per weapon family. Fixes silent fire failure for non-standard weapons (plasma, etc.) and enables heavy melee attacks for player weapons. | Need to map correct input names per weapon family (~15 families); some weapons have unique fire paths (plasma: charge-then-auto-fire) |
| 11 | **Sprinting** | **Yes** | High | `BotUnitInput` never sets `input.sprint`. Hook `_update_movement` to set `input.sprint = true` under appropriate conditions. `Sprint.check()` handles all validation (cooldowns, weapon blocks, `prevent_sprint` flags, forward movement). | Decision logic needed (when to sprint vs walk); must suppress near Daemonhosts (`sprint_flat_bonus` anger in `chaos_daemonhost_passive_action.lua`) |
| 12 | **Cover seeking improvement** | **Partial** | Medium | Cover candidate selection uses `SpawnPointQueries` (Lua wrapper around GwNav). Could hook to add position scoring or fallback positions when no spawn points exist. | GwNav queries are C++ — can call existing Lua wrappers but can't add new query types; navmesh geometry is fixed |
| 13 | **Block during revive** | **No** | High | Interaction and weapon action are exclusive state machines in the character state system. Cannot queue weapon inputs (`block`) during active interaction (`revive`). | Architectural incompatibility — ECS state components enforce exclusivity. Would need C++ changes to allow parallel states. |
| 14 | **New bot animations** | **No** | High | N/A — animation state machines are compiled assets loaded by C++ engine. | Cannot add new `anim_event` strings or state machine transitions via Lua |
| 15 | **New ECS components** | **No** | High | N/A — component schemas are defined in C++ and registered at engine init. | Cannot extend `unit_data_extension` with new component types |
| 16 | **Navmesh changes** | **No** | High | N/A — navmesh is baked per-level by the level editor. | Cannot modify navmesh geometry, add nav tags, or create new traversal links at runtime |

### What this means for BetterBots scope

**Already done:** Combat abilities (Tiers 1-3), per-ability heuristics, safety guards.

**Feasible additions (new features):**

| Feature | Effort | Issue | Notes |
|---|---|---|---|
| ADS for Tertium 5/6 bots | Low | #35 | Inject `bot_gestalts` into custom profiles (vanilla already has ADS) |
| Mule item pickup | Low | #32 | Shipped in BetterBots via template metadata mutation (`inventory_slot_name -> slot_name`, `bots_mule_pickup = true`) plus a grimoire opt-in toggle and order guard. |
| Player weapon ranged `attack_meta_data` | Medium-High | #31 | Inject per-weapon-family metadata so bots can fire non-standard weapons (plasma, etc.). Without this, Tertium 5/6 bots silently fail to shoot weapons that don't match hardcoded fallback names. |
| Player weapon melee `attack_meta_data` | Medium | #23 | Inject metadata with heavy/charged attack entries + timing. Enables heavy attacks, armor-penetrating swings, charged strikes for player weapons. |
| Weapon special actions | Medium | #33 | Queue `special_action` input + build decision logic (when to parry vs block) |
| Grenade/blitz support | High | #4 | 19 templates, item-based fallback needed for most; `adamant_whistle` is easiest |
| Healing item management | High | #24 | Inventory gate is the hard part; use sequence is proven (Tier 3 pattern) |
| Bot tagging | Medium | #16 | SmartTagSystem integration; solo-play only unless RPC handling is solved |
| Bot sprinting | Low | #36 | Hook `_update_movement` to set sprint input; suppress near Daemonhosts |
| Poxburster targeting | Low-Medium | #34 | Re-enable with safe distance gate (>8m shoot, <5m suppress) |
| Bot warp venting | Medium | #30 | BT vent node exists; translate `reload` → `vent` in action input hook |

**Cannot fix (engine constraints):**

| Limitation | Why |
|---|---|
| No blocking during revive | Exclusive state machines (interaction vs weapon action) |
| No new melee animation patterns | Animation state machines are compiled C++ assets |
| No new navmesh traversals | Navmesh is baked per-level |
| No new ECS components for custom state | Component schema is C++ |
| No persistent ground hazard avoidance | Would need new pathfinding cost layers (C++ navmesh) |
| No multiplayer compatibility | Mods only work in solo play (local host); dedicated servers don't load mods |

---

## Source Files

| File | Contains |
|---|---|
| `bt_bot_conditions.lua` | All BT condition functions including the ability whitelist |
| `bt_bot_melee_action.lua` | Melee combat: attack selection, defense, dodge |
| `bt_bot_shoot_action.lua` | Ranged combat: aim, fire, charge, obstruction |
| `bt_bot_activate_ability_action.lua` | Ability activation: metadata read, input queue |
| `bt_bot_interact_action.lua` | Interactions: revive, rescue, loot, health station |
| `bot_actions.lua` | Action data for all BT nodes (timings, gestures, ranges) |
| `bot_behavior_extension.lua` | Brain update tick, navigation, dodge execution |
| `bot_behavior_tree.lua` | Full BT node hierarchy and priority structure |
| `bot_weapons/*.lua` | Bot weapon templates (action inputs, metadata) |
| `bot_target_selection.lua` | Dual melee/ranged scoring system |

All under `scripts/extension_systems/behavior/` in decompiled source (`../Darktide-Source-Code/`).
