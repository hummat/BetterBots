std = "lua51+luajit"
max_line_length = 120

read_globals = {
	"get_mod",
	"ScriptUnit",
	"cjson",
	"ALIVE",
	"POSITION_LOOKUP",
	"Vector3",
	"Managers",
}

files["tests/**"] = {
	std = "+busted",
}
