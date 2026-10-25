--!strict
-- Маленькие помощники для интерфейса в неоновом стиле.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Accent = Color3.fromRGB(0, 255, 200),
	Glitch = Color3.fromRGB(255, 40, 120),
	Panel = Color3.fromRGB(12, 16, 22),
	Text = Color3.fromRGB(230, 240, 240),
	Muted = Color3.fromRGB(140, 160, 165),
}

-- Создаёт объект и задаёт свойства: UI.new("Frame", { Size = ..., Parent = ... })
function UI.new(className: string, props: { [string]: any }?): any
	local instance = Instance.new(className)
	if props then
		local parent = props.Parent
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
		instance.Parent = parent
	end
	return instance
end

function UI.screen(name: string): ScreenGui
	local player = Players.LocalPlayer
	return UI.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
end

function UI.panel(props: { [string]: any }): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or UI.Colors.Panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.15
	props.BorderSizePixel = 0
	local frame = UI.new("Frame", props)
	UI.new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = frame })
	UI.new("UIStroke", { Color = UI.Colors.Accent, Transparency = 0.5, Thickness = 1.5, Parent = frame })
	return frame
end

function UI.label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextColor3 = props.TextColor3 or UI.Colors.Text
	props.TextSize = props.TextSize or 18
	return UI.new("TextLabel", props)
end

function UI.button(props: { [string]: any }, onClick: () -> ()): TextButton
	props.BackgroundColor3 = props.BackgroundColor3 or UI.Colors.Accent
	props.BorderSizePixel = 0
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or UI.Colors.Panel
	props.TextSize = props.TextSize or 18
	props.AutoButtonColor = true
	local button = UI.new("TextButton", props)
	UI.new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = button })
	button.Activated:Connect(onClick)
	return button
end

-- Всплывающие сообщения сверху экрана
local toastGui: ScreenGui? = nil
local toastList: Frame? = nil

function UI.toast(text: string)
	if not toastGui then
		toastGui = UI.screen("Toasts")
		toastList = UI.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 70),
			Size = UDim2.fromOffset(460, 300),
			Parent = toastGui,
		})
		UI.new("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = toastList,
		})
	end

	local item = UI.panel({
		Size = UDim2.fromOffset(440, 40),
		LayoutOrder = math.floor(os.clock() * 1000),
		Parent = toastList,
	})
	local label = UI.label({
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Text = text,
		TextWrapped = true,
		Parent = item,
	})

	task.delay(4, function()
		local info = TweenInfo.new(0.5)
		TweenService:Create(item, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		task.wait(0.5)
		item:Destroy()
	end)
end

return UI
