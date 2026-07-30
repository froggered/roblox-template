-- Global leaderboards on OrderedDataStore.
--
-- Boards are declared, not written ad hoc: every board has a store name and a
-- profile path, so SaveAll can push a player's whole set on the events that
-- matter (round end, leave) without each caller knowing the store names.
--
-- Currency boards register themselves from Data/Currencies (the Board field).
-- Add non-currency boards to EXTRA_BOARDS below.
local DataStoreService   = game:GetService("DataStoreService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

local Currencies = require(ReplicatedStorage.Data.Currencies)
local DataService = require(ReplicatedStorage.Packages.DataService).server
local GameConfig  = require(ReplicatedStorage.Data.GameConfig)

local LeaderboardManager = {}

-- key = { store = OrderedDataStore name, path = profile path to the value }
local EXTRA_BOARDS: { [string]: { store: string, path: { string } } } = {
	-- Wins = { store = "LB_Wins", path = { "Stats", "Wins" } },
}

local BOARDS = table.clone(EXTRA_BOARDS)
for key, config in Currencies do
	if config.Board then
		BOARDS[key] = { store = config.Board, path = { key } }
	end
end

-- Studio writes to a fenced-off scope so playtest scores never appear on the
-- live board. nil is the default global scope, where the live data lives.
local SCOPE = if RunService:IsStudio() then "Test" else nil

------------------------------------------------
-- Writing
------------------------------------------------
-- OrderedDataStore writes are rate-limited per key, so a board that changes
-- every few seconds (a score counter) would burn the budget. One write per
-- key per THROTTLE_S; the value written is always the latest.
local THROTTLE_S = 20
local lastWrite: { [Player]: { [string]: { at: number, value: number } } } = {}

function LeaderboardManager.Save(player: Player, key: string, value: number, force: boolean?)
	local config = BOARDS[key]
	if not config then return end

	local playerWrites = lastWrite[player]
	if not playerWrites then
		playerWrites = {}
		lastWrite[player] = playerWrites
	end

	local previous = playerWrites[key]
	if not force and previous then
		if previous.value == value then return end
		if os.clock() - previous.at < THROTTLE_S then return end
	end
	playerWrites[key] = { at = os.clock(), value = value }

	task.spawn(function()
		local success, err
		local attempt = 1
		repeat
			success, err = pcall(function()
				DataStoreService:GetOrderedDataStore(config.store, SCOPE)
					:SetAsync(tostring(player.UserId), math.floor(value))
			end)
			attempt += 1
			if not success then
				warn(`[LeaderboardManager] save failed for {config.store}: {err}`)
				task.wait(3)
			end
		until success or attempt == 5

		if not success then
			warn(`[LeaderboardManager] giving up on {config.store} for {player.Name}`)
		end
	end)
end

-- Pushes every board for a player. Call on the events worth persisting (round
-- end, leave) — `force` bypasses the throttle, for the leave path.
function LeaderboardManager.SaveAll(player: Player, force: boolean?)
	if not DataService:hasProfile(player) then return end
	for key, config in BOARDS do
		local value = DataService:get(player, config.path)
		if type(value) == "number" then
			LeaderboardManager.Save(player, key, value, force)
		end
	end
end

------------------------------------------------
-- Reading
------------------------------------------------
-- Top N as { { userId, name, value } }, best first. YIELDS on a cold cache,
-- so call it from a remote handler, not from a render loop. Returns the stale
-- page if a refetch fails — stale beats an empty board.
local cache: { [string]: { at: number, entries: { any } } } = {}

function LeaderboardManager.GetTop(key: string): { any }?
	local config = BOARDS[key]
	if not config then return nil end

	local cached = cache[key]
	if cached and os.clock() - cached.at < GameConfig.BOARD_CACHE_S then
		return cached.entries
	end

	local ok, pages = pcall(function()
		return DataStoreService:GetOrderedDataStore(config.store, SCOPE)
			:GetSortedAsync(false, GameConfig.BOARD_TOP_N)
	end)
	if not ok then
		warn(`[LeaderboardManager] read failed for {config.store}: {pages}`)
		return cached and cached.entries
	end

	local entries = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		local nameOk, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		table.insert(entries, {
			userId = userId,
			name   = if nameOk then name else `Player {userId}`,
			value  = entry.value,
		})
	end

	cache[key] = { at = os.clock(), entries = entries }
	return entries
end

-- Final push on leave. This runs through DataService's removing callback, NOT
-- Players.PlayerRemoving: by the time that fires the profile session has
-- already ended and there is nothing left to read.
DataService:addPlayerRemovingCallback(function(player, data)
	for key, config in BOARDS do
		local value: any = data
		for _, step in config.path do
			value = if type(value) == "table" then value[step] else nil
		end
		if type(value) == "number" then
			LeaderboardManager.Save(player, key, value, true)
		end
	end
	lastWrite[player] = nil
end)

return LeaderboardManager
