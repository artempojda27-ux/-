--!strict
-- Внешний вид Штаба поверх простой площадки LobbyMap: скрытый сервер на краю Сети.
--   Вокруг — кольцо детальных небоскрёбов (наборы Neon и Core) и летающий транспорт.
--   В центре — голостол, над ним вращается Кристалл семи миров и семь малых кристаллов по цветам миров.
--   У стола стоит Командор Вега — по кнопке «Поговорить» рассказывает историю (реплики — Config.Commander,
--     показывает клиент Commander.client.luau).
--   Над порталами — арки, из площадок поднимаются искры; название игры — мигающая голограмма.
-- Двигает всё клиент (WorldMotion, Ambience — общие с Миссией).

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CityLife = require(ServerScriptService.Common.CityLife)

local CYAN = Color3.fromRGB(0, 255, 200)
local FLOOR_Y = 1
-- Цвета семи миров для малых кристаллов (как в «Кристалле семи миров»)
local SEVEN_WORLDS = {
	Color3.fromRGB(0, 255, 200),
	Color3.fromRGB(255, 50, 70),
	Color3.fromRGB(235, 185, 70),
	Color3.fromRGB(190, 150, 255),
	Color3.fromRGB(245, 245, 250),
	Color3.fromRGB(20, 20, 24),
	Color3.fromRGB(150, 220, 255),
}

local LobbyLook = {}

local random = Random.new(777)
local templates: { [number]: BasePart } = {}

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

-- Копия модели-ассета высотой height (или с длинной стороной length, если height не задан)
local function prop(assetId: number, height: number?, length: number?): BasePart?
	if assetId == 0 then
		return nil
	end
	local source = templates[assetId]
	if not source then
		local ok, container = pcall(InsertService.LoadAsset, InsertService, assetId)
		if not ok then
			warn(`Не загрузилась модель Штаба {assetId}: {container}`)
			return nil
		end
		local found = container:FindFirstChildWhichIsA("BasePart", true)
		container:Destroy()
		if not found then
			return nil
		end
		found.Parent = nil
		templates[assetId] = found
		source = found
	end
	local copy = source:Clone()
	local scale = if height then height / source.Size.Y else (length or 1) / math.max(source.Size.X, source.Size.Y, source.Size.Z)
	copy.Size = source.Size * scale
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	return copy
end

local function motion(instance: Instance, spin: Vector3?, bob: number?)
	if spin then
		instance:SetAttribute("Spin", spin)
	end
	if bob then
		instance:SetAttribute("Bob", bob)
	end
	instance:SetAttribute("Phase", random:NextNumber(0, math.pi * 2))
	CollectionService:AddTag(instance, "Motion")
end

-- Кольцо небоскрёбов за трассой: Штаб стоит посреди ночного мегаполиса Сети
local function skyline(folder: Folder)
	local sets = {}
	for _, id in Config.BuildingSets.Neon or {} do
		table.insert(sets, id)
	end
	for _, id in Config.BuildingSets.Core or {} do
		table.insert(sets, id)
	end
	if #sets == 0 then
		return
	end
	local count = 30
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + random:NextNumber(-0.06, 0.06)
		local distance = random:NextNumber(150, 230)
		local height = random:NextNumber(70, 150)
		local tower = prop(sets[random:NextInteger(1, #sets)], height)
		if tower then
			tower.CFrame = CFrame.new(math.cos(angle) * distance, FLOOR_Y + height / 2 - 2, math.sin(angle) * distance)
				* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
			tower.Name = "Tower"
			tower.Parent = folder
			-- маяк на крыше
			if random:NextNumber() < 0.5 then
				part({
					Name = "Beacon",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 2,
					Position = tower.Position + Vector3.new(0, height / 2 + 1, 0),
					Color = if random:NextNumber() < 0.5 then Color3.fromRGB(255, 40, 80) else CYAN,
					Parent = folder,
				})
			end
		end
	end
end

-- Голостол и Кристалл семи миров над ним
local function holoTable(folder: Folder, center: Vector3)
	local table_ = prop(Config.LobbyProps.HoloTable, nil, 14)
	local top = center.Y
	if table_ then
		table_.CFrame = CFrame.new(center + Vector3.new(0, table_.Size.Y / 2, 0))
		table_.CanCollide = true
		table_.Name = "HoloTable"
		table_.Parent = folder
		top = center.Y + table_.Size.Y
	end
	-- луч проектора и сам Кристалл
	part({
		Name = "ProjectorBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 1.2, 1.2),
		CFrame = CFrame.new(center.X, top + 4.5, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = CYAN,
		Transparency = 0.75,
		Parent = folder,
	})
	local crystalSpec = Config.WorldProps.BigCrystal
	local crystal = crystalSpec and crystalSpec.Asset and prop(crystalSpec.Asset, nil, 6)
	local crystalCenter = Vector3.new(center.X, top + 7, center.Z)
	if crystal then
		crystal.CFrame = CFrame.new(crystalCenter)
		crystal.Transparency = 0.25
		crystal.Name = "HoloCrystal"
		crystal.Parent = folder
		motion(crystal, Vector3.new(0, 25, 0), 0.4)
	end
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = 22
	light.Brightness = 2.5
	light.Parent = folder:FindFirstChild("ProjectorBeam") :: Instance
	-- семь малых кристаллов — по одному на мир — кружат вокруг
	local model = Instance.new("Model")
	model.Name = "SevenWorlds"
	local hub = part({ Name = "Hub", Size = Vector3.one * 0.2, Position = crystalCenter, Transparency = 1, Parent = model })
	for i, color in SEVEN_WORLDS do
		local angle = (i / #SEVEN_WORLDS) * math.pi * 2
		part({
			Name = "WorldGem",
			Size = Vector3.new(0.6, 1.2, 0.6),
			CFrame = CFrame.new(crystalCenter + Vector3.new(math.cos(angle) * 5, math.sin(angle * 2) * 0.6, math.sin(angle) * 5))
				* CFrame.Angles(0, angle, math.rad(45)),
			Color = color,
			Material = if i == 6 then Enum.Material.Glass else Enum.Material.Neon,
			Parent = model,
		})
	end
	model.PrimaryPart = hub
	model.Parent = folder
	motion(model, Vector3.new(0, -18, 0))
end

-- Командор Вега у стола: модель-ассет (или простая фигура) и кнопка «Поговорить»
local function commander(folder: Folder, position: Vector3, look: Vector3)
	local body = prop(Config.LobbyProps.Commander, 6.5)
	local holder: BasePart
	if body then
		body.CFrame = CFrame.lookAt(position + Vector3.new(0, body.Size.Y / 2, 0), Vector3.new(look.X, position.Y + body.Size.Y / 2, look.Z))
		body.CanCollide = true
		body.CanQuery = true
		body.Name = "Commander"
		body.Parent = folder
		holder = body
	else
		holder = part({
			Name = "Commander",
			Size = Vector3.new(2, 6, 1.2),
			CFrame = CFrame.lookAt(position + Vector3.new(0, 3, 0), Vector3.new(look.X, position.Y + 3, look.Z)),
			Color = Color3.fromRGB(30, 34, 44),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			Parent = folder,
		})
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Talk"
	prompt.ActionText = "Поговорить"
	prompt.ObjectText = Config.Commander.Name
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = holder
	CollectionService:AddTag(holder, "Commander")
	-- имя над головой
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(200, 40)
	tag.StudsOffset = Vector3.new(0, holder.Size.Y / 2 + 1, 0)
	tag.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = CYAN
	label.TextStrokeTransparency = 0.4
	label.Text = Config.Commander.Name
	label.Parent = tag
	tag.Parent = holder
end

-- Арки над порталами и искры, поднимающиеся с площадок
local function portalGates(map: Instance, folder: Folder)
	local portals = map:FindFirstChild("Portals")
	if not portals then
		return
	end
	for _, pad in portals:GetChildren() do
		if not pad:IsA("BasePart") then
			continue
		end
		local arch = prop(Config.LobbyProps.PortalArch, 16)
		if arch then
			arch.CFrame = CFrame.new(pad.Position.X, FLOOR_Y + arch.Size.Y / 2, pad.Position.Z)
			arch.Name = "PortalArch"
			arch.Parent = folder
		end
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(CYAN, Color3.fromRGB(255, 255, 255))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.25, 0)
		sparks.Lifetime = NumberRange.new(1.5, 2.5)
		sparks.Rate = 18
		sparks.Speed = NumberRange.new(3, 6)
		sparks.SpreadAngle = Vector2.new(15, 15)
		sparks.EmissionDirection = Enum.NormalId.Right -- площадка — повёрнутый цилиндр, его «право» смотрит вверх
		sparks.Parent = pad
	end
end

-- Название игры над площадкой — мигающая голограмма вместо тёмной таблички
local function titleHolo(map: Instance, folder: Folder)
	local sign = map:FindFirstChild("Sign")
	if sign and sign:IsA("BasePart") then
		sign.Transparency = 1
		for _, child in sign:GetChildren() do
			child:Destroy()
		end
		local position = sign.Position + Vector3.new(0, 10, 0)
		CityLife.holo(folder, CFrame.lookAt(position, position + Vector3.new(0, 0, 1)), "ИСКАЖЕНИЕ", CYAN, 3)
	end
end

-- Пол площадки: тонкая светящаяся сетка и круг под голостолом, как на палубе корабля
local function floorGrid(folder: Folder)
	for offset = -54, 54, 12 do
		for _, alongX in { true, false } do
			part({
				Name = "Grid",
				Size = if alongX then Vector3.new(118, 0.04, 0.18) else Vector3.new(0.18, 0.04, 118),
				Position = if alongX then Vector3.new(0, FLOOR_Y + 0.02, offset) else Vector3.new(offset, FLOOR_Y + 0.02, 0),
				Color = CYAN,
				Transparency = 0.7,
				Parent = folder,
			})
		end
	end
	for _, radius in { 11, 14 } do
		part({
			Name = "TableRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, radius * 2, radius * 2),
			CFrame = CFrame.new(0, FLOOR_Y + 0.03 + radius * 0.001, 2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CYAN,
			Transparency = if radius == 11 then 0.94 else 0.75,
			Parent = folder,
		})
	end
end

function LobbyLook.apply(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "LobbyLook"
	floorGrid(folder)
	skyline(folder)
	holoTable(folder, Vector3.new(0, FLOOR_Y, 2))
	commander(folder, Vector3.new(11, FLOOR_Y, 6), Vector3.new(0, FLOOR_Y, 30))
	portalGates(map, folder)
	titleHolo(map, folder)
	CityLife.traffic(folder, 16, 120, 220, 40, 110)
	folder.Parent = map
	Workspace:SetAttribute("WorldAccent", CYAN) -- пыль данных в воздухе (Ambience.client)
end

return LobbyLook
