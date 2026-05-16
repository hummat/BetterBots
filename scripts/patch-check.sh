#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DECOMPILE_ROOT="${DECOMPILE_ROOT:-$REPO_ROOT/../Darktide-Source-Code}"
REFRESH=false
errors=0

usage() {
	cat <<'EOF'
Usage:
  scripts/patch-check.sh [--refresh]

Checks the decompiled Darktide source for the engine anchors BetterBots depends on.

Options:
  --refresh   Run 'git pull --ff-only' in the decompile repo before checking.

Environment:
  DECOMPILE_ROOT   Override the decompiled source checkout path.
EOF
}

err() {
	echo "ERROR: $*" >&2
	errors=$((errors + 1))
}

ok() {
	echo "  ok:  $*"
}

check_anchor() {
	local relative_file="$1"
	local anchor="$2"
	local label="$3"
	local file="$DECOMPILE_ROOT/$relative_file"
	local match

	if [[ ! -f "$file" ]]; then
		err "$label missing file: $relative_file"
		return
	fi

	match=$(rg -nF -m 1 "$anchor" "$file" 2>/dev/null || true)
	if [[ -z "$match" ]]; then
		err "$label missing anchor in $relative_file: $anchor"
		return
	fi

	ok "$label -> ${match%%:*}:${match#*:}"
}

check_engine_module_paths() {
	local tmp_file path missing_count=0

	tmp_file="$(mktemp)"

	awk '
		{
			line = $0
			while (match(line, /"scripts\/[^"]+"/)) {
				path = substr(line, RSTART + 1, RLENGTH - 2)
				if (path !~ /^scripts\/mods\/BetterBots\//) {
					print path
				}
				line = substr(line, RSTART + RLENGTH)
			}
		}
	' "$REPO_ROOT"/scripts/mods/BetterBots/*.lua | sort -u > "$tmp_file"

	while IFS= read -r path; do
		if [[ ! -f "$DECOMPILE_ROOT/$path.lua" ]]; then
			err "engine module path missing: $path.lua"
			missing_count=$((missing_count + 1))
		fi
	done < "$tmp_file"

	if ((missing_count == 0)); then
		ok "engine module path inventory -> $(wc -l < "$tmp_file") paths"
	fi

	rm -f "$tmp_file"
}

check_minion_attack_damage_hooks() {
	local minion_file="$DECOMPILE_ROOT/scripts/utilities/minion_attack.lua"
	local hooks_file="$REPO_ROOT/scripts/mods/BetterBots/bot_compensation.lua"
	local tmp_dir expected_file declared_file missing extra

	if [[ ! -f "$minion_file" ]]; then
		err "bot compensation MinionAttack coverage missing file: scripts/utilities/minion_attack.lua"
		return
	fi

	if [[ ! -f "$hooks_file" ]]; then
		err "bot compensation hook table missing file: scripts/mods/BetterBots/bot_compensation.lua"
		return
	fi

	tmp_dir="$(mktemp -d)"
	expected_file="$tmp_dir/expected"
	declared_file="$tmp_dir/declared"

	awk '
		/^MinionAttack\.[[:alnum:]_]+[[:space:]]*=[[:space:]]*function/ {
			if (in_func && reaches_modifier) {
				print name
			}

			in_func = 1
			reaches_modifier = 0
			name = $0
			sub(/^MinionAttack\./, "", name)
			sub(/[[:space:]]*=.*/, "", name)
		}

		in_func && /^((local[[:space:]]+)?function)[[:space:]]+[[:alnum:]_]+/ {
			if (reaches_modifier) {
				print name
			}

			in_func = 0
			reaches_modifier = 0
			name = ""
			next
		}

		in_func && /^end$/ {
			if (reaches_modifier) {
				print name
			}

			in_func = 0
			reaches_modifier = 0
			name = ""
			next
		}

		in_func && (/bot_power_level_modifier/ || /_melee_hit/ || (name == "melee" && /_melee_with_/)) {
			reaches_modifier = 1
		}

		END {
			if (in_func && reaches_modifier) {
				print name
			}
		}
	' "$minion_file" | sort -u > "$expected_file"

	awk '
		/local MINION_ATTACK_DAMAGE_HOOKS[[:space:]]*=/ {
			in_hooks = 1
			next
		}

		in_hooks && /^}/ {
			exit
		}

		in_hooks && /method[[:space:]]*=[[:space:]]*"/ {
			line = $0
			sub(/.*method[[:space:]]*=[[:space:]]*"/, "", line)
			sub(/".*/, "", line)
			print line
		}
	' "$hooks_file" | sort -u > "$declared_file"

	missing="$(comm -23 "$expected_file" "$declared_file" || true)"
	extra="$(comm -13 "$expected_file" "$declared_file" || true)"

	if [[ -n "$missing" ]]; then
		err "bot compensation missing MinionAttack hook(s): ${missing//$'\n'/, }"
	fi

	if [[ -n "$extra" ]]; then
		err "bot compensation declares stale MinionAttack hook(s): ${extra//$'\n'/, }"
	fi

	if [[ -z "$missing" && -z "$extra" ]]; then
		ok "bot compensation MinionAttack damage hooks -> $(paste -sd, "$declared_file")"
	fi

	rm -rf "$tmp_dir"
}

while (($# > 0)); do
	case "$1" in
		--refresh)
			REFRESH=true
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

if [[ ! -d "$DECOMPILE_ROOT/.git" ]]; then
	echo "Missing decompiled source checkout: $DECOMPILE_ROOT" >&2
	echo "Clone it with:" >&2
	echo "  gh repo clone Aussiemon/Darktide-Source-Code \"$DECOMPILE_ROOT\" -- --depth 1" >&2
	exit 2
fi

if $REFRESH; then
	echo "Refreshing decompiled source..."
	git -C "$DECOMPILE_ROOT" pull --ff-only
fi

echo "Using decompiled source: $(git -C "$DECOMPILE_ROOT" log -1 --format='%h %s')"

check_engine_module_paths

check_anchor \
	"scripts/extension_systems/ability/player_unit_ability_extension.lua" \
	"PlayerUnitAbilityExtension.use_ability_charge = function" \
	"ability charge hook"
check_anchor \
	"scripts/extension_systems/ability/actions/action_character_state_change.lua" \
	'_character_sate_component = unit_data_extension:read_component("character_state")' \
	"state-change component read"
check_anchor \
	"scripts/extension_systems/ability/actions/action_character_state_change.lua" \
	"_wanted_state_name = action_settings.state_name" \
	"state-change wanted state"
check_anchor \
	"scripts/extension_systems/ability/actions/action_character_state_change.lua" \
	"ability_extension:use_ability_charge(ability_type)" \
	"state-change charge consume"
check_anchor \
	"scripts/extension_systems/behavior/bot_behavior_extension.lua" \
	"BotBehaviorExtension._init_blackboard_components = function" \
	"behavior blackboard init hook"
check_anchor \
	"scripts/extension_systems/behavior/bot_behavior_extension.lua" \
	"BotBehaviorExtension.update = function" \
	"behavior update hook"
check_anchor \
	"scripts/extension_systems/behavior/bot_behavior_extension.lua" \
	"self._player:is_human_controlled()" \
	"behavior human-control gate"
check_anchor \
	"scripts/extension_systems/behavior/bot_behavior_extension.lua" \
	"BotBehaviorExtension._refresh_destination = function" \
	"behavior refresh-destination hook"
check_anchor \
	"scripts/extension_systems/interaction/interactor_extension.lua" \
	"InteractorExtension.can_interact = function (self, target_unit, interaction_type)" \
	"interactor can_interact signature"
check_anchor \
	"scripts/extension_systems/interaction/interactor_extension.lua" \
	"InteractorExtension._max_interaction_distance = function (self)" \
	"interactor max interaction distance helper"
check_anchor \
	"scripts/settings/interaction/interaction_templates.lua" \
	"interaction_class_name = \"health_station\"" \
	"health station interaction template"
check_anchor \
	"scripts/extension_systems/interaction/interactions/health_station_interaction.lua" \
	"HealthStationInteraction.stop = function (self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)" \
	"health station interaction stop signature"
check_anchor \
	"scripts/extension_systems/interaction/interactions/revive_interaction.lua" \
	"ReviveInteraction.stop = function (self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)" \
	"revive interaction stop signature"
check_anchor \
	"scripts/extension_systems/interaction/interactions/remove_net_interaction.lua" \
	"RemoveNetInteraction.stop = function (self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)" \
	"remove-net interaction stop signature"
check_anchor \
	"scripts/extension_systems/interaction/interactions/pull_up_interaction.lua" \
	"PullUpInteraction.stop = function (self, world, interactor_unit, unit_data_component, t, result, is_server)" \
	"pull-up interaction stop signature"
check_anchor \
	"scripts/extension_systems/interaction/interactions/rescue_interaction.lua" \
	"RescueInteraction.stop = function (self, world, interactor_unit, unit_data_component, t, result, interactor_is_server)" \
	"rescue interaction stop signature"
check_anchor \
	"scripts/extension_systems/health_station/health_station_extension.lua" \
	"HealthStationExtension.charge_amount = function (self)" \
	"health station charge amount accessor"
check_anchor \
	"scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua" \
	"ScriptUnit.extension(unit, \"interactor_system\")" \
	"bot condition interactor extension"
check_anchor \
	"scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua" \
	"conditions.can_activate_ability = function" \
	"bot condition gate"
check_anchor \
	"scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions.lua" \
	"conditions.should_vent_overheat = function" \
	"vent overheat condition"
check_anchor \
	"scripts/extension_systems/behavior/utilities/bt_conditions.lua" \
	'_add_conditions("scripts/extension_systems/behavior/utilities/conditions/bt_bot_conditions")' \
	"bt condition aggregator"
check_anchor \
	"scripts/extension_systems/input/player_unit_input_extension.lua" \
	"PlayerUnitInputExtension.bot_unit_input = function" \
	"player input bot accessor"
check_anchor \
	"scripts/extension_systems/action_input/player_unit_action_input_extension.lua" \
	"PlayerUnitActionInputExtension.bot_queue_action_input = function" \
	"action input bot queue"
check_anchor \
	"scripts/extension_systems/input/bot_unit_input.lua" \
	"BotUnitInput.set_aim_position = function" \
	"bot input aim position"
check_anchor \
	"scripts/extension_systems/input/bot_unit_input.lua" \
	"BotUnitInput.set_aim_rotation = function" \
	"bot input aim rotation"
check_anchor \
	"scripts/extension_systems/input/bot_unit_input.lua" \
	"BotUnitInput.set_aiming = function" \
	"bot input aiming toggle"
check_anchor \
	"scripts/extension_systems/input/bot_unit_input.lua" \
	"BotUnitInput._update_movement = function" \
	"bot input movement hook"
check_anchor \
	"scripts/extension_systems/group/bot_group.lua" \
	"BotGroup.aoe_threat_created = function" \
	"bot group AoE threat hook"
check_anchor \
	"scripts/extension_systems/hazard_prop/hazard_prop_extension.lua" \
	"HazardPropExtension.set_current_state = function" \
	"hazard prop state hook"
check_anchor \
	"scripts/extension_systems/behavior/nodes/actions/bot/bt_bot_shoot_action.lua" \
	"BtBotShootAction._set_new_aim_target = function" \
	"bot shoot aim-target hook (#92)"
check_anchor \
	"scripts/managers/bot/bot_spawning.lua" \
	"BotSpawning.get_bot_config_identifier = function ()" \
	"bot spawning config selector"
check_anchor \
	"scripts/managers/game_mode/game_modes/game_mode_coop_complete_objective.lua" \
	"GameModeCoopCompleteObjective.on_player_unit_spawn = function (self, player, unit, is_respawn)" \
	"coop game mode spawn hook"
check_anchor \
	"scripts/managers/game_mode/game_modes/game_mode_coop_complete_objective.lua" \
	'BotSpawning.get_bot_config_identifier()' \
	"coop game mode bot compensation selector"
check_anchor \
	"scripts/managers/game_mode/game_modes/game_mode_coop_complete_objective.lua" \
	'add_internally_controlled_buff("bot_" .. bot_config_identifier .. "_buff", t)' \
	"coop game mode bot compensation buff"
check_anchor \
	"scripts/managers/game_mode/game_modes/game_mode_expedition.lua" \
	"GameModeExpedition.on_player_unit_spawn = function (self, player, unit, is_respawn)" \
	"expedition game mode spawn hook"
check_anchor \
	"scripts/managers/game_mode/game_modes/game_mode_expedition.lua" \
	'BotSpawning.get_bot_config_identifier()' \
	"expedition game mode bot compensation selector"
check_anchor \
	"scripts/managers/game_mode/game_modes/game_mode_expedition.lua" \
	'add_internally_controlled_buff("bot_" .. bot_config_identifier .. "_buff", t)' \
	"expedition game mode bot compensation buff"
check_anchor \
	"scripts/settings/buff/player_buff_templates.lua" \
	"templates.bot_medium_buff = {" \
	"bot medium compensation buff"
check_anchor \
	"scripts/settings/buff/player_buff_templates.lua" \
	"templates.bot_high_buff = {" \
	"bot high compensation buff"

check_minion_attack_damage_hooks

echo ""
if ((errors > 0)); then
	echo "patch-check: $errors error(s)"
	exit 1
fi

echo "patch-check: all engine anchors present"
