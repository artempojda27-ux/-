--!strict
-- Гардероб в Штабе: скины-ордены борцов с Искажением (Config.Skins).
-- Купленный или бесплатный скин можно надеть, платный — купить (Game Pass). Надевает сервер (SkinService).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

local player = Players.LocalPlayer
local skinAction = Remotes.get("SkinAction")

local gui = UI.screen("WardrobeUI")
gui.DisplayOrder = 10

local window = UI.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 500, 0.8, 0),
	Visible = false,
	Parent = gui,
})
UI.new("UISizeConstraint", { MaxSize = Vector2.new(500, 600), Parent = window })
UI.new("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = window,
})

local header = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = window })
UI.label({
	Size = UDim2.new(1, -44, 1, 0),
	Font = Enum.Font.GothamBlack,
	TextSize = 24,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Ордены борцов с Искажением",
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

local buttons: { [string]: TextButton } = {}

local function owns(skin: Config.Skin): boolean
	return skin.Price == 0 or player:GetAttribute(`Pass_Skin_{skin.Key}`) == true
end

local function refresh()
	local current = player:GetAttribute("Skin") or "None"
	for key, button in buttons do
		local skin = Config.getSkin(key)
		local worn = current == key
		if worn then
			button.Text = "Надет"
			button.BackgroundColor3 = UI.Colors.Muted
		elseif key == "None" or (skin and owns(skin)) then
			button.Text = "Надеть"
			button.BackgroundColor3 = UI.Colors.Accent
		elseif skin then
			button.Text = `{skin.Price} R$`
			button.BackgroundColor3 = UI.Colors.Glitch
		end
		button.AutoButtonColor = not worn
	end
end

local function row(order: number, key: string, name: string, description: string, accent: Color3)
	local frame = UI.panel({
		LayoutOrder = order,
		Size = UDim2.new(1, -10, 0, 74),
		BackgroundColor3 = Color3.fromRGB(20, 26, 34),
		Parent = list,
	})
	-- полоска цвета ордена
	UI.new("Frame", {
		Size = UDim2.new(0, 6, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = frame,
	})
	UI.label({
		Position = UDim2.fromOffset(22, 6),
		Size = UDim2.new(1, -150, 0, 24),
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
		Parent = frame,
	})
	UI.label({
		Position = UDim2.fromOffset(22, 30),
		Size = UDim2.new(1, -150, 0, 38),
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = description,
		Parent = frame,
	})
	buttons[key] = UI.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(110, 40),
		TextColor3 = UI.Colors.Text,
		Parent = frame,
	}, function()
		if player:GetAttribute("Skin") == key then
			return
		end
		local skin = Config.getSkin(key)
		if key == "None" or (skin and owns(skin)) then
			skinAction:FireServer("Equip", key)
		elseif skin then
			if skin.Id == 0 then
				UI.toast("Покупки заработают после публикации игры.")
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, skin.Id)
		end
	end)
end

row(0, "None", "Свой облик", "Твой аватар Roblox без брони", UI.Colors.Muted)
for index, skin in Config.Skins do
	row(index, skin.Key, skin.Name, skin.Description, skin.Accent)
	player:GetAttributeChangedSignal(`Pass_Skin_{skin.Key}`):Connect(refresh)
end
player:GetAttributeChangedSignal("Skin"):Connect(refresh)
refresh()

UI.button({
	Name = "WardrobeButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 20, 0.5, 54),
	Size = UDim2.fromOffset(140, 44),
	Text = "ГАРДЕРОБ",
	Parent = gui,
}, function()
	window.Visible = not window.Visible
end)
