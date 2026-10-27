--!strict
-- Атмосфера Миссии, которую считает клиент (так плавно и без нагрузки на сеть):
-- летающий транспорт (тег "SkyCar", маршрут — атрибуты от сервера, по времени сервера),
-- мигание голограмм (тег "Holo") и светящаяся пыль данных в воздухе вокруг камеры
-- (цвет — атрибут Workspace "WorldAccent"), погода мира (атрибут "Weather": Rain, Lanterns, Paper, Ash, Sparks)
-- и молнии (атрибут "Lightning" — их цвет). Атрибуты ставит сервер — WorldDetails.luau.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local random = Random.new()

---------------------------------------------------------------- Транспорт

RunService.Heartbeat:Connect(function()
	local now = Workspace:GetServerTimeNow()
	for _, model in CollectionService:GetTagged("SkyCar") do
		if not model:IsA("Model") or not model.PrimaryPart then
			continue
		end
		local radius = model:GetAttribute("Radius") :: number?
		local height = model:GetAttribute("Height") :: number?
		local speed = model:GetAttribute("Speed") :: number?
		local phase = model:GetAttribute("Phase") :: number?
		local bob = model:GetAttribute("Bob") :: number?
		if not (radius and height and speed and phase and bob) then
			continue
		end
		local angle = phase + now * speed / radius
		local position = Vector3.new(math.cos(angle) * radius, height + math.sin(now * 0.8 + phase) * bob, math.sin(angle) * radius)
		local sign = if speed >= 0 then 1 else -1
		local heading = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * sign
		-- лёгкий крен в поворот
		model:PivotTo(CFrame.lookAt(position, position + heading) * CFrame.Angles(0, 0, math.rad(-12 * sign)))
	end
end)

---------------------------------------------------------------- Голограммы

task.spawn(function()
	while true do
		task.wait(random:NextNumber(0.15, 0.4))
		local holos = CollectionService:GetTagged("Holo")
		if #holos == 0 then
			continue
		end
		-- случайная вывеска «сбоит»: мигает и дёргается, потом возвращается
		local panel = holos[random:NextInteger(1, #holos)]
		local labels = {}
		for _, descendant in panel:GetDescendants() do
			if descendant:IsA("TextLabel") then
				table.insert(labels, descendant)
			end
		end
		for _ = 1, random:NextInteger(2, 4) do
			for _, label in labels do
				label.TextTransparency = random:NextNumber(0.3, 0.9)
				label.Position = UDim2.fromOffset(random:NextInteger(-6, 6), 0)
			end
			task.wait(0.05)
		end
		for _, label in labels do
			label.TextTransparency = 0
			label.Position = UDim2.new()
		end
	end
end)

---------------------------------------------------------------- Пыль данных

local holder = Instance.new("Part")
holder.Name = "DataDust"
holder.Anchored = true
holder.CanCollide = false
holder.CanQuery = false
holder.CanTouch = false
holder.Transparency = 1
holder.Size = Vector3.new(70, 30, 70)
local dust = Instance.new("ParticleEmitter")
dust.Shape = Enum.ParticleEmitterShape.Box
dust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
dust.Rate = 40
dust.Lifetime = NumberRange.new(4, 7)
dust.Speed = NumberRange.new(0.2, 0.8)
dust.SpreadAngle = Vector2.new(180, 180)
dust.Acceleration = Vector3.new(0, 0.3, 0)
dust.LightEmission = 1
dust.LightInfluence = 0
dust.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0.12),
	NumberSequenceKeypoint.new(1, 0),
})
dust.Transparency = NumberSequence.new(0.3)
dust.Parent = holder
holder.Parent = Workspace

local function refreshColor()
	local accent = Workspace:GetAttribute("WorldAccent")
	dust.Color = ColorSequence.new(if typeof(accent) == "Color3" then accent else Color3.fromRGB(0, 255, 220))
end
refreshColor()
Workspace:GetAttributeChangedSignal("WorldAccent"):Connect(refreshColor)

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if camera then
		holder.CFrame = CFrame.new(camera.CFrame.Position)
	end
end)

---------------------------------------------------------------- Погода

-- Облако частиц над камерой (дождь, пепел, бумага, искры) или над всем городом (фонарики)
local weatherHolder = holder:Clone()
weatherHolder.Name = "Weather"
weatherHolder:ClearAllChildren()
weatherHolder.Parent = Workspace
local weather = Instance.new("ParticleEmitter")
weather.Enabled = false
weather.Shape = Enum.ParticleEmitterShape.Box
weather.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
weather.Parent = weatherHolder
local followCamera = true
local weatherOffset = Vector3.zero

local WEATHER: { [string]: { [string]: any } } = {
	Rain = {
		Size = Vector3.new(90, 1, 90),
		Offset = Vector3.new(0, 30, 0),
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(170, 200, 255)),
			Transparency = NumberSequence.new(0.55),
			LightEmission = 0.3,
			LightInfluence = 1,
			Size = NumberSequence.new(0.07),
			Squash = NumberSequence.new(-4), -- вытянутая капля
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Lifetime = NumberRange.new(0.6, 0.8),
			Rate = 500,
			Speed = NumberRange.new(70, 85),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(4, 4),
			Acceleration = Vector3.zero,
		},
	},
	Lanterns = {
		City = true,
		Size = Vector3.new(240, 1, 240),
		Offset = Vector3.new(0, 4, 0),
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(255, 170, 80), Color3.fromRGB(255, 110, 50)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 1,
			LightInfluence = 0,
			Size = NumberSequence.new(0.9),
			Squash = NumberSequence.new(0.4), -- фонарик чуть выше, чем шире
			Orientation = Enum.ParticleOrientation.FacingCamera,
			Lifetime = NumberRange.new(30, 40),
			Rate = 4,
			Speed = NumberRange.new(2.5, 4),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(0.4, 0, 0.2),
		},
	},
	Paper = {
		Size = Vector3.new(90, 40, 90),
		Offset = Vector3.new(0, 10, 0),
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(250, 250, 250)),
			Transparency = NumberSequence.new(0.1),
			LightEmission = 0,
			LightInfluence = 1,
			Size = NumberSequence.new(0.45),
			Squash = NumberSequence.new(0.6),
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Lifetime = NumberRange.new(5, 8),
			Rate = 18,
			Speed = NumberRange.new(3, 6),
			EmissionDirection = Enum.NormalId.Right,
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(1.5, -0.8, 0.5),
			RotSpeed = NumberRange.new(-200, 200),
			Rotation = NumberRange.new(0, 360),
		},
	},
	Ash = {
		Size = Vector3.new(90, 1, 90),
		Offset = Vector3.new(0, 30, 0),
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(30, 30, 34)),
			Transparency = NumberSequence.new(0.2),
			LightEmission = 0,
			LightInfluence = 1,
			Size = NumberSequence.new(0.2),
			Orientation = Enum.ParticleOrientation.FacingCamera,
			Lifetime = NumberRange.new(8, 12),
			Rate = 90,
			Speed = NumberRange.new(2, 4),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(0.5, 0, 0),
			RotSpeed = NumberRange.new(-90, 90),
		},
	},
	Sparks = {
		Size = Vector3.new(80, 2, 80),
		Offset = Vector3.new(0, -4, 0),
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 200, 255)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 1,
			LightInfluence = 0,
			Size = NumberSequence.new(0.12),
			Orientation = Enum.ParticleOrientation.FacingCamera,
			Lifetime = NumberRange.new(4, 7),
			Rate = 45,
			Speed = NumberRange.new(2, 5),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(0, 1, 0),
		},
	},
}

local function refreshWeather()
	local kind = Workspace:GetAttribute("Weather")
	local config = if typeof(kind) == "string" then WEATHER[kind] else nil
	if not config then
		weather.Enabled = false
		return
	end
	for key, value in config.Props do
		(weather :: any)[key] = value
	end
	weatherHolder.Size = config.Size
	weatherOffset = config.Offset
	followCamera = config.City ~= true
	if not followCamera then
		weatherHolder.CFrame = CFrame.new(weatherOffset)
	end
	weather.Enabled = true
end
refreshWeather()
Workspace:GetAttributeChangedSignal("Weather"):Connect(refreshWeather)

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if camera and followCamera then
		weatherHolder.CFrame = CFrame.new(camera.CFrame.Position + weatherOffset)
	end
end)

---------------------------------------------------------------- Молнии

local flash = Instance.new("ColorCorrectionEffect")
flash.Name = "LightningFlash"
flash.Enabled = false
flash.Parent = Lighting

-- Ломаная молния в небе: несколько светящихся отрезков, видна долю секунды
local function bolt(color: Color3)
	local camera = Workspace.CurrentCamera
	local around = if camera then camera.CFrame.Position else Vector3.zero
	local point = Vector3.new(around.X + random:NextNumber(-200, 200), 260, around.Z + random:NextNumber(-200, 200))
	local parts = {}
	for _ = 1, 7 do
		local nextPoint = point + Vector3.new(random:NextNumber(-25, 25), -random:NextNumber(20, 35), random:NextNumber(-25, 25))
		local segment = Instance.new("Part")
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Material = Enum.Material.Neon
		segment.Color = color
		segment.Size = Vector3.new(0.8, 0.8, (nextPoint - point).Magnitude)
		segment.CFrame = CFrame.lookAt((point + nextPoint) / 2, nextPoint)
		segment.Parent = Workspace
		table.insert(parts, segment)
		point = nextPoint
	end
	return parts
end

task.spawn(function()
	while true do
		task.wait(random:NextNumber(6, 13))
		local color = Workspace:GetAttribute("Lightning")
		if typeof(color) ~= "Color3" then
			continue
		end
		local parts = bolt(color)
		flash.TintColor = color:Lerp(Color3.new(1, 1, 1), 0.6)
		for _, brightness in { 0.35, 0, 0.25 } do
			flash.Brightness = brightness
			flash.Enabled = brightness > 0
			task.wait(0.06)
		end
		flash.Enabled = false
		task.wait(0.1)
		for _, segment in parts do
			segment:Destroy()
		end
	end
end)
