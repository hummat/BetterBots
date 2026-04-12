std = "lua51+luajit"
max_line_length = 120

read_globals = {
	"get_mod",
	"ScriptUnit",
	"cjson",
	"ALIVE",
	"BLACKBOARDS",
	"Broadphase",
	"HEALTH_ALIVE",
	"POSITION_LOOKUP",
	"Quaternion",
	"Unit",
	"Vector3",
	"Managers",
}

files["tests/**"] = {
	std = "+busted",
	-- Tests mock engine globals; allow writing to them
	globals = {
		"BLACKBOARDS",
		"POSITION_LOOKUP",
	},
}
