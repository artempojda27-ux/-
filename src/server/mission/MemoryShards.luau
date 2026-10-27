--!strict
-- Письмо-зацепка (Config.Story.Letters, номер вида "Neon_2"), спрятанное в городе: светящийся кристалл данных,
-- над ним столб света, чтобы его было видно издалека. Каждый игрок подбирает свой: кнопка «Прочитать»
-- открывает текст и сохраняет находку (StoryService). Тому, кто уже нашёл, клиент осколок прячет.
-- В «Ядре» осколок (значок Кая) выпадает из Нуля после победы — BossService зовёт MemoryShards.place.

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local StoryService = require(ServerScriptService.Common.StoryService)

local STREETS = { -90, -30, 30, 90 }
local COLORS: { [string]: Color3 } = {
	Neon = Color3.fromRGB(0, 255, 220),
	Mirror = Color3.fromRGB(255, 60, 80),
	Temple = Color3.fromRGB(255, 190, 80),
	Crystal = Color3.fromRGB(190, 150, 255),
	Erased = Color3.fromRGB(255, 255, 255),
	Monolith = Color3.fromRGB(255, 40, 50),
	Core = Color3.fromRGB(150, 220, 255),
}

local MemoryShards = {}

local random = Random.new()

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Ставит осколок мира worldId в точку position (на земле)
function MemoryShards.place(id: string, position: Vector3)
	local worldId = string.match(id, "^(%a+)") or "Neon"
	local color = COLORS[worldId] or COLORS.Neon
	local model = Instance.new("Model")
	model.Name = "MemoryShard"
	model:SetAttribute("ShardId", id)

	local gem = part({
		Name = "Gem",
		Size = Vector3.new(1.4, 2.6, 1.4),
		CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(45)),
		Color = color,
		Parent = model,
	})
	part({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		Position = gem.Position,
		Color = Color3.new(1, 1, 1),
		Parent = model,
	})
	-- столб света: видно с другого конца города
	part({
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(120, 1.6, 1.6),
		CFrame = CFrame.new(position + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.7,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = gem
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.2, 0)
	sparks.Lifetime = NumberRange.new(1, 2)
	sparks.Rate = 12
	sparks.Speed = NumberRange.new(1, 2)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = gem

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Прочитать"
	prompt.ObjectText = "Письмо"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = gem
	prompt.Triggered:Connect(function(player)
		StoryService.collect(player, id)
	end)

	model.PrimaryPart = gem
	-- кристалл вращается и покачивается (WorldMotion на клиенте)
	gem:SetAttribute("Spin", Vector3.new(0, 60, 0))
	gem:SetAttribute("Bob", 0.4)
	CollectionService:AddTag(gem, "Motion")
	CollectionService:AddTag(model, "MemoryShard")
	model.Parent = Workspace
end

-- Прячет письмо в случайном месте на улицах, подальше от площади
function MemoryShards.hide(id: string, groundAt: (number, number) -> Vector3)
	local street = STREETS[random:NextInteger(1, #STREETS)]
	local along = random:NextNumber(40, 110) * (if random:NextNumber() < 0.5 then -1 else 1)
	local x, z = street + random:NextNumber(-4, 4), along
	if random:NextNumber() < 0.5 then
		x, z = z, x
	end
	MemoryShards.place(id, groundAt(x, z))
end

return MemoryShards
