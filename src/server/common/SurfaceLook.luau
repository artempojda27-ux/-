--!strict
-- Поверхности высокого качества (Штаб и Миссия): настоящие PBR-материалы вместо гладкого пластика
-- и световые эффекты улиц.
--   Материалы — MaterialVariant в MaterialService (заданы в *.project.json, текстуры сгенерированы в Studio):
--     IskAsphalt — мокрый асфальт с бликами луж, IskTiles — плитка тротуара со светящимися швами,
--     IskPanels — металлическая палуба с болтами, IskTempleStone — камень храма с мхом и лепестками.
--   Фонари: конус света вниз (Beam) и тёплое пятно на асфальте — как в дождливом ночном городе.
--   Лужи: тёмные зеркальные пятна на дороге, в них отражаются неон и фонари.

-- Какие материалы у мира: дорога, тротуар (nil — не трогать: у мира своя задумка — стекло, гипс)
local WORLD_SURFACES: { [string]: { Ground: { string }?, Sidewalk: { string }?, Puddles: boolean? } } = {
	Neon = { Ground = { "Asphalt", "IskAsphalt" }, Sidewalk = { "CeramicTiles", "IskTiles" }, Puddles = true },
	Mirror = { Ground = { "Asphalt", "IskAsphalt" }, Sidewalk = { "CeramicTiles", "IskTiles" }, Puddles = true },
	Temple = { Ground = { "Cobblestone", "IskTempleStone" }, Sidewalk = { "Cobblestone", "IskTempleStone" } },
	Core = { Ground = { "DiamondPlate", "IskPanels" }, Sidewalk = { "CeramicTiles", "IskTiles" } },
}
local STREETS = { -90, -30, 30, 90 }

local SurfaceLook = {}

local random = Random.new(2049)

-- Текстура умножается на цвет детали: у тёмной дороги рисунка не видно, поэтому
-- ставим светлый оттенок прежнего цвета — сама текстура и так тёмная
local function setMaterial(part: BasePart, spec: { string })
	part.Material = (Enum.Material :: any)[spec[1]]
	part.MaterialVariant = spec[2]
	local h, sat, v = part.Color:ToHSV()
	part.Color = Color3.fromHSV(h, math.min(sat, 0.25), math.max(v, 0.48))
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Конус света под фонарём: полупрозрачный луч (Beam) от лампы к земле и пятно на асфальте
local function lightCone(lamp: BasePart, groundY: number, color: Color3)
	local top = Instance.new("Attachment")
	top.Name = "ConeTop"
	top.Parent = lamp
	local floor = part({
		Name = "ConeFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, 12, 12),
		CFrame = CFrame.new(lamp.Position.X, groundY + 0.03, lamp.Position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.88,
		Parent = lamp,
	})
	local bottom = Instance.new("Attachment")
	bottom.Name = "ConeBottom"
	bottom.Parent = floor
	local beam = Instance.new("Beam")
	beam.Attachment0 = top
	beam.Attachment1 = bottom
	beam.Width0 = 1.5
	beam.Width1 = 11
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.97) })
	beam.Segments = 2
	beam.Parent = lamp
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = 22
	spot.Brightness = 2.5
	spot.Color = color
	spot.Parent = lamp
end

-- Лужи на дорогах: тонкие зеркальные пятна неровной формы из нескольких кругов
local function puddles(map: Instance, groundY: number)
	local folder = Instance.new("Folder")
	folder.Name = "Puddles"
	for _ = 1, 40 do
		local street = STREETS[random:NextInteger(1, #STREETS)]
		local along = random:NextNumber(-120, 120)
		local x, z = street + random:NextNumber(-6, 6), along
		if random:NextNumber() < 0.5 then
			x, z = z, x
		end
		for _ = 1, random:NextInteger(2, 4) do
			local size = random:NextNumber(2.5, 6)
			part({
				Name = "Puddle",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.04, size, size * random:NextNumber(0.6, 1)),
				CFrame = CFrame.new(x + random:NextNumber(-2.5, 2.5), groundY + 0.025, z + random:NextNumber(-2.5, 2.5))
					* CFrame.Angles(0, random:NextNumber(0, 6), math.rad(90)),
				Color = Color3.fromRGB(10, 12, 18),
				Material = Enum.Material.Glass,
				Reflectance = 0.55,
				Transparency = 0.15,
				Parent = folder,
			})
		end
	end
	folder.Parent = map
end

-- Город Миссии: материалы мира, конусы фонарей, лужи
function SurfaceLook.applyCity(worldId: string, map: Instance)
	local surfaces = WORLD_SURFACES[worldId]
	local groundY = 1
	for _, descendant in map:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant.Name == "Ground" then
			groundY = descendant.Position.Y + descendant.Size.Y / 2
			if surfaces and surfaces.Ground then
				setMaterial(descendant, surfaces.Ground)
			end
		elseif descendant.Name == "Sidewalk" and surfaces and surfaces.Sidewalk then
			setMaterial(descendant, surfaces.Sidewalk)
		end
	end
	local lights = map:FindFirstChild("StreetLights")
	if lights and worldId ~= "Erased" then -- в Стёртом мире фонари погашены
		for _, lamp in lights:GetDescendants() do
			if lamp:IsA("BasePart") and lamp.Name == "Lamp" then
				lightCone(lamp, groundY, lamp.Color)
			end
		end
	end
	if surfaces and surfaces.Puddles then
		puddles(map, groundY)
	end
end

-- Штаб: пол — металлическая палуба
function SurfaceLook.applyLobby(map: Instance)
	local floor = map:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		floor.Material = Enum.Material.DiamondPlate
		floor.MaterialVariant = "IskPanels"
		floor.Color = Color3.fromRGB(110, 120, 145) -- текстура тёмная сама по себе, цвет детали её только подсвечивает
	end
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Material == Enum.Material.Asphalt then
			descendant.MaterialVariant = "IskAsphalt" -- трасса вокруг площадки
		end
	end
end

return SurfaceLook
