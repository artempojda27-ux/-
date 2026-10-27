--!strict
-- Платные бусты навсегда (Game Pass). Работает и в Штабе, и в Миссии.
-- Сервер узнаёт у Roblox, куплен ли пропуск, и ставит игроку атрибут "Pass_<Key>" = true.
-- Клиент по атрибутам включает то, что видно только ему (двойной прыжок, подсветка врагов),
-- а скорость бега задаёт сервер.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local BASE_WALK_SPEED = 16
local VIP_COLOR = Color3.fromRGB(255, 190, 40)

local PassService = {}

function PassService.owns(player: Player, key: string): boolean
	return player:GetAttribute(`Pass_{key}`) == true
end

local function applySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if PassService.owns(player, "Speed")
			then BASE_WALK_SPEED * Config.SpeedBoostMultiplier
			else BASE_WALK_SPEED
	end
end

-- Значок VIP над головой и неоновый след: их видят все игроки
local function applyVip(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not PassService.owns(player, "VIP") or not head or not root or head:FindFirstChild("VipTag") then
		return
	end

	local tag = Instance.new("BillboardGui")
	tag.Name = "VipTag"
	tag.Size = UDim2.fromOffset(60, 24)
	tag.StudsOffset = Vector3.new(0, 2.6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = VIP_COLOR
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "VIP"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	label.Parent = tag
	tag.Parent = head

	local top = Instance.new("Attachment")
	top.Name = "VipTrailTop"
	top.Position = Vector3.new(0, 1, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "VipTrailBottom"
	bottom.Position = Vector3.new(0, -1, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(VIP_COLOR, Color3.fromRGB(0, 255, 200))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Parent = root
end

local function grant(player: Player, key: string)
	player:SetAttribute(`Pass_{key}`, true)
	if key == "Speed" then
		applySpeed(player)
	elseif key == "VIP" then
		applyVip(player)
	end
end

-- Все пропуски: бусты и платные скины (у скина ключ "Skin_<Key>")
local function allPasses(): { { Key: string, Id: number } }
	local list = {}
	for _, pass in Config.GamePasses do
		table.insert(list, { Key = pass.Key, Id = pass.Id })
	end
	for _, skin in Config.Skins do
		if skin.Price > 0 then
			table.insert(list, { Key = `Skin_{skin.Key}`, Id = skin.Id })
		end
	end
	return list
end

local function checkOwnership(player: Player)
	for _, pass in allPasses() do
		if RunService:IsStudio() and Config.StudioOwnsAllPasses then
			grant(player, pass.Key)
		elseif pass.Id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns then
				grant(player, pass.Key)
			elseif not ok then
				warn(`Не удалось проверить пропуск {pass.Key}: {owns}`)
			end
		end
	end
end

function PassService.start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			character:WaitForChild("Head")
			character:WaitForChild("HumanoidRootPart")
			applySpeed(player)
			applyVip(player)
		end)
		checkOwnership(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Покупка прямо в игре: включаем буст сразу, без перезахода
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, pass in allPasses() do
			if pass.Id == passId and pass.Id ~= 0 then
				grant(player, pass.Key)
			end
		end
	end)
end

return PassService
