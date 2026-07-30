-- Client entry point. Brings up the data replica, then starts every
-- controller.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- WaitForChild through the whole require chain: a client's LocalScripts can
-- start before ReplicatedStorage has finished replicating, and the failure
-- reads as "X is not a valid member of ReplicatedStorage" on one client only.
-- Waiting for the three shared folders HERE means everything downstream can
-- index ReplicatedStorage directly: by the time a controller runs, they exist.
local Packages = ReplicatedStorage:WaitForChild("Packages")
ReplicatedStorage:WaitForChild("Data")
ReplicatedStorage:WaitForChild("Modules")

local DataService = require(Packages:WaitForChild("DataService")).client

-- YIELDS until the server pushes the initial profile snapshot. Doing it here,
-- before the controllers load, means every controller can read data
-- synchronously — no controller needs its own "wait for data" dance.
DataService:init()

-- Controllers are self-starting modules: requiring one runs it. Alphabetical
-- by name; if two ever need a specific order, require them explicitly above
-- this loop instead of encoding the order in a file name.
for _, module in script.Controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		-- One broken controller must not take the rest of the client down.
		-- xpcall, not pcall: the traceback has to be captured at the point of
		-- the error, and a plain pcall throws away everything but the message.
		local ok, err = xpcall(require, debug.traceback, module)
		if not ok then
			warn(`[Client] {module.Name} failed to start:\n{err}`)
		end
	end
end
