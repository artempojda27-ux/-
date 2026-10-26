--!strict
-- Автосалон Штаба: на каждом подиуме стоит машина. Подходишь, держишь E — эта машина появляется
-- на трассе за подиумом (старая твоя машина исчезает). Пока все машины бесплатные;
-- позже часть станет платной (за биты или Robux).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VehicleService = require(ServerScriptService.Common.VehicleService)

local SPOT_SHIFTS = { 0, 24, -24, 48 } -- если место занято другой машиной, ставим дальше по трассе
local COOLDOWN = 3
local PAD_TOP = 1.4

type Slot = {
	Pad: BasePart,
	Kind: string,
	Spot: CFrame,
}

local Garage = {}

-- Свободное место на трассе: рядом не должно быть другой машины
local function freeSpot(spot: CFrame): CFrame
	local vehicles = Workspace:FindFirstChild("Vehicles")
	for _, shift in SPOT_SHIFTS do
		local candidate = spot * CFrame.new(0, 0, -shift)
		local busy = false
		if vehicles then
			for _, model in vehicles:GetChildren() do
				if model:IsA("Model") and (model:GetPivot().Position - candidate.Position).Magnitude < 14 then
					busy = true
				end
			end
		end
		if not busy then
			return candidate
		end
	end
	return spot
end

function Garage.start(slots: { Slot })
	local notify = Remotes.get("Notify")
	local lastUse: { [Player]: number } = {}

	for _, slot in slots do
		local kind = Config.Vehicles[slot.Kind]
		if not kind then
			continue
		end

		-- Витрина: машина парит над подиумом (крутится она на стороне игрока, см. Lobby.client)
		local pivot = CFrame.new(slot.Pad.Position.X, PAD_TOP + kind.HoverHeight * 0.6 + kind.Size.Y / 2, slot.Pad.Position.Z)
			* CFrame.Angles(0, math.rad(35), 0)
		local display = VehicleService.buildDisplay(kind.Id, pivot)
		if display then
			display.Name = `Display_{kind.Id}`
			display:SetAttribute("Showcase", true)
			display.Parent = slot.Pad.Parent
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = `Вызвать: {kind.Name}`
		prompt.ObjectText = `{kind.Seats} мест · скорость {kind.MaxSpeed}`
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 18
		prompt.RequiresLineOfSight = false
		prompt.Parent = slot.Pad

		prompt.Triggered:Connect(function(player)
			local now = os.clock()
			if lastUse[player] and now - lastUse[player] < COOLDOWN then
				return
			end
			lastUse[player] = now
			local model, reason = VehicleService.spawnFor(player, kind.Id, freeSpot(slot.Spot))
			if model then
				notify:FireClient(player, `{kind.Name} ждёт на трассе! W/S — газ, A/D — руль, пробел — выйти.`)
			elseif reason then
				notify:FireClient(player, reason)
			end
		end)
	end
end

return Garage
