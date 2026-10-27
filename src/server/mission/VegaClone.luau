--!strict
-- Клон Веги в городе: голубая голограмма-копия Командора (модель — Config.LobbyProps.Commander).
-- По кнопке «Поговорить» подсказывает по заданию (Config.Story.CloneHints). В задании «Удержать канал»
-- у неё есть здоровье: враги атакуют её наравне с игроками (EnemyService.setDecoy).

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local StoryService = require(ServerScriptService.Common.StoryService)

local HOLO = Color3.fromRGB(110, 230, 255)

local VegaClone = {}

-- Ставит клона в position лицом к look. health — если задано, клон можно ранить
function VegaClone.spawn(position: Vector3, look: Vector3, hint: string, health: number?): Model
	local model = Instance.new("Model")
	model.Name = "VegaClone"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.4, 6.5, 1.6)
	root.CFrame = CFrame.lookAt(position + Vector3.new(0, 3.25, 0), Vector3.new(look.X, position.Y + 3.25, look.Z))
	root.Anchored = true
	root.CanCollide = true
	root.Transparency = 1
	root.Parent = model

	local ok, container = pcall(InsertService.LoadAsset, InsertService, Config.LobbyProps.Commander)
	local mesh = ok and container:FindFirstChildWhichIsA("BasePart", true)
	if mesh then
		mesh.Parent = nil
		container:Destroy()
		mesh.Name = "Body"
		mesh.Size = mesh.Size * (6.5 / mesh.Size.Y)
		mesh.CFrame = root.CFrame
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = true -- пули врагов попадают и в голограмму
		mesh.Transparency = 0.35
		mesh.Parent = model
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = HOLO
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = HOLO
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	-- голопроектор под ногами и мерцающие искры
	local base = Instance.new("Part")
	base.Name = "Projector"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.3, 4, 4)
	base.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.CanCollide = false
	base.Material = Enum.Material.Neon
	base.Color = HOLO
	base.Parent = model
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(HOLO)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.15, 0)
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Rate = 10
	sparks.Speed = NumberRange.new(1, 2)
	sparks.EmissionDirection = Enum.NormalId.Right
	sparks.Parent = base
	local light = Instance.new("PointLight")
	light.Color = HOLO
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = "Клон Веги"
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = health or 100
	humanoid.Health = humanoid.MaxHealth
	humanoid.HealthDisplayType = if health then Enum.HumanoidHealthDisplayType.AlwaysOn else Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	if health then
		model:SetAttribute("Decoy", true)
	else
		local field = Instance.new("ForceField") -- просто подсказчица: её не ранить
		field.Visible = false
		field.Parent = model
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Поговорить"
	prompt.ObjectText = "Клон Веги"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		StoryService.say("Клон Веги", hint, player)
	end)

	model.PrimaryPart = root
	CollectionService:AddTag(model, "VegaClone")
	model.Parent = Workspace
	return model
end

return VegaClone
