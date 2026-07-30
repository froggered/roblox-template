-- Reacts to a confirmed purchase. The server fires PurchaseMade only after
-- the grant is saved, so this is the right place for the celebration — the
-- prompt closing is not (the receipt can still fail).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductUtil = require(ReplicatedStorage.Modules.ProductUtil)
local Remotes     = require(ReplicatedStorage.Modules.Remotes)

local PurchaseFeedback = {}

Remotes.event("PurchaseMade").OnClientEvent:Connect(function(productKey: string)
	local entry = ProductUtil.byKey(productKey)
	if not entry then return end

	-- Sound, confetti, "thanks!" toast — hook up per project.
	print(`[PurchaseFeedback] purchased {entry.Name}`)
end)

return PurchaseFeedback
