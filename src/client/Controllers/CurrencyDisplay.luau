-- Keeps currency labels in sync with the data replica.
--
-- Reference implementation for the whole client: never poll, never ask the
-- server. Read once for the initial value, then let getChangedSignal push
-- updates — the replica is already up to date by the time any UI needs it.
--
-- Convention: any TextLabel tagged with the CollectionService tag
-- "CurrencyLabel" and an attribute Currency = "Coins" is bound automatically,
-- wherever it lives in the GUI. No hard-coded GUI paths, so restructuring the
-- interface never breaks this file.
local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Currencies = require(ReplicatedStorage.Data.Currencies)
local Format     = require(ReplicatedStorage.Modules.Format)
local DataService = require(ReplicatedStorage.Packages.DataService).client

local TAG = "CurrencyLabel"

local CurrencyDisplay = {}

local function bind(label: Instance)
	if not label:IsA("TextLabel") and not label:IsA("TextButton") then return end
	local text = label :: TextLabel -- both classes carry .Text

	local currency = label:GetAttribute("Currency") or "Coins"
	if not Currencies[currency] then
		warn(`[CurrencyDisplay] {label:GetFullName()} wants unknown currency "{currency}"`)
		return
	end

	local function render(value: number)
		text.Text = Format.abbreviate(value or 0)
	end

	render(DataService:get({ currency }))
	local connection = DataService:getChangedSignal({ currency }):Connect(render)
	label.Destroying:Once(function()
		connection:Disconnect()
	end)
end

for _, label in CollectionService:GetTagged(TAG) do
	if label:IsDescendantOf(Players.LocalPlayer) then
		bind(label)
	end
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(bind)

return CurrencyDisplay
