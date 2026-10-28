--!strict
-- Способности героя (Config.Abilities): Q — Импульс, F — Рывок, G — Перезапись (ультимейт).
-- Справа над оружием — три круглые кнопки с перезарядкой и зарядом ультимейта (на телефоне на них жмут пальцем).
-- Урон считает сервер (AbilityService); рывок двигает клиент — своего персонажа двигает он сам.
-- Здесь же рисуются эффекты способностей всех игроков (событие AbilityFx).
-- В машине клавиши Q/F заняты нитро и прыжком — там способности не срабатывают.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

local player = Players.LocalPlayer
local abilityAction = Remotes.get("AbilityAction")

local COLORS = {
	Pulse = Color3.fromRGB(0, 255, 200),
	Dash = Color3.fromRGB(120, 180, 255),
	Ultimate = Color3.fromRGB(255, 60, 160),
}
local ORDER = { "Pulse", "Dash", "Ultimate" }

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and not humanoid.Sit and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function readyIn(name: string): number
	if name == "Ultimate" then
		local charge = player:GetAttribute("UltCharge")
		return if typeof(charge) == "number" and charge >= 100 then 0 else 1
	end
	local readyAt = player:GetAttribute(`{name}ReadyAt`)
	return if typeof(readyAt) == "number" then math.max(0, readyAt - Workspace:GetServerTimeNow()) else 0
end

-- Рывок: бросок в сторону движения (или взгляда), сервер даёт короткое защитное поле
local function dash()
	local humanoid, root = humanoidAndRoot()
	if not humanoid or not root or readyIn("Dash") > 0 then
		return
	end
	local spec = Config.Abilities.Dash
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		local look = Workspace.CurrentCamera.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	if direction.Magnitude < 0.01 then
		return
	end
	direction = direction.Unit
	abilityAction:FireServer("Dash")
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if os.clock() - started > spec.Duration or not root.Parent then
			connection:Disconnect()
			return
		end
		root.AssemblyLinearVelocity = direction * spec.Speed + Vector3.new(0, root.AssemblyLinearVelocity.Y * 0.2, 0)
	end)
end

local function use(name: string)
	if name == "Dash" then
		dash()
		return
	end
	local humanoid = humanoidAndRoot()
	if humanoid and readyIn(name) <= 0 then
		abilityAction:FireServer(name)
	end
end

---------------------------------------------------------------- Кнопки

local gui = UI.screen("AbilityUI")
local isTouch = UI.isTouch
local size = if isTouch then 74 else 62
local holder = UI.new("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	-- на телефоне — над кнопками огня и прыжка, на компьютере — над панелью патронов
	Position = if isTouch then UDim2.new(1, -24, 1, -262) else UDim2.new(1, -20, 1, -110),
	Size = UDim2.fromOffset(size * 3 + 20, size + 18),
	BackgroundTransparency = 1,
	Parent = gui,
})
UI.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 10),
	Parent = holder,
})

type Slot = { Button: TextButton, Shade: Frame, Label: TextLabel }
local slots: { [string]: Slot } = {}
for order, name in ORDER do
	local spec = (Config.Abilities :: any)[name]
	local button = UI.button({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size, size),
		Text = "",
		BackgroundColor3 = UI.Colors.Panel,
		Parent = holder,
	}, function()
		use(name)
	end)
	UI.round(button)
	UI.new("UIStroke", { Color = COLORS[name], Thickness = 2.5, Parent = button })
	-- затемнение снизу вверх показывает перезарядку
	local shade = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = button,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shade })
	UI.label({
		Size = UDim2.new(0.8, 0, 0.3, 0), -- название внутри круга, не вылезает за край
		Position = UDim2.fromScale(0.1, 0.22),
		Font = Enum.Font.GothamBlack,
		TextSize = if isTouch then 14 else 13,
		TextColor3 = COLORS[name],
		Text = spec.Name,
		TextScaled = true,
		Parent = button,
	})
	local label = UI.label({
		Size = UDim2.new(1, 0, 0.35, 0),
		Position = UDim2.fromScale(0, 0.58),
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Text = if isTouch then "" else spec.Key,
		Parent = button,
	})
	slots[name] = { Button = button, Shade = shade, Label = label }
end

RunService.RenderStepped:Connect(function()
	for _, name in ORDER do
		local slot = slots[name]
		local spec = (Config.Abilities :: any)[name]
		if name == "Ultimate" then
			local charge = player:GetAttribute("UltCharge")
			local value = if typeof(charge) == "number" then charge else 0
			slot.Shade.Size = UDim2.fromScale(1, 1 - value / 100)
			slot.Label.Text = if value >= 100 then (if isTouch then "ГОТОВО" else `{spec.Key} · ГОТОВО`) else `{value}%`
		else
			local left = readyIn(name)
			slot.Shade.Size = UDim2.fromScale(1, math.clamp(left / spec.Cooldown, 0, 1))
			slot.Label.Text = if left > 0 then `{math.ceil(left)}` else (if isTouch then "" else spec.Key)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	for _, name in ORDER do
		if input.KeyCode == (Enum.KeyCode :: any)[(Config.Abilities :: any)[name].Key] then
			use(name)
		end
	end
end)

---------------------------------------------------------------- Эффекты

local function fxPart(props: { [string]: any }): Part
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
	p.Parent = Workspace.CurrentCamera
	return p
end

local function ring(position: Vector3, radius: number, color: Color3, time: number)
	local disc = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 2, 2),
		CFrame = CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.2,
	})
	TweenService:Create(disc, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(time, function()
		disc:Destroy()
	end)
end

Remotes.get("AbilityFx").OnClientEvent:Connect(function(_who: Player, name: string, position: Vector3)
	local color = COLORS[name] or Color3.new(1, 1, 1)
	if name == "Pulse" then
		ring(position, Config.Abilities.Pulse.Radius, color, 0.45)
		local ball = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Position = position, Color = color, Transparency = 0.3 })
		TweenService:Create(ball, TweenInfo.new(0.35), { Size = Vector3.one * Config.Abilities.Pulse.Radius * 1.4, Transparency = 1 }):Play()
		task.delay(0.35, function()
			ball:Destroy()
		end)
	elseif name == "Dash" then
		for i = 1, 5 do
			task.delay(i * 0.04, function()
				ring(position, 5, color, 0.3)
			end)
		end
	elseif name == "Ultimate" then
		-- столб света вверх и волна до края радиуса; у всех игроков на миг белеет экран рядом со вспышкой
		local pillar = fxPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(200, 4, 4),
			CFrame = CFrame.new(position + Vector3.new(0, 100, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Transparency = 0.1,
		})
		TweenService:Create(pillar, TweenInfo.new(0.8), { Size = Vector3.new(200, 30, 30), Transparency = 1 }):Play()
		task.delay(0.8, function()
			pillar:Destroy()
		end)
		task.delay(0.3, function()
			ring(position, Config.Abilities.Ultimate.Radius, color, 0.6)
			ring(position, Config.Abilities.Ultimate.Radius * 0.6, Color3.new(1, 1, 1), 0.5)
		end)
	end
end)
