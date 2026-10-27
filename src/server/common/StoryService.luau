--!strict
-- Сюжет (docs/Saga.md, тексты — Config.Commander и Config.Story). Работает и в Штабе, и в Миссии.
-- Ставит игроку атрибуты прогресса для клиента: "WorldsDone" (сколько миров пройдено — по ним Вега
-- выбирает реплики), "Missions_<мир>" (сколько заданий мира пройдено) и "Shard_<мир>_<задание>"
-- (найдено ли письмо-зацепка). Выдаёт письма и показывает реплики.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Common.DataService)

local StoryService = {}

local speech = Remotes.get("Speech")
local lore = Remotes.get("Lore")

function StoryService.refresh(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local done = 0
	for _, world in Config.Worlds do
		if data.WorldsCompleted[world.Id] then
			done += 1
		end
	end
	player:SetAttribute("WorldsDone", done)
	for _, id in Config.letterIds() do
		player:SetAttribute(`Shard_{id}`, data.ShardsFound[id] == true)
	end
	for _, world in Config.Worlds do
		player:SetAttribute(`Missions_{world.Id}`, data.WorldMissions[world.Id] or 0)
	end
end

-- Игрок подобрал письмо-зацепку id ("Neon_2"). true — если впервые
function StoryService.collect(player: Player, id: string): boolean
	local letter = Config.getLetter(id)
	local data = DataService.get(player)
	if not letter or not data then
		return false
	end
	lore:FireClient(player, letter.Title, letter.Text .. "\n\n— " .. letter.From)
	if data.ShardsFound[id] then
		return false
	end
	data.ShardsFound[id] = true
	player:SetAttribute(`Shard_{id}`, true)
	return true
end

-- Реплика персонажа: всем игрокам или одному
function StoryService.say(speaker: string, text: string, player: Player?)
	if player then
		speech:FireClient(player, speaker, text)
	else
		speech:FireAllClients(speaker, text)
	end
end

function StoryService.start()
	DataService.Loaded:Connect(StoryService.refresh)
	for _, player in Players:GetPlayers() do
		task.spawn(StoryService.refresh, player)
	end
end

return StoryService
