--!strict
-- Камера в машине: обычная камера Roblox в машине висит низко и сзади-сбоку — на трассе «Побега» не видно
-- препятствий. Пока игрок сидит в машине, камера плавно летит за ней сама.
-- Три вида (кнопка «ВИД» на экране или V): «Сзади» — высоко и далеко, видно дорогу далеко вперёд (по умолчанию);
-- «Близко» — ниже и ближе, как в гонках; «Из кабины» — от первого лица над капотом.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer

type View = { Name: string, Back: number, Up: number, Ahead: number, Fov: number }
local VIEWS: { View } = {
	{ Name = "Сзади", Back = 22, Up = 9, Ahead = 30, Fov = 75 },
	{ Name = "Близко", Back = 13, Up = 4.5, Ahead = 25, Fov = 80 },
	{ Name = "Из кабины", Back = -1.5, Up = 2.6, Ahead = 40, Fov = 85 },
}

local viewIndex = 1
local car: BasePart? = nil -- шасси машины, в которой сидит игрок
local smoothed: CFrame? = nil
local savedFov = 70

local gui = UI.screen("VehicleCameraUI")
local viewButton = UI.button({
	Name = "ViewButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 120),
	Size = UDim2.fromOffset(150, 44),
	Text = "ВИД: Сзади",
	TextSize = 16,
	Visible = false,
	Parent = gui,
}, function()
	viewIndex = viewIndex % #VIEWS + 1
end)

local function stopFollowing()
	if car then
		car = nil
		smoothed = nil
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = savedFov
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	viewButton.Visible = false
end

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	stopFollowing()
	humanoid.Seated:Connect(function(active, seat)
		if active and seat then
			local model = seat.Parent
			local chassis = model and model:FindFirstChild("Chassis")
			if chassis and chassis:IsA("BasePart") then
				car = chassis
				savedFov = Workspace.CurrentCamera.FieldOfView
				viewButton.Visible = true
				return
			end
		end
		stopFollowing()
	end)
end

if player.Character then
	task.spawn(watch, player.Character)
end
player.CharacterAdded:Connect(watch)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and car and input.KeyCode == Enum.KeyCode.V then
		viewIndex = viewIndex % #VIEWS + 1
	end
end)

RunService:BindToRenderStep("VehicleCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local chassis = car
	if not chassis or not chassis.Parent then
		if car then
			stopFollowing()
		end
		return
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local view = VIEWS[viewIndex]
	viewButton.Text = `ВИД: {view.Name}`
	-- направление машины по горизонтали: в сальто камера не кувыркается вместе с ней
	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local position = chassis.Position - flat * view.Back + Vector3.new(0, view.Up, 0)
	local target = chassis.Position + flat * view.Ahead + Vector3.new(0, view.Up * 0.3, 0)
	local goal = CFrame.lookAt(position, target)
	-- вид из кабины жёсткий, остальные плавно догоняют машину
	local alpha = if viewIndex == 3 then 1 else math.clamp(dt * 8, 0, 1)
	smoothed = if smoothed then smoothed:Lerp(goal, alpha) else goal
	camera.CFrame = smoothed :: CFrame
	camera.FieldOfView = view.Fov
end)
