local Perf = dofile("scripts/mods/BetterBots/perf.lua")

describe("perf", function()
	local _setting_enabled

	local function reset()
		_setting_enabled = false

		Perf.init({
			get_setting = function()
				return _setting_enabled
			end,
			setting_id = "enable_perf_timing",
		})
	end

	before_each(function()
		reset()
	end)

	it("starts recording immediately when the setting is enabled mid-run", function()
		Perf.enter_run()
		assert.is_false(Perf.is_enabled())

		_setting_enabled = true
		assert.is_true(Perf.sync_setting())
		assert.is_true(Perf.is_enabled())

		local t0 = Perf.begin()
		Perf.finish("update", t0, 0.0002)
		Perf.mark_bot_frame()

		local report = Perf.report_and_reset()
		assert.is_not_nil(report)
		assert.equals(1, report.bot_frames)
		assert.equals(1, report.total_calls)
		assert.is_true(report.total_us_per_bot_frame > 0)
	end)

	it("stops recording when the setting is disabled mid-run but preserves prior samples", function()
		_setting_enabled = true
		Perf.enter_run()
		assert.is_true(Perf.is_enabled())

		local t0 = Perf.begin()
		Perf.finish("update", t0, 0.0003)
		Perf.mark_bot_frame()

		_setting_enabled = false
		assert.is_false(Perf.sync_setting())
		assert.is_false(Perf.is_enabled())

		local disabled_t0 = Perf.begin()
		assert.is_nil(disabled_t0)

		local report = Perf.report_and_reset()
		assert.is_not_nil(report)
		assert.equals(1, report.bot_frames)
		assert.equals(1, report.total_calls)
	end)

	it("aggregates per-tag totals and resets after reporting", function()
		_setting_enabled = true
		Perf.enter_run()

		Perf.mark_bot_frame()
		Perf.finish("ability_queue", Perf.begin(), 0.0001)
		Perf.finish("grenade_fallback", Perf.begin(), 0.0002)
		Perf.finish("target_selection", Perf.begin(), 0.00005)

		local report = Perf.report_and_reset()
		assert.is_not_nil(report)
		assert.equals(1, report.bot_frames)
		assert.equals(3, report.total_calls)
		assert.is_true(report.total_us_per_bot_frame > 300)
		assert.equals(100, math.floor(report.tags.ability_queue.total_us + 0.5))
		assert.equals(200, math.floor(report.tags.grenade_fallback.total_us + 0.5))
		assert.equals(50, math.floor(report.tags.target_selection.total_us + 0.5))

		assert.is_nil(Perf.report_and_reset())
	end)

	it("records breakdown tags without inflating headline totals", function()
		_setting_enabled = true
		Perf.enter_run()

		Perf.mark_bot_frame()
		Perf.finish("grenade_fallback", Perf.begin(), 0.0003)
		Perf.finish("grenade_fallback.build_context", Perf.begin(), 0.0001, { include_total = false })
		Perf.finish("grenade_fallback.heuristic", Perf.begin(), 0.00005, { include_total = false })

		local report = Perf.report_and_reset()
		assert.is_not_nil(report)
		assert.equals(1, report.bot_frames)
		assert.equals(1, report.total_calls)
		assert.equals(300, math.floor(report.total_us_per_bot_frame + 0.5))
		assert.equals(300, math.floor(report.tags.grenade_fallback.total_us + 0.5))
		assert.equals(100, math.floor(report.tags["grenade_fallback.build_context"].total_us + 0.5))
		assert.equals(50, math.floor(report.tags["grenade_fallback.heuristic"].total_us + 0.5))
	end)
end)
