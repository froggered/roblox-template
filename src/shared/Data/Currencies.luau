-- Every persistent currency in the game, keyed by its DataTemplate key.
-- DataManager.AddCurrency is the ONLY writer; it reads this table to decide
-- what to mirror (leaderstats / attributes) and how to log the economy event.
--
-- Adding a currency = add a key here + the same key in ServerData/DataTemplate.
--
--   Leaderstat -- also mirror into player.leaderstats (the platform playerlist)
--   Attribute  -- also mirror onto the Player as an attribute. Turn this on
--                 ONLY for a value OTHER players need to read — something
--                 rendered over someone's head, or read off a nearby player.
--                 The owner's own balance already reaches their client on the
--                 data replica, so mirroring that is duplicate replication of
--                 the same number. A wallet is private; a level badge is not.
--   Board      -- OrderedDataStore name for the global board, or nil for none
--                 (must also be listed in ServerModules/LeaderboardManager)
return {
	Coins = {
		Name       = "Coins",
		Leaderstat = false,
		Attribute  = false, -- private: the owner reads it off the replica
		Board      = "LB_Coins",
	},

	-- Gems = {
	-- 	Name       = "Gems",
	-- 	Leaderstat = false,
	-- 	Attribute  = false,
	-- 	Board      = nil,
	-- },
}
