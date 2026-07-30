-- Tunable game-wide constants. Anything a designer might want to change
-- without reading code belongs here, not inline in a module.
return {
	------------------------------------------------
	-- Leaderboards (OrderedDataStore)
	------------------------------------------------
	BOARD_TOP_N   = 10, -- entries fetched per board
	BOARD_CACHE_S = 60, -- one fetch a minute per board serves the whole server

	------------------------------------------------
	-- Gameplay
	------------------------------------------------
	WALK_SPEED = 16,
}
