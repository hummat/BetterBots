local Identity = dofile("scripts/mods/BetterBots/combat_ability_identity.lua")
local helper = require("tests.test_helper")

local function make_mod_stub()
	local stub = { calls = {} }
	stub.mod = {
		warning = function(_self, message)
			table.insert(stub.calls, message)
		end,
	}
	return stub
end

local function make_debug_log_stub()
	local stub = { calls = {} }
	stub.debug_log = function(key, _t, message, _interval, level)
		table.insert(stub.calls, { key = key, message = message, level = level })
	end
	stub.debug_enabled = function()
		return true
	end
	return stub
end

describe("combat_ability_identity", function()
	before_each(function()
		Identity.init({})
	end)

	it("separates engine template from veteran shout semantic identity", function()
		local ability_extension = helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout")
		local identity = Identity.resolve(nil, ability_extension, { template_name = "veteran_combat_ability" })

		assert.equals("veteran_combat_ability", identity.template_name)
		assert.equals("veteran_combat_ability_shout", identity.ability_name)
		assert.equals("veteran_combat_ability_shout", identity.semantic_key)
		assert.equals("squad_leader", identity.class_tag)
		assert.equals("class_tag", identity.class_tag_source)
	end)

	it("falls back to ability name when veteran class_tag is absent", function()
		local ability_extension = helper.make_veteran_ability_extension(nil, "veteran_combat_ability_shout")
		local identity = Identity.resolve(nil, ability_extension, { template_name = "veteran_combat_ability" })

		assert.equals("veteran_combat_ability_shout", identity.semantic_key)
		assert.equals("squad_leader", identity.class_tag)
		assert.equals("ability_name", identity.class_tag_source)
	end)

	it("keeps non-shared templates as their template semantic key", function()
		local ability_extension = {
			_equipped_abilities = {
				combat_ability = {
					name = "psyker_combat_ability_stance",
				},
			},
		}
		local identity = Identity.resolve(nil, ability_extension, { template_name = "psyker_overcharge_stance" })

		assert.equals("psyker_overcharge_stance", identity.template_name)
		assert.equals("psyker_combat_ability_stance", identity.ability_name)
		assert.equals("psyker_overcharge_stance", identity.semantic_key)
	end)

	it("maps semantic identity to settings category", function()
		local shout = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout"),
			{ template_name = "veteran_combat_ability" }
		)
		local stance = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("ranger", "veteran_combat_ability_stance"),
			{ template_name = "veteran_combat_ability" }
		)

		assert.equals("enable_shouts", Identity.category_setting_id(shout))
		assert.equals("enable_stances", Identity.category_setting_id(stance))
		assert.equals("enable_stances", Identity.category_setting_id({ semantic_key = "psyker_overcharge_stance" }))
	end)

	it("uses semantic identity for revive defensive and cooldown categories", function()
		local shout = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout"),
			{ template_name = "veteran_combat_ability" }
		)
		local stance = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("ranger", "veteran_combat_ability_stance"),
			{ template_name = "veteran_combat_ability" }
		)

		assert.is_true(Identity.is_revive_defensive(shout))
		assert.is_false(Identity.is_revive_defensive(stance))
		assert.equals("aoe_shout", Identity.team_cooldown_category(shout))
		assert.is_nil(Identity.team_cooldown_category(stance))
	end)

	it("emits a deduped warning for unknown template names", function()
		local debug_stub = make_debug_log_stub()
		Identity.init({
			mod = make_mod_stub().mod,
			debug_log = debug_stub.debug_log,
			debug_enabled = debug_stub.debug_enabled,
		})

		local identity = Identity.resolve(
			nil,
			{ _equipped_abilities = { combat_ability = {} } },
			{ template_name = "made_up_ability_template" }
		)

		assert.equals("made_up_ability_template", identity.template_name)
		assert.equals("made_up_ability_template", identity.semantic_key)
		assert.is_nil(Identity.category_setting_id(identity))
		assert.is_nil(Identity.team_cooldown_category(identity))
		assert.is_false(Identity.is_revive_defensive(identity))

		assert.equals(1, #debug_stub.calls)
		assert.equals("unknown_combat_template:made_up_ability_template", debug_stub.calls[1].key)
		assert.is_true(debug_stub.calls[1].message:find("made_up_ability_template", 1, true) ~= nil)
	end)

	it("deduplicates unknown-template warnings across repeated resolve calls", function()
		local debug_stub = make_debug_log_stub()
		Identity.init({
			debug_log = debug_stub.debug_log,
			debug_enabled = debug_stub.debug_enabled,
		})

		Identity.resolve(nil, nil, { template_name = "made_up_ability_template" })
		Identity.resolve(nil, nil, { template_name = "made_up_ability_template" })
		Identity.resolve(nil, nil, { template_name = "made_up_ability_template" })

		assert.equals(1, #debug_stub.calls)
	end)

	it("does not warn on known non-veteran templates", function()
		local debug_stub = make_debug_log_stub()
		local mod_stub = make_mod_stub()
		Identity.init({
			mod = mod_stub.mod,
			debug_log = debug_stub.debug_log,
			debug_enabled = debug_stub.debug_enabled,
		})

		Identity.resolve(nil, nil, { template_name = "zealot_dash" })
		Identity.resolve(nil, nil, { template_name = "psyker_shout" })
		Identity.resolve(nil, nil, { template_name = "ogryn_taunt_shout" })

		assert.equals(0, #debug_stub.calls)
		assert.equals(0, #mod_stub.calls)
	end)

	it("does not warn on nil template_name (unequipped combat ability)", function()
		local debug_stub = make_debug_log_stub()
		local mod_stub = make_mod_stub()
		Identity.init({
			mod = mod_stub.mod,
			debug_log = debug_stub.debug_log,
			debug_enabled = debug_stub.debug_enabled,
		})

		Identity.resolve(nil, nil, {})

		assert.equals(0, #debug_stub.calls)
		assert.equals(0, #mod_stub.calls)
	end)

	it("does not warn on 'none' sentinel template_name", function()
		-- The engine's action_handler initializes combat_ability_action.template_name
		-- to the literal "none" when no ability is active. That's not an
		-- unrecognized template — it's a known sentinel — so resolve() must
		-- stay silent instead of firing the unknown-template warning.
		local debug_stub = make_debug_log_stub()
		local mod_stub = make_mod_stub()
		Identity.init({
			mod = mod_stub.mod,
			debug_log = debug_stub.debug_log,
			debug_enabled = debug_stub.debug_enabled,
		})

		local identity = Identity.resolve(nil, nil, { template_name = "none" })

		assert.equals("none", identity.template_name)
		assert.is_false(Identity.is_revive_defensive(identity))
		assert.equals(0, #debug_stub.calls)
		assert.equals(0, #mod_stub.calls)
	end)

	it("flags unresolved veteran identities and warns exactly once", function()
		local mod_stub = make_mod_stub()
		local debug_stub = make_debug_log_stub()
		Identity.init({
			mod = mod_stub.mod,
			debug_log = debug_stub.debug_log,
			debug_enabled = debug_stub.debug_enabled,
		})

		local ability_extension = helper.make_veteran_ability_extension(nil, "veteran_combat_ability_mystery")
		local identity = Identity.resolve(nil, ability_extension, { template_name = "veteran_combat_ability" })

		assert.is_true(identity.unresolved)
		assert.equals("unknown", identity.class_tag_source)
		-- category_setting_id still defaults to enable_stances (observational change only).
		assert.equals("enable_stances", Identity.category_setting_id(identity))

		assert.equals(1, #mod_stub.calls)
		assert.is_true(mod_stub.calls[1]:find("veteran combat ability", 1, true) ~= nil)
		assert.is_true(mod_stub.calls[1]:find("stance gating", 1, true) ~= nil)

		-- Second call: should not re-warn.
		Identity.resolve(nil, ability_extension, { template_name = "veteran_combat_ability" })
		assert.equals(1, #mod_stub.calls)

		-- Unknown-template warn hook should NOT fire for the veteran case.
		assert.equals(0, #debug_stub.calls)
	end)

	it("does not flag resolved veteran identities (class_tag path)", function()
		local mod_stub = make_mod_stub()
		Identity.init({ mod = mod_stub.mod })

		local identity = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension("squad_leader", "veteran_combat_ability_shout"),
			{ template_name = "veteran_combat_ability" }
		)

		assert.is_false(identity.unresolved)
		assert.equals("class_tag", identity.class_tag_source)
		assert.equals(0, #mod_stub.calls)
	end)

	it("does not flag resolved veteran identities (ability_name path)", function()
		local mod_stub = make_mod_stub()
		Identity.init({ mod = mod_stub.mod })

		local identity = Identity.resolve(
			nil,
			helper.make_veteran_ability_extension(nil, "veteran_combat_ability_shout"),
			{ template_name = "veteran_combat_ability" }
		)

		assert.is_false(identity.unresolved)
		assert.equals("ability_name", identity.class_tag_source)
		assert.equals(0, #mod_stub.calls)
	end)
end)
