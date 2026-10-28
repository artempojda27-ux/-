--!strict
-- Боевой интерфейс Миссии: здоровье, слоты оружия, патроны и отметка попадания.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Weapons = require(ReplicatedStorage.Shared.Weapons)
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

local Hud = {}

-- Свои полоски вместо стандартных
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

local gui = UI.screen("CombatUI")

-- Здоровье слева внизу
local healthPanel = UI.panel({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -20),
	Size = UDim2.fromOffset(260, 56),
	Parent = gui,
})
local healthBack = UI.new("Frame", {
	Position = UDim2.fromOffset(12, 30),
	Size = UDim2.new(1, -24, 0, 14),
	BackgroundColor3 = Color3.fromRGB(40, 46, 56),
	BorderSizePixel = 0,
	Parent = healthPanel,
})
UI.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = healthBack })
local healthFill = UI.new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = UI.Colors.Accent,
	BorderSizePixel = 0,
	Parent = healthBack,
})
UI.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = healthFill })
local healthLabel = UI.label({
	Position = UDim2.fromOffset(12, 4),
	Size = UDim2.new(1, -24, 0, 24),
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Здоровье",
	Parent = healthPanel,
})

-- Патроны справа внизу
local ammoPanel = UI.panel({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.fromOffset(260, 76),
	Parent = gui,
})
local weaponLabel = UI.label({
	Position = UDim2.fromOffset(12, 4),
	Size = UDim2.new(1, -24, 0, 22),
	TextSize = 15,
	TextColor3 = UI.Colors.Muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = ammoPanel,
})
local ammoLabel = UI.label({
	Position = UDim2.fromOffset(12, 26),
	Size = UDim2.new(1, -24, 0, 44),
	Font = Enum.Font.GothamBlack,
	TextSize = 34,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = ammoPanel,
})

-- Слоты оружия по центру внизу
local slots = UI.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.fromOffset(4 * 96 + 3 * 8, 52),
	BackgroundTransparency = 1,
	Parent = gui,
})
UI.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = slots,
})
local slotFrames: { [string]: Frame } = {}
local onSlotClicked: ((weaponId: string) -> ())? = nil
for _, weapon in Weapons.List do
	local slot = UI.panel({
		LayoutOrder = weapon.Slot,
		Size = UDim2.fromOffset(96, 52),
		Parent = slots,
	})
	UI.label({
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.fromOffset(20, 20),
		TextSize = 14,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = tostring(weapon.Slot),
		Parent = slot,
	})
	UI.label({
		Position = UDim2.fromOffset(4, 18),
		Size = UDim2.new(1, -8, 0, 30),
		TextSize = 12,
		TextWrapped = true,
		Text = weapon.Name,
		Parent = slot,
	})
	-- На телефоне оружие выбирают нажатием на слот
	local button = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = slot,
	})
	button.Activated:Connect(function()
		if onSlotClicked then
			onSlotClicked(weapon.Id)
		end
	end)
	slotFrames[weapon.Id] = slot
end

-- Отметка попадания у прицела
local hitMarker = UI.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(40, 40),
	Font = Enum.Font.GothamBlack,
	TextSize = 28,
	Text = "×",
	TextTransparency = 1,
	Parent = gui,
})

-- Телефон: внизу слева — джойстик, справа — кнопки прыжка и огня; здоровье и патроны уходят наверх
if UI.isTouch then
	healthPanel.AnchorPoint = Vector2.new(0, 0)
	healthPanel.Position = UDim2.fromOffset(12, 8)
	ammoPanel.AnchorPoint = Vector2.new(1, 0)
	ammoPanel.Position = UDim2.new(1, -12, 0, 8)
	-- прицел в центре экрана: стреляют туда, куда смотрит камера
	local cross = UI.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		Font = Enum.Font.GothamBold,
		TextSize = 26,
		Text = "+",
		TextColor3 = UI.Colors.Accent,
		TextStrokeTransparency = 0.4,
		Parent = gui,
	})
	cross.Name = "Crosshair"
end

function Hud.onSlotClicked(callback: (weaponId: string) -> ())
	onSlotClicked = callback
end

function Hud.setHealth(health: number, maxHealth: number)
	local ratio = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
	healthFill.Size = UDim2.fromScale(ratio, 1)
	healthFill.BackgroundColor3 = if ratio > 0.3 then UI.Colors.Accent else UI.Colors.Glitch
	healthLabel.Text = `Здоровье {math.ceil(health)}`
end

function Hud.setWeapon(weapon: Weapons.Weapon, ammo: number?, reloading: boolean)
	weaponLabel.Text = weapon.Name
	if reloading then
		ammoLabel.Text = "ПЕРЕЗАРЯДКА"
		ammoLabel.TextSize = 22
		ammoLabel.TextColor3 = UI.Colors.Muted
	elseif weapon.MagSize then
		ammoLabel.Text = `{ammo or 0} / {weapon.MagSize}`
		ammoLabel.TextSize = 34
		ammoLabel.TextColor3 = if (ammo or 0) == 0 then UI.Colors.Glitch else UI.Colors.Text
	else
		ammoLabel.Text = "∞"
		ammoLabel.TextSize = 34
		ammoLabel.TextColor3 = UI.Colors.Text
	end
	for id, slot in slotFrames do
		local stroke = slot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = if id == weapon.Id then 0 else 0.7
			stroke.Thickness = if id == weapon.Id then 3 else 1.5
		end
	end
end

function Hud.showHit(killed: boolean)
	if UI.isTouch then
		hitMarker.Position = UDim2.fromScale(0.5, 0.5) -- на телефоне целятся центром экрана
	else
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		hitMarker.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	end
	hitMarker.TextColor3 = if killed then UI.Colors.Glitch else UI.Colors.Accent
	hitMarker.TextTransparency = 0
	TweenService:Create(hitMarker, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
end

-- Следим за здоровьем персонажа
local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	Hud.setHealth(humanoid.Health, humanoid.MaxHealth)
	humanoid.HealthChanged:Connect(function(health)
		Hud.setHealth(health, humanoid.MaxHealth)
	end)
end

local player = Players.LocalPlayer
if player.Character then
	task.spawn(watchCharacter, player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

return Hud
