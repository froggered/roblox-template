-- What each product DOES when bought, keyed by its key in Data/Products.
--
-- Keyed by key, not by asset id, so a product can be written and tested
-- before its id exists — MarketManager resolves receipt id -> catalog entry
-- -> this table.
--
--   fn(player, entry, receiptInfo?) -> ()
--
-- Two rules, both about being called more than once:
--
--  * DEV PRODUCTS: a grant that errors is retried on the next receipt pass,
--    and only a grant that SAVES is confirmed to Roblox. Never mark anything
--    "already given" outside the profile.
--  * GAMEPASSES: the grant runs on purchase AND on every subsequent join
--    (that's how a pass keeps applying). Make pass grants idempotent — set a
--    flag, don't add to a balance. A pass that should pay out ONCE must check
--    a Claimed flag on the profile itself.
--
-- A product with no entry here is NEVER confirmed: the receipt stays pending
-- and Roblox retries it. That's deliberate — it means an unfinished product
-- can't take Robux and award nothing.
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.ServerModules.DataManager)
local ProductUtil = require(ReplicatedStorage.Modules.ProductUtil)

local functions: { [string]: (player: Player, entry: any, receiptInfo: any?) -> () } = {}

------------------------------------------------
-- Currency packs (generated from the catalog)
------------------------------------------------
for _, entry in ProductUtil.group("Currency") do
	functions[entry.key] = function(player, product)
		DataManager.AddCurrency(player, product.Currency, product.Quantity, product.key)
	end
end

------------------------------------------------
-- Everything else
------------------------------------------------
-- functions.VIP = function(player, entry)
-- 	-- idempotent: safe to run on every join
-- 	DataManager.GrantItem(player, "Titles", "VIP")
-- end

return functions
