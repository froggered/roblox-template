-- The shape of a player profile. ProfileStore reconciles this into every
-- stored profile on load, so ADDING a key is free — existing players get the
-- default on their next join.
--
-- RULES
--  * JSON only: no Vector3/CFrame/Color3/Instance, no mixed array+dict
--    tables, no nil holes in arrays. Store a Color3 as { R, G, B }.
--  * Give every key a real default so readers never need a fallback. A key
--    that is legitimately absent (`nil`) can't be reconciled — document it.
--  * Never COMPUTE a value here (os.time(), math.random()): the module is
--    required once per server, so every profile created that session would
--    share the same value. Seed per-profile values in DataManager's
--    onPlayerInit instead.
--  * Removing a key does NOT strip it from stored profiles. Old keys linger
--    harmlessly; that's the migration escape hatch.
return {
	------------------------------------------------
	-- Currencies (keys must match Data/Currencies)
	------------------------------------------------
	Coins = 0,

	------------------------------------------------
	-- Collection
	------------------------------------------------
	Inventory = {
		-- Owned things, as sets keyed by catalog name: Hats = { Top = true }
	},
	Equipped = {
		-- The single equipped thing per slot: Hat = "Top"
	},

	------------------------------------------------
	-- Progress
	------------------------------------------------
	Stats = {
		JoinCount  = 0,
		TimePlayed = 0, -- seconds, accumulated on leave
	},

	------------------------------------------------
	-- Monetization
	------------------------------------------------
	-- [tostring(gamepassId)] = true. Written by MarketManager's join poll and
	-- its purchase handler; string keys because JSON has no integer keys.
	Gamepasses = {},
	-- Receipt dedupe ring buffer (MarketManager). Server-only — never
	-- replicated to the client.
	PurchaseIdCache = {},

	------------------------------------------------
	-- Client-owned preferences (the client may write these locally)
	------------------------------------------------
	Settings = {
		Music  = true,
		SFX    = true,
		Volume = 1,
	},

	------------------------------------------------
	-- Session bookkeeping
	------------------------------------------------
	CreatedAt  = 0,   -- stamped once in onPlayerInit
	LastPlayed = nil, -- nil means NEVER PLAYED — the first-join test
}
