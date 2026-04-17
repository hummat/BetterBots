local test_helper = require("tests.test_helper")

local UpdateDispatcher = dofile("scripts/mods/BetterBots/update_dispatcher.lua")

local saved_script_unit = rawget(_G, "ScriptUnit")

describe("update_dispatcher", function()
	local extension_map
	local call_log
	local emitted_events
	local snapshot_state
	local session_start_state
	local fixed_t
	local collect_alive_bots_calls

	local function count_events(event_name)
		local count = 0
		for i = 1, #emitted_events do
			if emitted_events[i].event == event_name then
				count = count + 1
			end
		end
		return count
	end

	local function make_self(is_human)
		return {
			_player = {
				is_human_controlled = function()
					return is_human == true
				end,
			},
			_brain = {
				_blackboard = {
					perception = {},
				},
			},
		}
	end

	local function make_deps(opts)
		opts = opts or {}
		return {
			perf = {
				sync_setting = function()
					call_log[#call_log + 1] = "perf_sync"
				end,
				mark_bot_frame = function()
					call_log[#call_log + 1] = "perf_mark_bot_frame"
				end,
				begin = function()
					return {}
				end,
				finish = function(name)
					call_log[#call_log + 1] = "perf_finish:" .. name
				end,
			},
			event_log = {
				is_enabled = function()
					return opts.event_log_enabled ~= false
				end,
				emit = function(event)
					emitted_events[#emitted_events + 1] = event
					if event.event == "session_start" then
						call_log[#call_log + 1] = "session_start_emit"
					elseif event.event == "snapshot" then
						call_log[#call_log + 1] = "snapshot_emit"
					end
				end,
				try_flush = function()
					call_log[#call_log + 1] = "event_log_flush"
				end,
			},
			debug = {
				collect_alive_bots = function()
					collect_alive_bots_calls = collect_alive_bots_calls + 1
					return opts.bots
						or {
							{
								player = {
									slot = function()
										return 2
									end,
									archetype_name = function()
										return "psyker"
									end,
								},
								unit = "unit_stub",
							},
						}
				end,
				bot_slot_for_unit = function()
					return 2
				end,
				context_snapshot = function(context)
					return context
				end,
			},
			ability_queue = {
				try_queue = function(_unit, _blackboard)
					call_log[#call_log + 1] = "ability_queue"
				end,
			},
			grenade_fallback = {
				try_queue = function(_unit, _blackboard)
					call_log[#call_log + 1] = "grenade_fallback"
				end,
			},
			ping_system = {
				update = function(_unit, _blackboard)
					call_log[#call_log + 1] = "ping_system"
				end,
			},
			companion_tag = {
				update = function(_unit, _blackboard)
					call_log[#call_log + 1] = "companion_tag"
				end,
			},
			settings = {
				is_feature_enabled = function(feature_name)
					assert.equals("pinging", feature_name)
					return opts.pinging_enabled ~= false
				end,
			},
			build_context = function(_unit, _blackboard)
				return { num_nearby = 3 }
			end,
			equipped_combat_ability_name = function()
				return "veteran_stance"
			end,
			fallback_state_by_unit = opts.fallback_state_by_unit or {},
			last_snapshot_t_by_unit = snapshot_state,
			session_start_state = session_start_state,
			snapshot_interval_s = opts.snapshot_interval_s or 30,
			meta_patch_version = "test-version",
			fixed_time = function()
				return fixed_t
			end,
		}
	end

	before_each(function()
		call_log = {}
		emitted_events = {}
		snapshot_state = {}
		session_start_state = { emitted = false }
		fixed_t = 100
		collect_alive_bots_calls = 0
		extension_map = {
			unit_stub = {
				ability_system = test_helper.make_player_ability_extension({
					remaining_ability_charges = function()
						return 2
					end,
				}),
			},
		}
		_G.ScriptUnit = test_helper.make_script_unit_mock(extension_map)
		UpdateDispatcher.init(make_deps())
	end)

	after_each(function()
		_G.ScriptUnit = saved_script_unit
	end)

	it("short-circuits for human-controlled players", function()
		UpdateDispatcher.dispatch(make_self(true), "unit_stub")

		assert.same({}, call_log)
		assert.same({}, emitted_events)
	end)

	it("dispatches ability queue and grenade fallback every frame", function()
		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		assert.truthy(table.concat(call_log, ","):find("ability_queue", 1, true))
		assert.truthy(table.concat(call_log, ","):find("grenade_fallback", 1, true))
	end)

	it("dispatches pinging collaborators when the feature is enabled", function()
		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		assert.truthy(table.concat(call_log, ","):find("ping_system", 1, true))
		assert.truthy(table.concat(call_log, ","):find("companion_tag", 1, true))
	end)

	it("skips pinging collaborators when the feature is disabled", function()
		UpdateDispatcher.init(make_deps({ pinging_enabled = false }))

		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		assert.falsy(table.concat(call_log, ","):find("ping_system", 1, true))
		assert.falsy(table.concat(call_log, ","):find("companion_tag", 1, true))
	end)

	it("emits session_start exactly once across multiple calls", function()
		local self = make_self(false)

		UpdateDispatcher.dispatch(self, "unit_stub")
		UpdateDispatcher.dispatch(self, "unit_stub")

		assert.equals(1, count_events("session_start"))
	end)

	it("does not emit session_start when no alive bots are reported", function()
		UpdateDispatcher.init(make_deps({ bots = {} }))

		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		assert.equals(0, count_events("session_start"))
		assert.is_false(session_start_state.emitted)
	end)

	it("re-emits session_start after the emitted flag is reset", function()
		local self = make_self(false)

		UpdateDispatcher.dispatch(self, "unit_stub")
		session_start_state.emitted = false
		UpdateDispatcher.dispatch(self, "unit_stub")

		assert.equals(2, count_events("session_start"))
		assert.is_true(session_start_state.emitted)
	end)

	it("emits snapshot on first call and again after the cadence elapses", function()
		local self = make_self(false)

		UpdateDispatcher.dispatch(self, "unit_stub")
		fixed_t = fixed_t + 31
		UpdateDispatcher.dispatch(self, "unit_stub")

		assert.equals(2, count_events("snapshot"))
	end)

	it("does not emit snapshot within the cadence window", function()
		local self = make_self(false)

		UpdateDispatcher.dispatch(self, "unit_stub")
		fixed_t = fixed_t + 5
		UpdateDispatcher.dispatch(self, "unit_stub")

		assert.equals(1, count_events("snapshot"))
	end)

	it("sets snapshot cooldown_ready to false when the ability extension is missing", function()
		extension_map.unit_stub = {}

		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		assert.equals(1, count_events("snapshot"))
		assert.is_false(emitted_events[#emitted_events].cooldown_ready)
		assert.is_nil(emitted_events[#emitted_events].charges)
	end)

	-- Explicit order check required by the plan.
	it("calls event_log_flush after grenade fallback and before snapshot emission", function()
		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		local function pos(name)
			for i = 1, #call_log do
				if call_log[i] == name then
					return i
				end
			end
			return -1
		end

		assert.is_true(pos("grenade_fallback") < pos("event_log_flush"))
		assert.is_true(pos("event_log_flush") < pos("snapshot_emit"))
	end)

	it("does not emit snapshots when the event log is disabled", function()
		UpdateDispatcher.init(make_deps({ event_log_enabled = false }))

		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		assert.equals(0, count_events("snapshot"))
	end)

	it("does not collect alive bots when the event log is disabled", function()
		UpdateDispatcher.init(make_deps({ event_log_enabled = false }))

		UpdateDispatcher.dispatch(make_self(false), "unit_stub")

		assert.equals(0, collect_alive_bots_calls)
	end)
end)
