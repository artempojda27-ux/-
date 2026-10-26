--!strict
-- Ход миссии. Два вида:
--   Сюжетная глава: ждём отряд → брифинг → бой (закрыть три сбоя, пока лезут Пиксели) →
--     победа и награда → все вместе возвращаются в Штаб.
--   Выживание: ждём отряд → брифинг → волны врагов, каждая сильнее → когда отряд пал,
--     награда за пройденные волны и рекорд → возвращение в Штаб.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Common.DataService)
local MissionStore = require(ServerScriptService.Common.MissionStore)
local PassService = require(ServerScriptService.Common.PassService)
local Teleport = require(ServerScriptService.Common.Teleport)
local DoppelgangerService = require(script.Parent.DoppelgangerService)
local EnemyService = require(script.Parent.EnemyService)
local MissionMap = require(script.Parent.MissionMap)

local RETURN_ATTEMPTS = 3
local SPAWN_RADIUS = 70 -- запасной вариант, если на карте нет точек появления врагов
local STORY_SPAWN_INTERVAL = 6 -- в сюжетной главе Пиксели лезут из открытых сбоев
local STORY_MAX_ENEMIES = 10
local DEFEAT_GRACE = 1 -- столько секунд все должны быть мертвы, чтобы засчитать поражение

type MissionState = "Waiting" | "Briefing" | "Combat" | "Break" | "Victory" | "GameOver" | "Returning"

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

-- Выживание
local wave = 0
local waveSize = 0
local waveKilled = 0
local wavesCleared = 0

local MissionService = {}

local function chapterKind(): "Story" | "Survival"
	local chapter = Config.getChapter(info.Chapter)
	return if chapter then chapter.Kind else "Story"
end

function MissionService.isSurvival(): boolean
	return chapterKind() == "Survival"
end

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
	local survival = MissionService.isSurvival()
	return {
		State = state,
		Kind = chapterKind(),
		ChapterName = if chapter then Config.chapterTitle(chapter) else "?",
		DifficultyName = if difficulty then difficulty.Name else "?",
		Objective = if survival then `Волна {wave}` else "Закройте все сбои",
		Progress = if survival then waveKilled else closedCount(),
		Total = if survival then waveSize else #nodes,
		Wave = wave,
		WavesCleared = wavesCleared,
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
		-- Тест в Studio: какую главу запускать, задаёт атрибут "TestChapter" у ServerScriptService
		local testChapter = game:GetService("ServerScriptService"):GetAttribute("TestChapter")
		if typeof(testChapter) == "number" and Config.getChapter(testChapter) then
			info.Chapter = testChapter
		end
		print(`Тестовый запуск миссии: {Config.chapterTitle(Config.getChapter(info.Chapter) :: any)}, обычная сложность`)
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

-- Множители врагов от сложности и числа игроков
local function enemyMultipliers(): (number, number, number)
	local difficulty = Config.getDifficulty(info.Difficulty)
	local squad = Config.SquadScaling[math.clamp(#Players:GetPlayers(), 1, 4)]
	local health = squad.Health * (if difficulty then difficulty.EnemyHealth else 1)
	local damage = if difficulty then difficulty.EnemyDamage else 1
	return health, damage, squad.Count
end

local function anyoneAlive(): boolean
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return true
		end
	end
	return false
end

-- Точка на земле (на полу или на укрытии) над координатами x, z
local function groundAt(x: number, z: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local map = Workspace:FindFirstChild("MissionMap")
	params.FilterDescendantsInstances = if map then { map } else {}
	local hit = Workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position else Vector3.new(x, 1, z)
end

-- Случайная точка появления врага: одна из точек карты с небольшим разбросом
local function spawnPoint(random: Random): Vector3
	local points = MissionMap.enemySpawns()
	if #points == 0 then
		local angle = random:NextNumber() * math.pi * 2
		return groundAt(math.cos(angle) * SPAWN_RADIUS, math.sin(angle) * SPAWN_RADIUS)
	end
	local point = points[random:NextInteger(1, #points)]
	return groundAt(point.X + random:NextNumber(-5, 5), point.Z + random:NextNumber(-5, 5))
end

-- Сюжетная глава: закрыть сбои, пока из открытых сбоев лезут Пиксели
local function runStory()
	closed = {}
	for _, node in nodes do
		MissionMap.setNodeActive(node, true)
	end
	setState("Combat")
	local healthMultiplier, damageMultiplier = enemyMultipliers()
	local random = Random.new()
	local lastSpawn = 0

	-- Двойник появится посреди боя; если предаст — снова откроет один из закрытых сбоев
	local delay = Config.Doppelganger.StoryDelay
	local doubleAt = os.clock() + random:NextNumber(delay[1], delay[2])
	-- Тест в Studio: атрибут "TestDoubleDelay" у ServerScriptService — через сколько секунд появится двойник
	local testDelay = ServerScriptService:GetAttribute("TestDoubleDelay")
	if RunService:IsStudio() and typeof(testDelay) == "number" then
		doubleAt = os.clock() + testDelay
	end
	local doubleTried = false
	DoppelgangerService.setBetrayHandler(function()
		local closedNodes = {}
		for node in closed do
			table.insert(closedNodes, node)
		end
		if #closedNodes > 0 then
			local node = closedNodes[random:NextInteger(1, #closedNodes)]
			closed[node] = nil
			MissionMap.setNodeActive(node, true)
			notifyAll("Двойник взломал систему: сбой снова открыт!")
			sendAll()
		end
	end)

	while closedCount() < #nodes do
		if not doubleTried and os.clock() >= doubleAt then
			doubleTried = true
			DoppelgangerService.spawn()
		end
		if os.clock() - lastSpawn >= STORY_SPAWN_INTERVAL and EnemyService.aliveCount() < STORY_MAX_ENEMIES then
			lastSpawn = os.clock()
			for _, node in nodes do
				if not closed[node] then
					local spot = groundAt(node.Position.X + random:NextNumber(-5, 5), node.Position.Z + random:NextNumber(-5, 5))
					EnemyService.spawn("Pixel", spot, healthMultiplier, damageMultiplier)
				end
			end
		end
		task.wait(0.25)
	end
	EnemyService.clear()
	DoppelgangerService.clear()
end

-- Какой враг появится: сначала только Пиксели, потом Стрелки, потом Блоки
local function pickKind(waveNumber: number, random: Random): string
	local roll = random:NextNumber()
	if waveNumber >= 3 and roll < 0.12 + 0.01 * waveNumber then
		return "Block"
	elseif waveNumber >= 2 and roll < 0.35 then
		return "Shooter"
	end
	return "Pixel"
end

-- Одна волна. false, если отряд пал
local function runWave(random: Random): boolean
	local healthMultiplier, damageMultiplier, countMultiplier = enemyMultipliers()
	healthMultiplier *= 1 + Config.Survival.HealthGrowth * (wave - 1)
	local base = Config.Survival.FirstWaveSize + Config.Survival.WaveGrowth * (wave - 1)
	waveSize = math.max(1, math.floor(base * countMultiplier + 0.5))
	waveKilled = 0
	setState("Combat")
	if wave % Config.Doppelganger.SurvivalEvery == 0 then
		DoppelgangerService.spawn()
	end

	local spawned = 0
	local lastSpawn = 0
	local deadSince: number? = nil
	local connection = EnemyService.Died:Connect(function()
		waveKilled += 1
		sendAll()
	end)

	while true do
		local now = os.clock()
		if spawned < waveSize and now - lastSpawn >= Config.Survival.SpawnInterval
			and EnemyService.aliveCount() < Config.Survival.MaxAlive then
			lastSpawn = now
			spawned += 1
			EnemyService.spawn(pickKind(wave, random), spawnPoint(random), healthMultiplier, damageMultiplier)
		end
		if spawned >= waveSize and EnemyService.aliveCount() == 0 then
			connection:Disconnect()
			return true
		end
		if anyoneAlive() then
			deadSince = nil
		elseif not deadSince then
			deadSince = now
		elseif now - deadSince >= DEFEAT_GRACE then
			connection:Disconnect()
			return false
		end
		task.wait(0.1)
	end
end

local function runSurvival()
	local random = Random.new()
	wave = 0
	wavesCleared = 0
	while true do
		wave += 1
		local survived = runWave(random)
		if not survived then
			break
		end
		wavesCleared = wave
		notifyAll(`Волна {wave} пройдена!`)
		setState("Break")
		countdown(Config.Survival.BreakTime)
	end
	EnemyService.clear()
	DoppelgangerService.clear()
end

local function rewardMultiplier(player: Player): (number, boolean)
	local difficulty = Config.getDifficulty(info.Difficulty)
	local multiplier = if difficulty then difficulty.RewardMultiplier else 1
	local vip = PassService.owns(player, "VIP")
	return if vip then multiplier * Config.VipRewardMultiplier else multiplier, vip
end

local function giveStoryRewards()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			local multiplier, vip = rewardMultiplier(player)
			local reward = math.floor(Config.MissionReward * multiplier)
			if DataService.waitFor(player, 10) and DataService.completeMission(player, info.Chapter, reward) then
				notify:FireClient(player, if vip then `Награда: +{reward} бит (x2 VIP)` else `Награда: +{reward} бит`)
			end
		end)
	end
end

local function giveSurvivalRewards()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			local multiplier, vip = rewardMultiplier(player)
			local reward = math.floor(Config.Survival.RewardPerWave * wavesCleared * multiplier)
			if not DataService.waitFor(player, 10) then
				return
			end
			if reward > 0 and DataService.addBits(player, reward) then
				notify:FireClient(player, if vip then `Награда: +{reward} бит (x2 VIP)` else `Награда: +{reward} бит`)
			end
			if DataService.recordWave(player, wavesCleared) then
				notify:FireClient(player, `Новый рекорд: {wavesCleared} волн!`)
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

-- Возрождает погибших (после поражения в Выживании, перед новой попыткой)
local function respawnDead()
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			player:LoadCharacter()
		end
	end
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

			if MissionService.isSurvival() then
				runSurvival()
				setState("GameOver")
				notifyAll(`Отряд пал. Пройдено волн: {wavesCleared}`)
				giveSurvivalRewards()
			else
				runStory()
				setState("Victory")
				notifyAll("Сектор очищен!")
				giveStoryRewards()
			end
			countdown(Config.ReturnDelay)

			if returnToLobby() then
				break
			end
			-- Перенос недоступен (например, тест в Studio) — играем снова
			respawnDead()
			if not RunService:IsStudio() then
				task.wait(5)
			end
		end
	end)
end

return MissionService
