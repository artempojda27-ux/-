--!strict
-- Временный Штаб из простых блоков. Если в Workspace уже есть модель
-- «LobbyMap» с папкой «Portals», берём порталы оттуда и ничего не строим —
-- так позже можно заменить карту на нарисованную в Studio.

local Workspace = game:GetService("Workspace")

local CYAN = Color3.fromRGB(0, 255, 200)
local DARK = Color3.fromRGB(18, 22, 28)

local PORTAL_COUNT = 3
local FLOOR_SIZE = 120

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

	map.Parent = Workspace
	return map
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
