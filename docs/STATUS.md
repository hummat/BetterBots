# Status Snapshot (March 4, 2026)

## Evidence Source

- Latest analyzed log:
  `/run/media/matthias/58ACC87DACC856E2/Program Files (x86)/Steam/steamapps/compatdata/1361210/pfx/drive_c/users/steamuser/AppData/Roaming/Fatshark/Darktide/console_logs/console-2026-03-04-17.02.57-4e629ca9-45b7-405b-948d-541bffcb815c.log`
- Last observed BetterBots entries in this run are around `17:18:56`-`17:18:59`.

## Confirmed Working In This Run

1. Startup patching is active.
   - `BetterBots loaded`
   - `patched bt_bot_conditions.can_activate_ability`
   - `patched bt_conditions.can_activate_ability`

2. Template-path casts are working (charge actually consumed).
   - Veteran: `charge consumed for veteran_combat_ability_stance_improved`
   - Ogryn: `charge consumed for ogryn_charge_increased_distance`
   - Zealot: `charge consumed for zealot_invisibility_improved`

3. Item-path cast success was observed for Psyker force-field earlier in the same run.
   - `17:11:49.154`: `charge consumed for psyker_force_field`
   - `17:12:37.639`: `charge consumed for psyker_force_field`

## Partial / Experimental

1. Psyker force-field post-reload behavior is mixed.
   - After reload around `17:16:41`, the fallback changed to `aim_force_field -> place_force_field -> unwield_to_previous`.
   - That sequence is being queued repeatedly, but no new `charge consumed for psyker_force_field` is visible in the later slice of this log.

2. Item fallback is still heuristic and not yet fully stable across templates/variants.

## Known Log Noise

1. Frequent `fallback blocked ... invalid action_input=...` appears during combat.
   - This is expected whenever an action input is temporarily invalid (cooldown, active state, or transition timing).
   - It is noisy and can hide real issues; logging rate/conditions should be tightened.

2. Non-mod errors in the same log:
   - `ERROR [BotNavigationExtension] Can't path, AStar was cancelled...`
   - These are engine/navigation-side and not a BetterBots Lua traceback.

## Current Conclusion

1. Bot combat abilities are definitely firing for Veteran, Ogryn, and Zealot in live combat.
2. Psyker force-field worked earlier, but the newest fallback sequencing after reload is not consistently confirmed by charge-consume evidence yet.
3. Grenade support remains out of scope.
