--!strict
-- Детальные здания и монументы: модели, сгенерированные в Studio (номера — Config.BuildingSets и
-- Config.Monuments), надеваются на простые дома города. Коробка дома остаётся невидимой: по ней
-- работают стрельба, укрытия и пути врагов, а глаз видит детальную модель.
-- У каждого мира свой набор: неоновые небоскрёбы, пагоды, кристальные башни. Стёртый мир и Монолит
-- берут неоновые формы без текстур — белые, как гипс, или графитовые зеркальные.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

type Style = {
	Set: string, -- какой набор зданий
	Color: Color3?, -- если задан — текстуру снимаем и красим
	Material: Enum.Material?,
	Reflectance: number?,
}

local STYLES: { [string]: Style } = {
	Neon = { Set = "Neon" },
	Mirror = { Set = "Neon" },
	Temple = { Set = "Temple" },
	Crystal = { Set = "Crystal" },
	Core = { Set = "Core" },
	Erased = { Set = "Neon", Color = Color3.fromRGB(232, 232, 236), Material = Enum.Material.Plaster },
	-- графитовый металл: в чёрной пустоте совсем чёрные дома не видно, а так силуэты ловят отблески
	Monolith = { Set = "Neon", Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Metal, Reflectance = 0.6 },
}

local CitySkins = {}

local random = Random.new(4242)
local cache: { [number]: BasePart } = {}

-- Деталь с моделью из ассета (один раз на номер, дальше — копии)
local function template(assetId: number): BasePart?
	if cache[assetId] then
		return cache[assetId]
	end
	local ok, container = pcall(InsertService.LoadAsset, InsertService, assetId)
	if not ok then
		warn(`Не загрузилось здание {assetId}: {container}`)
		return nil
	end
	local mesh = container:FindFirstChildWhichIsA("BasePart", true)
	if mesh then
		mesh.Parent = nil
		cache[assetId] = mesh
	end
	container:Destroy()
	return mesh
end

local function dress(part: BasePart, style: Style, anchored: boolean, collide: boolean)
	part.Anchored = anchored
	part.CanCollide = collide
	part.CanQuery = collide
	part.CanTouch = false
	if style.Color then
		if part:IsA("MeshPart") then
			part.TextureID = ""
		end
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		part.Color = style.Color
		part.Material = style.Material or Enum.Material.SmoothPlastic
		part.Reflectance = style.Reflectance or 0
	end
end

-- Самый похожий по пропорциям шаблон: высокий дом — небоскрёб, низкий — дом пониже
local function pick(templates: { BasePart }, ratio: number): BasePart
	local best, bestDiff = templates[1], math.huge
	for _, t in templates do
		local diff = math.abs(t.Size.Y / math.max(t.Size.X, t.Size.Z) - ratio)
		if diff < bestDiff then
			best, bestDiff = t, diff
		end
	end
	return best
end

-- Надевает модель на один дом. Простое убранство дома (окна, вывески, края крыши) больше не нужно.
local function skinBuilding(building: Model, templates: { BasePart }, style: Style)
	local body = building:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end
	local size = body.Size
	local source = pick(templates, size.Y / math.max(size.X, size.Z))
	local skin = source:Clone()
	skin.Name = "Skin"
	-- по высоте — точно как дом, по ширине — не шире участка (иначе модель залезает на тротуар
	-- и в соседние дома); высокий дом из-за этого становится стройнее — так даже лучше
	local scale = size.Y / source.Size.Y
	local lot = math.max(size.X, size.Z) * 1.08 / math.max(source.Size.X, source.Size.Z)
	local width = math.clamp(lot, scale * 0.35, scale * 1.35)
	skin.Size = Vector3.new(source.Size.X * width, size.Y, source.Size.Z * width)
	skin.CFrame = CFrame.new(body.Position) * CFrame.Angles(0, math.rad(90 * random:NextInteger(0, 3)), 0)
	dress(skin, style, true, false)
	skin.Parent = building

	for _, child in building:GetChildren() do
		if child ~= body and child ~= skin then
			child:Destroy()
		end
	end
	body.Transparency = 1
end

local function placeMonument(map: Instance, assetId: number, style: Style)
	local source = template(assetId)
	if not source then
		return
	end
	local monument = source:Clone()
	monument.Name = "Monument"
	local scale = 26 / source.Size.Y
	monument.Size = source.Size * scale
	-- у края площади, между укрытиями, лицом к месту появления
	local position = Vector3.new(0, 1.6 + monument.Size.Y / 2, -17)
	monument.CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	dress(monument, style, true, true)
	monument.Parent = map
end

-- Применяет детальные здания и монумент мира к карте города
function CitySkins.apply(worldId: string, map: Instance)
	local style = STYLES[worldId] or STYLES.Neon
	local templates = {}
	for _, assetId in Config.BuildingSets[style.Set] or {} do
		local t = template(assetId)
		if t then
			table.insert(templates, t)
		end
	end
	if #templates > 0 then
		for _, descendant in map:GetDescendants() do
			if descendant:IsA("Model") and descendant.Name == "Building" then
				skinBuilding(descendant, templates, style)
			end
		end
	end
	local monumentId = Config.Monuments[style.Set]
	if monumentId and monumentId ~= 0 then
		placeMonument(map, monumentId, style)
	end
end

return CitySkins
