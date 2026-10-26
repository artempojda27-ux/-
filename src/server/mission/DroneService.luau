--!strict
-- Дрон-помощник (Game Pass "Drone"): летает над плечом владельца и сам стреляет
-- по ближайшему видимому врагу. Всё считает сервер, поэтому урон честный.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PassService = require(ServerScriptService.Common.PassService)
local BoostEffects = require(script.Parent.BoostEffects)

local OFFSET = Vector3.new(2.5, 3, 1.5) -- над правым плечом
local CYAN = Color3.fromRGB(0, 255, 200)

type Drone = {
	Part: BasePart,
	LastShot: number,
}

local DroneService = {}

local drones: { [Player]: Drone } = {}
local folder: Folder

local function makeDrone(player: Player): BasePart
	local part = Instance.new("Part")
	part.Name = `Drone_{player.Name}`
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * 1.2
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = CYAN
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = 8
	light.Parent = part
	part.Parent = folder
	return part
end

local function tracer(from: Vector3, to: Vector3)
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = CYAN
	beam.Size = Vector3.new(0.1, 0.1, (to - from).Magnitude)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = folder
	TweenService:Create(beam, TweenInfo.new(0.15), { Transparency = 1 }):Play()
	task.delay(0.15, function()
		beam:Destroy()
	end)
end

-- Ближайший враг, до которого дрону ничего не мешает долететь
local function findTarget(from: Vector3): (Model?, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore

	local best: Model? = nil
	local bestPoint: Vector3? = nil
	local bestDistance = Config.DroneRange
	for _, enemy in CollectionService:GetTagged("Enemy") do
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		local hiddenDouble = enemy:GetAttribute("Doppelganger") and not enemy:GetAttribute("Revealed")
		if enemy:IsA("Model") and humanoid and humanoid.Health > 0 and not hiddenDouble then
			local point = enemy:GetPivot().Position
			local distance = (point - from).Magnitude
			if distance < bestDistance then
				local hit = Workspace:Raycast(from, point - from, params)
				if hit and hit.Instance:IsDescendantOf(enemy) then
					best, bestPoint, bestDistance = enemy, hit.Position, distance
				end
			end
		end
	end
	return best, bestPoint
end

local function update()
	local now = os.clock()
	for player, drone in drones do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			drone.Part.Transparency = 1
			continue
		end
		drone.Part.Transparency = 0
		local wobble = Vector3.new(0, math.sin(now * 3) * 0.3, 0)
		drone.Part.Position = (root.CFrame * CFrame.new(OFFSET)).Position + wobble

		if now - drone.LastShot >= Config.DroneFireInterval then
			local enemy, point = findTarget(drone.Part.Position)
			if enemy and point then
				drone.LastShot = now
				local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
				if enemyHumanoid then
					enemyHumanoid:TakeDamage(Config.DroneDamage * BoostEffects.damageMultiplier(player))
				end
				tracer(drone.Part.Position, point)
			end
		end
	end
end

local function refresh(player: Player)
	local owns = PassService.owns(player, "Drone")
	if owns and not drones[player] then
		drones[player] = { Part = makeDrone(player), LastShot = 0 }
	elseif not owns and drones[player] then
		drones[player].Part:Destroy()
		drones[player] = nil
	end
end

function DroneService.start()
	folder = Instance.new("Folder")
	folder.Name = "Drones"
	folder.Parent = Workspace

	local function onPlayerAdded(player: Player)
		player:GetAttributeChangedSignal("Pass_Drone"):Connect(function()
			refresh(player)
		end)
		refresh(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local drone = drones[player]
		if drone then
			drone.Part:Destroy()
			drones[player] = nil
		end
	end)

	RunService.Heartbeat:Connect(update)
end

return DroneService
