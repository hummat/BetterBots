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

`scripts/mods/BetterBots/BetterBots.lua` does four things:

1. Injects missing `ability_meta_data` for Tier 2 templates.
2. Overrides selected template metadata (`veteran_*`) to use bot-valid inputs.
3. Replaces `can_activate_ability` so templates with valid metadata can pass.
4. Adds a fallback in `BotBehaviorExtension:update`:
   - template fallback: queue ability action input directly on `combat_ability_action`
   - item fallback: queue explicit `weapon_action` sequence (`combat_ability` wield + cast follow-ups + unwind)

## Why item fallback is needed

Item-based abilities rely heavily on weapon `conditional_state_to_action_input` chains (for example wield -> channel/place).

In `ActionInputParser.action_transitioned_with_automatic_input`, bots early-return, so these automatic chains do not advance for bot-controlled units. Humans get those automatic transitions; bots do not.

Result: item abilities need explicit queued inputs from the mod.

## Ability tiers in this repo

| Tier | Current handling | Notes |
|---|---|---|
| 1 | Whitelist bypass | Templates already define `ability_meta_data` |
| 2 | Runtime metadata injection | Includes template-specific `wait_action`/`end_condition` where needed |
| 3a | Item-based combat fallback (experimental) | Driven via `weapon_action` sequence probing by action-input names |
| 3b | Grenades | Not implemented |

## Class ability references

Detailed per-class ability breakdowns (internal IDs, input patterns, cooldowns, talent modifiers, bot usage notes) are in:
- `CLASS_VETERAN.md`, `CLASS_ZEALOT.md`, `CLASS_PSYKER.md`, `CLASS_OGRYN.md`, `CLASS_ARBITES.md`, `CLASS_HIVE_SCUM.md`

Each doc classifies abilities into the tiers above and includes implementation guidance for bot activation.

## Key constraints

- Template path still depends on valid `ability_meta_data.activation.action_input`.
- Item path is heuristic: it inspects the wielded combat-ability weapon template and chooses a known sequence shape (for example `channel`, `ability_pressed`/`ability_released`, `instant_aim_force_field`/`instant_place_force_field`).
- Unsupported item templates are skipped with explicit debug logs.
