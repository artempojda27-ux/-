--!strict
-- Сюжет на экране (тексты — Config.Story, присылает StoryService):
--   субтитры реплик (Вега по связи, Нуль в бою) — внизу экрана, сами исчезают;
--   окно найденного осколка памяти (записи Кая);
--   уже найденные осколки в мире прячутся (их видят только те, кто ещё не нашёл);
--   в Штабе — кнопка «ПАМЯТЬ»: журнал найденных записей, а после победы над Нулём над голостолом висит значок Кая.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer
local gui = UI.screen("StoryUI")
gui.DisplayOrder = 8

local NULL_COLOR = Color3.fromRGB(150, 210, 255)
local LETTER_IDS = Config.letterIds() -- письма-зацепки: "Neon_1" … "Core_3"

---------------------------------------------------------------- Субтитры

local subtitle = UI.panel({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -170),
	Size = UDim2.new(0.55, 0, 0, 64),
	Visible = false,
	Parent = gui,
})
UI.new("UISizeConstraint", { MinSize = Vector2.new(300, 64), MaxSize = Vector2.new(720, 64), Parent = subtitle })
local speakerLabel = UI.label({
	Position = UDim2.fromOffset(14, 6),
	Size = UDim2.new(1, -28, 0, 18),
	Font = Enum.Font.GothamBlack,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = subtitle,
})
local speechLabel = UI.label({
	Position = UDim2.fromOffset(14, 26),
	Size = UDim2.new(1, -28, 1, -30),
	TextSize = 16,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = subtitle,
})
local speechId = 0

Remotes.get("Speech").OnClientEvent:Connect(function(speaker: string, text: string)
	speechId += 1
	local id = speechId
	speakerLabel.Text = speaker
	speakerLabel.TextColor3 = if speaker == "Нуль" then NULL_COLOR else UI.Colors.Accent
	speechLabel.Text = `«{text}»`
	subtitle.Visible = true
	task.delay(math.clamp(#text / 14, 4, 9), function()
		if speechId == id then
			subtitle.Visible = false
		end
	end)
end)

---------------------------------------------------------------- Окно записи

local lorePanel = UI.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.6), -- ниже больших надписей миссии («ПОБЕДА!»)
	Size = UDim2.fromOffset(460, 220),
	Visible = false,
	Parent = gui,
})
local loreTitle = UI.label({
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -32, 0, 26),
	Font = Enum.Font.GothamBlack,
	TextSize = 20,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = lorePanel,
})
local loreText = UI.label({
	Position = UDim2.fromOffset(16, 46),
	Size = UDim2.new(1, -32, 1, -104),
	TextSize = 17,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = lorePanel,
})
UI.button({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(120, 40),
	Text = "Закрыть",
	Parent = lorePanel,
}, function()
	lorePanel.Visible = false
end)

local function showLore(title: string, text: string)
	loreTitle.Text = title
	loreText.Text = text
	lorePanel.Visible = true
end

Remotes.get("Lore").OnClientEvent:Connect(showLore)

---------------------------------------------------------------- Найденные осколки прячем

local function refreshShard(model: Instance)
	local id = model:GetAttribute("ShardId")
	local found = typeof(id) == "string" and player:GetAttribute(`Shard_{id}`) == true
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = if found then 1 else 0
		elseif descendant:IsA("ProximityPrompt") then
			descendant.Enabled = not found
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Light") then
			descendant.Enabled = not found
		end
	end
end

local function refreshAllShards()
	for _, model in CollectionService:GetTagged("MemoryShard") do
		refreshShard(model)
	end
end
CollectionService:GetInstanceAddedSignal("MemoryShard"):Connect(function(model)
	task.wait() -- детали модели могут прийти чуть позже
	refreshShard(model)
end)
for _, id in LETTER_IDS do
	player:GetAttributeChangedSignal(`Shard_{id}`):Connect(refreshAllShards)
end
refreshAllShards()

---------------------------------------------------------------- Штаб: журнал и значок Кая

while Workspace:GetAttribute("PlaceKind") == nil do
	task.wait(0.2) -- сервер ставит атрибут при запуске; ждём, пока он дойдёт
end
if Workspace:GetAttribute("PlaceKind") ~= "Lobby" then
	return
end

local journal = UI.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 460, 0.75, 0),
	Visible = false,
	Parent = gui,
})
UI.new("UISizeConstraint", { MaxSize = Vector2.new(460, 520), Parent = journal })
local journalTitle = UI.label({
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -70, 0, 30),
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextColor3 = UI.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Письма и зацепки",
	Parent = journal,
})
UI.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(36, 36),
	Text = "×",
	TextSize = 24,
	Parent = journal,
}, function()
	journal.Visible = false
end)
local list = UI.new("ScrollingFrame", {
	Position = UDim2.fromOffset(12, 54),
	Size = UDim2.new(1, -24, 1, -66),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = UI.Colors.Accent,
	Parent = journal,
})
UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

local function fillJournal()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = 0
	local lastWorld = ""
	for order, id in LETTER_IDS do
		local letter = Config.getLetter(id) :: any
		local worldId, index = string.match(id, "^(%a+)_(%d+)$")
		if worldId ~= lastWorld then
			lastWorld = worldId :: string
			UI.label({
				LayoutOrder = order * 2 - 1,
				Size = UDim2.new(1, -8, 0, 22),
				Font = Enum.Font.GothamBold,
				TextSize = 15,
				TextColor3 = UI.Colors.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Config.getWorld(worldId).Name,
				Parent = list,
			})
		end
		local found = player:GetAttribute(`Shard_{id}`) == true
		if found then
			count += 1
		end
		UI.button({
			LayoutOrder = order * 2,
			Size = UDim2.new(1, -8, 0, 40),
			Text = if found then `{letter.Title} · {letter.From}` else `??? · задание {index}`,
			TextSize = 15,
			BackgroundColor3 = if found then UI.Colors.Accent else UI.Colors.Muted,
			AutoButtonColor = found,
			Parent = list,
		}, function()
			if found then
				showLore(letter.Title, letter.Text .. "\n\n— " .. letter.From)
			end
		end)
	end
	journalTitle.Text = `Письма и зацепки · {count}/{#LETTER_IDS}`
end

UI.button({
	Name = "MemoryButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 20, 0.5, 108),
	Size = UDim2.fromOffset(140, 44),
	Text = "ПИСЬМА",
	BackgroundColor3 = Color3.fromRGB(150, 210, 255),
	Parent = gui,
}, function()
	fillJournal()
	journal.Visible = not journal.Visible
	-- диалог с Вегой и журнал не должны перекрывать друг друга
	local commander = player.PlayerGui:FindFirstChild("CommanderUI")
	local dialog = commander and commander:FindFirstChildWhichIsA("Frame")
	if journal.Visible and dialog then
		dialog.Visible = false
	end
end)

-- Значок Кая над голостолом — только у тех, кто победил Нуля (виден лишь им самим)
local badge: BasePart? = nil
local function refreshBadge()
	local done = player:GetAttribute("WorldsDone")
	local show = typeof(done) == "number" and done >= #Config.Worlds
	if show and not badge then
		local disc = Instance.new("Part")
		disc.Name = "KaiBadge"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.3, 4, 4)
		disc.CFrame = CFrame.new(0, 20, 2) * CFrame.Angles(0, math.rad(90), 0)
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.Material = Enum.Material.Neon
		disc.Color = Color3.fromRGB(0, 255, 200)
		disc:SetAttribute("Spin", Vector3.new(0, 40, 0))
		disc:SetAttribute("Bob", 0.6)
		CollectionService:AddTag(disc, "Motion")
		disc.Parent = Workspace
		badge = disc
	elseif not show and badge then
		badge:Destroy()
		badge = nil
	end
end
player:GetAttributeChangedSignal("WorldsDone"):Connect(refreshBadge)
refreshBadge()
