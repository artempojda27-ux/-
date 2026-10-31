--!strict
-- Окно сезонного пропуска в Штабе (кнопка «ПРОПУСК»). Вверху — уровень и полоска опыта, кнопка покупки
-- премиума; ниже — лента уровней: у каждого бесплатная награда (сверху) и премиальная (снизу).
-- Нажал на открытую награду — сервер её выдаёт (SeasonService). Данные — атрибуты игрока от сервера.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

local player = Players.LocalPlayer
local seasonAction = Remotes.get("SeasonAction")
local season = Config.Season

local GOLD = Color3.fromRGB(255, 200, 60)
local CARD = 104

local gui = UI.screen("SeasonUI")
gui.DisplayOrder = 10

local window = UI.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.9, 0, 0, 380),
	Visible = false,
	Parent = gui,
})
UI.new("UISizeConstraint", { MaxSize = Vector2.new(980, 380), Parent = window })

UI.label({
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -260, 0, 30),
	Font = Enum.Font.GothamBlack,
	TextSize = 24,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = season.Name,
	Parent = window,
})
local levelLabel = UI.label({
	Position = UDim2.fromOffset(16, 44),
	Size = UDim2.new(0, 300, 0, 22),
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = window,
})
local barBack = UI.new("Frame", {
	Position = UDim2.fromOffset(16, 70),
	Size = UDim2.new(1, -260, 0, 10),
	BackgroundColor3 = Color3.fromRGB(40, 46, 56),
	BorderSizePixel = 0,
	Parent = window,
})
UI.new("UICorner", { CornerRadius = UDim.new(0, 5), Parent = barBack })
local barFill = UI.new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = UI.Colors.Accent,
	BorderSizePixel = 0,
	Parent = barBack,
})
UI.new("UICorner", { CornerRadius = UDim.new(0, 5), Parent = barFill })

local buyButton = UI.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -60, 0, 14),
	Size = UDim2.fromOffset(180, 56),
	TextSize = 15,
	TextWrapped = true,
	BackgroundColor3 = GOLD,
	Parent = window,
}, function()
	if player:GetAttribute("Pass_SeasonPass") then
		return
	end
	local pass = Config.getPass("SeasonPass")
	if not pass or pass.Id == 0 then
		UI.toast("Покупки заработают, когда пропуск появится в Creator Hub.")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end)
UI.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(36, 36),
	Text = "×",
	TextSize = 24,
	Parent = window,
}, function()
	window.Visible = false
end)

-- подписи рядов (слева от ленты)
UI.label({
	Position = UDim2.fromOffset(12, 159),
	Size = UDim2.fromOffset(92, 18),
	TextSize = 13,
	TextColor3 = UI.Colors.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Бесплатно",
	Parent = window,
})
UI.label({
	Position = UDim2.fromOffset(12, 261),
	Size = UDim2.fromOffset(92, 18),
	TextSize = 13,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Премиум",
	Parent = window,
})

local track = UI.new("ScrollingFrame", {
	Position = UDim2.fromOffset(108, 98),
	Size = UDim2.new(1, -120, 1, -106),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	CanvasSize = UDim2.fromOffset(season.Levels * (CARD + 8), 0),
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = UI.Colors.Accent,
	Parent = window,
})

type Card = { Button: TextButton, Stroke: UIStroke }
local cards: { [string]: Card } = {}

local function rewardText(reward: Config.SeasonReward): string
	if reward.Kind == "Skin" then
		return `СКИН\n{reward.Name:gsub("Скин ", "")}`
	elseif reward.Kind == "Trail" then
		return "НЕОНОВЫЙ\nСЛЕД"
	end
	return `{reward.Amount}\nбит`
end

for levelNumber = 1, season.Levels do
	local x = (levelNumber - 1) * (CARD + 8)
	UI.label({
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.fromOffset(CARD, 18),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Text = `Уровень {levelNumber}`,
		Parent = track,
	})
	for row, key in { "F", "P" } do
		local reward = (if key == "F" then season.Free else season.Premium)[levelNumber]
		local button = UI.button({
			Position = UDim2.fromOffset(x, if row == 1 then 22 else 124),
			Size = UDim2.fromOffset(CARD, 96),
			Text = rewardText(reward),
			TextSize = if reward.Kind == "Bits" then 15 else 12,
			TextWrapped = true,
			BackgroundColor3 = Color3.fromRGB(24, 30, 40),
			TextColor3 = if reward.Kind == "Bits" then UI.Colors.Text else (if key == "P" then GOLD else UI.Colors.Accent),
			Parent = track,
		}, function()
			seasonAction:FireServer("Claim", levelNumber, key)
		end)
		local stroke = UI.new("UIStroke", { Thickness = 2, Parent = button })
		cards[`{levelNumber}{key}`] = { Button = button, Stroke = stroke }
	end
end

local function refresh()
	local xp = player:GetAttribute("SeasonXP")
	xp = if typeof(xp) == "number" then xp else 0
	local level = math.min(season.Levels, math.floor(xp / season.XPPerLevel))
	local inLevel = if level >= season.Levels then season.XPPerLevel else xp % season.XPPerLevel
	levelLabel.Text = if level >= season.Levels
		then `Уровень {level} — максимум!`
		else `Уровень {level} · до следующего {season.XPPerLevel - inLevel} опыта`
	barFill.Size = UDim2.fromScale(inLevel / season.XPPerLevel, 1)
	local premium = player:GetAttribute("Pass_SeasonPass") == true
	local pass = Config.getPass("SeasonPass")
	buyButton.Text = if premium then "ПРЕМИУМ\nАКТИВЕН" else `ПРЕМИУМ\n{pass and pass.Price or "?"} R$`
	local claimedRaw = player:GetAttribute("SeasonClaimed")
	local ok, claimed = pcall(HttpService.JSONDecode, HttpService, if typeof(claimedRaw) == "string" then claimedRaw else "{}")
	claimed = if ok and typeof(claimed) == "table" then claimed else {}
	for id, card in cards do
		local cardLevel = tonumber(string.match(id, "^(%d+)")) :: number
		local isPremium = string.sub(id, -1) == "P"
		local open = cardLevel <= level and (not isPremium or premium)
		if claimed[id] then
			card.Stroke.Color = UI.Colors.Muted
			card.Stroke.Transparency = 0.6
			card.Button.BackgroundTransparency = 0.6
			card.Button.AutoButtonColor = false
		elseif open then
			card.Stroke.Color = if isPremium then GOLD else UI.Colors.Accent
			card.Stroke.Transparency = 0
			card.Button.BackgroundTransparency = 0
			card.Button.AutoButtonColor = true
		else
			card.Stroke.Color = Color3.fromRGB(70, 76, 90)
			card.Stroke.Transparency = 0.3
			card.Button.BackgroundTransparency = 0.35
			card.Button.AutoButtonColor = false
		end
	end
end

for _, name in { "SeasonXP", "SeasonClaimed", "Pass_SeasonPass" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

UI.button({
	Name = "SeasonButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 20, 0.5, -54),
	Size = UDim2.fromOffset(140, 44),
	Text = "ПРОПУСК",
	BackgroundColor3 = GOLD,
	Parent = gui,
}, function()
	refresh()
	window.Visible = not window.Visible
	-- прокрутить к текущему уровню
	local xp = player:GetAttribute("SeasonXP")
	local level = math.floor((if typeof(xp) == "number" then xp else 0) / season.XPPerLevel)
	track.CanvasPosition = Vector2.new(math.max(0, (level - 2) * (CARD + 8)), 0)
end)
