-- THE monetization catalog. Every gamepass and developer product id in the
-- game lives here exactly once — shop UI, receipt handling, ownership checks
-- and price labels all read this table, so an id is never written twice.
--
-- Groups are arbitrary; add your own. Modules/ProductUtil flattens them, so
-- nothing downstream needs to know the group layout.
--
-- ENTRY SHAPE
--   Name        string           display name (falls back to the key)
--   Description string?          shop blurb
--   Id          number           the real asset id. Leave nil while the
--                                product is unmade: an entry with no Id is
--                                INERT — never mapped to a receipt, never
--                                prompted, never listed for sale. This is the
--                                safe way to design the shop before the
--                                products exist.
--   Type        Enum.InfoType    Product (dev product) or GamePass
--   ForSale     boolean          shown in the shop. Retired products keep
--                                their entry (ForSale = false) so old
--                                receipts still resolve — NEVER delete an id.
--   Thumbnail   string?          rbxassetid:// for the shop tile
--
-- Group-specific fields (Currency.Quantity, Passes.Grants, ...) are read by
-- ServerModules/MarketFunctions — see there for what a group means.
return {
	--[[

		DEVELOPER PRODUCTS — currency packs

		Quantity per Robux must rise MONOTONICALLY with pack size, or a
		smaller pack is strictly better value and the ladder leaks revenue.

	]]
	Currency = {
		CoinsSmall  = { Name = "Handful of Coins", Currency = "Coins", Quantity = 400,   Id = nil, Type = Enum.InfoType.Product, ForSale = true },
		CoinsMedium = { Name = "Bag of Coins",     Currency = "Coins", Quantity = 2600,  Id = nil, Type = Enum.InfoType.Product, ForSale = true },
		CoinsLarge  = { Name = "Chest of Coins",   Currency = "Coins", Quantity = 8000,  Id = nil, Type = Enum.InfoType.Product, ForSale = true },
		CoinsHuge   = { Name = "Vault of Coins",   Currency = "Coins", Quantity = 70000, Id = nil, Type = Enum.InfoType.Product, ForSale = true },
	},

	--[[

		DEVELOPER PRODUCTS — everything else

		Each entry needs a grant function in ServerModules/MarketFunctions,
		keyed by the SAME key used here.

	]]
	Products = {
		-- Example = { Name = "Example", Id = nil, Type = Enum.InfoType.Product, ForSale = true },
	},

	--[[

		GAMEPASSES

		Ownership is polled on join and cached on the profile under
		Gamepasses[tostring(Id)], so client-side gates never need a web call.

	]]
	Passes = {
		-- VIP = {
		-- 	Name        = "VIP",
		-- 	Description = "Double coins from every reward",
		-- 	Id          = nil,
		-- 	Type        = Enum.InfoType.GamePass,
		-- 	ForSale     = true,
		-- },
	},
}
