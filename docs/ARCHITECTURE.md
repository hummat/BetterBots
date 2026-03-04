# Architecture

## Scope

This mod targets bot `combat_ability` activation in two paths:

1. Template-based abilities (`combat_ability_action.template_name ~= "none"`).
2. Item-based abilities (`combat_ability_action.template_name == "none"` with an equipped combat-ability item).

Grenade abilities are still out of scope.

## Vanilla bot ability flow

1. `bot_behavior_tree.lua` runs `activate_combat_ability`.
2. `bt_bot_conditions.can_activate_ability` hard-gates most templates.
3. `BtBotActivateAbilityAction` queues bot input for ability templates only.
4. If `combat_ability_action.template_name == "none"`, vanilla exits early.

## Mod behavior

`scripts/mods/BetterBots/BetterBots.lua` does six things:

1. Injects missing `ability_meta_data` for Tier 2 templates.
2. Overrides selected template metadata (`veteran_*`) to use bot-valid inputs.
3. Replaces `can_activate_ability` so templates with valid metadata can pass.
4. Adds a fallback in `BotBehaviorExtension:update`:
   - template fallback: queue ability action input directly on `combat_ability_action`
   - item fallback: queue explicit `weapon_action` sequence (`combat_ability` wield + cast follow-ups + unwind)
   - item sequence selection is profile-driven (shared profile catalog + per-ability priority order)
5. Adds state-transition recovery:
   - hook `ActionCharacterStateChange.finish`
   - if bot combat ability did not reach wanted character state, schedule a fast fallback retry
6. Adds queue-level weapon-switch protection for item abilities:
   - hook `PlayerUnitActionInputExtension.bot_queue_action_input`
   - block bot `weapon_action:wield` while protected item abilities are active/in-sequence

## Why item fallback is needed

Item-based abilities rely heavily on weapon `conditional_state_to_action_input` chains (for example wield -> channel/place).

In `ActionInputParser.action_transitioned_with_automatic_input`, bots early-return, so these automatic chains do not advance for bot-controlled units. Humans get those automatic transitions; bots do not.

Result: item abilities need explicit queued inputs from the mod.

## Ability tiers in this repo

| Tier | Current handling | Notes |
|---|---|---|
| 1 | Whitelist bypass | Templates define usable `ability_meta_data` |
| 2 | Runtime metadata injection | Includes template-specific `wait_action`/`end_condition` where needed |
| 3a | Item-based combat fallback (experimental) | Driven via `weapon_action` sequence probing by action-input names |
| 3b | Grenades | Not implemented |

## Class ability references

Detailed per-class ability breakdowns (internal IDs, input patterns, cooldowns, talent modifiers, bot usage notes) are in:
- `CLASS_VETERAN.md`, `CLASS_ZEALOT.md`, `CLASS_PSYKER.md`, `CLASS_OGRYN.md`, `CLASS_ARBITES.md`, `CLASS_HIVE_SCUM.md`

Each doc classifies abilities into the tiers above and includes implementation guidance for bot activation.

## Key constraints

- Template path still depends on valid `ability_meta_data.activation.action_input`.
- Some vanilla templates ship metadata that does not match their action-input graph (for example Veteran `stance_pressed` vs actual `combat_ability_pressed`/`combat_ability_released`), so metadata overrides are required.
- Item path is profile-based: it inspects weapon-template `action_inputs`, picks a compatible sequence profile, and runs one shared stage machine.
- Unsupported item templates are skipped with explicit debug logs.

## Item fallback lessons (generalized)

The same reliability rules apply across relic/force-field/drone-style abilities:

1. **Lock by stage, not by one-shot queue**
   - Separate `waiting_wield`, `waiting_start`, `waiting_followup`, `waiting_unwield`, `waiting_charge_confirmation`.
   - Validate slot/template at each stage before queueing input.

2. **Treat parser drift as first-class**
   - Before each queued input, verify the currently active `weapon_action` template still supports that input.
   - If not, abort and retry instead of sending invalid parser input.

3. **Use charge-consume as success signal**
   - Track `use_ability_charge(combat_ability)` for bots per unit.
   - Confirm sequence success via charge consumption, not only via queued inputs.

4. **Support multiple valid input profiles**
   - Some weapons expose both regular and instant cast paths.
   - Keep a prioritized profile list per ability and rotate profile when a full sequence ends without charge consumption.

5. **Prevent BT switch-away during critical item stages**
   - Some abilities are broken by immediate re-wield decisions from other bot nodes.
   - Queue-level filtering of bot `wield` requests is a reliable guardrail for channel/deploy flows.
