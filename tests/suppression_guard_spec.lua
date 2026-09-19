local function load_module()
	local ok, mod = pcall(dofile, "scripts/mods/BetterBots/suppression_guard.lua")
	assert.is_true(ok, "suppression_guard.lua should load: " .. tostring(mod))
	return mod
end

local MISSING_NODE_ERROR = "scripts/utilities/attack/suppression.lua:344: UnitApi node failed, "
	.. "node `#ID[409f026d]` was not found in unit `#ID[cc3a140289edfcca]`"

local function with_unit_api(has_node, fn)
	local saved_unit = rawget(_G, "Unit")
	rawset(_G, "Unit", {
		has_node = function(_unit, _node_name)
			return has_node
		end,
	})

	local ok, err = pcall(fn)
	rawset(_G, "Unit", saved_unit)

	if not ok then
		error(err, 0)
	end
end

-- Mirrors the production `wrap_engine_field` contract: wrap what we originally
-- wrapped, leave anything a foreign mod installed in the chain.
local function make_wrap_engine_field()
	local wrappers = setmetatable({}, { __mode = "k" })

	return function(target, key, make_wrapper)
		local original = target[key]
		while wrappers[original] ~= nil do
			original = wrappers[original]
		end
		if original == nil then
			return nil
		end

		local wrapper = make_wrapper(original)
		if type(wrapper) == "function" then
			target[key] = wrapper
			wrappers[wrapper] = original
		end

		return original
	end
end

local function init_guard(Suppression, debug_logs, wrap_engine_field)
	local Guard = load_module()

	Guard.init({
		debug_log = function(key, fixed_t, message, interval, level)
			debug_logs[#debug_logs + 1] = {
				key = key,
				fixed_t = fixed_t,
				message = message,
				interval = interval,
				level = level,
			}
		end,
		debug_enabled = function()
			return true
		end,
		fixed_time = function()
			return 12.5
		end,
		wrap_engine_field = wrap_engine_field,
	})
	Guard.install(Suppression)

	return Guard
end

describe("suppression_guard", function()
	it("swallows the vanilla missing enemy aim node crash after direct suppression side effects ran", function()
		with_unit_api(false, function()
			local calls = 0
			local debug_logs = {}
			local Suppression = {
				apply_suppression = function()
					calls = calls + 1
					error(MISSING_NODE_ERROR)
				end,
				apply_area_minion_suppression = function() end,
			}

			init_guard(Suppression, debug_logs)

			assert.has_no.errors(function()
				Suppression.apply_suppression("hit_unit", "attacker_unit", {}, "hit_position")
			end)
			assert.equals(1, calls)
			assert.equals(1, #debug_logs)
			assert.equals("suppression_guard:attacker_unit", debug_logs[1].key)
			assert.equals(12.5, debug_logs[1].fixed_t)
			assert.equals("warning", debug_logs[1].level)
			assert.matches("guarded vanilla suppression missing-node crash", debug_logs[1].message, 1, true)
		end)
	end)

	it("swallows the same missing enemy aim node crash from area suppression", function()
		with_unit_api(false, function()
			local calls = 0
			local debug_logs = {}
			local Suppression = {
				apply_suppression = function() end,
				apply_area_minion_suppression = function()
					calls = calls + 1
					error(MISSING_NODE_ERROR)
				end,
			}

			init_guard(Suppression, debug_logs)

			assert.has_no.errors(function()
				Suppression.apply_area_minion_suppression("attacker_unit", {}, "from_position")
			end)
			assert.equals(1, calls)
			assert.equals(1, #debug_logs)
			assert.equals("suppression_guard:attacker_unit", debug_logs[1].key)
		end)
	end)

	it("rethrows unrelated suppression errors", function()
		with_unit_api(false, function()
			local debug_logs = {}
			local Suppression = {
				apply_suppression = function()
					error("scripts/utilities/attack/suppression.lua:344: unexpected failure")
				end,
				apply_area_minion_suppression = function() end,
			}

			init_guard(Suppression, debug_logs)

			local ok, err = pcall(Suppression.apply_suppression, "hit_unit", "attacker_unit", {}, "hit_position")

			assert.is_false(ok)
			assert.matches("unexpected failure", tostring(err), 1, true)
			assert.equals(0, #debug_logs)
		end)
	end)

	it("rethrows unrelated area suppression errors", function()
		with_unit_api(false, function()
			local debug_logs = {}
			local Suppression = {
				apply_suppression = function() end,
				apply_area_minion_suppression = function()
					error("scripts/utilities/attack/suppression.lua:344: unexpected area failure")
				end,
			}

			init_guard(Suppression, debug_logs)

			local ok, err = pcall(Suppression.apply_area_minion_suppression, "attacker_unit", {}, "from_position")

			assert.is_false(ok)
			assert.matches("unexpected area failure", tostring(err), 1, true)
			assert.equals(0, #debug_logs)
		end)
	end)

	it("preserves normal return values when the attacker has the enemy aim node", function()
		with_unit_api(true, function()
			local debug_logs = {}
			local Suppression = {
				apply_suppression = function()
					return "normal"
				end,
				apply_area_minion_suppression = function()
					return "area"
				end,
			}

			init_guard(Suppression, debug_logs)

			assert.equals("normal", Suppression.apply_suppression("hit_unit", "attacker_unit", {}, "hit_position"))
			assert.equals("area", Suppression.apply_area_minion_suppression("attacker_unit", {}, "from_position"))
			assert.equals(0, #debug_logs)
		end)
	end)

	it("keeps a single wrapper when the same module instance reinstalls", function()
		with_unit_api(true, function()
			local debug_logs = {}
			local Suppression = {
				apply_suppression = function()
					return "normal"
				end,
				apply_area_minion_suppression = function()
					return "area"
				end,
			}

			local Guard = init_guard(Suppression, debug_logs)
			local first_apply = Suppression.apply_suppression
			local first_area = Suppression.apply_area_minion_suppression

			Guard.install(Suppression)

			assert.equals(first_apply, Suppression.apply_suppression)
			assert.equals(first_area, Suppression.apply_area_minion_suppression)
		end)
	end)

	it("re-wraps the pristine functions after a hot reload instead of its own wrapper (#116)", function()
		with_unit_api(false, function()
			-- Stacked wrappers would route the guard log into the dead load's
			-- logger and add a redundant pcall layer on every suppression call.
			local wrap = make_wrap_engine_field()
			local stale_logs, live_logs = {}, {}
			local Suppression = {
				apply_suppression = function()
					error(MISSING_NODE_ERROR, 0)
				end,
				apply_area_minion_suppression = function()
					return "area"
				end,
			}

			init_guard(Suppression, stale_logs, wrap)
			init_guard(Suppression, live_logs, wrap)

			Suppression.apply_suppression("hit_unit", "attacker_unit", {}, "hit_position")

			assert.equals(0, #stale_logs)
			assert.equals(1, #live_logs)
		end)
	end)

	it("keeps a foreign mod's wrapper in the chain across a reload (#116)", function()
		with_unit_api(true, function()
			-- Another mod re-hooking between our loads owns the field now; we
			-- must wrap what is live, not unwrap past it back to vanilla.
			local wrap = make_wrap_engine_field()
			local foreign_calls = 0
			local Suppression = {
				apply_suppression = function()
					return "normal"
				end,
				apply_area_minion_suppression = function()
					return "area"
				end,
			}

			init_guard(Suppression, {}, wrap)

			local ours = Suppression.apply_suppression
			Suppression.apply_suppression = function(...)
				foreign_calls = foreign_calls + 1
				return ours(...)
			end

			init_guard(Suppression, {}, wrap)

			assert.equals("normal", Suppression.apply_suppression("hit_unit", "attacker_unit", {}, "hit_position"))
			assert.equals(1, foreign_calls)
		end)
	end)
end)
