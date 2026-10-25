--!strict
-- Временная арена Главы 1 из простых блоков: пол, укрытия и три «сбоя»,
-- которые отряд должен закрыть. Враги и настоящая карта города появятся позже.

local Workspace = game:GetService("Workspace")

local CYAN = Color3.fromRGB(0, 255, 200)
local GLITCH = Color3.fromRGB(255, 40, 120)
local DARK = Color3.fromRGB(14, 16, 22)

local ARENA_SIZE = 160
local NODE_RADIUS = 50

local MissionMap = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function build(): Model
	local map = Instance.new("Model")
	map.Name = "MissionMap"

	part({
		Name = "Floor",
		Size = Vector3.new(ARENA_SIZE, 1, ARENA_SIZE),
		Position = Vector3.new(0, 0.5, 0),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
		Parent = map,
	})

	-- Светящаяся сетка на полу — «мир-код»
	local half = ARENA_SIZE / 2
	for offset = -half, half, 20 do
		part({
			Name = "Grid",
			Size = Vector3.new(ARENA_SIZE, 0.1, 0.2),
			Position = Vector3.new(0, 1.05, offset),
			Color = CYAN,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			CanCollide = false,
			Parent = map,
		})
		part({
			Name = "Grid",
			Size = Vector3.new(0.2, 0.1, ARENA_SIZE),
			Position = Vector3.new(offset, 1.05, 0),
			Color = CYAN,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			CanCollide = false,
			Parent = map,
		})
	end

	-- Укрытия
	local random = Random.new(42)
	for _ = 1, 14 do
		local height = random:NextInteger(4, 10)
		local x = random:NextInteger(-65, 65)
		local z = random:NextInteger(-65, 65)
		if math.abs(x) < 15 and math.abs(z) < 15 then
			continue -- центр оставляем свободным под точку появления
		end
		part({
			Name = "Cover",
			Size = Vector3.new(random:NextInteger(4, 12), height, random:NextInteger(4, 12)),
			Position = Vector3.new(x, 1 + height / 2, z),
			Color = Color3.fromRGB(30, 36, 46),
			Material = Enum.Material.SmoothPlastic,
			Parent = map,
		})
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 1.5, 0)
	spawn.Color = DARK
	spawn.Duration = 0
	spawn.Parent = map

	-- Три сбоя по кругу
	local nodes = Instance.new("Folder")
	nodes.Name = "GlitchNodes"
	nodes.Parent = map
	for i = 1, 3 do
		local angle = math.rad(120 * i - 90)
		local node = part({
			Name = `Glitch{i}`,
			Size = Vector3.new(4, 4, 4),
			CFrame = CFrame.new(math.cos(angle) * NODE_RADIUS, 5, math.sin(angle) * NODE_RADIUS)
				* CFrame.Angles(math.rad(45), math.rad(45), 0),
			Color = GLITCH,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = nodes,
		})

		local light = Instance.new("PointLight")
		light.Color = GLITCH
		light.Range = 18
		light.Brightness = 3
		light.Parent = node

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Закрыть сбой"
		prompt.ObjectText = "Сбой"
		prompt.HoldDuration = 3
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = node
	end

	map.Parent = Workspace
	return map
end

-- Возвращает точки-сбои
function MissionMap.setup(): { BasePart }
	local map = Workspace:FindFirstChild("MissionMap") or build()
	local folder = map:FindFirstChild("GlitchNodes")
	assert(folder, "В MissionMap нет папки GlitchNodes")

	local nodes = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(nodes, child)
		end
	end
	return nodes
end

-- Включает или выключает сбой
function MissionMap.setNodeActive(node: BasePart, active: boolean)
	node.Color = if active then GLITCH else CYAN
	node.Transparency = if active then 0 else 0.7
	local light = node:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = node.Color
		light.Enabled = active
	end
	local prompt = node:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = active
	end
end

return MissionMap
