--!strict
-- Управление машиной для водителя: подсказка внизу экрана и реактивный прыжок с сальто
-- (Shift или F; на телефоне — кнопка «ПРЫЖОК»). Прыжок проверяет и выполняет сервер (VehicleService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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
UI.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = jumpButton })

local driving = false

local function refresh()
	local owns = player:GetAttribute("Pass_Thrusters") == true
	hint.Visible = driving
	hint.Text = if owns
		then "W/S — газ, A/D — руль, Shift или F — реактивный прыжок, пробел — выйти"
		else "W/S — газ, A/D — руль, пробел — выйти · реактивный прыжок — в магазине"
	jumpButton.Visible = driving and owns and UserInputService.TouchEnabled
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	driving = false
	refresh()
	humanoid.Seated:Connect(function(active, seat)
		driving = active and seat ~= nil and seat.Name == "DriverSeat"
		refresh()
	end)
end

if player.Character then
	task.spawn(watchCharacter, player.Character)
end
player.CharacterAdded:Connect(watchCharacter)
player:GetAttributeChangedSignal("Pass_Thrusters"):Connect(refresh)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not driving then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.F then
		vehicleAction:FireServer("Flip")
	end
end)
