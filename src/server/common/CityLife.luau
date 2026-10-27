--!strict
-- Живой город (Неоновый и Зеркальный): над крышами летает транспорт, на домах висят голограммы.
-- Сервер только строит модели и задаёт им маршрут атрибутами; двигает и мигает клиент
-- (Ambience.client.luau), по времени сервера — у всех игроков машины в одних и тех же местах.

local CollectionService = game:GetService("CollectionService")

local CAR_COUNT = 14
local HOLO_COUNT = 10
local HOLO_TEXTS = {
	"НЕ ВЕРЬ ДВОЙНИКАМ",
	"ШТАБ ИЩЕТ КОРРЕКТОРОВ",
	"ОБНОВЛЕНИЕ СЕТИ · 99%",
	"ОШИБКА 0x00 · ПЕРЕЗАГРУЗКА",
	"ИСКАЖЕНИЕ НЕ ПРОЙДЁТ",
	"НУЛЬ СЛЕДИТ",
	"ВСЁ В ПОРЯДКЕ. НЕ СМОТРИ НАВЕРХ",
	"НЕОН-СИТИ · ГОРОД БЕЗ НОЧИ",
	"ЗАКРОЙ СБОЙ — СПАСИ СЕТЬ",
	"ДАННЫЕ ПОВРЕЖДЕНЫ",
}
local HOLO_COLORS = {
	Color3.fromRGB(0, 255, 220),
	Color3.fromRGB(255, 40, 200),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(120, 140, 255),
}

local CityLife = {}

local random = Random.new(2077)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Летающая машина: корпус, кабина, неоновое днище, фары и стоп-огни
local function car(parent: Instance, glow: Color3): Model
	local model = Instance.new("Model")
	model.Name = "SkyCar"
	local length = random:NextNumber(6, 9)
	local body = part({
		Name = "Body",
		Size = Vector3.new(3.2, 1.1, length),
		Color = Color3.fromRGB(28, 30, 40),
		Material = Enum.Material.Metal,
		Reflectance = 0.2,
		Parent = model,
	})
	part({
		Name = "Cabin",
		Size = Vector3.new(2.6, 0.9, length * 0.45),
		CFrame = body.CFrame * CFrame.new(0, 0.9, length * 0.05),
		Color = Color3.fromRGB(60, 90, 130),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Parent = model,
	})
	part({
		Name = "Underglow",
		Size = Vector3.new(2.8, 0.15, length * 0.85),
		CFrame = body.CFrame * CFrame.new(0, -0.62, 0),
		Color = glow,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Headlight",
			Size = Vector3.new(0.7, 0.3, 0.2),
			CFrame = body.CFrame * CFrame.new(side * 1.1, 0.1, -length / 2),
			Color = Color3.fromRGB(230, 240, 255),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		part({
			Name = "Taillight",
			Size = Vector3.new(0.9, 0.25, 0.2),
			CFrame = body.CFrame * CFrame.new(side * 1.0, 0.1, length / 2),
			Color = Color3.fromRGB(255, 30, 50),
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = body
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- Голограмма на стене дома: светящаяся панель с надписью, видна с обеих сторон
local function holo(parent: Instance, cf: CFrame, text: string, color: Color3, scale: number?)
	local width = math.max(10, #text * 0.75) * (scale or 1)
	local panel = part({
		Name = "Holo",
		Size = Vector3.new(width, 3.2 * (scale or 1), 0.1),
		CFrame = cf,
		Transparency = 1,
		Parent = parent,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.Brightness = 2.5
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.MaxDistance = 400
		local frame = Instance.new("Frame")
		frame.Name = "Plate"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0.82
		frame.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 3
		stroke.Parent = frame
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = text
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.04, 0)
		padding.PaddingRight = UDim.new(0.04, 0)
		padding.PaddingTop = UDim.new(0.12, 0)
		padding.PaddingBottom = UDim.new(0.12, 0)
		padding.Parent = label
		label.Parent = frame
		frame.Parent = gui
		gui.Parent = panel
	end
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Color = color
	light.Range = 12
	light.Brightness = 1.2
	light.Parent = panel
	CollectionService:AddTag(panel, "Holo")
end

-- Транспорт: кольцевые «воздушные трассы» на разной высоте, в обе стороны (Штаб тоже этим пользуется)
function CityLife.traffic(parent: Instance, count: number, minRadius: number, maxRadius: number, minHeight: number, maxHeight: number)
	for i = 1, count do
		local model = car(parent, HOLO_COLORS[(i % #HOLO_COLORS) + 1])
		model:SetAttribute("Radius", random:NextNumber(minRadius, maxRadius))
		model:SetAttribute("Height", random:NextNumber(minHeight, maxHeight))
		model:SetAttribute("Speed", (if i % 2 == 0 then 1 else -1) * random:NextNumber(18, 32)) -- студов в секунду
		model:SetAttribute("Phase", random:NextNumber(0, math.pi * 2))
		model:SetAttribute("Bob", random:NextNumber(0.5, 2))
		CollectionService:AddTag(model, "SkyCar")
	end
end

-- Голограмма-вывеска (Штаб использует для названия игры)
CityLife.holo = holo

function CityLife.apply(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CityLife"

	CityLife.traffic(folder, CAR_COUNT, 70, 190, 48, 95)

	-- Голограммы — на верхней части самых высоких домов, с наружной стороны
	local tall = {}
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == "Building" then
			local body = descendant:FindFirstChild("Body")
			if body and body:IsA("BasePart") and body.Size.Y > 30 then
				table.insert(tall, body)
			end
		end
	end
	for i = 1, math.min(HOLO_COUNT, #tall) do
		local body = table.remove(tall, random:NextInteger(1, #tall)) :: BasePart
		local flat = Vector3.new(body.Position.X, 0, body.Position.Z)
		local out = if flat.Magnitude > 1 then -flat.Unit else Vector3.zAxis -- в сторону центра города
		-- детальная модель дома бывает шире коробки, поэтому выносим панель с запасом
		local reach = math.max(body.Size.X, body.Size.Z) * 0.68 + 2
		local y = body.Position.Y - body.Size.Y / 2 + random:NextNumber(16, 28) -- видно с улицы
		local position = Vector3.new(body.Position.X, y, body.Position.Z) + out * reach
		holo(folder, CFrame.lookAt(position, position + out), HOLO_TEXTS[(i - 1) % #HOLO_TEXTS + 1], HOLO_COLORS[random:NextInteger(1, #HOLO_COLORS)])
	end

	folder.Parent = map
end

return CityLife
