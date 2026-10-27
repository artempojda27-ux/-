--!strict
-- Разговор с Командором Вегой в Штабе (кнопка «Поговорить» у голостола, строит LobbyLook).
-- Реплики — Config.Commander.Lines, по одной; «Далее» — следующая, после последней окно закрывается.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

local gui = UI.screen("CommanderUI")
gui.DisplayOrder = 9

local panel = UI.panel({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0.6, 0, 0, 130),
	Visible = false,
	Parent = gui,
})
UI.new("UISizeConstraint", { MinSize = Vector2.new(320, 130), MaxSize = Vector2.new(760, 130), Parent = panel })
UI.label({
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -32, 0, 22),
	Font = Enum.Font.GothamBlack,
	TextSize = 18,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = Config.Commander.Name,
	Parent = panel,
})
local text = UI.label({
	Position = UDim2.fromOffset(16, 36),
	Size = UDim2.new(1, -150, 1, -46),
	TextSize = 17,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = panel,
})

local index = 0
local nextButton: TextButton

local function show()
	local lines = Config.Commander.Lines
	if index > #lines then
		panel.Visible = false
		index = 0
		return
	end
	text.Text = lines[index]
	nextButton.Text = if index == #lines then "Понял" else "Далее"
	panel.Visible = true
end

nextButton = UI.button({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(110, 40),
	Text = "Далее",
	Parent = panel,
}, function()
	index += 1
	show()
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if player ~= Players.LocalPlayer or prompt.Name ~= "Talk" then
		return
	end
	if not panel.Visible then
		index = 1
		show()
	end
end)
