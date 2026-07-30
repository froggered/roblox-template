-- THE writer for core player data.
--
-- Every currency change in the game goes through AddCurrency/TrySpend — not
-- through DataService:set, not through profile.Data. That's what makes the
-- economy auditable: one place mirrors the balance onto the player, one place
-- logs the analytics event, one place can add a cap or an anti-cheat check
-- later. Gameplay modules call DataManager; they never touch the profile.
--
-- Reads are cheap and unrestricted: DataService:get(player, path) anywhere.
local AnalyticsService     = game:GetService("AnalyticsService")
local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local RunService           = game:GetService("RunService")
local ServerScriptService  = game:GetService("ServerScriptService")

local DataService  = require(ReplicatedStorage.Packages.DataService).server
local Currencies   = require(ReplicatedStorage.Data.Currencies)
local GameConfig   = require(ReplicatedStorage.Data.GameConfig)
local ProductUtil  = require(ReplicatedStorage.Modules.ProductUtil)
local Template     = require(ServerScriptService.ServerData.DataTemplate)
local LeaderboardManager = require(script.Parent.LeaderboardManager)

local DataManager = {}

local sessionStart: { [Player]: number } = {}

------------------------------------------------
-- Startup
------------------------------------------------
-- Call ONCE, first thing in Main.server.luau, before any module that reads
-- player data. Opens the profile store and starts loading profiles.
function DataManager.init()
	DataService:init({
		template = Template,
		-- Studio hits REAL DataStores on a separate index (needs Studio API
		-- access enabled). Live player data is unreachable from Studio, and
		-- test data is just data — wipe the index if it goes bad.
		profileStoreIndex = if RunService:IsStudio()
			then GameConfig.PROFILE_STORE_STUDIO
			else GameConfig.PROFILE_STORE,
	})
end

------------------------------------------------
-- Mirrors: leaderstats + player attributes
------------------------------------------------
-- Mirrors exist for readers the data replica can't serve: a replica only ever
-- reaches its OWNER, so anything another player must see (a level over their
-- head, a title on their nameplate) needs an attribute or a leaderstat. A
-- value only its owner reads needs neither — see Data/Currencies.
--
-- Driven off the changed signal rather than written inside AddCurrency, so a
-- balance set by ANY path still mirrors.
local function mirror(player: Player, key: string, config, value: number)
	if config.Attribute then
		player:SetAttribute(config.Name or key, value)
	end
	if config.Leaderstat then
		local stats = player:FindFirstChild("leaderstats")
		local stat  = stats and stats:FindFirstChild(config.Name or key)
		if stat then
			(stat :: IntValue).Value = value
		end
	end
end

local function setupMirrors(player: Player, data)
	local leaderstats
	for key, config in Currencies do
		if config.Leaderstat then
			if not leaderstats then
				leaderstats = Instance.new("Folder")
				leaderstats.Name = "leaderstats"
			end
			local stat = Instance.new("IntValue")
			stat.Name   = config.Name or key
			stat.Value  = data[key] or 0
			stat.Parent = leaderstats
		end
		if config.Attribute then
			player:SetAttribute(config.Name or key, data[key] or 0)
		end

		DataService:getChangedSignal(player, { key }):Connect(function(value)
			mirror(player, key, config, value)
		end)
	end
	if leaderstats then
		leaderstats.Parent = player
	end
end

------------------------------------------------
-- Profile lifecycle
------------------------------------------------
-- Runs after the profile loads but BEFORE it reaches the client or any other
-- server module — the one window where `data` can be mutated directly
-- (nothing is listening yet, so no replication is needed). Use it for
-- per-profile seeding and for migrations that must land before any reader
-- sees the profile.
function DataService:onPlayerInit(player: Player, data)
	sessionStart[player] = os.clock()

	-- FIRST JOIN: LastPlayed is only ever written on leave, so a nil means a
	-- brand-new profile.
	if data.LastPlayed == nil then
		data.CreatedAt = os.time()
	end
	data.Stats.JoinCount += 1

	-- MIGRATIONS go here — one `if` per stale shape, each safe to run on a
	-- profile that's already been migrated (reconcile can't rewrite VALUES,
	-- only fill missing keys). Delete a migration once no profile can still
	-- carry the old shape.

	setupMirrors(player, data)
end

DataService:addPlayerRemovingCallback(function(player: Player, data)
	data.LastPlayed = os.time()
	local started = sessionStart[player]
	if started then
		data.Stats.TimePlayed += math.floor(os.clock() - started)
		sessionStart[player] = nil
	end
end)

------------------------------------------------
-- Currency
------------------------------------------------
-- Whether an SKU names one of the Robux currency packs — a real-money source
-- rather than a gameplay one. Used for the analytics transaction type.
local function isIAP(itemSKU: string?): boolean
	if not itemSKU then return false end
	for _, entry in ProductUtil.group("Currency") do
		if entry.key == itemSKU then return true end
	end
	return false
end

function DataManager.GetCurrency(player: Player, currency: string): number
	if not DataService:hasProfile(player) then return 0 end
	return DataService:get(player, { currency }) or 0
end

-- Adds (or, with a negative amount, removes) currency and logs the economy
-- event. `itemSKU` is the thing bought or the source of the award — it's what
-- makes the analytics funnel readable, so always pass one.
--
-- Returns the new balance.
function DataManager.AddCurrency(player: Player, currency: string, amount: number, itemSKU: string?): number
	local config = Currencies[currency]
	if not config then
		warn(`[DataManager] unknown currency "{currency}"`)
		return 0
	end
	if not DataService:hasProfile(player) then return 0 end
	if amount == 0 then return DataManager.GetCurrency(player, currency) end

	local balance = (DataService:get(player, { currency }) or 0) + amount
	-- A negative balance is always a bug in the caller (spend without a
	-- CanAfford check). Clamp so the profile stays sane, and shout.
	if balance < 0 then
		warn(`[DataManager] {player.Name} went negative on {currency} ({balance}) — spend path skipped its affordability check`)
		balance = 0
	end
	DataService:set(player, { currency }, balance)

	local flowType = if amount > 0
		then Enum.AnalyticsEconomyFlowType.Source
		else Enum.AnalyticsEconomyFlowType.Sink

	local transactionType = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
	if isIAP(itemSKU) then
		transactionType = Enum.AnalyticsEconomyTransactionType.IAP.Name
	elseif itemSKU and flowType == Enum.AnalyticsEconomyFlowType.Sink then
		transactionType = Enum.AnalyticsEconomyTransactionType.Shop.Name
	end

	AnalyticsService:LogEconomyEvent(
		player, flowType, config.Name or currency,
		math.abs(amount), balance, transactionType, itemSKU
	)

	if config.Board then
		LeaderboardManager.Save(player, currency, balance)
	end

	return balance
end

function DataManager.CanAfford(player: Player, currency: string, cost: number): boolean
	return DataManager.GetCurrency(player, currency) >= cost
end

-- Charges `cost` if the player has it. Returns whether the charge went
-- through — check the return before granting anything.
--
--   if not DataManager.TrySpend(player, "Coins", item.Price, item.Name) then return end
--   grantItem(player, item)
function DataManager.TrySpend(player: Player, currency: string, cost: number, itemSKU: string?): boolean
	if cost < 0 then return false end
	if not DataManager.CanAfford(player, currency, cost) then return false end
	DataManager.AddCurrency(player, currency, -cost, itemSKU)
	return true
end

------------------------------------------------
-- Inventory
------------------------------------------------
-- Inventory categories are sets: Inventory[category][itemName] = true.
function DataManager.Owns(player: Player, category: string, item: string): boolean
	if not DataService:hasProfile(player) then return false end
	return DataService:get(player, { "Inventory", category, item }) == true
end

-- Returns false if they already owned it (so callers can skip the "new item!"
-- celebration on a duplicate).
function DataManager.GrantItem(player: Player, category: string, item: string): boolean
	if not DataService:hasProfile(player) then return false end
	if DataManager.Owns(player, category, item) then return false end
	-- The category table may not exist yet on an older profile.
	if DataService:get(player, { "Inventory", category }) == nil then
		DataService:set(player, { "Inventory", category }, {})
	end
	DataService:set(player, { "Inventory", category, item }, true)
	return true
end

-- Equips an owned item into a slot. Refuses to equip what isn't owned — the
-- server is the authority even when the request came from our own UI.
function DataManager.Equip(player: Player, slot: string, item: string): boolean
	if not DataService:hasProfile(player) then return false end
	if not DataManager.Owns(player, slot, item) then return false end
	DataService:set(player, { "Equipped", slot }, item)
	return true
end

------------------------------------------------
-- Stats
------------------------------------------------
function DataManager.IncrementStat(player: Player, stat: string, amount: number?): number?
	if not DataService:hasProfile(player) then return nil end
	local value = (DataService:get(player, { "Stats", stat }) or 0) + (amount or 1)
	DataService:set(player, { "Stats", stat }, value)
	return value
end

Players.PlayerRemoving:Connect(function(player)
	sessionStart[player] = nil
end)

return DataManager
