--!strict
-- Внешний вид параллельных миров. Обычный «Неоновый город» ничего не меняет.
--   «Зеркальный город»: всё в красных тонах, а над городом вниз головой висит его отражение.
--   «Храм ветра»: мир ниндзя на закате — пагоды из тёмного дерева, фонари, сакура и падающие лепестки,
--     горы со снежными шапками вокруг, над городом кружит золотой дракон.
--   «Кристалл семи миров»: дома — цветные полупрозрачные кристаллы, на улицах друзы, над площадью
--     большой Кристалл, вокруг которого вращаются семь малых — по одному на каждый мир.
--   «Стёртый мир»: почти чёрно-белый, в густом белом тумане; часть домов «стёрта» до призраков,
--     обломки кварталов висят в воздухе, над площадью парит огромная разломанная колонна.
--   «Монолит»: чёрная пустота; дома — глянцевые чёрные монолиты с белыми линиями,
--     пол светится белой сеткой, в небе висит гигантский красный механический глаз.

local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

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

---------------------------------------------------------------- Общее для живых декораций

-- Детальная модель мира, увеличенная так, чтобы её самая длинная сторона была length.
-- Берётся либо готовой моделью (Asset), либо собирается из сетки и текстуры (Mesh + Texture).
local function loadProp(spec: Config.PropSpec, length: number): Model?
	local model: Model? = nil
	if spec.Asset then
		local ok, container = pcall(InsertService.LoadAsset, InsertService, spec.Asset)
		model = if ok then container:FindFirstChildWhichIsA("Model") else nil
		if model then
			model.Parent = nil
		end
		if ok then
			container:Destroy()
		end
	elseif spec.Mesh then
		local meshId = `rbxassetid://{spec.Mesh}`
		local ok, mesh = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(meshId))
		end)
		if not ok then
			ok, mesh = pcall(function()
				return (AssetService :: any):CreateMeshPartAsync(meshId)
			end)
		end
		if ok and mesh then
			if spec.Texture then
				mesh.TextureID = `rbxassetid://{spec.Texture}`
			end
			local holder = Instance.new("Model")
			mesh.Parent = holder
			holder.PrimaryPart = mesh
			model = holder
		end
	end
	if not model then
		warn("Не загрузилась модель мира")
		return nil
	end
	local _, size = model:GetBoundingBox()
	model:ScaleTo(length / math.max(size.X, size.Y, size.Z))
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	return model
end

-- Модели, которые медленно летают по кругу: { модель, центр, радиус, высота, скорость, фаза }
type Orbiter = { Model: Model, Center: Vector3, Radius: number, Speed: number, Phase: number, Bob: number, Spin: number }
local orbiters: { Orbiter } = {}
local orbitConnection: RBXScriptConnection? = nil

local function orbit(model: Model, center: Vector3, radius: number, speed: number, phase: number, bob: number, spin: number)
	table.insert(orbiters, { Model = model, Center = center, Radius = radius, Speed = speed, Phase = phase, Bob = bob, Spin = spin })
	if orbitConnection then
		return
	end
	local elapsed = 0
	orbitConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		for _, o in orbiters do
			local angle = o.Phase + elapsed * o.Speed
			local position = o.Center + Vector3.new(math.cos(angle) * o.Radius, math.sin(elapsed * 0.7 + o.Phase) * o.Bob, math.sin(angle) * o.Radius)
			-- летит по касательной к кругу, Spin — собственное вращение (для кристаллов)
			local heading = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * (if o.Speed >= 0 then 1 else -1)
			local cf = if o.Spin ~= 0
				then CFrame.new(position) * CFrame.Angles(0, elapsed * o.Spin, 0)
				else CFrame.lookAt(position, position + heading)
			o.Model:PivotTo(cf)
		end
	end)
end

-- Кристалл-«самоцвет» из одной детали: вытянутый куб, повёрнутый на ребро
local function gem(parent: Instance, cf: CFrame, size: number, color: Color3, glow: boolean): BasePart
	return part({
		Name = "Gem",
		Size = Vector3.new(size, size * 1.8, size),
		CFrame = cf * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(12), 0, math.rad(12)),
		Color = color,
		Material = if glow then Enum.Material.Neon else Enum.Material.Glass,
		Transparency = if glow then 0.15 else 0.25,
		Reflectance = if glow then 0 else 0.3,
		Parent = parent,
	})
end

---------------------------------------------------------------- Храм ветра (мир ниндзя)

local TEMPLE_WOOD = {
	Color3.fromRGB(120, 32, 26),
	Color3.fromRGB(78, 34, 24),
	Color3.fromRGB(48, 34, 30),
}
local TEMPLE_WORDS = { "ВЕТЕР", "ОГОНЬ", "ЗЕМЛЯ", "МОЛНИЯ", "ЛЁД", "ТЕНЬ", "ВОДА", "ДУХ" }
local GOLD = Color3.fromRGB(235, 185, 70)
local LANTERN = Color3.fromRGB(255, 130, 60)
local BLOSSOM = Color3.fromRGB(255, 170, 200)

-- Крыша пагоды над домом и ярусы-навесы по высоте
local function pagodaRoofs(building: Model, parent: Instance)
	local body = building:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end
	local size = body.Size
	local top = body.Position + Vector3.new(0, size.Y / 2, 0)
	local roofColor = Color3.fromRGB(36, 34, 40)
	-- ярусы
	for y = 14, size.Y - 6, 16 do
		part({
			Name = "Eave",
			Size = Vector3.new(size.X + 5, 0.7, size.Z + 5),
			Position = body.Position + Vector3.new(0, -size.Y / 2 + y, 0),
			Color = roofColor,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end
	-- двускатная крыша из двух клиньев и золотые концы конька
	local half = (size.Z + 6) / 2
	for _, side in { -1, 1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Roof"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.Size = Vector3.new(size.X + 6, 5, half)
		wedge.CFrame = CFrame.new(top + Vector3.new(0, 2.5, side * half / 2)) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
		wedge.Color = roofColor
		wedge.Material = Enum.Material.Slate
		wedge.Parent = parent
	end
	for _, side in { -1, 1 } do
		part({
			Name = "RidgeTip",
			Size = Vector3.new(1.2, 2.5, 1.2),
			CFrame = CFrame.new(top + Vector3.new(side * (size.X / 2 + 3), 5.5, 0)) * CFrame.Angles(0, 0, math.rad(-25 * side)),
			Color = GOLD,
			Material = Enum.Material.Metal,
			Reflectance = 0.3,
			Parent = parent,
		})
	end
end

local function cherryTree(parent: Instance, position: Vector3)
	local height = random:NextNumber(7, 10)
	local trunk = part({
		Name = "Trunk",
		Size = Vector3.new(1.2, height, 1.2),
		Position = position + Vector3.new(0, height / 2, 0),
		Color = Color3.fromRGB(70, 44, 36),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	trunk.CanCollide = true
	for _ = 1, 4 do
		part({
			Name = "Blossom",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * random:NextNumber(4.5, 7),
			Position = position + Vector3.new(random:NextNumber(-2.5, 2.5), height + random:NextNumber(-1, 2), random:NextNumber(-2.5, 2.5)),
			Color = BLOSSOM,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
end

local function applyTemple(map: Instance?)
	setLighting({
		ClockTime = 17.6,
		Brightness = 2.5,
		Ambient = Color3.new(0.36, 0.26, 0.26),
		OutdoorAmbient = Color3.new(0.62, 0.46, 0.42),
		ExposureCompensation = 0.2,
	}, {
		Color = Color3.new(0.95, 0.6, 0.45),
		Decay = Color3.new(0.6, 0.3, 0.4),
		Density = 0.32,
		Offset = 0.2,
		Haze = 1.5,
		Glare = 0.6,
	}, {
		Saturation = 0.15,
		Contrast = 0.1,
		TintColor = Color3.new(1, 0.94, 0.88),
	})
	if not map then
		return
	end

	local props = Instance.new("Folder")
	props.Name = "TempleProps"

	-- Дерево, бумажные окна-фонари, золото; камень на земле
	eachPart(map, function(p)
		if p.Name == "Body" then
			p.Color = TEMPLE_WOOD[random:NextInteger(1, #TEMPLE_WOOD)]
			p.Material = Enum.Material.WoodPlanks
		elseif p.Name == "RoofEdge" then
			p.Color = GOLD
		elseif p.Material == Enum.Material.Neon and p.Name ~= "Beacon" then
			p.Color = LANTERN
			p.Transparency = math.max(p.Transparency, 0.62) -- мягкий свет бумажных окон
		elseif p.Name == "Ground" then
			p.Color = Color3.fromRGB(92, 88, 84)
			p.Material = Enum.Material.Slate
		elseif p.Name == "Sidewalk" then
			p.Color = Color3.fromRGB(124, 104, 86)
			p.Material = Enum.Material.Cobblestone
		end
	end)
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("PointLight") or descendant:IsA("SurfaceLight") then
			descendant.Color = LANTERN
		elseif descendant:IsA("TextLabel") then
			descendant.TextColor3 = GOLD
			descendant.Text = TEMPLE_WORDS[random:NextInteger(1, #TEMPLE_WORDS)]
		end
	end
	for _, building in buildings(map) do
		if not building:FindFirstChild("Skin") then -- у детальной пагоды крыша уже своя
			pagodaRoofs(building, props)
		end
	end

	-- Сакура по углам кварталов
	for _, x in { -60, 0, 60 } do
		for _, z in { -60, 0, 60 } do
			for _, corner in { Vector3.new(-19, 0, -19), Vector3.new(19, 0, 19), Vector3.new(19, 0, -19), Vector3.new(-19, 0, 19) } do
				if random:NextNumber() < 0.6 then
					cherryTree(props, Vector3.new(x, 1.6, z) + corner)
				end
			end
		end
	end

	-- Горы со снежными вершинами вокруг города (рельеф из шаров: скала, сверху снег)
	local terrain = Workspace.Terrain
	for i = 1, 12 do
		local angle = math.rad(i * 360 / 12 + random:NextNumber(-10, 10))
		local distance = random:NextNumber(250, 320)
		local base = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local height = random:NextNumber(110, 190)
		local radius = random:NextNumber(55, 85)
		-- гора — стопка шаров, сужающаяся кверху
		for level = 0, 4 do
			local t = level / 4
			local r = radius * (1 - t * 0.75)
			terrain:FillBall(base + Vector3.new(random:NextNumber(-6, 6), height * t * 0.8, random:NextNumber(-6, 6)), r, Enum.Material.Rock)
		end
		terrain:FillBall(base + Vector3.new(0, height * 0.82, 0), radius * 0.3, Enum.Material.Snow)
	end

	-- Падающие лепестки сакуры
	local sky = part({
		Name = "PetalCloud",
		Size = Vector3.new(240, 1, 240),
		Position = Vector3.new(0, 70, 0),
		Transparency = 1,
		Parent = props,
	})
	local petals = Instance.new("ParticleEmitter")
	petals.Color = ColorSequence.new(BLOSSOM)
	petals.Size = NumberSequence.new(0.35)
	petals.Lifetime = NumberRange.new(10, 14)
	petals.Rate = 70
	petals.Speed = NumberRange.new(1, 3)
	petals.Acceleration = Vector3.new(1.5, -4, 0.5)
	petals.Rotation = NumberRange.new(0, 360)
	petals.RotSpeed = NumberRange.new(-90, 90)
	petals.SpreadAngle = Vector2.new(180, 180)
	petals.EmissionDirection = Enum.NormalId.Bottom
	petals.Parent = sky

	props.Parent = Workspace

	-- Золотой дракон кружит над городом
	local dragon = loadProp(Config.WorldProps.Dragon, 110)
	if dragon then
		dragon.Name = "Dragon"
		dragon.Parent = props
		orbit(dragon, Vector3.new(0, 120, 0), 150, 0.12, 0, 12, 0)
	end
end

---------------------------------------------------------------- Кристалл семи миров

local CRYSTAL_COLORS = {
	Color3.fromRGB(190, 150, 255),
	Color3.fromRGB(130, 225, 255),
	Color3.fromRGB(255, 160, 225),
	Color3.fromRGB(150, 255, 215),
}
-- Семь малых кристаллов — по цвету каждого мира (седьмой — мир, который ещё впереди)
local SEVEN_WORLDS = {
	Color3.fromRGB(0, 255, 200), -- Неоновый город
	Color3.fromRGB(255, 50, 70), -- Зеркальный город
	Color3.fromRGB(235, 185, 70), -- Храм ветра
	Color3.fromRGB(190, 150, 255), -- Кристалл семи миров
	Color3.fromRGB(245, 245, 250), -- Стёртый мир
	Color3.fromRGB(20, 20, 24), -- Монолит
	Color3.fromRGB(90, 255, 90), -- Ядро (впереди)
}

local function applyCrystal(map: Instance?)
	setLighting({
		ClockTime = 22,
		Brightness = 2,
		Ambient = Color3.new(0.26, 0.2, 0.36),
		OutdoorAmbient = Color3.new(0.46, 0.4, 0.62),
		ExposureCompensation = 0.3,
	}, {
		Color = Color3.new(0.45, 0.35, 0.8),
		Decay = Color3.new(0.25, 0.5, 0.7),
		Density = 0.3,
		Offset = 0.2,
		Haze = 1.2,
		Glare = 0.3,
	}, {
		Saturation = 0.3,
		Contrast = 0.15,
		TintColor = Color3.new(0.96, 0.95, 1),
	})
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.StarCount = 5000
	end
	if not map then
		return
	end

	local props = Instance.new("Folder")
	props.Name = "CrystalProps"

	-- Дома — цветные полупрозрачные кристаллы с самоцветами на вершинах
	eachPart(map, function(p)
		if p.Name == "Body" then
			if p.Transparency < 1 then -- невидимая коробка под детальной моделью остаётся невидимой
				p.Color = CRYSTAL_COLORS[random:NextInteger(1, #CRYSTAL_COLORS)]
				p.Material = Enum.Material.Glass
				p.Transparency = 0.3
				p.Reflectance = 0.25
			end
		elseif p.Material == Enum.Material.Neon and p.Name ~= "Beacon" then
			p.Color = Color3.fromRGB(245, 240, 255)
		elseif p.Name == "Ground" then
			p.Color = Color3.fromRGB(28, 20, 46)
			p.Material = Enum.Material.Glass
			p.Reflectance = 0.3
		elseif p.Name == "Sidewalk" then
			p.Color = Color3.fromRGB(58, 40, 88)
		end
	end)
	for _, building in buildings(map) do
		local body = building:FindFirstChild("Body")
		if body and body:IsA("BasePart") and not building:FindFirstChild("Skin") then
			local size = math.min(body.Size.X, body.Size.Z) * 0.6
			gem(props, CFrame.new(body.Position + Vector3.new(0, body.Size.Y / 2 + size * 0.6, 0)), size, body.Color, false)
		end
	end

	-- Кристальные друзы на улицах
	local lights = 0
	for _ = 1, 32 do
		local x = ({ -90, -30, 30, 90 })[random:NextInteger(1, 4)] + random:NextNumber(-6, 6)
		local z = random:NextNumber(-110, 110)
		if random:NextNumber() < 0.5 then
			x, z = z, x
		end
		if math.abs(x) < 25 and math.abs(z) < 25 then
			continue -- площадь оставляем свободной
		end
		local color = CRYSTAL_COLORS[random:NextInteger(1, #CRYSTAL_COLORS)]
		for _ = 1, random:NextInteger(3, 5) do
			local g = gem(props, CFrame.new(x + random:NextNumber(-2, 2), 2.5, z + random:NextNumber(-2, 2))
				* CFrame.Angles(random:NextNumber(-0.5, 0.5), 0, random:NextNumber(-0.5, 0.5)), random:NextNumber(1.2, 2.6), color, true)
			if lights < 10 and random:NextNumber() < 0.3 then
				lights += 1
				local light = Instance.new("PointLight")
				light.Color = color
				light.Range = 18
				light.Brightness = 2
				light.Parent = g
			end
		end
	end

	-- Семь малых кристаллов вращаются вокруг большого над площадью
	local center = Vector3.new(0, 105, 0)
	for i, color in SEVEN_WORLDS do
		local holder = Instance.new("Model")
		holder.Name = `WorldCrystal{i}`
		local g = gem(holder, CFrame.new(center), 7, color, color ~= SEVEN_WORLDS[6])
		holder.PrimaryPart = g
		holder.Parent = props
		orbit(holder, center, 48, 0.25, (i - 1) * math.pi * 2 / #SEVEN_WORLDS, 6, 1.2)
	end

	props.Parent = Workspace

	local big = loadProp(Config.WorldProps.BigCrystal, 55)
	if big then
		big.Name = "BigCrystal"
		big.Parent = props
	else
		local holder = Instance.new("Model")
		holder.Name = "BigCrystal"
		holder.PrimaryPart = gem(holder, CFrame.new(center), 22, Color3.fromRGB(200, 170, 255), true)
		holder.Parent = props
		big = holder
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 170, 255)
	light.Range = 60
	light.Brightness = 3
	light.Parent = (big :: Model):FindFirstChildWhichIsA("BasePart", true)
	orbit(big :: Model, center, 0, 0, 0, 4, 0.3)
end

-- Применяет вид мира (map может быть nil, например в Побеге меняется только свет)
function WorldLook.apply(worldId: string, map: Instance?)
	if worldId == "Mirror" then
		applyMirror(map)
	elseif worldId == "Temple" then
		applyTemple(map)
	elseif worldId == "Crystal" then
		applyCrystal(map)
	elseif worldId == "Erased" then
		applyErased(map)
	elseif worldId == "Monolith" then
		applyMonolith(map)
	end
end

return WorldLook
