--!strict
-- Второй слой детализации миров (поверх WorldLook): то, что делает каждый мир живым.
-- Сервер строит модели; всё, что двигается, помечено тегом "Motion" и атрибутами, а двигает его клиент
-- (WorldMotion.client.luau) — плавно и без нагрузки на сеть. Погода и вспышки молний — атрибуты Workspace
-- "Weather" и "Lightning", их читает Ambience.client.luau.
--   Неоновый город: ночной дождь, мокрый асфальт, прожекторы на крышах шарят по небу.
--   Зеркальный город: в небе висят и вращаются осколки зеркала, красные молнии.
--   Храм ветра: ворота-тории у площади, каменные фонари вдоль улиц, туман у земли, в небо летят фонарики.
--   Кристалл семи миров: парящие острова с кристаллами, северное сияние, искры.
--   Стёртый мир: недорисованные дома-каркасы, линии разметки карандашом через всё небо, дыры-стирания
--     в земле, летят обрывки бумаги.
--   Монолит: вокруг города парят чёрные плиты, из глаза бьёт красный луч и обшаривает город, молнии.
--   Ядро: над площадью — пульсирующее ядро Сети с кольцами, от него лучи к башням, по улицам —
--     светящиеся дорожки схем, вверх бьют столбы света.

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local GROUND_Y = 1
local STREETS = { -90, -30, 30, 90 }

local WorldDetails = {}

local random = Random.new(9001)
local templates: { [number]: BasePart } = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Движение для клиента: Spin — градусы в секунду по осям, Bob — качание вверх-вниз (студы), Sway — покачивание (градусы)
local function motion(instance: Instance, spin: Vector3?, bob: number?, sway: number?)
	if spin then
		instance:SetAttribute("Spin", spin)
	end
	if bob then
		instance:SetAttribute("Bob", bob)
	end
	if sway then
		instance:SetAttribute("Sway", sway)
	end
	instance:SetAttribute("Phase", random:NextNumber(0, math.pi * 2))
	CollectionService:AddTag(instance, "Motion")
end

-- Модель-ассет (сгенерирована в Studio), увеличенная до высоты height
local function prop(assetId: number, height: number): BasePart?
	if assetId == 0 then
		return nil
	end
	local source = templates[assetId]
	if not source then
		local ok, container = pcall(InsertService.LoadAsset, InsertService, assetId)
		if not ok then
			warn(`Не загрузилась деталь мира {assetId}: {container}`)
			return nil
		end
		source = container:FindFirstChildWhichIsA("BasePart", true)
		if not source then
			return nil
		end
		source.Parent = nil
		templates[assetId] = source
		container:Destroy()
	end
	local copy = source:Clone()
	copy.Size = source.Size * (height / source.Size.Y)
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	return copy
end

local function buildings(map: Instance): { BasePart }
	local list = {}
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == "Building" then
			local body = descendant:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				table.insert(list, body)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Size.Y > b.Size.Y
	end)
	return list
end

local function setGround(map: Instance, props: { [string]: any })
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Ground" then
			for key, value in props do
				(descendant :: any)[key] = value
			end
		end
	end
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

---------------------------------------------------------------- Неоновый город

-- Прожектор на крыше: луч из основания, клиент вращает его вокруг вертикали
local function searchlight(parent: Instance, base: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Searchlight"
	local root = part({ Name = "Base", Size = Vector3.new(1.6, 1, 1.6), Position = base, Color = Color3.fromRGB(30, 30, 36), Material = Enum.Material.Metal, Parent = model })
	local length = 160
	local tilt = CFrame.new(base) * CFrame.Angles(math.rad(random:NextNumber(18, 32)), 0, 0)
	part({
		Name = "Beam",
		Size = Vector3.new(2.2, length, 2.2),
		CFrame = tilt * CFrame.new(0, length / 2, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.86,
		Parent = model,
	})
	model.PrimaryPart = root
	model.Parent = parent
	motion(model, Vector3.new(0, random:NextNumber(14, 26) * (if random:NextNumber() < 0.5 then -1 else 1), 0))
end

local function neon(map: Instance, folder: Folder)
	Workspace:SetAttribute("Weather", "Rain")
	setGround(map, { Reflectance = 0.22 }) -- мокрый асфальт
	local colors = { Color3.fromRGB(0, 255, 220), Color3.fromRGB(255, 40, 200), Color3.fromRGB(140, 120, 255) }
	for i, body in buildings(map) do
		if i > 8 then
			break
		end
		searchlight(folder, body.Position + Vector3.new(0, body.Size.Y / 2 + 0.5, 0), colors[(i % #colors) + 1])
	end
end

---------------------------------------------------------------- Зеркальный город

local function mirror(map: Instance, folder: Folder)
	Workspace:SetAttribute("Lightning", Color3.fromRGB(255, 60, 70))
	Workspace:SetAttribute("Weather", "Rain") -- ночной дождь, как в Неоновом, но под красными молниями
	for _ = 1, 34 do
		local size = random:NextNumber(3, 13)
		local shard = Instance.new("WedgePart")
		shard.Name = "Shard"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.Size = Vector3.new(0.3, size, size * random:NextNumber(0.4, 0.9))
		shard.Material = Enum.Material.Glass
		shard.Reflectance = 0.85
		shard.Transparency = 0.15
		shard.Color = Color3.fromRGB(255, 180, 190)
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(20, 170)
		shard.CFrame = CFrame.new(math.cos(angle) * distance, random:NextNumber(45, 140), math.sin(angle) * distance)
			* CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), random:NextNumber(0, 6))
		shard.Parent = folder
		motion(shard, Vector3.new(random:NextNumber(-20, 20), random:NextNumber(-30, 30), random:NextNumber(-20, 20)), random:NextNumber(1, 4))
	end
end

---------------------------------------------------------------- Храм ветра

local function temple(map: Instance, folder: Folder)
	Workspace:SetAttribute("Weather", "Lanterns")
	-- ворота у площади, с четырёх сторон
	for _, side in { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) } do
		local gate = prop(Config.WorldProps.Torii and Config.WorldProps.Torii.Asset or 0, 15)
		if gate then
			local position = side * 21 + Vector3.new(0, GROUND_Y + gate.Size.Y / 2, 0)
			gate.CFrame = CFrame.lookAt(position, position + side)
			gate.Name = "Torii"
			gate.Parent = folder
		end
	end
	-- каменные фонари вдоль улиц
	local lanternAsset = Config.WorldProps.StoneLantern and Config.WorldProps.StoneLantern.Asset or 0
	for _, street in STREETS do
		for along = -110, 110, 22 do
			for _, curb in { -6.5, 6.5 } do
				local nearCross = false
				for _, other in STREETS do
					if math.abs(along - other) < 11 then
						nearCross = true
					end
				end
				if not nearCross and random:NextNumber() < 0.7 then
					local x, z = street + curb, along
					if random:NextNumber() < 0.5 then
						x, z = along, street + curb
					end
					local lantern = prop(lanternAsset, 5)
					if lantern then
						lantern.CFrame = CFrame.new(x, GROUND_Y + lantern.Size.Y / 2, z) * CFrame.Angles(0, random:NextNumber(0, 6), 0)
						lantern.Name = "StoneLantern"
						lantern.Parent = folder
						local light = Instance.new("PointLight")
						light.Color = Color3.fromRGB(255, 150, 70)
						light.Range = 12
						light.Brightness = 1.2
						light.Parent = lantern
					end
				end
			end
		end
	end
	-- туман, стелющийся по улицам
	for _, street in STREETS do
		for _, axis in { "X", "Z" } do
			local mist = part({
				Name = "Mist",
				Size = if axis == "X" then Vector3.new(240, 1, 12) else Vector3.new(12, 1, 240),
				Position = if axis == "X" then Vector3.new(0, GROUND_Y + 1, street) else Vector3.new(street, GROUND_Y + 1, 0),
				Transparency = 1,
				Parent = folder,
			})
			emitter(mist, {
				Color = ColorSequence.new(Color3.fromRGB(255, 225, 215)),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(8, 12),
				Rate = 6,
				Speed = NumberRange.new(0.3, 1),
				SpreadAngle = Vector2.new(180, 10),
				LightInfluence = 1,
				Shape = Enum.ParticleEmitterShape.Box,
			})
		end
	end
end

---------------------------------------------------------------- Кристалл семи миров

local function crystal(_map: Instance, folder: Folder)
	Workspace:SetAttribute("Weather", "Sparks")
	-- парящие острова
	local islandAsset = Config.WorldProps.CrystalIsland and Config.WorldProps.CrystalIsland.Asset or 0
	for i = 1, 7 do
		local island = prop(islandAsset, random:NextNumber(18, 30))
		if island then
			local angle = (i / 7) * math.pi * 2 + random:NextNumber(-0.2, 0.2)
			local distance = random:NextNumber(160, 210)
			island.CFrame = CFrame.new(math.cos(angle) * distance, random:NextNumber(60, 120), math.sin(angle) * distance)
				* CFrame.Angles(0, random:NextNumber(0, 6), 0)
			island.Name = "Island"
			island.Parent = folder
			motion(island, Vector3.new(0, random:NextNumber(-4, 4), 0), random:NextNumber(3, 6))
		end
	end
	-- северное сияние: полотна из светящихся лент, клиент их покачивает
	local auroraColors = { Color3.fromRGB(120, 255, 200), Color3.fromRGB(150, 120, 255), Color3.fromRGB(255, 120, 220) }
	for curtain = 1, 4 do
		local model = Instance.new("Model")
		model.Name = "Aurora"
		local start = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(230, 290)
		local color = auroraColors[(curtain % #auroraColors) + 1]
		local root: BasePart? = nil
		for i = 0, 13 do
			local angle = start + i * 0.07
			local height = 50 + math.sin(i * 0.7) * 12
			local ribbon = part({
				Name = "Ribbon",
				Size = Vector3.new(0.4, height, radius * 0.075),
				CFrame = CFrame.new(math.cos(angle) * radius, 170 + math.sin(i * 0.9) * 8, math.sin(angle) * radius)
					* CFrame.Angles(0, -angle, 0),
				Color = color,
				Material = Enum.Material.Neon,
				Transparency = 0.84 + (i % 3) * 0.04, -- полупрозрачные ленты, сквозь них видны звёзды
				Parent = model,
			})
			root = root or ribbon
		end
		model.PrimaryPart = root
		model.Parent = folder
		motion(model, nil, 6, 3)
	end
end

---------------------------------------------------------------- Стёртый мир

local function erased(map: Instance, folder: Folder)
	Workspace:SetAttribute("Weather", "Paper")
	local ink = Color3.fromRGB(30, 30, 34)
	-- недорисованные дома: только карандашные рёбра
	for _ = 1, 16 do
		local size = Vector3.new(random:NextNumber(12, 22), random:NextNumber(20, 60), random:NextNumber(12, 22))
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(140, 230)
		local floating = random:NextNumber() < 0.5
		local frame = part({
			Name = "Sketch",
			Size = size,
			CFrame = CFrame.new(math.cos(angle) * distance, (if floating then random:NextNumber(40, 110) else GROUND_Y) + size.Y / 2, math.sin(angle) * distance)
				* CFrame.Angles(if floating then random:NextNumber(-0.4, 0.4) else 0, random:NextNumber(0, 6), 0),
			Transparency = 1,
			Parent = folder,
		})
		local box = Instance.new("SelectionBox")
		box.Adornee = frame
		box.Color3 = ink
		box.LineThickness = 0.12
		box.SurfaceTransparency = 1
		box.Parent = frame
		-- этажи — горизонтальные штрихи
		for floor = 1, math.floor(size.Y / 8) do
			part({
				Name = "Hatch",
				Size = Vector3.new(size.X, 0.08, 0.08),
				CFrame = frame.CFrame * CFrame.new(0, -size.Y / 2 + floor * 8, -size.Z / 2),
				Color = ink,
				Parent = folder,
			})
		end
		if floating then
			motion(frame, Vector3.new(0, random:NextNumber(-3, 3), 0), random:NextNumber(2, 4))
		end
	end
	-- длинные линии разметки через всё небо, как у художника
	for _ = 1, 12 do
		local length = random:NextNumber(300, 520)
		part({
			Name = "GuideLine",
			Size = Vector3.new(0.12, 0.12, length),
			CFrame = CFrame.new(random:NextNumber(-150, 150), random:NextNumber(60, 200), random:NextNumber(-150, 150))
				* CFrame.Angles(random:NextNumber(-0.25, 0.25), random:NextNumber(0, 6), 0),
			Color = ink,
			Transparency = 0.35,
			Parent = folder,
		})
	end
	-- дыры-стирания на улицах: белое свечение, из них выдувает пыль
	for _ = 1, 7 do
		local street = STREETS[random:NextInteger(1, #STREETS)]
		local along = random:NextNumber(-100, 100)
		local x, z = street, along
		if random:NextNumber() < 0.5 then
			x, z = along, street
		end
		local hole = part({
			Name = "EraseHole",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, random:NextNumber(6, 11), random:NextNumber(6, 11)),
			CFrame = CFrame.new(x, GROUND_Y + 0.06, z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		emitter(hole, {
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			Size = NumberSequence.new(0.3, 0),
			Lifetime = NumberRange.new(1.5, 3),
			Rate = 14,
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Right,
			LightEmission = 0.5,
		})
	end
	setGround(map, { Material = Enum.Material.Plaster })
end

---------------------------------------------------------------- Монолит

local function monolith(_map: Instance, folder: Folder)
	Workspace:SetAttribute("Lightning", Color3.fromRGB(255, 40, 50))
	Workspace:SetAttribute("Weather", "Ash")
	-- чёрные плиты вокруг города
	for i = 1, 9 do
		local angle = (i / 9) * math.pi * 2
		local distance = random:NextNumber(170, 230)
		local slab = part({
			Name = "Slab",
			Size = Vector3.new(random:NextNumber(10, 18), random:NextNumber(50, 110), random:NextNumber(2, 4)),
			CFrame = CFrame.new(math.cos(angle) * distance, random:NextNumber(50, 110), math.sin(angle) * distance)
				* CFrame.Angles(random:NextNumber(-0.2, 0.2), -angle, random:NextNumber(-0.2, 0.2)),
			Color = Color3.fromRGB(6, 6, 8),
			Material = Enum.Material.Glass,
			Reflectance = 0.5,
			Parent = folder,
		})
		-- тонкая белая полоса по ребру
		part({
			Name = "Edge",
			Size = Vector3.new(0.15, slab.Size.Y, slab.Size.Z + 0.05),
			CFrame = slab.CFrame * CFrame.new(slab.Size.X / 2, 0, 0),
			Color = Color3.fromRGB(240, 240, 255),
			Material = Enum.Material.Neon,
			Parent = slab,
		})
		motion(slab, Vector3.new(0, random:NextNumber(-2, 2), 0), random:NextNumber(3, 7))
	end
	-- красный луч из глаза шарит по городу: модель вращается вокруг вертикали над центром
	local eye = Vector3.new(0, 210, -300)
	local model = Instance.new("Model")
	model.Name = "EyeScan"
	local pivot = part({ Name = "Pivot", Size = Vector3.one, Position = Vector3.new(0, 0, 0), Transparency = 1, Parent = model })
	local target = Vector3.new(60, GROUND_Y, 0)
	local length = (target - eye).Magnitude
	part({
		Name = "Ray",
		Size = Vector3.new(1.2, 1.2, length),
		CFrame = CFrame.lookAt((eye + target) / 2, target),
		Color = Color3.fromRGB(255, 30, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Parent = model,
	})
	local spot = part({
		Name = "Spot",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 14, 14),
		CFrame = CFrame.new(target + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 30, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 40, 50)
	light.Range = 30
	light.Brightness = 3
	light.Parent = spot
	model.PrimaryPart = pivot
	model.Parent = folder
	motion(model, Vector3.new(0, 18, 0))
end

---------------------------------------------------------------- Ядро

local function core(map: Instance, folder: Folder)
	Workspace:SetAttribute("Weather", "Sparks")
	Workspace:SetAttribute("Lightning", Color3.fromRGB(160, 220, 255))
	local blue = Color3.fromRGB(120, 200, 255)
	local white = Color3.fromRGB(235, 245, 255)
	local center = Vector3.new(0, 115, 0)

	-- само ядро: светящаяся сфера в тёмной оболочке и три вращающихся кольца
	local heart = part({ Name = "CoreHeart", Shape = Enum.PartType.Ball, Size = Vector3.one * 26, Position = center, Color = white, Material = Enum.Material.Neon, Parent = folder })
	local shell = part({
		Name = "CoreShell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 34,
		Position = center,
		Color = Color3.fromRGB(20, 40, 70),
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		Parent = folder,
	})
	motion(shell, Vector3.new(0, 25, 0))
	local glow = Instance.new("PointLight")
	glow.Color = blue
	glow.Range = 60
	glow.Brightness = 4
	glow.Parent = heart
	heart:SetAttribute("Pulse", true)
	motion(heart, nil, 2)
	for ring = 1, 3 do
		local model = Instance.new("Model")
		model.Name = "CoreRing"
		local radius = 26 + ring * 9
		local tilt = CFrame.new(center) * CFrame.Angles(math.rad(ring * 50), math.rad(ring * 35), 0)
		local hub = part({ Name = "Hub", Size = Vector3.one, CFrame = tilt, Transparency = 1, Parent = model })
		for i = 1, 36 do
			local angle = (i / 36) * math.pi * 2
			part({
				Name = "Segment",
				Size = Vector3.new(1, 1, 2 * math.pi * radius / 36 * (if i % 4 == 0 then 0.4 else 0.95)),
				CFrame = tilt * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0),
				Color = if ring == 2 then white else blue,
				Material = Enum.Material.Neon,
				Parent = model,
			})
		end
		model.PrimaryPart = hub
		model.Parent = folder
		motion(model, Vector3.new(ring * 6, (if ring % 2 == 0 then -1 else 1) * (20 + ring * 8), 0))
	end

	-- лучи от ядра к самым высоким башням
	for i, body in buildings(map) do
		if i > 6 then
			break
		end
		local top = body.Position + Vector3.new(0, body.Size.Y / 2, 0)
		local length = (top - center).Magnitude
		local beam = part({
			Name = "CoreBeam",
			Size = Vector3.new(0.5, 0.5, length),
			CFrame = CFrame.lookAt((top + center) / 2, top),
			Color = blue,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			Parent = folder,
		})
		beam:SetAttribute("Pulse", true)
		motion(beam)
	end

	-- светящиеся дорожки схем по улицам: прямые с изломами
	for _ = 1, 26 do
		local street = STREETS[random:NextInteger(1, #STREETS)]
		local offset = random:NextNumber(-6, 6)
		local from = random:NextNumber(-120, 80)
		local length = random:NextNumber(20, 50)
		local alongX = random:NextNumber() < 0.5
		local mid = from + length / 2
		part({
			Name = "Trace",
			Size = if alongX then Vector3.new(length, 0.06, 0.35) else Vector3.new(0.35, 0.06, length),
			Position = if alongX then Vector3.new(mid, GROUND_Y + 0.04, street + offset) else Vector3.new(street + offset, GROUND_Y + 0.04, mid),
			Color = if random:NextNumber() < 0.7 then blue else white,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		-- «контакт» на конце дорожки
		local tip = from + length
		part({
			Name = "Pad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 1.2, 1.2),
			CFrame = CFrame.new(if alongX then Vector3.new(tip, GROUND_Y + 0.05, street + offset) else Vector3.new(street + offset, GROUND_Y + 0.05, tip))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = white,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
	end

	-- столбы света на перекрёстках, по ним вверх текут данные
	for _, x in STREETS do
		for _, z in STREETS do
			if random:NextNumber() < 0.6 then
				local pillar = part({
					Name = "LightPillar",
					Size = Vector3.new(2.5, 220, 2.5),
					Position = Vector3.new(x, GROUND_Y + 110, z),
					Color = blue,
					Material = Enum.Material.Neon,
					Transparency = 0.82,
					Parent = folder,
				})
				emitter(pillar, {
					Color = ColorSequence.new(white, blue),
					LightEmission = 1,
					Size = NumberSequence.new(0.35),
					Lifetime = NumberRange.new(3, 5),
					Rate = 8,
					Speed = NumberRange.new(0, 0),
					Acceleration = Vector3.new(0, 25, 0),
					Shape = Enum.ParticleEmitterShape.Box,
				})
			end
		end
	end
	setGround(map, { Color = Color3.fromRGB(10, 14, 22), Material = Enum.Material.Glass, Reflectance = 0.3 })
end

local BUILDERS: { [string]: (Instance, Folder) -> () } = {
	Neon = neon,
	Mirror = mirror,
	Temple = temple,
	Crystal = crystal,
	Erased = erased,
	Monolith = monolith,
	Core = core,
}

function WorldDetails.apply(worldId: string, map: Instance)
	Workspace:SetAttribute("Weather", nil)
	Workspace:SetAttribute("Lightning", nil)
	local build = BUILDERS[worldId]
	if not build then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "WorldDetails"
	build(map, folder)
	folder.Parent = map
end

return WorldDetails
