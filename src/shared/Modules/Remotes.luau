-- Single source of truth for every remote instance.
--
-- Remotes are created in code, never authored in the place file: a second
-- same-named folder in StarterGui/ReplicatedStorage silently splits client
-- and server onto two different instances, and the bug looks like "the event
-- just doesn't fire". Requiring this module from either side gets the SAME
-- instance or yields until it exists.
--
--   local Remotes = require(ReplicatedStorage.Modules.Remotes)
--   Remotes.event("PlaySound"):FireClient(player, "Purchase")
--   Remotes.fn("RequestPurchase").OnServerInvoke = handler
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local folder: Instance
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local Remotes = {}

local function get(className: string, name: string): any
	local existing = folder:FindFirstChild(name)
	if existing then
		if not existing:IsA(className) then
			error(`[Remotes] "{name}" exists as a {existing.ClassName}, expected {className}`, 3)
		end
		return existing
	end

	-- The client never creates remotes — it waits for the server's. A hang
	-- here means the server never asked for this name (usually a typo).
	if not IS_SERVER then
		return folder:WaitForChild(name)
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Remotes.event(name: string): RemoteEvent
	return get("RemoteEvent", name)
end

function Remotes.unreliable(name: string): UnreliableRemoteEvent
	return get("UnreliableRemoteEvent", name)
end

function Remotes.fn(name: string): RemoteFunction
	return get("RemoteFunction", name)
end

return Remotes
