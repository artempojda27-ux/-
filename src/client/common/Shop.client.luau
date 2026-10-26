--!strict
-- Магазин бустов: кнопка слева и окно со списком пропусков (Game Pass).
-- Покупку проводит сам Roblox, а включает буст сервер (PassService).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer

local function inMission(): boolean
	return Workspace:GetAttribute("PlaceKind") == "Mission"
end

local function buyProduct(key: string)
	local product = Config.getProduct(key)
	if not product then
		return
	end
	if not inMission() then
		UI.toast("Этот буст работает только в миссии.")
		return
	end
	if product.Id == 0 then
		if RunService:IsStudio() and Config.StudioOwnsAllPasses then
			Remotes.get("TestPurchase"):FireServer(key) -- в Studio — бесплатно, для проверки
			UI.toast(`Тест в Studio: «{product.Name}» выдан бесплатно.`)
		else
			UI.toast("Покупки заработают после публикации игры.")
		end
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
end
local gui = UI.screen("ShopUI")
gui.DisplayOrder = 10 -- окно магазина поверх остального интерфейса

local window = UI.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 480, 0.8, 0),
	Visible = false,
	Parent = gui,
})
UI.new("UISizeConstraint", { MaxSize = Vector2.new(480, 560), Parent = window })
UI.new("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = window,
})

local header = UI.new("Frame", {
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	Parent = window,
})

-- Список бустов прокручивается, если не влезает
local list = UI.new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 46),
	Size = UDim2.new(1, 0, 1, -46),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = UI.Colors.Accent,
	Parent = window,
})
UI.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
UI.label({
	Size = UDim2.new(1, -44, 1, 0),
	Font = Enum.Font.GothamBlack,
	TextSize = 24,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Читы симуляции",
	Parent = header,
})
UI.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(36, 36),
	Text = "×",
	TextSize = 24,
	Parent = header,
}, function()
	window.Visible = false
end)

local buyButtons: { [string]: TextButton } = {}

local function refresh()
	for key, button in buyButtons do
		local owned = player:GetAttribute(`Pass_{key}`) == true
		local pass = Config.getPass(key)
		button.Text = if owned then "Куплено" elseif pass then `{pass.Price} R$` else "?"
		button.Active = not owned
		button.AutoButtonColor = not owned
		button.BackgroundColor3 = if owned then UI.Colors.Muted else UI.Colors.Accent
	end
end

for index, pass in Config.GamePasses do
	local row = UI.panel({
		LayoutOrder = index,
		Size = UDim2.new(1, -10, 0, 68),
		BackgroundColor3 = Color3.fromRGB(20, 26, 34),
		Parent = list,
	})
	UI.label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -140, 0, 24),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = pass.Name,
		Parent = row,
	})
	UI.label({
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -140, 0, 32),
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = pass.Description,
		Parent = row,
	})
	buyButtons[pass.Key] = UI.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(110, 40),
		Parent = row,
	}, function()
		if player:GetAttribute(`Pass_{pass.Key}`) == true then
			return
		end
		if pass.Id == 0 then
			UI.toast("Покупки заработают после публикации игры.")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)
	player:GetAttributeChangedSignal(`Pass_{pass.Key}`):Connect(refresh)
end
refresh()

-- Разовые бусты
UI.label({
	LayoutOrder = 100,
	Size = UDim2.new(1, 0, 0, 24),
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = UI.Colors.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Разовые бусты — действуют в миссии",
	Parent = list,
})
for index, product in Config.Products do
	local row = UI.panel({
		LayoutOrder = 100 + index,
		Size = UDim2.new(1, -10, 0, 68),
		BackgroundColor3 = Color3.fromRGB(20, 26, 34),
		Parent = list,
	})
	UI.label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -140, 0, 24),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = product.Name,
		Parent = row,
	})
	UI.label({
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -140, 0, 32),
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = product.Description,
		Parent = row,
	})
	UI.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(110, 40),
		Text = `{product.Price} R$`,
		BackgroundColor3 = UI.Colors.Glitch,
		TextColor3 = UI.Colors.Text,
		Parent = row,
	}, function()
		buyProduct(product.Key)
	end)
end

-- Таймеры активных бустов под кнопкой магазина
local timers = UI.label({
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 20, 0.5, 30),
	Size = UDim2.fromOffset(240, 60),
	TextSize = 16,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextStrokeTransparency = 0.6,
	Parent = gui,
})
local TIMED = {
	{ Attribute = "InvincibleUntil", Name = "Бессмертие" },
	{ Attribute = "DamageBoostUntil", Name = "Двойной урон" },
}
task.spawn(function()
	while true do
		local lines = {}
		for _, timed in TIMED do
			local untilTime = player:GetAttribute(timed.Attribute)
			if typeof(untilTime) == "number" then
				local left = math.ceil(untilTime - Workspace:GetServerTimeNow())
				if left > 0 then
					table.insert(lines, `{timed.Name}: {left} с`)
				end
			end
		end
		timers.Text = table.concat(lines, "\n")
		task.wait(0.2)
	end
end)

-- После гибели в миссии — кнопка «Встать сразу»
local revive = Config.getProduct("Revive")
local reviveButton = UI.button({
	Name = "ReviveButton",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.6),
	Size = UDim2.fromOffset(300, 60),
	Text = if revive then `ВСТАТЬ СРАЗУ · {revive.Price} R$` else "ВСТАТЬ СРАЗУ",
	TextSize = 22,
	BackgroundColor3 = UI.Colors.Glitch,
	TextColor3 = UI.Colors.Text,
	Visible = false,
	Parent = gui,
}, function()
	buyProduct("Revive")
end)

-- Вставать имеет смысл только посреди боя: после поражения или победы кнопку прячем
local missionState = ""
local dead = false
local function refreshRevive()
	reviveButton.Visible = dead and inMission() and (missionState == "Combat" or missionState == "Break")
end
Remotes.get("MissionUpdate").OnClientEvent:Connect(function(view)
	missionState = view.State
	refreshRevive()
end)

local function watchCharacter(character: Model)
	dead = false
	refreshRevive()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		dead = true
		refreshRevive()
	end)
end
if player.Character then
	task.spawn(watchCharacter, player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

UI.button({
	Name = "ShopButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 20, 0.5, 0),
	Size = UDim2.fromOffset(140, 44),
	Text = "МАГАЗИН",
	BackgroundColor3 = UI.Colors.Glitch,
	TextColor3 = UI.Colors.Text,
	Parent = gui,
}, function()
	window.Visible = not window.Visible
end)
