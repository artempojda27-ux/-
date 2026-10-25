--!strict
-- Ход миссии: ждём отряд → брифинг → бой (пока: закрыть три сбоя) →
-- победа и награда → все вместе возвращаются в Штаб.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Common.DataService)
local MissionStore = require(ServerScriptService.Common.MissionStore)
local Teleport = require(ServerScriptService.Common.Teleport)
local MissionMap = require(script.Parent.MissionMap)

local RETURN_ATTEMPTS = 3

type MissionState = "Waiting" | "Briefing" | "Combat" | "Victory" | "Returning"

local notify = Remotes.get("Notify")
local missionUpdate = Remotes.get("MissionUpdate")

local info: MissionStore.MissionInfo = {
	Chapter = Config.Chapters[1].Id,
	Difficulty = Config.Difficulties[1].Id,
	Members = {},
}
local state: MissionState = "Waiting"
local timer: number? = nil -- секунд до следующего этапа
local nodes: { BasePart } = {}
local closed: { [BasePart]: boolean } = {}

local MissionService = {}

local function closedCount(): number
	local count = 0
	for _ in closed do
		count += 1
	end
	return count
end

local function snapshot()
	local chapter = Config.getChapter(info.Chapter)
	local difficulty = Config.getDifficulty(info.Difficulty)
	return {
		State = state,
		ChapterName = if chapter then `Глава {chapter.Id}: {chapter.Name}` else "?",
		DifficultyName = if difficulty then difficulty.Name else "?",
		Objective = "Закройте все сбои",
		Progress = closedCount(),
		Total = #nodes,
		Timer = timer,
	}
end

local function sendAll()
	missionUpdate:FireAllClients(snapshot())
end

local function notifyAll(text: string)
	notify:FireAllClients(text)
end

local function setState(newState: MissionState, newTimer: number?)
	state = newState
	timer = newTimer
	sendAll()
end

local function countdown(seconds: number)
	for left = seconds, 1, -1 do
		timer = left
		sendAll()
		task.wait(1)
	end
	timer = nil
end

local function isReservedServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function loadInfo()
	if not isReservedServer() then
		print("Тестовый запуск миссии: глава 1, обычная сложность")
		return
	end
	local loaded = MissionStore.load(game.PrivateServerId)
	if loaded then
		info = loaded
	else
		warn("Не нашли настройки миссии, запускаем по умолчанию")
	end
end

local function waitForSquad()
	setState("Waiting")
	local deadline = os.clock() + Config.MissionWaitForSquad
	while os.clock() < deadline do
		local present = #Players:GetPlayers()
		local expected = math.max(#info.Members, 1)
		if present >= expected then
			break
		end
		task.wait(0.5)
	end
	-- Хотя бы один игрок должен быть на сервере
	while #Players:GetPlayers() == 0 do
		task.wait(0.5)
	end
end

local function runCombat()
	closed = {}
	for _, node in nodes do
		MissionMap.setNodeActive(node, true)
	end
	setState("Combat")
	while closedCount() < #nodes do
		task.wait(0.25)
	end
end

local function giveRewards()
	local difficulty = Config.getDifficulty(info.Difficulty)
	local multiplier = if difficulty then difficulty.RewardMultiplier else 1
	local reward = math.floor(Config.MissionReward * multiplier)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			if DataService.waitFor(player, 10) and DataService.completeMission(player, info.Chapter, reward) then
				notify:FireClient(player, `Награда: +{reward} бит`)
			end
		end)
	end
end

-- true, если игроков отправили в Штаб
local function returnToLobby(): boolean
	local available, reason = Teleport.check(Config.PlaceIds.Lobby)
	if not available then
		notifyAll(`{reason} Миссия начнётся заново.`)
		return false
	end
	setState("Returning")
	for _ = 1, RETURN_ATTEMPTS do
		local players = Players:GetPlayers()
		if #players == 0 then
			return true
		end
		if Teleport.send(Config.PlaceIds.Lobby, players) then
			return true
		end
		notifyAll("Не получилось вернуться в Штаб, пробуем ещё раз…")
		task.wait(5)
	end
	return false
end

local function onNodeTriggered(node: BasePart, player: Player)
	if state ~= "Combat" or closed[node] then
		return
	end
	closed[node] = true
	MissionMap.setNodeActive(node, false)
	notifyAll(`{player.DisplayName} закрыл сбой`)
	sendAll()
end

function MissionService.start()
	nodes = MissionMap.setup()
	for _, node in nodes do
		MissionMap.setNodeActive(node, false)
		local prompt = node:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				onNodeTriggered(node, player)
			end)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		missionUpdate:FireClient(player, snapshot())
	end)

	loadInfo()

	task.spawn(function()
		while true do
			waitForSquad()

			setState("Briefing")
			countdown(Config.BriefingTime)

			runCombat()

			setState("Victory")
			notifyAll("Сектор очищен!")
			giveRewards()
			countdown(Config.ReturnDelay)

			if returnToLobby() then
				break
			end
			-- Перенос недоступен (например, тест в Studio) — играем снова
			if not RunService:IsStudio() then
				task.wait(5)
			end
		end
	end)
end

return MissionService
