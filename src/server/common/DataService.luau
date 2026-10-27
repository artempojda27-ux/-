--!strict
-- Сохранение прогресса игроков через ProfileStore.
-- Один и тот же модуль работает и в Штабе, и в Миссии: ProfileStore сам
-- передаёт «замок» на данные между серверами при переходе.

local Players = game:GetService("Players")

local ProfileStore = require(script.Parent.Packages.ProfileStore)

local TEMPLATE = {
	Bits = 0,
	SelectedHero = "Guard",
	UnlockedHeroes = { Guard = true, Bolt = true },
	SelectedSkin = "None", -- скин из Config.Skins или "None" — свой облик
	ChaptersCompleted = {} :: { [string]: boolean }, -- ключ — номер главы строкой
	MissionsCompleted = 0,
	BestWave = 0, -- рекорд в Выживании: сколько волн отряд продержался
	WorldsCompleted = {} :: { [string]: boolean }, -- в каких мирах отряд побеждал (открывает следующие)
	Purchases = {} :: { [string]: boolean }, -- PurchaseId выданных покупок, чтобы не выдать дважды
}

export type PlayerData = typeof(TEMPLATE)

local PlayerStore = ProfileStore.New("PlayerData_v1", TEMPLATE)

local profiles: { [Player]: any } = {}
local loadedEvent = Instance.new("BindableEvent")

local DataService = {}

-- Срабатывает, когда данные игрока загружены: DataService.Loaded:Connect(function(player) end)
DataService.Loaded = loadedEvent.Event

local function createLeaderstats(player: Player, data: PlayerData)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local bits = Instance.new("IntValue")
	bits.Name = "Биты"
	bits.Value = data.Bits
	bits.Parent = leaderstats

	leaderstats.Parent = player
end

local function updateLeaderstats(player: Player, data: PlayerData)
	local leaderstats = player:FindFirstChild("leaderstats")
	local bits = leaderstats and leaderstats:FindFirstChild("Биты")
	if bits and bits:IsA("IntValue") then
		bits.Value = data.Bits
	end
end

local function onPlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("Не удалось загрузить прогресс. Перезайди, пожалуйста.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Сессия завершена. Перезайди, пожалуйста.")
	end)

	if player.Parent == Players then
		profiles[player] = profile
		createLeaderstats(player, profile.Data)
		loadedEvent:Fire(player)
	else
		profile:EndSession()
	end
end

-- Данные игрока или nil, если ещё не загружены
function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Ждёт загрузки данных (до timeout секунд)
function DataService.waitFor(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.2)
	end
	return DataService.get(player)
end

function DataService.addBits(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	data.Bits = math.max(0, data.Bits + math.floor(amount))
	updateLeaderstats(player, data)
	return true
end

function DataService.completeMission(player: Player, chapterId: number, reward: number, worldId: string?): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	data.MissionsCompleted += 1
	data.ChaptersCompleted[tostring(chapterId)] = true
	data.WorldsCompleted[worldId or "Neon"] = true
	return DataService.addBits(player, reward)
end

-- Запоминает рекорд Выживания. true, если это новый рекорд
function DataService.recordWave(player: Player, waves: number): boolean
	local data = DataService.get(player)
	if not data or waves <= data.BestWave then
		return false
	end
	data.BestWave = waves
	return true
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end)

return DataService
