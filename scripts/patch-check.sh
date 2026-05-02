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

echo ""
if ((errors > 0)); then
	echo "patch-check: $errors error(s)"
	exit 1
fi

echo "patch-check: all engine anchors present"
