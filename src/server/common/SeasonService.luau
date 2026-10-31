--!strict
-- Сезонный пропуск (Config.Season). Работает и в Штабе, и в Миссии.
-- Опыт сезона копится за задания (SeasonService.addXP вызывает MissionService и StoryService);
-- награды забирают в Штабе кнопкой в окне «ПРОПУСК» (событие SeasonAction "Claim").
-- Игроку ставятся атрибуты для клиента: "SeasonXP" (опыт) и "SeasonClaimed" (JSON со списком забранного,
-- "5F" — бесплатная 5-го уровня, "5P" — премиальная). Открытые скины — атрибуты "Pass_Skin_<ключ>"
-- (их проверяют SkinService и гардероб), неоновый след — "SeasonTrail".

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Common.DataService)

local TRAIL_COLOR = Color3.fromRGB(0, 230, 255)

local SeasonService = {}

local notify = Remotes.get("Notify")

local function level(xp: number): number
	return math.min(Config.Season.Levels, math.floor(xp / Config.Season.XPPerLevel))
end

-- Новый сезон — опыт и забранные награды с нуля (скины и след остаются)
local function ensureSeason(data: DataService.PlayerData)
	if data.SeasonId ~= Config.Season.Id then
		data.SeasonId = Config.Season.Id
		data.SeasonXP = 0
		data.SeasonClaimed = {}
	end
end

local function applyTrail(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not player:GetAttribute("SeasonTrail") or not root or root:FindFirstChild("SeasonTrail") then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "SeasonTrailTop"
	top.Position = Vector3.new(0, 1.2, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "SeasonTrailBottom"
	bottom.Position = Vector3.new(0, -1.2, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SeasonTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(TRAIL_COLOR, Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = 0.6
	trail.LightEmission = 1
	trail.Parent = root
end

function SeasonService.refresh(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	ensureSeason(data)
	-- Тест в Studio: атрибут "TestSeasonXP" у ServerScriptService — сразу столько опыта сезона
	local testXP = ServerScriptService:GetAttribute("TestSeasonXP")
	if RunService:IsStudio() and typeof(testXP) == "number" and data.SeasonXP < testXP then
		data.SeasonXP = testXP
	end
	player:SetAttribute("SeasonXP", data.SeasonXP)
	player:SetAttribute("SeasonClaimed", HttpService:JSONEncode(data.SeasonClaimed))
	for key in data.UnlockedSkins do
		player:SetAttribute(`Pass_Skin_{key}`, true)
	end
	player:SetAttribute("SeasonTrail", data.SeasonTrail or nil)
	applyTrail(player)
end

-- Начислить опыт сезона (из Миссии: победа, волны, побег, письма)
function SeasonService.addXP(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	ensureSeason(data)
	local before = level(data.SeasonXP)
	data.SeasonXP += math.floor(amount)
	local after = level(data.SeasonXP)
	player:SetAttribute("SeasonXP", data.SeasonXP)
	notify:FireClient(player, `+{math.floor(amount)} опыта сезона`)
	if after > before then
		notify:FireClient(player, `Уровень пропуска {after}! Забери награду в Штабе`)
	end
end

local function owns(player: Player): boolean
	return player:GetAttribute("Pass_SeasonPass") == true
end

local function claim(player: Player, levelNumber: unknown, track: unknown)
	if typeof(levelNumber) ~= "number" or (track ~= "F" and track ~= "P") then
		return
	end
	if levelNumber ~= math.floor(levelNumber) or levelNumber < 1 or levelNumber > Config.Season.Levels then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	ensureSeason(data)
	if level(data.SeasonXP) < levelNumber then
		notify:FireClient(player, "Этот уровень ещё не открыт.")
		return
	end
	if track == "P" and not owns(player) then
		notify:FireClient(player, "Премиальные награды — с пропуском сезона.")
		return
	end
	local id = `{levelNumber}{track}`
	if data.SeasonClaimed[id] then
		return
	end
	local reward = (if track == "F" then Config.Season.Free else Config.Season.Premium)[levelNumber]
	if not reward then
		return
	end
	data.SeasonClaimed[id] = true
	if reward.Kind == "Bits" and reward.Amount then
		DataService.addBits(player, reward.Amount)
	elseif reward.Kind == "Skin" and reward.Key then
		data.UnlockedSkins[reward.Key] = true
	elseif reward.Kind == "Trail" then
		data.SeasonTrail = true
	end
	notify:FireClient(player, `Получено: {reward.Name}`)
	SeasonService.refresh(player)
end

function SeasonService.start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			applyTrail(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	DataService.Loaded:Connect(SeasonService.refresh)
	for _, player in Players:GetPlayers() do
		task.spawn(SeasonService.refresh, player)
	end
	-- забирать награды можно только в Штабе
	if Workspace:GetAttribute("PlaceKind") == "Lobby" then
		Remotes.get("SeasonAction").OnServerEvent:Connect(function(player, action, levelNumber, track)
			if action == "Claim" then
				claim(player, levelNumber, track)
			end
		end)
	end
end

return SeasonService
