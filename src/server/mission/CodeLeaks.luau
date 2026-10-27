--!strict
-- «Код утекает»: на стенах домов — чёрные рваные трещины, по ним стекают светящиеся символы,
-- а снизу капают пиксели. Так видно, что мир — симуляция, и Искажение её ломает.
-- Сервер строит трещины (их видят все), символы анимирует клиент (CodeLeaks.client.luau) по тегу "CodeLeak".
-- Трещины ставятся на поверхность детальной модели дома: точку находим лучом снаружи.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- Цвета символов по мирам: первый — «голова» потока, второй — хвост
local PALETTE: { [string]: { Color3 } } = {
	Neon = { Color3.fromRGB(0, 255, 220), Color3.fromRGB(255, 40, 200) },
	Mirror = { Color3.fromRGB(255, 70, 80), Color3.fromRGB(255, 150, 60) },
	Temple = { Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 120, 60) },
	Crystal = { Color3.fromRGB(190, 150, 255), Color3.fromRGB(120, 230, 255) },
	Erased = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 210) },
	Monolith = { Color3.fromRGB(255, 40, 50), Color3.fromRGB(255, 255, 255) },
	Core = { Color3.fromRGB(235, 245, 255), Color3.fromRGB(120, 200, 255) },
}
local MAX_LEAKS = 22
local CRACK_COLOR = Color3.fromRGB(4, 4, 7)

local CodeLeaks = {}

local random = Random.new(777)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Трещина длиной length сверху вниз от точки top на стене с нормалью normal
local function crack(parent: Instance, top: Vector3, normal: Vector3, length: number, colors: { Color3 })
	local folder = Instance.new("Model")
	folder.Name = "Leak"
	local base = CFrame.lookAt(top + normal * 0.1, top + normal * 2) -- LookVector смотрит из стены
	-- рваные чёрные куски зигзагом
	local y = 0
	local x = 0
	while y < length do
		local piece = random:NextNumber(1.6, 3.2)
		local width = random:NextNumber(0.8, 1.4)
		local nextX = math.clamp(x + random:NextNumber(-0.6, 0.6), -0.9, 0.9)
		local tilt = math.atan2(nextX - x, piece)
		part({
			Name = "Crack",
			Size = Vector3.new(width, piece + 0.3, 0.12),
			CFrame = base * CFrame.new((x + nextX) / 2, -y - piece / 2, 0) * CFrame.Angles(0, 0, tilt),
			Color = CRACK_COLOR,
			Parent = folder,
		})
		-- отколотые крошки по краям
		if random:NextNumber() < 0.6 then
			part({
				Name = "Chip",
				Size = Vector3.new(random:NextNumber(0.15, 0.35), random:NextNumber(0.15, 0.4), 0.1),
				CFrame = base * CFrame.new(x + random:NextNumber(-1, 1), -y - random:NextNumber(0, piece), -0.02)
					* CFrame.Angles(0, 0, random:NextNumber(0, 3)),
				Color = CRACK_COLOR,
				Parent = folder,
			})
		end
		x = nextX
		y += piece
	end

	-- два потока символов: прозрачные полоски с SurfaceGui по центру трещины
	for _, column in { -0.26, 0.26 } do
		local stream = part({
			Name = "Stream",
			Size = Vector3.new(0.55, length, 0.05),
			CFrame = base * CFrame.new(column, -length / 2, -0.09), -- −Z — наружу, перед трещиной
			Transparency = 1,
			Parent = folder,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		gui.Brightness = 3
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.MaxDistance = 220
		local label = Instance.new("TextLabel")
		label.Name = "Glyphs"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Code
		label.TextSize = 22
		label.RichText = true
		label.TextColor3 = colors[2]
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.LineHeight = 1
		label.Text = ""
		label.Parent = gui
		gui.Parent = stream
		stream:SetAttribute("Rows", math.floor(length * 40 / 22))
		stream:SetAttribute("Head", colors[1])
		CollectionService:AddTag(stream, "CodeLeak")
	end

	-- снизу капают светящиеся пиксели
	local drip = part({
		Name = "Drip",
		Size = Vector3.new(0.6, 0.2, 0.2),
		CFrame = base * CFrame.new(x, -length, -0.15),
		Transparency = 1,
		Parent = folder,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(colors[1], colors[2])
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.14)
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Rate = 5
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Parent = drip
	local glow = Instance.new("PointLight")
	glow.Color = colors[1]
	glow.Range = 7
	glow.Brightness = 0.8
	glow.Parent = drip

	folder.Parent = parent
end

-- Ищет точку на видимой стене дома: луч снаружи к центру на случайной высоте
local function findWall(building: Model): (Vector3?, Vector3?, number)
	local body = building:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return nil, nil, 0
	end
	local skin = building:FindFirstChild("Skin")
	local target: BasePart = if skin and skin:IsA("BasePart") then skin else body
	if target.Transparency > 0.5 then
		return nil, nil, 0 -- стёртый дом-призрак
	end
	local size = body.Size
	local directions = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }
	local dir = directions[random:NextInteger(1, 4)]
	local height = body.Position.Y + size.Y * random:NextNumber(-0.05, 0.35)
	local reach = math.max(size.X, size.Z) * 1.5
	local origin = Vector3.new(body.Position.X, height, body.Position.Z) + dir * reach
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { target }
	local wasQuery = target.CanQuery
	target.CanQuery = true
	local hit = Workspace:Raycast(origin, -dir * reach * 1.2, params)
	target.CanQuery = wasQuery
	if not hit or math.abs(hit.Normal.Y) > 0.45 then
		return nil, nil, 0
	end
	local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
	-- длина — до земли не доходит, но заметная
	local length = math.min(height - (body.Position.Y - size.Y / 2) - 1.5, random:NextNumber(6, 11))
	return hit.Position, normal, length
end

function CodeLeaks.apply(worldId: string, map: Instance)
	local colors = PALETTE[worldId] or PALETTE.Neon
	Workspace:SetAttribute("WorldAccent", colors[1]) -- цвет пыли данных в воздухе (Ambience.client)
	local all = {}
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == "Building" then
			table.insert(all, descendant)
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "CodeLeaks"
	local placed = 0
	local tries = 0
	while placed < MAX_LEAKS and tries < MAX_LEAKS * 4 and #all > 0 do
		tries += 1
		local building = all[random:NextInteger(1, #all)]
		local top, normal, length = findWall(building)
		if top and normal and length > 4 then
			crack(folder, top, normal, length, colors)
			placed += 1
		end
	end
	folder.Parent = map
end

return CodeLeaks
