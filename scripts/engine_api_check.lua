-- Engine API contract check, run by scripts/patch-check.sh.
--
-- Anchors in patch-check.sh only cover functions BetterBots hooks. Production
-- code also calls engine extension methods directly (`ability_extension:can_use_ability(...)`)
-- and reads private fields (`ability_extension._equipped_abilities`). When
-- Fatshark removes one, Lua raises "attempt to call a nil value" at runtime and
-- no static check notices (1.13.0 removed `remaining_ability_cooldown`).
--
-- Two surfaces are verified against the decompiled source:
--   1. Production accesses: every `name:member(` / `name.member` where `name` is
--      bound to `ScriptUnit.(has_)extension(unit, "<system>")` must resolve to a
--      method or `self.<field>` of a class under
--      scripts/extension_systems/<system dir>/ (or one of its base classes).
--   2. Mock builder allowlists in tests/test_helper.lua must name members that
--      exist on the specific engine class each builder stands in for.
--
-- Receiver resolution: a binding in the same file wins; otherwise a name bound to
-- exactly one system anywhere in the mod is used, which covers parameters and
-- helper return values that reuse the conventional variable name.

local M = {}

-- System name -> extension_systems directory, only where it differs from the
-- system name minus "_system".
M.SYSTEM_DIRS = {
	interactor_system = "interaction",
}

-- tests/test_helper.lua builder -> engine class it doubles.
M.BUILDER_CLASSES = {
	make_player_unit_data_extension = "PlayerUnitDataExtension",
	make_minion_unit_data_extension = "MinionUnitDataExtension",
	make_player_locomotion_extension = "PlayerUnitLocomotionExtension",
	make_minion_locomotion_extension = "MinionLocomotionExtension",
	make_player_ability_extension = "PlayerUnitAbilityExtension",
	make_player_action_input_extension = "PlayerUnitActionInputExtension",
	make_bot_unit_input = "BotUnitInput",
	make_player_input_extension = "PlayerUnitInputExtension",
	make_bot_perception_extension = "BotPerceptionExtension",
	make_minion_perception_extension = "MinionPerceptionExtension",
	make_bot_behavior_extension = "BotBehaviorExtension",
	make_interactor_extension = "InteractorExtension",
	make_smart_tag_extension = "SmartTagExtension",
	make_coherency_extension = "UnitCoherencyExtension",
	make_player_talent_extension = "PlayerUnitTalentExtension",
	make_player_buff_extension = "PlayerUnitBuffExtension",
	make_companion_spawner_extension = "CompanionSpawnerExtension",
	make_side_system_double = "SideSystem",
	make_liquid_area_system_double = "LiquidAreaSystem",
	make_group_system_double = "GroupSystem",
}

local function shell_quote(value)
	return "'" .. value:gsub("'", "'\"'\"'") .. "'"
end

local function read_file(path)
	local handle = assert(io.open(path, "r"))
	local content = handle:read("*a")
	handle:close()
	return content
end

local function command_lines(command)
	local handle = assert(io.popen(command, "r"))
	local lines = {}
	for line in handle:lines() do
		lines[#lines + 1] = line
	end
	handle:close()
	return lines
end

-- Joins wrapped statements (stylua breaks long `a and b and c` chains and call
-- arguments across lines) so a binding and its system string share one line.
-- Returns { { text = ..., line = first_line_number }, ... }.
function M.logical_lines(source)
	local result = {}
	local current
	local open_parens = 0

	local line_number = 0
	for raw in (source .. "\n"):gmatch("([^\n]*)\n") do
		line_number = line_number + 1
		local code = raw:gsub("%-%-.*$", "")
		local trimmed = code:match("^%s*(.-)%s*$")
		local continues = current
			and (
				open_parens > 0
				or trimmed:match("^and[%s(]")
				or trimmed:match("^or[%s(]")
				or trimmed:match("^[.:)]")
				or current.text:match("[=(,]%s*$")
				or current.text:match("%f[%w_]and%s*$")
				or current.text:match("%f[%w_]or%s*$")
			)

		if continues then
			current.text = current.text .. " " .. trimmed
		else
			current = { text = trimmed, line = line_number }
			result[#result + 1] = current
			open_parens = 0
		end

		local without_strings = trimmed:gsub('"[^"]*"', ""):gsub("'[^']*'", "")
		local _, opens = without_strings:gsub("%(", "")
		local _, closes = without_strings:gsub("%)", "")
		open_parens = math.max(0, open_parens + opens - closes)
	end

	return result
end

-- Returns name -> system for every `name = ...extension(<unit>, "<system>")`
-- binding in the source. Statements naming more than one system are ambiguous
-- and skipped.
function M.collect_bindings(source)
	local bindings = {}
	for _, statement in ipairs(M.logical_lines(source)) do
		local text = statement.text
		if text:find("[Ee]xtension%s*%(") then
			local systems = {}
			for system in text:gmatch('[Ee]xtension%s*%([^()]-,%s*"([%w_]+_system)"%s*%)') do
				systems[system] = true
			end
			local only_system
			local count = 0
			for system in pairs(systems) do
				only_system = system
				count = count + 1
			end
			local name = count == 1 and text:match("([%a_][%w_]*)%s*=[^=]")
			if name then
				bindings[name] = only_system
			end
		end
	end
	return bindings
end

-- Mod-namespaced markers BetterBots stores on engine objects (`self._betterbots_player_unit`,
-- `__bb_*` sentinels) are not engine API.
local function is_mod_owned(member)
	return member:sub(1, 12) == "_betterbots_" or member:sub(1, 4) == "__bb"
end

-- Returns { { name, member, line }, ... } for `name:member(` calls and `name.member`
-- reads. Assignments are writes, not API reads, and are skipped. Receivers that
-- are themselves fields (`Managers.state.extension:system()`) are skipped: their
-- variable name says nothing about which engine object they hold. Matching runs on
-- the whole file so calls wrapped before `:` or `(` are still seen; `line` is the
-- line holding the member name.
function M.collect_accesses(source)
	local stripped = {}
	for raw in (source .. "\n"):gmatch("([^\n]*)\n") do
		stripped[#stripped + 1] = raw:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%-%-.*$", "")
	end
	local code = table.concat(stripped, "\n")

	local accesses = {}
	local line_number = 1
	local counted_to = 0
	for start, name, separator, member_start, member, rest in
		code:gmatch("()([%a_][%w_]*)%s*([.:])%s*()([%a_][%w_]*)()")
	do
		local receiver_is_field = code:sub(math.max(1, start - 256), start - 1):match("[.:]%s*$")
		local tail = code:sub(rest, rest + 64)
		local is_read = separator == "." and not tail:match("^%s*=[^=]")
		local is_call = separator == ":" and tail:match("^%s*%(")
		if not receiver_is_field and (is_read or is_call) and not is_mod_owned(member) then
			local _, newlines = code:sub(counted_to + 1, member_start - 1):gsub("\n", "")
			line_number = line_number + newlines
			counted_to = member_start - 1
			accesses[#accesses + 1] = { name = name, member = member, line = line_number }
		end
	end
	return accesses
end

-- Returns builder -> { member, ... } from `_apply_audited_overrides("builder", ..., { member = true })`.
function M.collect_builder_allowlists(source)
	local allowlists = {}
	for builder, body in source:gmatch('_apply_audited_overrides%("([%w_]+)"[^{]-(%b{})') do
		local members = {}
		for member in body:gmatch("([%a_][%w_]*)%s*=%s*true") do
			members[#members + 1] = member
		end
		allowlists[builder] = members
	end
	return allowlists
end

-- Engine index over the decompiled checkout. Members are methods defined as
-- `Class.name = function` plus every `self.name =` assignment in the class file,
-- inherited through `class("Name", "Base")`.
function M.new_engine_index(decompile_root)
	local index = { root = decompile_root, classes = {}, members_cache = {} }

	local declarations = command_lines(
		"rg -n --no-heading -o "
			.. shell_quote('class\\("[A-Za-z0-9_]+"(, *"[A-Za-z0-9_]+")?\\)')
			.. " -g '*.lua' "
			.. shell_quote(decompile_root .. "/scripts")
	)
	for _, line in ipairs(declarations) do
		local path, declaration = line:match("^(.-):%d+:(.*)$")
		local name = declaration and declaration:match('^class%("([%w_]+)"')
		if name and not index.classes[name] then
			index.classes[name] = {
				path = path,
				base = declaration:match('^class%("[%w_]+",%s*"([%w_]+)"'),
			}
		end
	end

	return index
end

function M.class_members(index, class_name)
	local cached = index.members_cache[class_name]
	if cached then
		return cached
	end

	local members = {}
	index.members_cache[class_name] = members
	local class = index.classes[class_name]
	if not class then
		return members
	end

	local source = read_file(class.path)
	local escaped = class_name:gsub("%p", "%%%0")
	for member in source:gmatch("\n" .. escaped .. "%.([%a_][%w_]*)%s*=%s*function") do
		members[member] = true
	end
	for member in source:gmatch("self%.([%a_][%w_]*)%s*=[^=]") do
		members[member] = true
	end
	if class.base then
		for member in pairs(M.class_members(index, class.base)) do
			members[member] = true
		end
	end

	return members
end

function M.system_members(index, system)
	local dir = M.SYSTEM_DIRS[system] or system:gsub("_system$", "")
	local prefix = index.root .. "/scripts/extension_systems/" .. dir .. "/"
	local members = {}
	local found_class = false
	for class_name, class in pairs(index.classes) do
		if class.path:sub(1, #prefix) == prefix then
			found_class = true
			for member in pairs(M.class_members(index, class_name)) do
				members[member] = true
			end
		end
	end
	return found_class and members or nil, dir
end

-- Runs both checks. Returns errors (list of strings) and a summary table.
function M.run(repo_root, decompile_root)
	local index = M.new_engine_index(decompile_root)
	local errors = {}
	local summary = { accesses = 0, systems = 0, builder_members = 0 }

	local mod_files =
		command_lines("rg --files -g '*.lua' " .. shell_quote(repo_root .. "/scripts/mods/BetterBots") .. " | sort")
	local sources = {}
	local global_bindings = {}
	local ambiguous = {}
	for _, path in ipairs(mod_files) do
		local source = read_file(path)
		local bindings = M.collect_bindings(source)
		sources[#sources + 1] = { path = path, source = source, bindings = bindings }
		for name, system in pairs(bindings) do
			if global_bindings[name] and global_bindings[name] ~= system then
				ambiguous[name] = true
			end
			global_bindings[name] = system
		end
	end
	for name in pairs(ambiguous) do
		global_bindings[name] = nil
	end

	local system_cache = {}
	local seen_systems = {}
	for _, file in ipairs(sources) do
		local accesses = M.collect_accesses(file.source)
		local relative = file.path:sub(#repo_root + 2)
		for _, access in ipairs(accesses) do
			local system = file.bindings[access.name] or global_bindings[access.name]
			if system then
				if system_cache[system] == nil then
					local members, dir = M.system_members(index, system)
					system_cache[system] = members or false
					if not members then
						errors[#errors + 1] = string.format(
							"%s used by BetterBots has no engine classes under scripts/extension_systems/%s/"
								.. " (add it to SYSTEM_DIRS in scripts/engine_api_check.lua)",
							system,
							dir
						)
					end
				end
				local members = system_cache[system]
				seen_systems[system] = true
				summary.accesses = summary.accesses + 1
				if members and not members[access.member] then
					errors[#errors + 1] = string.format(
						"%s:%d: %s.%s not found on any %s engine class",
						relative,
						access.line,
						access.name,
						access.member,
						system
					)
				end
			end
		end
	end
	for _ in pairs(seen_systems) do
		summary.systems = summary.systems + 1
	end

	local helper_path = repo_root .. "/tests/test_helper.lua"
	local allowlists = M.collect_builder_allowlists(read_file(helper_path))
	for builder, members in pairs(allowlists) do
		local class_name = M.BUILDER_CLASSES[builder]
		if not class_name then
			errors[#errors + 1] = "tests/test_helper.lua: builder "
				.. builder
				.. " has no engine class mapping (add it to BUILDER_CLASSES in scripts/engine_api_check.lua)"
		elseif not index.classes[class_name] then
			errors[#errors + 1] = "tests/test_helper.lua: "
				.. builder
				.. " doubles "
				.. class_name
				.. ", which no longer exists in the decompiled source"
		else
			local class_members = M.class_members(index, class_name)
			for _, member in ipairs(members) do
				summary.builder_members = summary.builder_members + 1
				if not class_members[member] then
					errors[#errors + 1] = "tests/test_helper.lua: "
						.. builder
						.. " allows "
						.. member
						.. ", which "
						.. class_name
						.. " does not define"
				end
			end
		end
	end

	table.sort(errors)
	return errors, summary
end

if arg and arg[0] and arg[0]:match("engine_api_check%.lua$") then
	local repo_root, decompile_root = arg[1], arg[2]
	if not repo_root or not decompile_root then
		io.stderr:write("usage: lua scripts/engine_api_check.lua <repo_root> <decompile_root>\n")
		os.exit(2)
	end
	local errors, summary = M.run(repo_root, decompile_root)
	for _, message in ipairs(errors) do
		print("ERROR: engine API " .. message)
	end
	print(
		string.format(
			"  %s:  engine API usage -> %d production accesses across %d systems, %d mock allowlist members",
			#errors == 0 and "ok" or "--",
			summary.accesses,
			summary.systems,
			summary.builder_members
		)
	)
	os.exit(#errors == 0 and 0 or 1)
end

return M
