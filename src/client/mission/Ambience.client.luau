--!strict
-- Атмосфера Миссии, которую считает клиент (так плавно и без нагрузки на сеть):
-- летающий транспорт (тег "SkyCar", маршрут — атрибуты от сервера, по времени сервера),
-- мигание голограмм (тег "Holo") и светящаяся пыль данных в воздухе вокруг камеры
-- (цвет — атрибут Workspace "WorldAccent").

local CollectionService = game:GetService("CollectionService")
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
