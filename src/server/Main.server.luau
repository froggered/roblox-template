-- Server entry point. The one place that decides what runs and in what
-- order; every other server file is a module that does nothing until required
-- from here.
local ServerScriptService = game:GetService("ServerScriptService")

local ServerModules = ServerScriptService.ServerModules

-- FIRST, always: opens the profile store. Anything that reads player data
-- before this yields forever.
local DataManager = require(ServerModules.DataManager)
DataManager.init()

-- Robux purchases: binds ProcessReceipt and starts the join-time gamepass
-- ownership refresh.
local MarketManager = require(ServerModules.MarketManager)
MarketManager.start()

-- Leaderboards save themselves on leave; required here so the boards are
-- registered and readable from the first request.
require(ServerModules.LeaderboardManager)

-- Game systems go below.
