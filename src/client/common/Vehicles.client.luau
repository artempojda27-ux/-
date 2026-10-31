--!strict
-- Управление машиной для водителя: подсказка внизу экрана и платные возможности машины:
-- реактивный прыжок с сальто (Shift или F), нитро (Q), смена цвета неонового тюнинга (C).
-- У Вольта своя функция — ракетный рывок (X): полёт над препятствиями.
-- На телефоне — кнопки «ПРЫЖОК», «НИТРО» и «РАКЕТА». Всё проверяет и выполняет сервер (VehicleService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer
local vehicleAction = Remotes.get("VehicleAction")

local gui = UI.screen("VehicleUI")
local hint = UI.label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -84),
	Size = UDim2.fromOffset(620, 28),
	TextSize = 16,
	TextStrokeTransparency = 0.6,
	Visible = false,
	Parent = gui,
})
local jumpButton = UI.button({
	Name = "JumpButton",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -120),
	Size = UDim2.fromOffset(110, 110),
	Text = "ПРЫЖОК",
	TextSize = 18,
	BackgroundColor3 = UI.Colors.Glitch,
	TextColor3 = UI.Colors.Text,
	Visible = false,
	Parent = gui,
}, function()
	vehicleAction:FireServer("Flip")
end)
UI.round(jumpButton)
local nitroButton = UI.button({
	Name = "NitroButton",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -144, 1, -120),
	Size = UDim2.fromOffset(90, 90),
	Text = "НИТРО",
	TextSize = 16,
	Visible = false,
	Parent = gui,
}, function()
	vehicleAction:FireServer("Nitro")
end)
UI.round(nitroButton)
local rocketButton = UI.button({
	Name = "RocketButton",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -250, 1, -120),
	Size = UDim2.fromOffset(90, 90),
	Text = "РАКЕТА",
	TextSize = 16,
	BackgroundColor3 = Color3.fromRGB(255, 140, 40),
	Visible = false,
	Parent = gui,
}, function()
	vehicleAction:FireServer("Rocket")
end)
UI.round(rocketButton)

local driving = false
local rocketCar = false -- сидим за рулём машины с ракетой (Вольт)

local function owns(key: string): boolean
	return player:GetAttribute(`Pass_{key}`) == true
end

local function refresh()
	local parts = { "W/S — газ, A/D — руль" }
	if owns("Thrusters") then
		table.insert(parts, "Shift/F — прыжок")
	end
	if owns("Nitro") then
		table.insert(parts, "Q — нитро")
	end
	if owns("NeonTuning") then
		table.insert(parts, "C — цвет")
	end
	if rocketCar then
		table.insert(parts, "X — ракета")
	end
	table.insert(parts, "пробел — выйти")
	hint.Visible = driving
	hint.Text = table.concat(parts, ", ")
	jumpButton.Visible = driving and owns("Thrusters") and UserInputService.TouchEnabled
	nitroButton.Visible = driving and owns("Nitro") and UserInputService.TouchEnabled
	rocketButton.Visible = driving and rocketCar and UserInputService.TouchEnabled
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	-- следим за SeatPart: событие Seated не приходит, когда в машину сажает сервер
	local function update()
		local seat = humanoid.SeatPart
		driving = seat ~= nil and seat.Name == "DriverSeat"
		rocketCar = false
		if driving and seat and seat.Parent then
			for _, kind in Config.Vehicles do
				if kind.Name == seat.Parent.Name and kind.Special == "Rocket" then
					rocketCar = true
				end
			end
		end
		refresh()
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(update)
	update()
end

if player.Character then
	task.spawn(watchCharacter, player.Character)
end
player.CharacterAdded:Connect(watchCharacter)
for _, key in { "Thrusters", "Nitro", "NeonTuning" } do
	player:GetAttributeChangedSignal(`Pass_{key}`):Connect(refresh)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not driving then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.F then
		vehicleAction:FireServer("Flip")
	elseif input.KeyCode == Enum.KeyCode.Q then
		vehicleAction:FireServer("Nitro")
	elseif input.KeyCode == Enum.KeyCode.C then
		vehicleAction:FireServer("Color")
	elseif input.KeyCode == Enum.KeyCode.X and rocketCar then
		vehicleAction:FireServer("Rocket")
	end
end)
