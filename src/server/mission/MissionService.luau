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
local EscapeMap = require(script.Parent.EscapeMap)
local VehicleService = require(ServerScriptService.Common.VehicleService)
local BossService = require(script.Parent.BossService)
local CitySkins = require(script.Parent.CitySkins)
local CityLife = require(ServerScriptService.Common.CityLife)
local CodeLeaks = require(script.Parent.CodeLeaks)
local MemoryShards = require(script.Parent.MemoryShards)
local StoryService = require(ServerScriptService.Common.StoryService)
local WorldDetails = require(script.Parent.WorldDetails)
local WorldLook = require(script.Parent.WorldLook)
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

-- Побег
local course: EscapeMap.Course? = nil
local escapeProgress = 0 -- сколько студов прошёл лучший из отряда
local boss: { [string]: any }? = nil -- полоска здоровья Нуля в финальном бою (BossService)

local MissionService = {}

local function chapterKind(): "Story" | "Survival" | "Escape"
	local chapter = Config.getChapter(info.Chapter)
	return if chapter then chapter.Kind else "Story"
end

function MissionService.isSurvival(): boolean
	return chapterKind() == "Survival"
end

function MissionService.isEscape(): boolean
	return chapterKind() == "Escape"
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
	local kind = chapterKind()
	local objective, progress, total
	if kind == "Survival" then
		objective, progress, total = `Волна {wave}`, waveKilled, waveSize
	elseif kind == "Escape" then
		objective, progress, total = "Уйдите от вируса! Пройдено", escapeProgress, Config.Escape.Length
	elseif boss and not boss.Shield then
		objective, progress, total = "Победите Нуля", boss.Health, boss.MaxHealth
	else
		objective, progress, total = "Закройте все сбои", closedCount(), #nodes
	end
	return {
		State = state,
		Kind = kind,
		ChapterName = if chapter
			then (if info.World and info.World ~= Config.Worlds[1].Id
				then `{Config.chapterTitle(chapter)} · {Config.getWorld(info.World).Name}`
				else Config.chapterTitle(chapter))
			else "?",
		DifficultyName = if difficulty then difficulty.Name else "?",
		Objective = objective,
		Progress = progress,
		Total = total,
		Wave = wave,
		WavesCleared = wavesCleared,
		Timer = timer,
		Boss = boss,
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
		-- и в каком мире — атрибут "TestWorld" (например, "Mirror")
		local testWorld = game:GetService("ServerScriptService"):GetAttribute("TestWorld")
		if typeof(testWorld) == "string" then
			info.World = Config.getWorld(testWorld).Id
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
	local world = Config.getWorld(info.World)
	local health = squad.Health * (if difficulty then difficulty.EnemyHealth else 1) * world.EnemyHealth
	local damage = (if difficulty then difficulty.EnemyDamage else 1) * world.EnemyDamage
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
	local doubleAt = os.clock() + random:NextNumber(delay[1], delay[2]) / Config.getWorld(info.World).DoubleRate
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

-- Финал в мире «Ядро»: после сбоев — бой с Нулём. true — победа
local function isBossFight(): boolean
	return chapterKind() == "Story" and Config.getWorld(info.World).Id == "Core"
end

local function runBoss(): boolean
	setState("Combat") -- в тесте без сбоев бой начинается сразу с Нуля
	local healthMultiplier, damageMultiplier = enemyMultipliers()
	return BossService.run({
		HealthMultiplier = healthMultiplier,
		DamageMultiplier = damageMultiplier,
		GroundAt = groundAt,
		Notify = notifyAll,
		Say = StoryService.say,
		DropShard = function(position)
			MemoryShards.place("Core", groundAt(position.X, position.Z))
		end,
		Update = function(view)
			boss = view
			sendAll()
		end,
		OpenNodes = function()
			closed = {}
			for _, node in nodes do
				MissionMap.setNodeActive(node, true)
			end
			sendAll()
		end,
		OpenNodeCount = function()
			return #nodes - closedCount()
		end,
	})
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
	local every = math.max(1, math.floor(Config.Doppelganger.SurvivalEvery / Config.getWorld(info.World).DoubleRate + 0.5))
	if wave % every == 0 then
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

local function giveStoryRewards(bonus: number?)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			local multiplier, vip = rewardMultiplier(player)
			local reward = math.floor(Config.MissionReward * multiplier * (bonus or 1))
			if DataService.waitFor(player, 10) and DataService.completeMission(player, info.Chapter, reward, info.World) then
				StoryService.refresh(player)
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

-- Побег: отряд садится в машины и уходит по трассе от стены вируса
local function seatInVehicle(player: Player, model: Model): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	for _, seatName in { "DriverSeat", "Seat2", "Seat3", "Seat4" } do
		local seat = model:FindFirstChild(seatName)
		if seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and not seat.Occupant then
			character:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
			seat:Sit(humanoid)
			return true
		end
	end
	return false
end

local function runEscape(): boolean
	local escapeCourse = course :: EscapeMap.Course
	local settings = Config.Escape
	escapeProgress = 0
	local players = Players:GetPlayers()

	-- По машине на каждые четыре игрока; первый в четвёрке — водитель
	local spotIndex = 1
	for first = 1, #players, 4 do
		local spot = escapeCourse.VehicleSpots[spotIndex] or escapeCourse.VehicleSpots[1]
		spotIndex += 1
		local model = VehicleService.spawnFor(players[first], settings.Vehicle, spot)
		if model then
			task.wait(0.2)
			for i = first, math.min(first + 3, #players) do
				seatInVehicle(players[i], model)
			end
		end
	end

	-- Погибший возрождается сразу на свободном месте в машине отряда
	local respawnConnections = {}
	for _, player in Players:GetPlayers() do
		table.insert(respawnConnections, player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait(0.3)
			for _, model in VehicleService.all() do
				if seatInVehicle(player, model) then
					return
				end
			end
		end))
	end

	-- Стена вируса
	local wall = Instance.new("Part")
	wall.Name = "VirusWall"
	wall.Anchored = true
	wall.CanCollide = false
	wall.CanQuery = false
	wall.CanTouch = false
	wall.Material = Enum.Material.Neon
	wall.Color = Color3.fromRGB(255, 40, 120)
	wall.Transparency = 0.35
	wall.Size = Vector3.new(90, 80, 4)
	local wallZ = escapeCourse.Start + 70
	wall.Position = Vector3.new(0, 40, wallZ)
	wall.Parent = Workspace

	setState("Combat")
	local healthMultiplier, damageMultiplier = enemyMultipliers()
	local spawnedSpots: { [number]: boolean } = {}
	local started = os.clock()
	local last = started
	local lastSend = 0
	local deadSince: number? = nil
	local escaped = false

	while true do
		task.wait(0.1)
		local now = os.clock()
		local dt = now - last
		last = now
		local elapsed = now - started

		-- Стена трогается после форы и разгоняется
		if elapsed > settings.WallDelay then
			local speed = math.min(settings.WallMaxSpeed, settings.WallSpeed + settings.WallAcceleration * (elapsed - settings.WallDelay))
			wallZ -= speed * dt
			wall.Position = Vector3.new(0, 40, wallZ)
		end

		-- Кого догнала стена — гибнет; машины за стеной исчезают
		local leader = math.huge
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
				if root.Position.Z > wallZ - 2 then
					humanoid.Health = 0
				else
					leader = math.min(leader, root.Position.Z)
				end
			end
		end
		for _, model in VehicleService.all() do
			if model:GetPivot().Position.Z > wallZ + 4 then
				VehicleService.despawn(model)
			end
		end

		if leader < math.huge then
			escapeProgress = math.clamp(math.floor(escapeCourse.Start - leader), 0, settings.Length)
			if leader <= escapeCourse.Finish then
				escaped = true
				break
			end
			-- Враги у обочин появляются впереди отряда
			for index, spot in escapeCourse.EnemySpots do
				if not spawnedSpots[index] and leader - spot.Z < settings.EnemyAhead then
					spawnedSpots[index] = true
					EnemyService.spawn(if index % 3 == 0 then "Pixel" else "Shooter", spot, healthMultiplier, damageMultiplier)
				end
			end
		end

		-- Поражение: все мертвы и возродиться некуда
		if anyoneAlive() then
			deadSince = nil
		elseif not deadSince then
			deadSince = now
		elseif now - deadSince >= DEFEAT_GRACE + 1 and #VehicleService.all() == 0 then
			break
		end

		if now - lastSend > 0.5 then
			lastSend = now
			sendAll()
		end
	end

	for _, connection in respawnConnections do
		connection:Disconnect()
	end
	wall:Destroy()
	EnemyService.clear()
	VehicleService.clear()
	sendAll()
	return escaped
end

local function giveEscapeRewards()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			local multiplier, vip = rewardMultiplier(player)
			local reward = math.floor(Config.MissionReward * Config.Escape.RewardMultiplier * multiplier)
			if DataService.waitFor(player, 10) and DataService.completeMission(player, info.Chapter, reward, info.World) then
				notify:FireClient(player, if vip then `Награда: +{reward} бит (x2 VIP)` else `Награда: +{reward} бит`)
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
	loadInfo()
	if MissionService.isEscape() then
		course = EscapeMap.setup()
		WorldLook.apply(Config.getWorld(info.World).Id, nil)
	else
		nodes = MissionMap.setup()
		-- сначала детальные здания мира, потом живой город, свет и убранство, а трещины с кодом — поверх всего
		local worldId = Config.getWorld(info.World).Id
		local map = Workspace:FindFirstChild("MissionMap") :: Instance
		CitySkins.apply(worldId, map)
		if worldId == "Neon" or worldId == "Mirror" then
			CityLife.apply(map)
		end
		WorldLook.apply(worldId, map)
		WorldDetails.apply(worldId, map)
		CodeLeaks.apply(worldId, map)
		-- осколок памяти (запись Кая); в Ядре он выпадает из Нуля после победы
		if worldId ~= "Core" then
			MemoryShards.hide(worldId, groundAt)
		end
	end
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

	task.spawn(function()
		while true do
			waitForSquad()

			setState("Briefing")
			local briefing = Config.Story.Briefings[Config.getWorld(info.World).Id]
			if briefing and not MissionService.isEscape() then
				StoryService.say("Вега (связь)", briefing)
			end
			countdown(Config.BriefingTime)

			if MissionService.isEscape() then
				if runEscape() then
					setState("Victory")
					notifyAll("Отряд вырвался из сектора!")
					giveEscapeRewards()
				else
					setState("GameOver")
					notifyAll(`Вирус догнал отряд. Пройдено {math.floor(escapeProgress / Config.Escape.Length * 100)}% пути`)
				end
			elseif MissionService.isSurvival() then
				runSurvival()
				setState("GameOver")
				notifyAll(`Отряд пал. Пройдено волн: {wavesCleared}`)
				giveSurvivalRewards()
			else
				-- Тест в Studio: атрибут "TestBoss" у ServerScriptService — сразу к Нулю, без сбоев
				local skipNodes = RunService:IsStudio() and ServerScriptService:GetAttribute("TestBoss") == true and isBossFight()
				if not skipNodes then
					runStory()
				end
				if isBossFight() and not runBoss() then
					setState("GameOver")
				else
					setState("Victory")
					notifyAll(if isBossFight() then "Ядро свободно. Сезон «Трещина» пройден!" else "Сектор очищен!")
					giveStoryRewards(if isBossFight() then Config.BossRewardMultiplier else 1)
				end
			end
			-- после победы над Нулём — время подобрать значок Кая и дослушать Вегу
			countdown(if isBossFight() and state == "Victory" then Config.ReturnDelay * 3 else Config.ReturnDelay)

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
