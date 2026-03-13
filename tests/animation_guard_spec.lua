local function load_animation_guard()
	local ok, animation_guard = pcall(dofile, "scripts/mods/BetterBots/animation_guard.lua")
	assert.is_true(ok, "animation_guard.lua should load")
	return animation_guard
end

describe("animation_guard", function()
	it("treats nil variable ids as invalid", function()
		local AnimationGuard = load_animation_guard()
		assert.is_false(AnimationGuard.is_valid_variable_index(nil))
	end)

	it("treats 0xFFFFFFFF sentinel variable ids as invalid", function()
		local AnimationGuard = load_animation_guard()
		assert.is_false(AnimationGuard.is_valid_variable_index(4294967295))
	end)

	it("treats normal variable ids as valid", function()
		local AnimationGuard = load_animation_guard()
		assert.is_true(AnimationGuard.is_valid_variable_index(17))
	end)
end)
