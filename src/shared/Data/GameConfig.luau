-- Tunable game-wide constants. Anything a designer might want to change
-- without reading code belongs here, not inline in a module.
return {
	------------------------------------------------
	-- Data
	------------------------------------------------
	-- ProfileStore index. Studio uses a SEPARATE index so live player data is
	-- untouchable from Studio (needs Studio API access enabled in Game
	-- Settings). Rename PROFILE_STORE per project — the name is the store.
	PROFILE_STORE        = "Game",
	PROFILE_STORE_STUDIO = "Test",

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
