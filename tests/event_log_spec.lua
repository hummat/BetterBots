-- Stub cjson for test environment
_G.cjson = _G.cjson
	or {
		encode = function(t)
			-- Minimal JSON-like serialization for test assertions
			return tostring(t)
		end,
	}

local EventLog = dofile("scripts/mods/BetterBots/event_log.lua")

describe("event_log", function()
	local saved_mods

	before_each(function()
		saved_mods = rawget(_G, "Mods")
		EventLog._reset()
		EventLog.init({
			mod = { warning = function() end },
			context_snapshot = function(ctx)
				return { num_nearby = ctx and ctx.num_nearby or 0 }
			end,
		})
	end)

	after_each(function()
		_G.Mods = saved_mods
	end)

	describe("emit", function()
		it("does not buffer when disabled", function()
			EventLog.set_enabled(false)
			EventLog.emit({ event = "test" })
			assert.are.equal(0, #EventLog._get_buffer())
		end)

		it("buffers when enabled", function()
			EventLog.set_enabled(true)
			EventLog.emit({ event = "test" })
			assert.are.equal(1, #EventLog._get_buffer())
		end)

		it("accumulates multiple events", function()
			EventLog.set_enabled(true)
			EventLog.emit({ event = "a" })
			EventLog.emit({ event = "b" })
			EventLog.emit({ event = "c" })
			assert.are.equal(3, #EventLog._get_buffer())
		end)
	end)

	describe("emit_decision", function()
		it("logs true decisions with context snapshot", function()
			EventLog.set_enabled(true)
			EventLog.emit_decision(100, 1, "zealot_dash", "zealot_dash", true, "some_rule", "bt", { num_nearby = 5 })
			local buf = EventLog._get_buffer()
			assert.are.equal(1, #buf)
			assert.are.equal("decision", buf[1].event)
			assert.is_true(buf[1].result)
			assert.are.equal("some_rule", buf[1].rule)
			assert.are.equal(1, buf[1].bot)
			assert.are.equal("bt", buf[1].source)
			assert.are.equal(5, buf[1].ctx.num_nearby)
		end)

		it("logs false decisions with skipped_since_last", function()
			EventLog.set_enabled(true)
			EventLog.emit_decision(100, 1, "zealot_dash", "zealot_dash", false, "hold_a", "fallback", {})
			local buf = EventLog._get_buffer()
			assert.are.equal(1, #buf)
			assert.is_false(buf[1].result)
			assert.are.equal(1, buf[1].skipped_since_last)
		end)

		it("increments skip count across false decisions then resets", function()
			EventLog.set_enabled(true)
			-- First false
			EventLog.emit_decision(100, 2, "ogryn_charge", "ogryn_charge", false, "hold", "fallback", {})
			-- Second false
			EventLog.emit_decision(101, 2, "ogryn_charge", "ogryn_charge", false, "hold", "fallback", {})
			local buf = EventLog._get_buffer()
			assert.are.equal(2, #buf)
			assert.are.equal(1, buf[1].skipped_since_last)
			assert.are.equal(1, buf[2].skipped_since_last) -- reset after each emit
		end)

		it("tracks skip counts per bot+ability independently", function()
			EventLog.set_enabled(true)
			EventLog.emit_decision(100, 1, "zealot_dash", "zealot_dash", false, "hold", "bt", {})
			EventLog.emit_decision(100, 2, "ogryn_charge", "ogryn_charge", false, "hold", "bt", {})
			local buf = EventLog._get_buffer()
			assert.are.equal(1, buf[1].skipped_since_last)
			assert.are.equal(1, buf[2].skipped_since_last)
		end)
	end)

	describe("next_attempt_id", function()
		it("returns monotonically increasing IDs", function()
			local id1 = EventLog.next_attempt_id()
			local id2 = EventLog.next_attempt_id()
			local id3 = EventLog.next_attempt_id()
			assert.are.equal(1, id1)
			assert.are.equal(2, id2)
			assert.are.equal(3, id3)
		end)

		it("resets on start_session", function()
			EventLog.set_enabled(true)
			EventLog.next_attempt_id()
			EventLog.next_attempt_id()
			EventLog.start_session(0)
			local id = EventLog.next_attempt_id()
			assert.are.equal(1, id)
		end)
	end)

	describe("is_enabled", function()
		it("reflects set_enabled state", function()
			assert.is_false(EventLog.is_enabled())
			EventLog.set_enabled(true)
			assert.is_true(EventLog.is_enabled())
			EventLog.set_enabled(false)
			assert.is_false(EventLog.is_enabled())
		end)
	end)

	describe("flush", function()
		it("clears the buffer without crashing when io.open fails", function()
			_G.Mods = {
				lua = {
					io = {
						open = function()
							return nil, "permission denied"
						end,
					},
					os = {
						execute = function() end,
						time = function()
							return 123
						end,
					},
				},
			}

			EventLog._reset()
			EventLog.init({
				mod = { warning = function() end },
				context_snapshot = function(ctx)
					return { num_nearby = ctx and ctx.num_nearby or 0 }
				end,
			})
			EventLog.set_enabled(true)
			EventLog.start_session(0)
			EventLog.emit({ event = "test" })

			local ok, err = pcall(function()
				EventLog.end_session()
			end)

			assert.is_true(ok)
			assert.is_nil(err)
			assert.are.equal(0, #EventLog._get_buffer())
		end)
	end)
end)
