--!strict
-- Карта Главы 1 «Город» из простых блоков: ночной неоновый город-симуляция.
--   В центре — площадь с укрытиями, где появляются герои.
--   Вокруг — 8 кварталов с домами (неоновые окна, вывески, «глитчи»), между ними улицы с фонарями.
--   По краям — стена из высоких домов, чтобы никто не ушёл за карту.
--   На улицах — три «сбоя» (цели Главы 1) с розовыми лучами и точки появления врагов.
-- Город строится по одному и тому же «зерну», поэтому всегда одинаковый.
-- Если положить в Workspace свою модель MissionMap (с папками GlitchNodes и EnemySpawns), код возьмёт её.

local Workspace = game:GetService("Workspace")

local CYAN = Color3.fromRGB(0, 255, 200)
local GLITCH = Color3.fromRGB(255, 40, 120)
local NEON_COLORS = {
	Color3.fromRGB(0, 255, 200),
	Color3.fromRGB(255, 40, 120),
	Color3.fromRGB(150, 80, 255),
	Color3.fromRGB(60, 140, 255),
}
local FACADE_COLORS = {
	Color3.fromRGB(48, 52, 78),
	Color3.fromRGB(62, 52, 88),
	Color3.fromRGB(40, 62, 80),
	Color3.fromRGB(56, 56, 66),
}
local SIGN_WORDS = { "КОД", "СИСТЕМА", "ОШИБКА 404", "ДОСТУП", "СИГНАЛ", "ЯДРО", "ПАМЯТЬ", "ОБНОВЛЕНИЕ" }

local HALF = 130 -- половина размера карты
local BLOCK = 44 -- размер квартала
local BLOCK_CENTERS = { -60, 0, 60 }
local STREETS = { -90, -30, 30, 90 } -- центры улиц
local STREET_WIDTH = 16
local GROUND_Y = 1 -- верх асфальта
local SIDEWALK_HEIGHT = 0.6

local NODE_POSITIONS = {
	Vector3.new(0, 5, -90),
	Vector3.new(90, 5, 30),
	Vector3.new(-90, 5, 60),
}
local ENEMY_SPAWNS = {
	Vector3.new(-90, GROUND_Y, -90),
	Vector3.new(90, GROUND_Y, -90),
	Vector3.new(-90, GROUND_Y, 90),
	Vector3.new(90, GROUND_Y, 90),
	Vector3.new(0, GROUND_Y, 90),
	Vector3.new(0, GROUND_Y, -90),
	Vector3.new(-90, GROUND_Y, 0),
	Vector3.new(90, GROUND_Y, 0),
}

local MissionMap = {}

local random = Random.new(2026)

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

-- Светящаяся деталь-украшение: не мешает ходить и стрелять
local function neon(props: { [string]: any }): Part
	props.Material = Enum.Material.Neon
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return part(props)
end

local function pick<T>(list: { T }): T
	return list[random:NextInteger(1, #list)]
end

local function buildGround(map: Model)
	part({
		Name = "Ground",
		Size = Vector3.new(HALF * 2, 1, HALF * 2),
		Position = Vector3.new(0, GROUND_Y - 0.5, 0),
		Color = Color3.fromRGB(20, 20, 28),
		Material = Enum.Material.Asphalt,
		Parent = map,
	})

	-- Разметка: пунктир по центру улиц
	local markings = Instance.new("Folder")
	markings.Name = "Markings"
	markings.Parent = map
	for _, street in STREETS do
		for along = -HALF + 6, HALF - 6, 14 do
			local nearCrossing = false
			for _, other in STREETS do
				if math.abs(along - other) < STREET_WIDTH / 2 + 2 then
					nearCrossing = true
				end
			end
			if not nearCrossing then
				neon({
					Size = Vector3.new(0.4, 0.05, 6),
					Position = Vector3.new(street, GROUND_Y + 0.03, along),
					Color = CYAN,
					Transparency = 0.55,
					Parent = markings,
				})
				neon({
					Size = Vector3.new(6, 0.05, 0.4),
					Position = Vector3.new(along, GROUND_Y + 0.03, street),
					Color = CYAN,
					Transparency = 0.55,
					Parent = markings,
				})
			end
		end
	end
end

-- Тротуар квартала с неоновым бордюром
local function buildSidewalk(parent: Instance, center: Vector3, size: number)
	part({
		Name = "Sidewalk",
		Size = Vector3.new(size, SIDEWALK_HEIGHT, size),
		Position = center + Vector3.new(0, SIDEWALK_HEIGHT / 2, 0),
		Color = Color3.fromRGB(40, 42, 54),
		Material = Enum.Material.Concrete,
		Parent = parent,
	})
	local edge = size / 2
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local alongX = side[2] ~= 0
		neon({
			Size = if alongX then Vector3.new(size, 0.15, 0.3) else Vector3.new(0.3, 0.15, size),
			Position = center + Vector3.new(side[1] * edge, SIDEWALK_HEIGHT + 0.05, side[2] * edge),
			Color = CYAN,
			Transparency = 0.35,
			Parent = parent,
		})
	end
end

-- Неоновая вывеска со словом на стене дома
local function buildSign(parent: Instance, facePosition: Vector3, normal: Vector3, height: number)
	local color = pick(NEON_COLORS)
	local cf = CFrame.lookAt(facePosition + normal * 0.6, facePosition + normal * 2) + Vector3.new(0, height, 0)
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(14, 4, 0.5),
		CFrame = cf,
		Color = Color3.fromRGB(10, 10, 16),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = pick(SIGN_WORDS)
	label.Parent = gui
	gui.Parent = sign
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Color = color
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = sign
end

-- «Глитч»: дом рассыпается на розовые пиксели у одного угла крыши
local function buildGlitch(parent: Instance, corner: Vector3)
	for _ = 1, random:NextInteger(6, 11) do
		local size = random:NextNumber(1, 3)
		neon({
			Name = "GlitchPixel",
			Size = Vector3.one * size,
			Position = corner + Vector3.new(random:NextNumber(-4, 4), random:NextNumber(-2, 8), random:NextNumber(-4, 4)),
			Color = if random:NextNumber() < 0.75 then GLITCH else CYAN,
			Transparency = random:NextNumber(0, 0.3),
			Parent = parent,
		})
	end
end

local function buildBuilding(parent: Instance, center: Vector3, width: number, depth: number, height: number, streetSides: { Vector3 })
	local building = Instance.new("Model")
	building.Name = "Building"
	local base = center + Vector3.new(0, SIDEWALK_HEIGHT, 0)
	part({
		Name = "Body",
		Size = Vector3.new(width, height, depth),
		Position = base + Vector3.new(0, height / 2, 0),
		Color = pick(FACADE_COLORS),
		Material = if random:NextNumber() < 0.5 then Enum.Material.Concrete else Enum.Material.SmoothPlastic,
		Parent = building,
	})

	-- Полосы окон на каждой стене; часть «окон» не горит
	local windowColor = pick(NEON_COLORS)
	for _, face in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local faceWidth = if face.X ~= 0 then depth else width
		local offset = (if face.X ~= 0 then width else depth) / 2 + 0.08
		for y = 6, height - 4, 7 do
			if random:NextNumber() < 0.7 then
				neon({
					Name = "Windows",
					Size = if face.X ~= 0 then Vector3.new(0.15, 0.7, faceWidth - 3) else Vector3.new(faceWidth - 3, 0.7, 0.15),
					Position = base + face * offset + Vector3.new(0, y, 0),
					Color = windowColor,
					Transparency = random:NextNumber(0, 0.45),
					Parent = building,
				})
			end
		end
	end

	-- Светящийся край крыши
	local top = base + Vector3.new(0, height + 0.1, 0)
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local alongX = side[2] ~= 0
		neon({
			Name = "RoofEdge",
			Size = if alongX then Vector3.new(width, 0.3, 0.3) else Vector3.new(0.3, 0.3, depth),
			Position = top + Vector3.new(side[1] * width / 2, 0, side[2] * depth / 2),
			Color = windowColor,
			Parent = building,
		})
	end

	-- Вывеска на стене, смотрящей на улицу
	if #streetSides > 0 and random:NextNumber() < 0.6 then
		local normal = pick(streetSides)
		local faceOffset = (if normal.X ~= 0 then width else depth) / 2
		buildSign(building, base + normal * faceOffset, normal, random:NextNumber(10, math.min(height - 6, 26)))
	end

	if random:NextNumber() < 0.3 then
		buildGlitch(building, top + Vector3.new(width / 2 * pick({ -1, 1 }), 0, depth / 2 * pick({ -1, 1 })))
	end

	building.Parent = parent
end

-- Квартал: тротуар и до четырёх домов; пустой участок — двор
local function buildBlock(parent: Instance, cx: number, cz: number)
	local block = Instance.new("Model")
	block.Name = `Block_{cx}_{cz}`
	local center = Vector3.new(cx, GROUND_Y, cz)
	buildSidewalk(block, center, BLOCK)

	local lot = (BLOCK - 8) / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			if random:NextNumber() < 0.8 then
				local lotCenter = center + Vector3.new(sx * (lot / 2 + 1), 0, sz * (lot / 2 + 1))
				local edgeBlock = math.abs(cx) == 60 or math.abs(cz) == 60
				local height = random:NextInteger(if edgeBlock then 30 else 20, if edgeBlock then 80 else 50)
				buildBuilding(block, lotCenter, lot, lot, height, { Vector3.new(sx, 0, 0), Vector3.new(0, 0, sz) })
			end
		end
	end
	block.Parent = parent
end

-- Высокие дома по краю карты — стена, за которую не выйти
local function buildBoundary(parent: Instance)
	local wall = Instance.new("Model")
	wall.Name = "Boundary"
	local depth = HALF - 98
	for _, side in { -1, 1 } do
		for along = -HALF + 20, HALF - 20, 40 do
			local h1 = random:NextInteger(60, 110)
			local h2 = random:NextInteger(60, 110)
			local inward = side * (98 + depth / 2)
			buildBuilding(wall, Vector3.new(inward, GROUND_Y, along), depth, 38, h1, { Vector3.new(-side, 0, 0) })
			if math.abs(along) < HALF - 30 then
				buildBuilding(wall, Vector3.new(along, GROUND_Y, inward), 38, depth, h2, { Vector3.new(0, 0, -side) })
			end
		end
	end
	-- Невидимые стены на случай щелей между домами
	for _, side in { -1, 1 } do
		part({ Name = "Invisible", Size = Vector3.new(2, 200, HALF * 2), Position = Vector3.new(side * HALF, 100, 0), Transparency = 1, Parent = wall })
		part({ Name = "Invisible", Size = Vector3.new(HALF * 2, 200, 2), Position = Vector3.new(0, 100, side * HALF), Transparency = 1, Parent = wall })
	end
	wall.Parent = parent
end

local function buildStreetLight(parent: Instance, position: Vector3)
	local lamp = Instance.new("Model")
	lamp.Name = "StreetLight"
	part({
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(14, 0.6, 0.6),
		CFrame = CFrame.new(position + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(30, 32, 40),
		Material = Enum.Material.Metal,
		Parent = lamp,
	})
	local head = neon({
		Name = "Lamp",
		Size = Vector3.new(2.5, 0.4, 1.2),
		Position = position + Vector3.new(0, 14, 0),
		Color = Color3.fromRGB(200, 240, 255),
		Parent = lamp,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 220, 255)
	light.Range = 30
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = head
	lamp.Parent = parent
end

-- Площадь в центре: место появления героев и укрытия
local function buildPlaza(parent: Instance)
	local plaza = Instance.new("Model")
	plaza.Name = "Plaza"
	local center = Vector3.new(0, GROUND_Y, 0)
	buildSidewalk(plaza, center, BLOCK)

	-- Неоновый круг под точкой появления
	neon({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 16, 16),
		CFrame = CFrame.new(center + Vector3.new(0, SIDEWALK_HEIGHT + 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = CYAN,
		Transparency = 0.9,
		Parent = plaza,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.Position = center + Vector3.new(0, SIDEWALK_HEIGHT + 0.1, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = plaza

	-- Укрытия: бетонные блоки и ящики
	local covers = {
		{ Vector3.new(-12, 0, -12), Vector3.new(8, 3, 2) },
		{ Vector3.new(12, 0, -12), Vector3.new(8, 3, 2) },
		{ Vector3.new(-12, 0, 12), Vector3.new(2, 3, 8) },
		{ Vector3.new(12, 0, 12), Vector3.new(2, 3, 8) },
		{ Vector3.new(0, 0, 16), Vector3.new(4, 4, 4) },
		{ Vector3.new(-17, 0, 0), Vector3.new(4, 4, 4) },
		{ Vector3.new(17, 0, 3), Vector3.new(4, 5, 4) },
	}
	for _, cover in covers do
		local offset, size = cover[1], cover[2]
		local isCrate = size.X == size.Z
		part({
			Name = "Cover",
			Size = size,
			Position = center + offset + Vector3.new(0, SIDEWALK_HEIGHT + size.Y / 2, 0),
			Color = if isCrate then Color3.fromRGB(46, 40, 60) else Color3.fromRGB(70, 72, 82),
			Material = if isCrate then Enum.Material.DiamondPlate else Enum.Material.Concrete,
			Parent = plaza,
		})
	end
	plaza.Parent = parent
end

-- Укрытия на улицах: бетонные блоки поперёк и вдоль дороги
local function buildStreetCovers(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "StreetCovers"
	for _, street in STREETS do
		for _, along in BLOCK_CENTERS do
			for _, alongX in { true, false } do
				if random:NextNumber() < 0.55 then
					local shift = random:NextNumber(-4, 4)
					local position = if alongX
						then Vector3.new(along + random:NextNumber(-12, 12), GROUND_Y + 1.5, street + shift)
						else Vector3.new(street + shift, GROUND_Y + 1.5, along + random:NextNumber(-12, 12))
					part({
						Name = "Barrier",
						Size = if random:NextNumber() < 0.5 then Vector3.new(7, 3, 2) else Vector3.new(2, 3, 7),
						Position = position,
						Color = Color3.fromRGB(70, 72, 82),
						Material = Enum.Material.Concrete,
						Parent = folder,
					})
				end
			end
		end
	end
	folder.Parent = parent
end

local function buildNodes(map: Model)
	local nodes = Instance.new("Folder")
	nodes.Name = "GlitchNodes"
	nodes.Parent = map
	for i, position in NODE_POSITIONS do
		local node = part({
			Name = `Glitch{i}`,
			Size = Vector3.new(4, 4, 4),
			CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), math.rad(45), 0),
			Color = GLITCH,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = nodes,
		})
		-- Луч в небо: видно издалека, где сбой
		neon({
			Name = "Beacon",
			Size = Vector3.new(1.5, 120, 1.5),
			Position = Vector3.new(position.X, 60, position.Z),
			Color = GLITCH,
			Transparency = 0.6,
			Parent = node,
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
end

local function buildEnemySpawns(map: Model)
	local folder = Instance.new("Folder")
	folder.Name = "EnemySpawns"
	for i, position in ENEMY_SPAWNS do
		part({
			Name = `Spawn{i}`,
			Size = Vector3.new(4, 0.2, 4),
			Position = position + Vector3.new(0, 0.1, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = folder,
		})
	end
	folder.Parent = map
end

local function build(): Model
	local map = Instance.new("Model")
	map.Name = "MissionMap"

	buildGround(map)
	buildPlaza(map)
	for _, cx in BLOCK_CENTERS do
		for _, cz in BLOCK_CENTERS do
			if cx ~= 0 or cz ~= 0 then
				buildBlock(map, cx, cz)
			end
		end
	end
	buildBoundary(map)
	buildStreetCovers(map)

	local lights = Instance.new("Folder")
	lights.Name = "StreetLights"
	lights.Parent = map
	for _, x in STREETS do
		for _, z in STREETS do
			buildStreetLight(lights, Vector3.new(x + STREET_WIDTH / 2 - 1, GROUND_Y, z + STREET_WIDTH / 2 - 1))
		end
	end

	buildNodes(map)
	buildEnemySpawns(map)

	map.Parent = Workspace
	return map
end

-- Строит карту (если её нет) и возвращает точки-сбои
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

-- Точки, где появляются враги
function MissionMap.enemySpawns(): { Vector3 }
	local map = Workspace:FindFirstChild("MissionMap")
	local folder = map and map:FindFirstChild("EnemySpawns")
	local points = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(points, child.Position)
			end
		end
	end
	return points
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
	local beacon = node:FindFirstChild("Beacon")
	if beacon and beacon:IsA("BasePart") then
		beacon.Transparency = if active then 0.6 else 1
	end
	local prompt = node:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = active
	end
end

return MissionMap
