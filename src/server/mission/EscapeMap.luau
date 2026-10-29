--!strict
-- Трасса для режима «Побег»: прямая неоновая дорога от старта (z = 0) вперёд по −Z до ворот выхода.
-- На дороге — бетонные блоки и трамплины, по бокам — неоновые башни и стены (за трассу не вылететь).
-- Трасса строится по одному «зерну», поэтому всегда одинаковая.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local CYAN = Color3.fromRGB(0, 255, 200)
local GLITCH = Color3.fromRGB(255, 40, 120)
local NEON_COLORS = {
	Color3.fromRGB(0, 255, 200),
	Color3.fromRGB(255, 40, 120),
	Color3.fromRGB(150, 80, 255),
	Color3.fromRGB(60, 140, 255),
}

local WIDTH = 64 -- ширина дороги
local SEGMENT = 120
local GROUND_Y = 1 -- верх асфальта
local START_LENGTH = 80 -- площадка старта за линией z = 0
local OBSTACLES_FROM = 220 -- первые столько студов дорога свободна
local ENEMY_EVERY = 240

export type Course = {
	Start: number, -- z старта
	Finish: number, -- z ворот выхода
	VehicleSpots: { CFrame }, -- где ставить машины отряда
	EnemySpots: { Vector3 }, -- где у обочин появляются враги
}

local EscapeMap = {}

local random = Random.new(777)

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

local function neon(props: { [string]: any }): Part
	props.Material = Enum.Material.Neon
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return part(props)
end

local function buildRoad(map: Model, length: number)
	local road = Instance.new("Folder")
	road.Name = "Road"
	road.Parent = map
	local total = length + START_LENGTH + 120
	for z = START_LENGTH, -length - 120, -SEGMENT do
		part({
			Name = "Asphalt",
			Size = Vector3.new(WIDTH, 1, SEGMENT),
			Position = Vector3.new(0, GROUND_Y - 0.5, z - SEGMENT / 2),
			Color = Color3.fromRGB(20, 20, 28),
			Material = Enum.Material.Asphalt,
			Parent = road,
		})
	end
	-- Неоновые края и пунктир по центру
	for _, side in { -1, 1 } do
		for z = START_LENGTH, -length - 120, -SEGMENT do
			neon({
				Size = Vector3.new(0.6, 0.1, SEGMENT),
				Position = Vector3.new(side * (WIDTH / 2 - 1), GROUND_Y + 0.05, z - SEGMENT / 2),
				Color = if side < 0 then CYAN else GLITCH,
				Transparency = 0.2,
				Parent = road,
			})
		end
	end
	for z = 0, -length, -16 do
		neon({
			Size = Vector3.new(0.5, 0.05, 7),
			Position = Vector3.new(0, GROUND_Y + 0.03, z),
			Color = CYAN,
			Transparency = 0.5,
			Parent = road,
		})
	end
	-- Стены: низкие видимые и высокие невидимые (после трамплина и сальто за трассу не вылететь)
	for _, side in { -1, 1 } do
		part({
			Name = "Wall",
			Size = Vector3.new(2, 5, total),
			Position = Vector3.new(side * (WIDTH / 2 + 1), GROUND_Y + 2.5, (START_LENGTH - length - 120) / 2),
			Color = Color3.fromRGB(30, 32, 44),
			Parent = road,
		})
		part({
			Name = "Barrier",
			Size = Vector3.new(2, 120, total),
			Position = Vector3.new(side * (WIDTH / 2 + 1), GROUND_Y + 60, (START_LENGTH - length - 120) / 2),
			Transparency = 1,
			Parent = road,
		})
	end
	-- Стена позади старта
	part({
		Name = "Barrier",
		Size = Vector3.new(WIDTH + 4, 120, 2),
		Position = Vector3.new(0, GROUND_Y + 60, START_LENGTH + 1),
		Transparency = 1,
		Parent = road,
	})
end

-- Неоновые башни вдоль трассы — «город» по сторонам
local function buildTowers(map: Model, length: number)
	local towers = Instance.new("Folder")
	towers.Name = "Towers"
	towers.Parent = map
	for z = 0, -length, -70 do
		for _, side in { -1, 1 } do
			local height = random:NextInteger(30, 110)
			local width = random:NextInteger(16, 28)
			local x = side * (WIDTH / 2 + 8 + width / 2 + random:NextInteger(0, 12))
			local color = NEON_COLORS[random:NextInteger(1, #NEON_COLORS)]
			part({
				Name = "Tower",
				Size = Vector3.new(width, height, width),
				Position = Vector3.new(x, GROUND_Y + height / 2, z),
				Color = Color3.fromRGB(44, 46, 70),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = towers,
			})
			for y = 8, height - 4, 9 do
				if random:NextNumber() < 0.7 then
					neon({
						Size = Vector3.new(0.2, 0.8, width - 3),
						Position = Vector3.new(x - side * (width / 2 + 0.1), GROUND_Y + y, z),
						Color = color,
						Transparency = random:NextNumber(0, 0.4),
						Parent = towers,
					})
				end
			end
		end
	end
end

-- Препятствия: бетонные блоки и трамплины
local function buildObstacles(map: Model, length: number)
	local obstacles = Instance.new("Folder")
	obstacles.Name = "Obstacles"
	obstacles.Parent = map
	for z = -OBSTACLES_FROM, -length + 120, -SEGMENT do
		for _ = 1, random:NextInteger(1, 3) do
			local x = random:NextNumber(-WIDTH / 2 + 6, WIDTH / 2 - 6)
			local shiftZ = random:NextNumber(-40, 40)
			-- барьер должен быть виден издалека: светлый бетон, красно-белые неоновые полосы и маяк сверху
			local width = random:NextInteger(6, 12)
			local barrier = part({
				Name = "Barrier",
				Size = Vector3.new(width, 4, 3),
				Position = Vector3.new(x, GROUND_Y + 2, z + shiftZ),
				Color = Color3.fromRGB(210, 210, 220),
				Material = Enum.Material.Concrete,
				Parent = obstacles,
			})
			for i = 0, math.floor(width / 2) - 1 do
				neon({
					Size = Vector3.new(1, 3.6, 0.2),
					CFrame = barrier.CFrame * CFrame.new(-width / 2 + 1 + i * 2, 0, 1.55) * CFrame.Angles(0, 0, math.rad(30)),
					Color = Color3.fromRGB(255, 40, 60),
					Parent = obstacles,
				})
			end
			local lamp = neon({
				Size = Vector3.new(width, 0.4, 0.4),
				Position = barrier.Position + Vector3.new(0, 2.2, 0),
				Color = Color3.fromRGB(255, 60, 60),
				Parent = obstacles,
			})
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 50, 50)
			glow.Range = 18
			glow.Brightness = 2
			glow.Parent = lamp
		end
		if random:NextNumber() < 0.45 then
			-- Трамплин: поднимается по ходу движения (к −Z)
			local x = random:NextNumber(-WIDTH / 2 + 12, WIDTH / 2 - 12)
			local ramp = Instance.new("WedgePart")
			ramp.Name = "Ramp"
			ramp.Anchored = true
			ramp.Size = Vector3.new(16, 4, 16)
			ramp.CFrame = CFrame.new(x, GROUND_Y + 2, z - 60) * CFrame.Angles(0, math.rad(180), 0)
			ramp.Color = Color3.fromRGB(40, 42, 58)
			ramp.Material = Enum.Material.DiamondPlate
			ramp.Parent = obstacles
			neon({
				Size = Vector3.new(16, 0.2, 0.4),
				Position = Vector3.new(x, GROUND_Y + 4.1, z - 68),
				Color = Color3.fromRGB(255, 190, 40),
				Parent = obstacles,
			})
		end
	end
end

-- Ворота выхода: неоновая арка и линия финиша
local function buildFinish(map: Model, finishZ: number)
	local gate = Instance.new("Model")
	gate.Name = "Finish"
	for _, side in { -1, 1 } do
		neon({
			Size = Vector3.new(2, 30, 2),
			Position = Vector3.new(side * (WIDTH / 2 - 2), GROUND_Y + 15, finishZ),
			Color = CYAN,
			Parent = gate,
		})
	end
	neon({
		Size = Vector3.new(WIDTH, 2, 2),
		Position = Vector3.new(0, GROUND_Y + 30, finishZ),
		Color = CYAN,
		Parent = gate,
	})
	neon({
		Name = "Line",
		Size = Vector3.new(WIDTH, 0.1, 4),
		Position = Vector3.new(0, GROUND_Y + 0.06, finishZ),
		Color = Color3.fromRGB(255, 255, 255),
		Parent = gate,
	})
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(30, 6, 0.5),
		Position = Vector3.new(0, GROUND_Y + 24, finishZ),
		Color = Color3.fromRGB(10, 10, 16),
		CanCollide = false,
		Parent = gate,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = CYAN
	label.Text = "ВЫХОД"
	label.Parent = gui
	gui.Parent = sign
	gate.Parent = map
end

local function buildStart(map: Model)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.2, 10)
	spawn.Position = Vector3.new(0, GROUND_Y + 0.1, 50)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = map
	neon({
		Name = "StartLine",
		Size = Vector3.new(WIDTH, 0.1, 3),
		Position = Vector3.new(0, GROUND_Y + 0.06, 0),
		Color = GLITCH,
		Parent = map,
	})
end

-- Строит трассу (если её ещё нет) и возвращает её описание
function EscapeMap.setup(): Course
	local length = Config.Escape.Length
	if not Workspace:FindFirstChild("EscapeMap") then
		local map = Instance.new("Model")
		map.Name = "EscapeMap"
		buildRoad(map, length)
		buildTowers(map, length)
		buildObstacles(map, length)
		buildFinish(map, -length)
		buildStart(map)
		map.Parent = Workspace
	end

	local spots = {}
	for _, x in { -12, 12, -30 + 8, 30 - 8 } do
		local position = Vector3.new(x, GROUND_Y + 4, 25)
		table.insert(spots, CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	end
	local enemySpots = {}
	for z = -OBSTACLES_FROM - 60, -length + 60, -ENEMY_EVERY do
		for _, side in { -1, 1 } do
			table.insert(enemySpots, Vector3.new(side * (WIDTH / 2 - 5), GROUND_Y, z))
		end
	end
	return {
		Start = 0,
		Finish = -length,
		VehicleSpots = spots,
		EnemySpots = enemySpots,
	}
end

return EscapeMap
