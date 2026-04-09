# Revive-with-ability design (#7 P1)

## Problem

The BT priority selector evaluates revive (priority 2) before ability activation (priority 8). Once `can_revive` returns true, `BtBotInteractAction.enter()` sets `current_interaction_unit`, which blocks all three BetterBots ability paths (BT condition, ability_queue fallback, grenade_fallback). Bots never fire defensive abilities before reviving downed allies, leaving them vulnerable during the long revive interaction.

VT2's Bot Improvements (Grimalackt) solved this by injecting a `BTBotActivateAbilityAction` node before the revive interact node in the BT. P1 scope avoids BT injection — instead hooks `BtBotInteractAction.enter` and delegates the hold+release lifecycle to the existing ability_queue state machine.

## Approach

Hook `BtBotInteractAction.enter` via `mod:hook`. Before calling the original function:

1. Detect rescue-type interactions
2. Verify threat, ability readiness, and safety gates
3. Queue the initial ability input
4. Set up the ability_queue state machine for hold+release

The existing ability_queue cleanup code (lines 154–171 of `ability_queue.lua`) runs every tick BEFORE the `current_interaction_unit` guard, so it handles the `shout_released` / `combat_ability_released` follow-up input during the interaction. No modifications to ability_queue.lua are needed.

## Hook sequence

```
BtBotInteractAction.enter hook (pre-call):
  1. action_data.interaction_type in RESCUE_INTERACTION_TYPES?
  2. perception.enemies_in_proximity > 0?
  3. _is_suppressed(unit) == false?
  4. Read combat_ability_action component → template_name
  5. template_name in REVIVE_DEFENSIVE_ABILITIES?
  6. Settings category gate passes? (enable_shouts / enable_stealth)
  7. MetaData.inject(AbilityTemplates)
  8. Read activation.action_input + wait_action from ability_meta_data
  9. _action_input_is_bot_queueable() validates input?
  10. ability_extension:can_use_ability("combat_ability") + charges > 0?
  11. bot_queue_action_input("combat_ability_action", action_input, nil)
  12. Set ability_queue state: active, hold_until, wait_action_input, wait_sent
  13. Debug log + event log
  → Call func(self, ...) — proceed with revive
```

Guards 1–10 are cheap reads. Any failure → skip to func(self, ...) silently (no-op paths produce no log output per CLAUDE.md rules).

## Ability whitelist

```lua
REVIVE_DEFENSIVE_ABILITIES = {
    ogryn_taunt_shout              = true,  -- AoE taunt, draws aggro
    psyker_shout                   = true,  -- AoE stagger, clears area
    adamant_shout                  = true,  -- AoE shout
    zealot_invisibility            = true,  -- stealth, safe revive
    veteran_stealth_combat_ability = true,  -- stealth, safe revive
}
```

### Excluded

- **Charges/dashes** (`zealot_dash`, `ogryn_charge`, `adamant_charge`): movement away from downed ally
- **Item abilities** (`zealot_relic`, `force_field`, `drone`): multi-step wield sequence, too slow
- **VoC / ranger stance** (`veteran_combat_ability`): toggle — pressing during revive might deactivate an active stance. P2 enhancement: detect active state.
- **Psyker stance** (`psyker_overcharge_stance`): self-buff, not defensive for revive protection

## Rescue interaction types

```lua
RESCUE_INTERACTION_TYPES = {
    revive     = true,  -- knocked_down ally
    rescue     = true,  -- hogtied ally
    pull_up    = true,  -- ledge hanging ally
    remove_net = true,  -- netted ally
}
```

Non-rescue interactions (health_station, loot) have nil `action_data`, so `action_data.interaction_type` is nil → guard 1 rejects them.

## State machine handoff

After queuing the initial input, set up the shared `_fallback_state_by_unit[unit]` table:

```lua
state.active = true
state.hold_until = fixed_t + (activation_data.min_hold_time or 0)
state.wait_action_input = wait_action and wait_action.action_input or nil
state.wait_sent = false
state.action_input_extension = action_input_extension
```

The ability_queue cleanup code runs every tick:

```lua
if state.active then
    if fixed_t >= state.hold_until then
        if state.wait_action_input and not state.wait_sent then
            action_input_extension:bot_queue_action_input(...)
            state.wait_sent = true
        end
        state.active = nil
        ...
    end
    return  -- prevents new activations during hold
end
-- ... interaction guard is below here, never reached while active
```

This handles the full press→hold→release lifecycle without any changes to ability_queue.lua.

## Team cooldown

Not checked in the hook — team cooldown `is_suppressed()` only runs in `condition_patch.lua`'s BT path. The hook fires independently.

Team cooldown recording happens automatically: the `use_ability_charge` hook on `PlayerUnitAbilityExtension` (BetterBots.lua:790) calls `TeamCooldown.record()` at charge consumption time, regardless of which path queued the ability. Other bots' shouts will be staggered normally.

## Settings gates

Reuses existing category gates from `settings.lua`:
- Shouts: `enable_shouts` (ogryn_taunt, psyker_shout, adamant_shout)
- Stealth: `enable_stealth` (zealot_invisibility, veteran_stealth)

Checked via `Settings.is_combat_template_enabled(template_name, ability_extension)`. No new feature gate for P1.

## Module structure

New file: `scripts/mods/BetterBots/revive_ability.lua` (~80–100 LOC)

```
M.init(deps)           -- mod, debug_log, debug_enabled, fixed_time, is_suppressed,
                       --   perf, fallback_state_by_unit, shared_rules
M.wire(deps)           -- MetaData, EventLog, Debug, is_combat_template_enabled
M.register_hooks()     -- install BtBotInteractAction.enter hook
```

Loaded in BetterBots.lua via `mod:io_dofile`, wired alongside other modules.

## Debug logging

- Key: `"revive_ability:" .. ability_template_name .. ":" .. tostring(unit)` — per-bot discriminator
- Message: `"revive ability queued: <template> (interaction=<type>, enemies=<N>)"`
- Gated behind `_debug_enabled()` per CLAUDE.md rules
- No-op paths produce no output

## Event logging

Emit to JSONL event log:

```lua
EventLog.emit({
    t = fixed_t,
    event = "revive_ability",
    bot = bot_slot,
    ability = equipped_ability_name,
    template = ability_template_name,
    interaction = interaction_type,
    enemies = enemies_in_proximity,
})
```

## Interaction with #37

Complementary:
- **#7**: The reviving bot self-casts a defensive ability (this feature)
- **#37**: Other bots observing the revive lower their ability thresholds

A revive under threat gets double protection: the reviver goes invisible or shouts, and nearby bots become more aggressive.

## Known P1 risks

1. **Ability-interaction race**: Ability and interact inputs both process on the next frame. For shouts, the stagger/taunt effect fires on `ActionAbilityBase.start()` before the interaction state can interrupt. For stealth, the invisibility buff persists past action interruption. Charge may be spent for a partial effect — acceptable in a dangerous revive scenario.

2. **VoC veteran gap**: Default veteran bot (VoC) has no revive-with-ability due to toggle risk. P2: detect active VoC state via ability component and skip if already active.

## Tests (~14)

- Fires for each rescue interaction type (revive, rescue, pull_up, remove_net)
- Does NOT fire for nil action_data (health_station, loot)
- Does NOT fire when enemies_in_proximity == 0
- Does NOT fire when ability on cooldown / no charges
- Does NOT fire for non-whitelisted templates (charge, stance, item)
- Does NOT fire when suppressed
- Does NOT fire when category disabled (enable_shouts=false, enable_stealth=false)
- Validates input via _action_input_is_bot_queueable before queuing
- Calls MetaData.inject() before reading meta_data
- Sets up state machine correctly (active, hold_until, wait_action_input)
- Debug log emitted with correct key format
- Event log emitted with interaction type and enemy count

## In-game validation

Look for `revive_ability:` log entries in `bb-log` output. Verify:
- Ability fires when bot starts reviving with enemies nearby
- Ability does NOT fire on safe revives (no enemies)
- Shout stagger visibly affects enemies near the revive
- Stealth makes bot invisible during revive
- Hold+release completes (check for state machine cleanup logs if present)
