--!strict
-- Интерфейс Штаба: кнопка «Пригласить друга» и панель отряда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

local player = Players.LocalPlayer
local squadAction = Remotes.get("SquadAction")

Remotes.get("Notify").OnClientEvent:Connect(function(text: string)
	UI.toast(text)
end)

local gui = UI.screen("LobbyUI")

-- Пригласить друга
UI.button({
	Text = "Пригласить друга",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -20),
	Size = UDim2.fromOffset(200, 48),
	Parent = gui,
}, function()
	local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and canInvite then
		SocialService:PromptGameInvite(player)
	else
		UI.toast("Приглашения сейчас недоступны.")
	end
end)

local hintLabel = UI.label({
	Text = "Встань на портал, чтобы собрать отряд",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.fromOffset(500, 30),
	TextColor3 = UI.Colors.Muted,
	Parent = gui,
})

-- Большой отсчёт по центру
local countdownLabel = UI.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.35),
	Size = UDim2.fromOffset(600, 80),
	Font = Enum.Font.GothamBlack,
	TextSize = 48,
	TextColor3 = UI.Colors.Accent,
	TextStrokeTransparency = 0.5,
	Visible = false,
	Parent = gui,
})

-- Панель отряда справа
local panel = UI.panel({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -20, 0.5, 0),
	Size = UDim2.fromOffset(300, 468),
	Visible = false,
	Parent = gui,
})
UI.new("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = panel,
})
UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })

local title = UI.label({
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 28),
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

local membersLabel = UI.label({
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 100),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = panel,
})

-- Строка настройки: «название: значение» со стрелками для лидера
local function settingRow(order: number, action: string)
	local row = UI.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local left = UI.button({
		Text = "<",
		Size = UDim2.fromOffset(36, 36),
		Parent = row,
	}, function()
		squadAction:FireServer(action, -1)
	end)
	local right = UI.button({
		Text = ">",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(36, 36),
		Parent = row,
	}, function()
		squadAction:FireServer(action, 1)
	end)
	local value = UI.label({
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -84, 1, 0),
		TextSize = 16,
		TextWrapped = true,
		Parent = row,
	})
	return value, left, right
end

local chapterValue, chapterLeft, chapterRight = settingRow(3, "Chapter")
local difficultyValue, difficultyLeft, difficultyRight = settingRow(4, "Difficulty")
local worldValue, worldLeft, worldRight = settingRow(5, "World")
local missionValue, missionLeft, missionRight = settingRow(6, "Mission")
local missionRow = missionValue.Parent :: Frame
local modeValue, modeLeft, modeRight = settingRow(7, "Mode")

local statusLabel = UI.label({
	LayoutOrder = 8,
	Size = UDim2.new(1, 0, 0, 24),
	TextSize = 16,
	TextColor3 = UI.Colors.Muted,
	Parent = panel,
})

local currentCountdown: number? = nil

local startButton = UI.button({
	LayoutOrder = 9,
	Text = "СТАРТ",
	Size = UDim2.new(1, 0, 0, 48),
	TextSize = 22,
	Parent = panel,
}, function()
	squadAction:FireServer(if currentCountdown then "Cancel" else "Start")
end)

Remotes.get("SquadUpdate").OnClientEvent:Connect(function(view)
	panel.Visible = view ~= nil
	hintLabel.Visible = view == nil
	countdownLabel.Visible = false
	if not view then
		currentCountdown = nil
		return
	end

	currentCountdown = view.Countdown
	title.Text = `Отряд · Портал {view.Portal}`

	local lines = {}
	for i, name in view.Members do
		table.insert(lines, if i == 1 then `★ {name} (лидер)` else `• {name}`)
	end
	table.insert(lines, `{#view.Members}/{view.MaxMembers} игроков`)
	membersLabel.Text = table.concat(lines, "\n")

	chapterValue.Text = view.ChapterName
	difficultyValue.Text = `Сложность: {view.DifficultyName}`
	worldValue.Text = `Мир: {view.WorldName}`
	missionValue.Text = view.MissionName
	missionRow.Visible = view.IsStory
	modeValue.Text = if view.Mode == "Friends" then "Только друзья" else "Открытый отряд"

	for _, button in { chapterLeft, chapterRight, difficultyLeft, difficultyRight, worldLeft, worldRight, missionLeft, missionRight, modeLeft, modeRight } do
		button.Visible = view.IsLeader
	end
	startButton.Visible = view.IsLeader and not view.Launching
	startButton.Text = if view.Countdown then "ОТМЕНА" else "СТАРТ"
	startButton.BackgroundColor3 = if view.Countdown then UI.Colors.Glitch else UI.Colors.Accent

	if view.Launching then
		statusLabel.Text = "Перенос в миссию…"
		countdownLabel.Text = "ПЕРЕНОС…"
		countdownLabel.Visible = true
	elseif view.Countdown then
		statusLabel.Text = "Отряд готовится"
		countdownLabel.Text = `Старт через {view.Countdown}`
		countdownLabel.Visible = true
	elseif view.AutoStart then
		statusLabel.Text = `Автостарт через {view.AutoStart} с`
	else
		statusLabel.Text = if view.IsLeader then "Нажми «Старт», когда все готовы" else "Ждём лидера…"
	end
end)

-- Машины на подиумах автосалона медленно крутятся (только у игрока на экране)
local RunService = game:GetService("RunService")
local SHOWCASE_SPIN = 0.4 -- радиан в секунду
task.spawn(function()
	local map = workspace:WaitForChild("LobbyMap", 30)
	local garage = map and map:WaitForChild("Garage", 30)
	if not garage then
		return
	end
	RunService.RenderStepped:Connect(function(dt)
		for _, model in garage:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("Showcase") then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, SHOWCASE_SPIN * dt, 0))
			end
		end
	end)
end)
