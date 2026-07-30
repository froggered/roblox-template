-- Robux purchases: receipts, gamepass ownership, purchase prompts.
--
-- The grant itself lives in MarketFunctions; this module is the plumbing that
-- makes a grant exactly-once and durable.
local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local DataService     = require(ReplicatedStorage.Packages.DataService).server
local MarketFunctions = require(script.Parent.MarketFunctions)
local ProductUtil     = require(ReplicatedStorage.Modules.ProductUtil)
local Remotes         = require(ReplicatedStorage.Modules.Remotes)

local MarketManager = {}

local PurchaseMade = Remotes.event("PurchaseMade") -- client-side celebration/sfx
local MAX_CACHE_SIZE = 100 -- purchase ids kept per profile

------------------------------------------------
-- Receipts
------------------------------------------------
-- The exactly-once guarantee. Roblox only stops retrying a receipt once we
-- return PurchaseGranted, so we must not say "granted" until the grant is
-- SAVED — a server crash between granting and saving would otherwise eat the
-- purchase. So: grant, record the purchase id on the profile, force a save,
-- and only confirm once that save lands.
local function checkPurchaseIdAsync(profile, purchaseId, grant): Enum.ProductPurchaseDecision
	if not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseIdCache = profile.Data.PurchaseIdCache
	if not purchaseIdCache then
		purchaseIdCache = {}
		profile.Data.PurchaseIdCache = purchaseIdCache
	end

	if not table.find(purchaseIdCache, purchaseId) then
		local success, err = pcall(grant)
		if not success then
			warn(`[MarketManager] grant failed for {profile.Key} / {purchaseId}: {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		while #purchaseIdCache >= MAX_CACHE_SIZE do
			table.remove(purchaseIdCache, 1)
		end
		table.insert(purchaseIdCache, purchaseId)
	end

	local function isPurchaseSaved()
		local savedCache = profile.LastSavedData.PurchaseIdCache
		return savedCache and table.find(savedCache, purchaseId) ~= nil
	end

	if isPurchaseSaved() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	while profile:IsActive() do
		local lastSavedDataCopy = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == lastSavedDataCopy then
			profile.OnAfterSave:Wait()
		end
		if isPurchaseSaved() then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if profile:IsActive() then
			task.wait(10)
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- They left mid-purchase. Roblox re-delivers the receipt next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	DataService:waitForData(player)
	if not DataService:hasProfile(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService:getProfile(player)

	local entry = ProductUtil.byId(receiptInfo.ProductId)
	local grant = entry and MarketFunctions[entry.key]
	if not grant then
		-- Unmapped id: leave the receipt PENDING rather than swallow it. Map
		-- the product and the player gets what they paid for on their next
		-- join, no refund needed.
		warn(`[MarketManager] no grant function for product {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return checkPurchaseIdAsync(profile, receiptInfo.PurchaseId, function()
		grant(player, entry, receiptInfo)
		PurchaseMade:FireClient(player, entry.key)
	end)
end

MarketplaceService.ProcessReceipt = processReceipt

------------------------------------------------
-- Gamepasses
------------------------------------------------
-- Records ownership on the profile through DataService:set — the
-- replica-aware path. Writing profile.Data directly persists fine but never
-- reaches the client's copy, so every client-side gate reads "unowned" for
-- the rest of the session.
local function recordOwnership(player: Player, entry)
	if not DataService:hasProfile(player) then return end
	DataService:set(player, { "Gamepasses", tostring(entry.Id) }, true)
	local grant = MarketFunctions[entry.key]
	if grant then grant(player, entry) end
end

-- Cheap ownership test for gameplay code: the cached profile record, no web
-- call. Accurate from the moment refreshOwnership finishes on join.
function MarketManager.OwnsPass(player: Player, key: string): boolean
	if not DataService:hasProfile(player) then return false end
	local entry = ProductUtil.byKey(key)
	if not entry then return false end
	return DataService:get(player, { "Gamepasses", tostring(entry.Id) }) == true
end

-- Re-checks every pass against the web and applies the ones they own. Passes
-- are checked IN PARALLEL: run sequentially, a player with several passes
-- waits several round trips before their profile reflects reality.
function MarketManager.RefreshOwnership(player: Player)
	if not DataService:hasProfile(player) then return end

	for _, entry in ProductUtil.ofType(Enum.InfoType.GamePass) do
		task.spawn(function()
			local owned = DataService:get(player, { "Gamepasses", tostring(entry.Id) }) == true
			if not owned then
				local ok, result = pcall(
					MarketplaceService.UserOwnsGamePassAsync,
					MarketplaceService, player.UserId, entry.Id
				)
				if not ok then
					warn(`[MarketManager] ownership check failed for {entry.key}: {result}`)
					return
				end
				owned = result
			end
			if owned then
				recordOwnership(player, entry)
			end
		end)
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end
	local entry = ProductUtil.byId(passId)
	if not entry then return end
	recordOwnership(player, entry)
	PurchaseMade:FireClient(player, entry.key)
end)

------------------------------------------------
-- Prompts
------------------------------------------------
-- Prompt by catalog key, from anywhere: MarketManager.Prompt(player, "VIP").
-- A pass they already own is silently skipped instead of showing them a
-- "you already own this" dialog.
function MarketManager.Prompt(player: Player, key: string)
	local entry = ProductUtil.byKey(key)
	if not entry then
		warn(`[MarketManager] no catalog entry named "{key}"`)
		return
	end
	if entry.Type == Enum.InfoType.GamePass and MarketManager.OwnsPass(player, key) then
		return
	end
	ProductUtil.prompt(player, entry)
end

------------------------------------------------
-- Startup
------------------------------------------------
function MarketManager.start()
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			DataService:waitForData(player)
			MarketManager.RefreshOwnership(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return MarketManager
