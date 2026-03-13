-- Shared rule tables used across multiple BetterBots modules.
-- Keep duplicated gameplay identifiers here so drift becomes a single-file edit.
local M = {}

M.DAEMONHOST_BREED_NAMES = {
	chaos_daemonhost = true,
	chaos_mutator_daemonhost = true,
}

M.RESCUE_CHARGE_RULES = {
	ogryn_charge_ally_aid = true,
	zealot_dash_ally_aid = true,
	adamant_charge_ally_aid = true,
}

return M
