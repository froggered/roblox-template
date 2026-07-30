-- Read-side helpers over Data/Products. Nothing here knows what a group
-- MEANS — it only flattens the catalog so callers can look up by id or list
-- what's on sale without walking the nested shape by hand.
--
-- Entries with no Id are INERT and are skipped by every function here (see
-- the header of Data/Products for why).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Products = require(ReplicatedStorage.Data.Products)

local ProductUtil = {}

export type Entry = {
	key: string,     -- the entry's key within its group ("CoinsSmall")
	group: string,   -- the group it came from ("Currency")
	Name: string,
	Id: number,
	Type: EnumItem,
	ForSale: boolean?,
	[string]: any,
}

local flat: { Entry } = {}
local byId: { [number]: Entry } = {}
local byKey: { [string]: Entry } = {}

for groupName, group in Products do
	for key, entry in group do
		if type(entry) ~= "table" or not entry.Id then continue end -- inert
		local resolved = table.clone(entry) :: any
		resolved.key   = key
		resolved.group = groupName
		resolved.Name  = entry.Name or key
		table.insert(flat, resolved)

		-- Ids and keys are both used as lookup keys downstream (receipts by
		-- id, everything else by key), so a duplicate would make a grant
		-- unreachable. Loud at require time beats silent in production.
		if byId[entry.Id] then
			warn(`[ProductUtil] duplicate product id {entry.Id}: {byId[entry.Id].key} and {key}`)
		end
		if byKey[key] then
			warn(`[ProductUtil] duplicate product key "{key}" in {byKey[key].group} and {groupName}`)
		end
		byId[entry.Id]  = resolved
		byKey[key]      = resolved
	end
end

-- Every live catalog entry, flattened. Order is undefined.
function ProductUtil.all(): { Entry }
	return flat
end

-- Every live entry in one group, e.g. ProductUtil.group("Currency").
function ProductUtil.group(groupName: string): { Entry }
	local result = {}
	for _, entry in flat do
		if entry.group == groupName then table.insert(result, entry) end
	end
	return result
end

-- The entry behind an asset id, or nil for an id we don't sell.
function ProductUtil.byId(id: number): Entry?
	return byId[id]
end

-- The entry with this catalog key, from any group. Keys are unique across the
-- whole catalog — this is how gameplay code names a product.
function ProductUtil.byKey(key: string): Entry?
	return byKey[key]
end

-- Entries of one InfoType, e.g. ProductUtil.ofType(Enum.InfoType.GamePass).
function ProductUtil.ofType(infoType: EnumItem): { Entry }
	local result = {}
	for _, entry in flat do
		if entry.Type == infoType then table.insert(result, entry) end
	end
	return result
end

-- Shop listing for a group: live, ForSale entries only.
function ProductUtil.forSale(groupName: string?): { Entry }
	local result = {}
	for _, entry in flat do
		if entry.ForSale and (groupName == nil or entry.group == groupName) then
			table.insert(result, entry)
		end
	end
	return result
end

------------------------------------------------
-- Prices
------------------------------------------------
-- Robux price for an entry. YIELDS on a cold cache (one web call per id per
-- server), nil if the lookup fails — callers should leave the label alone
-- rather than render "0 R$".
local priceCache: { [number]: number } = {}

function ProductUtil.getPrice(entry: Entry): number?
	if priceCache[entry.Id] then return priceCache[entry.Id] end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.Id, entry.Type)
	if not ok or not info then
		warn(`[ProductUtil] price lookup failed for {entry.key}: {info}`)
		return nil
	end
	priceCache[entry.Id] = info.PriceInRobux or 0
	return priceCache[entry.Id]
end

-- Prompts the right purchase flow for either product type.
function ProductUtil.prompt(player: Player, entry: Entry)
	if entry.Type == Enum.InfoType.GamePass then
		MarketplaceService:PromptGamePassPurchase(player, entry.Id)
	else
		MarketplaceService:PromptProductPurchase(player, entry.Id)
	end
end

return ProductUtil
