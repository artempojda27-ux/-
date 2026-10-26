--!strict
-- Временный Штаб из простых блоков. Если в Workspace уже есть модель
-- «LobbyMap» с папкой «Portals», берём порталы оттуда и ничего не строим —
-- так позже можно заменить карту на нарисованную в Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local CYAN = Color3.fromRGB(0, 255, 200)
local DARK = Color3.fromRGB(18, 22, 28)

local PORTAL_COUNT = 3
local FLOOR_SIZE = 120
local TRACK_OUTER = 100 -- внешний край трассы для машин

local LobbyMap = {}

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

local function addLabel(pad: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 70)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = CYAN
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui

	gui.Parent = pad
end

local function build(): Model
	local map = Instance.new("Model")
	map.Name = "LobbyMap"

	-- Пол на высоте 1, чтобы не сливаться со стандартным Baseplate
	part({
		Name = "Floor",
		Size = Vector3.new(FLOOR_SIZE, 1, FLOOR_SIZE),
		Position = Vector3.new(0, 0.5, 0),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
		Parent = map,
	})

	-- Светящиеся края
	local half = FLOOR_SIZE / 2
	for _, side in { { 0, -half, FLOOR_SIZE, 1 }, { 0, half, FLOOR_SIZE, 1 }, { -half, 0, 1, FLOOR_SIZE }, { half, 0, 1, FLOOR_SIZE } } do
		part({
			Name = "Edge",
			Size = Vector3.new(side[3], 0.3, side[4]),
			Position = Vector3.new(side[1], 1.15, side[2]),
			Color = CYAN,
			Material = Enum.Material.Neon,
			Parent = map,
		})
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 1.5, 30)
	spawn.Color = DARK
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Parent = map

	-- Табличка с названием
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(40, 10, 1),
		Position = Vector3.new(0, 12, -55),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
		Parent = map,
	})
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Back
	surface.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = CYAN
	title.Text = "ИСКАЖЕНИЕ"
	title.Parent = surface

	-- Порталы отряда
	local portals = Instance.new("Folder")
	portals.Name = "Portals"
	portals.Parent = map
	for i = 1, PORTAL_COUNT do
		local x = (i - (PORTAL_COUNT + 1) / 2) * 30
		local pad = part({
			Name = `Portal{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 14, 14),
			CFrame = CFrame.new(x, 1.3, -30) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CYAN,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CanCollide = false,
			Parent = portals,
		})
		addLabel(pad, `ПОРТАЛ {i}`)
	end

	-- Трасса для машин вокруг площадки: кольцо дороги со стенами снаружи
	local track = Instance.new("Folder")
	track.Name = "Track"
	track.Parent = map
	local inner, outer = half, TRACK_OUTER
	local width = outer - inner
	for _, side in { -1, 1 } do
		-- полосы вдоль X (сверху и снизу) и вдоль Z (слева и справа)
		part({
			Name = "Road",
			Size = Vector3.new(outer * 2, 1, width),
			Position = Vector3.new(0, 0.5, side * (inner + width / 2)),
			Color = Color3.fromRGB(20, 20, 28),
			Material = Enum.Material.Asphalt,
			Parent = track,
		})
		part({
			Name = "Road",
			Size = Vector3.new(width, 1, inner * 2),
			Position = Vector3.new(side * (inner + width / 2), 0.5, 0),
			Color = Color3.fromRGB(20, 20, 28),
			Material = Enum.Material.Asphalt,
			Parent = track,
		})
		part({
			Name = "Wall",
			Size = Vector3.new(outer * 2 + 2, 6, 2),
			Position = Vector3.new(0, 3, side * (outer + 1)),
			Color = Color3.fromRGB(30, 32, 44),
			Parent = track,
		})
		part({
			Name = "Wall",
			Size = Vector3.new(2, 6, outer * 2 + 2),
			Position = Vector3.new(side * (outer + 1), 3, 0),
			Color = Color3.fromRGB(30, 32, 44),
			Parent = track,
		})
		-- невидимая преграда над стенами: после реактивного прыжка машина не улетит за карту
		part({
			Name = "Barrier",
			Size = Vector3.new(outer * 2 + 2, 80, 2),
			Position = Vector3.new(0, 46, side * (outer + 1)),
			Transparency = 1,
			Parent = track,
		})
		part({
			Name = "Barrier",
			Size = Vector3.new(2, 80, outer * 2 + 2),
			Position = Vector3.new(side * (outer + 1), 46, 0),
			Transparency = 1,
			Parent = track,
		})
		-- неоновые полосы по верху стен
		part({
			Name = "WallGlow",
			Size = Vector3.new(outer * 2 + 2, 0.3, 2.2),
			Position = Vector3.new(0, 6.15, side * (outer + 1)),
			Color = if side > 0 then CYAN else Color3.fromRGB(255, 40, 120),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = track,
		})
		part({
			Name = "WallGlow",
			Size = Vector3.new(2.2, 0.3, outer * 2 + 2),
			Position = Vector3.new(side * (outer + 1), 6.15, 0),
			Color = if side > 0 then Color3.fromRGB(255, 40, 120) else CYAN,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = track,
		})
	end

	-- Автосалон: подиумы с машинами у трассы. Машина появляется на трассе прямо за подиумом
	local garage = Instance.new("Folder")
	garage.Name = "Garage"
	garage.Parent = map
	local kinds = {}
	for _, kind in Config.Vehicles do
		table.insert(kinds, kind)
	end
	table.sort(kinds, function(a, b)
		return a.Order < b.Order
	end)
	for i, kind in kinds do
		local x = (i - (#kinds + 1) / 2) * 24
		local pad = part({
			Name = `Pad_{kind.Id}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 18, 18),
			CFrame = CFrame.new(x, 1.2, 47) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(24, 26, 36),
			Material = Enum.Material.SmoothPlastic,
			Parent = garage,
		})
		pad:SetAttribute("VehicleKind", kind.Id)
		part({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 18.6, 18.6),
			CFrame = CFrame.new(x, 1.15, 47) * CFrame.Angles(0, 0, math.rad(90)),
			Color = kind.GlowColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = garage,
		})
		addLabel(pad, kind.Name)
		local spot = part({
			Name = `Spot_{kind.Id}`,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.lookAt(Vector3.new(x, 4, inner + width / 2), Vector3.new(x + 1, 4, inner + width / 2)),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = garage,
		})
		spot:SetAttribute("Note", "Здесь появляется вызванная машина")
	end

	map.Parent = Workspace
	return map
end

export type GarageSlot = {
	Pad: BasePart,
	Kind: string,
	Spot: CFrame, -- где появляется вызванная машина
}

-- Подиумы автосалона: какая машина и где она появляется
function LobbyMap.garage(): { GarageSlot }
	local map = Workspace:FindFirstChild("LobbyMap")
	local folder = map and map:FindFirstChild("Garage")
	local slots = {}
	if not folder then
		return slots
	end
	for _, pad in folder:GetChildren() do
		local kind = pad:GetAttribute("VehicleKind")
		local spot = folder:FindFirstChild(`Spot_{kind}`)
		if pad:IsA("BasePart") and typeof(kind) == "string" and spot and spot:IsA("BasePart") then
			table.insert(slots, { Pad = pad, Kind = kind, Spot = spot.CFrame })
		end
	end
	return slots
end

-- Возвращает площадки порталов по порядку
function LobbyMap.setup(): { BasePart }
	local map = Workspace:FindFirstChild("LobbyMap") or build()
	local folder = map:FindFirstChild("Portals")
	assert(folder, "В LobbyMap нет папки Portals")

	local pads = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(pads, child)
		end
	end
	table.sort(pads, function(a, b)
		return a.Name < b.Name
	end)
	return pads
end

return LobbyMap
