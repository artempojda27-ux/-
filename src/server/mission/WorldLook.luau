--!strict
-- Внешний вид параллельных миров. Обычный «Неоновый город» ничего не меняет.
--   «Зеркальный город»: всё в красных тонах, а над городом вниз головой висит его отражение.
--   «Стёртый мир»: почти чёрно-белый, в густом белом тумане; часть домов «стёрта» до призраков,
--     обломки кварталов висят в воздухе, над площадью парит огромная разломанная колонна.
--   «Монолит»: чёрная пустота; дома — глянцевые чёрные монолиты с белыми линиями,
--     пол светится белой сеткой, в небе висит гигантский красный механический глаз.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local MIRROR_HEIGHT = 170 -- город отражается относительно этой высоты (земля → небо)

-- Неоновые цвета обычного города → цвета Зеркального
local MIRROR_NEON = {
	Color3.fromRGB(255, 50, 70),
	Color3.fromRGB(255, 120, 40),
	Color3.fromRGB(255, 230, 230),
	Color3.fromRGB(200, 20, 60),
}

local WorldLook = {}

local random = Random.new(1313)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function setLighting(props: { [string]: any }, atmosphere: { [string]: any }?, correction: { [string]: any }?)
	for key, value in props do
		(Lighting :: any)[key] = value
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo and atmosphere then
		for key, value in atmosphere do
			(atmo :: any)[key] = value
		end
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc and correction then
		for key, value in correction do
			(cc :: any)[key] = value
		end
	end
end

-- Обходит детали карты, кроме сбоев (по ним игроки ищут цель — их не трогаем)
local function eachPart(map: Instance, callback: (BasePart) -> ())
	local nodes = map:FindFirstChild("GlitchNodes")
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and not (nodes and descendant:IsDescendantOf(nodes)) then
			callback(descendant)
		end
	end
end

local function buildings(map: Instance): { Model }
	local list = {}
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == "Building" then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Копия модели, висящая в воздухе: без столкновений и света
local function floatingCopy(model: Model, cf: CFrame, parent: Instance)
	local copy = model:Clone()
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Light") then
			descendant:Destroy()
		end
	end
	copy:PivotTo(cf)
	copy.Parent = parent
end

---------------------------------------------------------------- Зеркальный город

local function applyMirror(map: Instance?)
	setLighting({
		Ambient = Color3.new(0.3, 0.14, 0.18),
		OutdoorAmbient = Color3.new(0.6, 0.3, 0.35),
	}, {
		Color = Color3.new(0.75, 0.22, 0.3),
		Decay = Color3.new(0.45, 0.05, 0.12),
		Density = 0.34,
	}, {
		TintColor = Color3.new(1, 0.82, 0.85),
		Contrast = 0.2,
	})
	if not map then
		return
	end
	local index = 0
	eachPart(map, function(p)
		if p.Material == Enum.Material.Neon then
			index += 1
			p.Color = MIRROR_NEON[index % #MIRROR_NEON + 1]
		elseif p.Name == "Body" then
			local _, saturation, value = p.Color:ToHSV()
			p.Color = Color3.fromHSV(0.98, math.max(saturation, 0.45), value * 0.8 + 0.05)
		end
	end)
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("PointLight") or descendant:IsA("SurfaceLight") then
			descendant.Color = Color3.fromRGB(255, 90, 90)
		elseif descendant:IsA("TextLabel") then
			descendant.TextColor3 = Color3.fromRGB(255, 70, 80)
		end
	end

	-- Перевёрнутая копия кварталов в небе
	local reflection = Instance.new("Folder")
	reflection.Name = "Reflection"
	local flip = CFrame.new(0, MIRROR_HEIGHT, 0) * CFrame.Angles(math.pi, 0, 0) * CFrame.new(0, -MIRROR_HEIGHT, 0)
	for _, child in map:GetChildren() do
		if child:IsA("Model") and (child.Name:sub(1, 6) == "Block_" or child.Name == "Boundary") then
			local copy = child:Clone()
			for _, descendant in copy:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.CFrame = flip * descendant.CFrame
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.CastShadow = false
				elseif descendant:IsA("Light") or descendant:IsA("ProximityPrompt") then
					descendant:Destroy()
				end
			end
			copy.Parent = reflection
		end
	end
	reflection.Parent = Workspace
end

---------------------------------------------------------------- Стёртый мир

-- Огромная белая колонна, разломанная на куски и зависшая над площадью
local function brokenColumn(parent: Instance)
	local base = CFrame.new(0, 150, 0) * CFrame.Angles(math.rad(18), math.rad(30), math.rad(70))
	local offset = 0
	for i = 1, 4 do
		local length = random:NextNumber(26, 44)
		local piece = base * CFrame.new(offset + length / 2, 0, 0)
			* CFrame.Angles(random:NextNumber(-0.15, 0.15), random:NextNumber(-0.15, 0.15), random:NextNumber(-0.1, 0.1))
		part({
			Name = `Column{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, 22, 22),
			CFrame = piece,
			Color = Color3.fromRGB(236, 236, 240),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		-- осколки в щели между кусками
		for _ = 1, 6 do
			part({
				Name = "Shard",
				Size = Vector3.one * random:NextNumber(1, 4),
				CFrame = piece * CFrame.new(length / 2 + random:NextNumber(1, 6), random:NextNumber(-10, 10), random:NextNumber(-10, 10))
					* CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0),
				Color = Color3.fromRGB(220, 220, 226),
				Material = Enum.Material.Marble,
				Parent = parent,
			})
		end
		offset += length + random:NextNumber(5, 10)
	end
end

local function applyErased(map: Instance?)
	setLighting({
		ClockTime = 13,
		Brightness = 3,
		Ambient = Color3.new(0.7, 0.7, 0.72),
		OutdoorAmbient = Color3.new(0.9, 0.9, 0.92),
		ExposureCompensation = 0.2,
	}, {
		Color = Color3.new(1, 1, 1),
		Decay = Color3.new(0.92, 0.92, 0.95),
		Density = 0.48,
		Offset = 0.1,
		Haze = 3,
		Glare = 0,
	}, {
		Saturation = -0.85,
		Contrast = 0.25,
		TintColor = Color3.new(1, 1, 1),
	})
	if not map then
		return
	end

	-- Город как набросок карандашом: белые дома, тёмные линии вместо неона
	eachPart(map, function(p)
		if p.Material == Enum.Material.Neon then
			p.Material = Enum.Material.SmoothPlastic
			p.Color = Color3.fromRGB(28, 28, 32)
			p.Transparency = math.min(p.Transparency, 0.3)
		elseif p.Name == "Body" then
			p.Color = Color3.fromRGB(random:NextInteger(200, 240), random:NextInteger(200, 240), random:NextInteger(205, 245))
			p.Material = Enum.Material.Plaster
		elseif p.Name == "Ground" or p.Name == "Sidewalk" then
			p.Color = Color3.fromRGB(180, 180, 186)
		end
	end)
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Light") then
			descendant.Enabled = false
		elseif descendant:IsA("TextLabel") then
			descendant.TextColor3 = Color3.fromRGB(20, 20, 24)
		end
	end

	-- Часть домов «стёрта»: остались полупрозрачные призраки, сквозь которые можно пройти
	local all = buildings(map)
	for _, building in all do
		if random:NextNumber() < 0.3 then
			for _, descendant in building:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Transparency = math.max(descendant.Transparency, 0.85)
					descendant.CanCollide = false
				end
			end
		end
	end

	-- Обломки кварталов в воздухе и разломанная колонна
	local debris = Instance.new("Folder")
	debris.Name = "ErasedDebris"
	for _ = 1, 10 do
		local source = all[random:NextInteger(1, #all)]
		if source then
			local position = Vector3.new(random:NextNumber(-120, 120), random:NextNumber(70, 160), random:NextNumber(-120, 120))
			floatingCopy(source, CFrame.new(position) * CFrame.Angles(random:NextNumber(-1, 1), random:NextNumber(0, 6), random:NextNumber(-1, 1)), debris)
		end
	end
	brokenColumn(debris)
	debris.Parent = Workspace
end

---------------------------------------------------------------- Монолит

-- Гигантский красный механический глаз в небе, смотрит на площадь
local function giantEye(parent: Instance)
	local center = Vector3.new(0, 210, -300)
	local look = CFrame.lookAt(center, Vector3.new(0, 0, 0))
	part({
		Name = "Eyeball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 120,
		CFrame = look,
		Color = Color3.fromRGB(12, 12, 14),
		Material = Enum.Material.Glass,
		Reflectance = 0.4,
		Parent = parent,
	})
	local iris = part({
		Name = "Iris",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 74, 74),
		CFrame = look * CFrame.new(0, 0, -59) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(230, 0, 20),
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	-- белое кольцо вокруг радужки
	part({
		Name = "IrisRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.5, 84, 84),
		CFrame = look * CFrame.new(0, 0, -57.5) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(240, 240, 255),
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	-- зрачок вынесен вперёд и крупнее, чтобы его не забивало свечение радужки
	part({
		Name = "Pupil",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 38, 38),
		CFrame = look * CFrame.new(0, 0, -63) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(0, 0, 0),
		Material = Enum.Material.Glass,
		Reflectance = 0.6,
		Parent = parent,
	})
	-- механические «веки»: кольцо из пластин вокруг глаза
	for i = 1, 16 do
		local angle = math.rad(i * 360 / 16)
		part({
			Name = "Plate",
			Size = Vector3.new(14, 4, 30),
			CFrame = look * CFrame.Angles(0, 0, angle) * CFrame.new(0, 66, -20) * CFrame.Angles(math.rad(-30), 0, 0),
			Color = Color3.fromRGB(30, 30, 34),
			Material = Enum.Material.Metal,
			Reflectance = 0.2,
			Parent = parent,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 20, 30)
	light.Range = 60
	light.Brightness = 6
	light.Parent = iris
end

local function applyMonolith(map: Instance?)
	setLighting({
		ClockTime = 0,
		Brightness = 1,
		Ambient = Color3.new(0.16, 0.16, 0.18),
		OutdoorAmbient = Color3.new(0.26, 0.26, 0.3),
		ExposureCompensation = 0.3,
	}, {
		Color = Color3.new(0.02, 0.02, 0.03),
		Decay = Color3.new(0, 0, 0),
		Density = 0.4,
		Offset = 0,
		Haze = 0,
		Glare = 0,
	}, {
		Saturation = -0.4,
		Contrast = 0.4,
		TintColor = Color3.new(1, 0.96, 0.96),
	})
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.StarCount = 0
	end
	if not map then
		return
	end

	-- Дома — глянцевые чёрные монолиты, неон — тонкие белые линии, пол — чёрное зеркало
	eachPart(map, function(p)
		if p.Material == Enum.Material.Neon then
			p.Color = Color3.fromRGB(235, 235, 240)
			p.Transparency = math.max(p.Transparency, 0.15)
		elseif p.Name == "Body" then
			p.Color = Color3.fromRGB(8, 8, 10)
			p.Material = Enum.Material.Glass
			p.Reflectance = 0.35
		elseif p.Name == "Ground" or p.Name == "Sidewalk" then
			p.Color = Color3.fromRGB(6, 6, 8)
			p.Material = Enum.Material.Glass
			p.Reflectance = 0.25
		end
	end)
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("PointLight") or descendant:IsA("SurfaceLight") then
			descendant.Color = Color3.fromRGB(240, 240, 255)
		elseif descendant:IsA("TextLabel") then
			descendant.TextColor3 = Color3.fromRGB(240, 240, 245)
		end
	end

	local props = Instance.new("Folder")
	props.Name = "MonolithProps"
	-- Светящаяся белая сетка на полу
	for offset = -120, 120, 24 do
		part({
			Name = "Grid",
			Size = Vector3.new(240, 0.06, 0.25),
			Position = Vector3.new(0, 1.04, offset),
			Color = Color3.fromRGB(240, 240, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			Parent = props,
		})
		part({
			Name = "Grid",
			Size = Vector3.new(0.25, 0.06, 240),
			Position = Vector3.new(offset, 1.04, 0),
			Color = Color3.fromRGB(240, 240, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			Parent = props,
		})
	end
	-- Висящие в небе плиты-монолиты вокруг глаза
	for i = 1, 6 do
		local angle = math.rad(i * 60)
		part({
			Name = "Slab",
			Size = Vector3.new(16, 90, 5),
			CFrame = CFrame.new(math.cos(angle) * 160, 170 + math.sin(angle * 2) * 20, -300 + math.sin(angle) * 80)
				* CFrame.Angles(0, angle, math.rad(10)),
			Color = Color3.fromRGB(6, 6, 8),
			Material = Enum.Material.Glass,
			Reflectance = 0.5,
			Parent = props,
		})
	end
	giantEye(props)
	props.Parent = Workspace
end

-- Применяет вид мира (map может быть nil, например в Побеге меняется только свет)
function WorldLook.apply(worldId: string, map: Instance?)
	if worldId == "Mirror" then
		applyMirror(map)
	elseif worldId == "Erased" then
		applyErased(map)
	elseif worldId == "Monolith" then
		applyMonolith(map)
	end
end

return WorldLook
