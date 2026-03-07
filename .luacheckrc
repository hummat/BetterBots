std = "lua51+luajit"
max_line_length = 120

read_globals = {
	"get_mod",
	"ScriptUnit",
	"cjson",
}

files["tests/**"] = {
	std = "+busted",
}
