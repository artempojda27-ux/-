--!strict
-- Сюжет (docs/Saga.md, тексты — Config.Commander и Config.Story). Работает и в Штабе, и в Миссии.
-- Ставит игроку атрибуты прогресса для клиента: "WorldsDone" (сколько миров пройдено — по ним Вега
-- выбирает реплики) и "Shard_<мир>" (найден ли осколок памяти). Выдаёт осколки и показывает реплики.

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
	for worldId in Config.Story.Shards do
		player:SetAttribute(`Shard_{worldId}`, data.ShardsFound[worldId] == true)
	end
end

-- Игрок подобрал осколок памяти мира worldId. true — если впервые
function StoryService.collect(player: Player, worldId: string): boolean
	local shard = Config.Story.Shards[worldId]
	local data = DataService.get(player)
	if not shard or not data then
		return false
	end
	lore:FireClient(player, shard.Title, shard.Text)
	if data.ShardsFound[worldId] then
		return false
	end
	data.ShardsFound[worldId] = true
	player:SetAttribute(`Shard_{worldId}`, true)
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
