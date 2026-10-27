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
local VegaClone = require(script.Parent.VegaClone)
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
-- задача на экране для заданий «Удержать канал» и «Охота за данными» (nil — обычная)
local objectiveView: { Text: string, Progress: number, Total: number }? = nil
local failTitle: string? = nil -- заголовок поражения в сюжетной главе

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

-- Текущее задание в мире (Config.Missions)
local function currentMission(): Config.Mission
	return Config.getMission(Config.getWorld(info.World).Id, info.Mission)
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
	elseif objectiveView then
		objective, progress, total = objectiveView.Text, objectiveView.Progress, objectiveView.Total
	else
		objective, progress, total = "Закройте все сбои", closedCount(), #nodes
	end
	return {
		State = state,
		Kind = kind,
		ChapterName = if chapter
			then (if kind == "Story"
				then `{Config.getWorld(info.World).Name} · Задание {currentMission().Index}/{#Config.Missions}: {currentMission().Name}`
				elseif info.World and info.World ~= Config.Worlds[1].Id
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
		FailTitle = failTitle,
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
		-- и какое задание — атрибут "TestMission" (1–3)
		local testMission = game:GetService("ServerScriptService"):GetAttribute("TestMission")
		if typeof(testMission) == "number" then
			info.Mission = testMission
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
	-- каждое следующее задание в мире тяжелее (Config.Missions[].Power)
	local power = if chapterKind() == "Story" then currentMission().Power else 1
	local health = squad.Health * (if difficulty then difficulty.EnemyHealth else 1) * world.EnemyHealth * power
	local damage = (if difficulty then difficulty.EnemyDamage else 1) * world.EnemyDamage * power
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
	return chapterKind() == "Story" and currentMission().Kind == "Boss"
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
			MemoryShards.place(`Core_{currentMission().Index}`, groundAt(position.X, position.Z))
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

-- Задание «Удержать канал»: клон Веги в центре держит связь со Штабом, враги лезут волнами
-- и атакуют её наравне с игроками. true — продержались, false — клон стёрт
local function runDefend(): boolean
	setState("Combat")
	local healthMultiplier, damageMultiplier = enemyMultipliers()
	local random = Random.new()
	local clone = VegaClone.spawn(groundAt(0, 8), Vector3.new(0, 0, 40), Config.Story.CloneHints[2],
		math.floor(Config.DefendCloneHealth * math.max(1, healthMultiplier)))
	local humanoid = clone:FindFirstChildOfClass("Humanoid") :: Humanoid
	EnemyService.setDecoy(clone)
	notifyAll("Защищайте клона Веги, пока идёт передача!")

	local total = Config.DefendTime
	local started = os.clock()
	local lastSpawn = 0
	local doubled = false
	local result = false
	while true do
		local elapsed = os.clock() - started
		local health = math.max(0, math.ceil(humanoid.Health / humanoid.MaxHealth * 100))
		objectiveView = { Text = `Удержите канал · клон {health}%`, Progress = math.floor(elapsed), Total = total }
		if humanoid.Health <= 0 then
			break
		end
		if elapsed >= total then
			result = true
			break
		end
		-- волна каждые 5 секунд, к концу передачи — всё злее
		if os.clock() - lastSpawn >= 5 and EnemyService.aliveCount() < 14 then
			lastSpawn = os.clock()
			local wave = 2 + math.floor(elapsed / 25)
			for _ = 1, wave do
				EnemyService.spawn(pickKind(1 + math.floor(elapsed / 20), random), spawnPoint(random), healthMultiplier, damageMultiplier)
			end
		end
		if not doubled and elapsed > total * 0.4 then
			doubled = true
			DoppelgangerService.spawn()
		end
		sendAll()
		task.wait(0.5)
	end
	EnemyService.setDecoy(nil)
	EnemyService.clear()
	DoppelgangerService.clear()
	objectiveView = nil
	clone:Destroy()
	if result then
		notifyAll("Передача завершена! Клон Веги успел")
	else
		failTitle = "КЛОН ВЕГИ СТЁРТ"
		notifyAll("Вирус стёр клона Веги. Канал потерян")
	end
	return result
end

-- Задание «Охота за данными»: по городу раскиданы осколки данных; каждый поднятый будит врагов рядом.
-- Когда собраны все, на площадь приходит Страж данных — крепкий Блок. Победа — когда Страж пал
local function runHunt()
	setState("Combat")
	local healthMultiplier, damageMultiplier = enemyMultipliers()
	local random = Random.new()
	local total = Config.HuntFragments
	local found = 0
	local folder = Instance.new("Folder")
	folder.Name = "DataFragments"
	folder.Parent = Workspace
	local streets = { -90, -30, 30, 90 }
	for i = 1, total do
		local street = streets[random:NextInteger(1, #streets)]
		local along = random:NextNumber(-110, 110)
		local x, z = street + random:NextNumber(-4, 4), along
		if i % 2 == 0 then
			x, z = z, x
		end
		local spot = groundAt(x, z)
		local cube = Instance.new("Part")
		cube.Name = "DataFragment"
		cube.Size = Vector3.one * 1.6
		cube.CFrame = CFrame.new(spot + Vector3.new(0, 2.5, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		cube.Anchored = true
		cube.CanCollide = false
		cube.Material = Enum.Material.Neon
		cube.Color = Color3.fromRGB(255, 200, 60)
		cube:SetAttribute("Spin", Vector3.new(40, 80, 0))
		cube:SetAttribute("Bob", 0.5)
		game:GetService("CollectionService"):AddTag(cube, "Motion")
		local beam = Instance.new("Part")
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(60, 0.8, 0.8)
		beam.CFrame = CFrame.new(spot + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Material = Enum.Material.Neon
		beam.Color = cube.Color
		beam.Transparency = 0.75
		beam.Parent = cube
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Забрать данные"
		prompt.ObjectText = "Осколок данных"
		prompt.HoldDuration = 1.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = cube
		prompt.Triggered:Connect(function(player)
			if not cube.Parent then
				return
			end
			cube:Destroy()
			found += 1
			notifyAll(`{player.DisplayName} забрал данные ({found}/{total}). Вирус проснулся рядом!`)
			for _ = 1, 3 do
				EnemyService.spawn(if random:NextNumber() < 0.3 then "Shooter" else "Pixel",
					groundAt(spot.X + random:NextNumber(-12, 12), spot.Z + random:NextNumber(-12, 12)), healthMultiplier, damageMultiplier)
			end
		end)
		cube.Parent = folder
	end

	local lastSpawn = 0
	while found < total do
		objectiveView = { Text = "Соберите данные", Progress = found, Total = total }
		if os.clock() - lastSpawn >= 8 and EnemyService.aliveCount() < 10 then
			lastSpawn = os.clock()
			EnemyService.spawn(pickKind(2, random), spawnPoint(random), healthMultiplier, damageMultiplier)
		end
		sendAll()
		task.wait(0.5)
	end
	folder:Destroy()

	-- Страж данных: Блок-великан с красным контуром
	notifyAll("Данные собраны! Их Страж идёт на площадь")
	local guardian = EnemyService.spawn("Block", groundAt(0, 22), healthMultiplier * 8, damageMultiplier * 1.4)
	if guardian then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 40, 40)
		highlight.FillTransparency = 0.7
		highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
		highlight.Parent = guardian
		local guardianHumanoid = guardian:FindFirstChildOfClass("Humanoid") :: Humanoid
		guardianHumanoid.DisplayName = "Страж данных"
		while guardian.Parent and guardianHumanoid.Health > 0 do
			objectiveView = {
				Text = "Победите Стража данных",
				Progress = math.max(0, math.ceil(guardianHumanoid.Health)),
				Total = math.ceil(guardianHumanoid.MaxHealth),
			}
			sendAll()
			task.wait(0.5)
		end
	end
	objectiveView = nil
	EnemyService.clear()
	DoppelgangerService.clear()
end

-- Случайная точка на улицах подальше от площади (для особых заданий)
local function streetSpot(random: Random): Vector3
	local streets = { -90, -30, 30, 90 }
	local street = streets[random:NextInteger(1, #streets)]
	local along = random:NextNumber(40, 110) * (if random:NextNumber() < 0.5 then -1 else 1)
	local x, z = street + random:NextNumber(-4, 4), along
	if random:NextNumber() < 0.5 then
		x, z = z, x
	end
	return groundAt(x, z)
end

local function hazardPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for key, value in props do
		(p :: any)[key] = value
	end
	if not p.Parent then
		p.Parent = Workspace
	end
	return p
end

local function livingRoots(): { { Root: BasePart, Humanoid: Humanoid } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(list, { Root = root, Humanoid = humanoid })
		end
	end
	return list
end

-- Помеха мира в особом задании (раз в несколько секунд):
--   "Fire" — дракон дышит огнём: под игроком красный круг, через секунду туда бьёт пламя;
--   "Eye" — красный луч глаза Нуля: кто остался в круге, поднимает тревогу (враги рядом)
local function hazardStrike(kind: string, damageMultiplier: number, healthMultiplier: number, random: Random)
	local targets = livingRoots()
	if #targets == 0 then
		return
	end
	local target = targets[random:NextInteger(1, #targets)]
	local spot = groundAt(target.Root.Position.X, target.Root.Position.Z)
	local color = if kind == "Fire" then Color3.fromRGB(255, 120, 30) else Color3.fromRGB(255, 30, 40)
	local radius = if kind == "Fire" then 7 else 9
	local marker = hazardPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, radius * 2, radius * 2),
		CFrame = CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.5,
	})
	local ray: Part? = nil
	if kind == "Eye" then
		local eye = Vector3.new(0, 210, -300)
		ray = hazardPart({
			Size = Vector3.new(1.5, 1.5, (spot - eye).Magnitude),
			CFrame = CFrame.lookAt((spot + eye) / 2, spot),
			Color = color,
			Transparency = 0.3,
		})
	end
	task.wait(1.3)
	marker:Destroy()
	local hit = false
	for _, other in livingRoots() do
		local offset = other.Root.Position - spot
		if Vector3.new(offset.X, 0, offset.Z).Magnitude < radius then
			hit = true
			if kind == "Fire" then
				other.Humanoid:TakeDamage(30 * damageMultiplier)
			end
		end
	end
	if kind == "Fire" then
		local flame = hazardPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(80, radius * 1.6, radius * 1.6),
			CFrame = CFrame.new(spot + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Transparency = 0.2,
		})
		task.delay(0.35, function()
			flame:Destroy()
		end)
	elseif hit then
		notifyAll("Глаз Нуля заметил отряд! Тревога!")
		for _ = 1, 4 do
			EnemyService.spawn(pickKind(3, random), groundAt(spot.X + random:NextNumber(-14, 14), spot.Z + random:NextNumber(-14, 14)),
				healthMultiplier, damageMultiplier)
		end
	end
	if ray then
		ray:Destroy()
	end
end

-- Особое задание «Targets»: активировать точки по городу (фонари, узлы цвета, ретрансляторы),
-- пока мешают враги и помеха мира. Каждая точка будит врагов рядом
local function runTargets(mission: Config.Mission)
	setState("Combat")
	local spec = mission.Target :: Config.TargetSpec
	local healthMultiplier, damageMultiplier = enemyMultipliers()
	local random = Random.new()
	local done = 0
	local folder = Instance.new("Folder")
	folder.Name = "MissionTargets"
	folder.Parent = Workspace
	for _ = 1, spec.Count do
		local spot = streetSpot(random)
		local pillar = hazardPart({
			Name = "Target",
			Size = Vector3.new(2, 6, 2),
			CFrame = CFrame.new(spot + Vector3.new(0, 3, 0)),
			Color = spec.Color,
			Material = Enum.Material.SmoothPlastic,
			CanQuery = true,
			Parent = folder,
		})
		local cap = hazardPart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.6,
			Position = spot + Vector3.new(0, 7, 0),
			Color = spec.Color,
			Parent = pillar,
		})
		local beam = hazardPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(70, 1, 1),
			CFrame = CFrame.new(spot + Vector3.new(0, 42, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = spec.DoneColor,
			Transparency = 0.75,
			Parent = pillar,
		})
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = spec.Action
		prompt.ObjectText = spec.Object
		prompt.HoldDuration = spec.Hold
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = pillar
		prompt.Triggered:Connect(function(player)
			if not prompt.Enabled then
				return
			end
			prompt.Enabled = false
			done += 1
			cap.Color = spec.DoneColor
			pillar.Color = spec.DoneColor
			pillar.Material = Enum.Material.Neon
			beam:Destroy()
			local light = Instance.new("PointLight")
			light.Color = spec.DoneColor
			light.Range = 20
			light.Brightness = 3
			light.Parent = cap
			notifyAll(`{player.DisplayName}: {spec.Object} ({done}/{spec.Count})`)
			for _ = 1, 3 do
				EnemyService.spawn(pickKind(2, random), groundAt(spot.X + random:NextNumber(-12, 12), spot.Z + random:NextNumber(-12, 12)),
					healthMultiplier, damageMultiplier)
			end
		end)
	end

	local lastSpawn, lastHazard = 0, os.clock()
	while done < spec.Count do
		objectiveView = { Text = mission.Name, Progress = done, Total = spec.Count }
		if os.clock() - lastSpawn >= 7 and EnemyService.aliveCount() < 12 then
			lastSpawn = os.clock()
			EnemyService.spawn(pickKind(2, random), spawnPoint(random), healthMultiplier, damageMultiplier)
		end
		if mission.Hazard and os.clock() - lastHazard >= 6 then
			lastHazard = os.clock()
			task.spawn(hazardStrike, mission.Hazard, damageMultiplier, healthMultiplier, random)
		end
		sendAll()
		task.wait(0.5)
	end
	task.wait(2)
	folder:Destroy()
	objectiveView = nil
	EnemyService.clear()
	DoppelgangerService.clear()
end

-- Особое задание «Настоящая Вега» (Зеркальный город): четыре клона, настоящий один.
-- У подделок контур чуть розовее; проверенная подделка рассыпается врагами
local function runRealClone()
	setState("Combat")
	local healthMultiplier, damageMultiplier = enemyMultipliers()
	local random = Random.new()
	local count = 4
	local real = random:NextInteger(1, count)
	local found = false
	local checked = 0
	local clones = {}
	for i = 1, count do
		local spot = streetSpot(random)
		local isReal = i == real
		clones[i] = VegaClone.spawn(spot, Vector3.new(0, spot.Y, 0), "", nil, {
			Outline = if isReal then nil else Color3.fromRGB(200, 190, 255),
			Action = "Проверить",
			Hold = 1,
			OnTalk = function(player, model)
				if found or not model.Parent then
					return
				end
				if isReal then
					found = true
					StoryService.say("Вега", "Это я. Настоящая. Спасибо, что не поверили отражениям.")
					notifyAll(`{player.DisplayName} нашёл настоящую Вегу!`)
				else
					checked += 1
					local position = model:GetPivot().Position
					model:Destroy()
					notifyAll("Подделка! Копия Нуля рассыпалась на вирус")
					StoryService.say("Нуль", "Ты почти поверил. Почти.")
					for _ = 1, 4 do
						EnemyService.spawn(pickKind(3, random), groundAt(position.X + random:NextNumber(-8, 8), position.Z + random:NextNumber(-8, 8)),
							healthMultiplier, damageMultiplier)
					end
				end
			end,
		})
	end
	local lastSpawn = 0
	DoppelgangerService.spawn()
	while not found do
		objectiveView = { Text = "Найдите настоящую Вегу · подделок раскрыто", Progress = checked, Total = count - 1 }
		if os.clock() - lastSpawn >= 7 and EnemyService.aliveCount() < 12 then
			lastSpawn = os.clock()
			EnemyService.spawn(pickKind(3, random), spawnPoint(random), healthMultiplier, damageMultiplier)
		end
		sendAll()
		task.wait(0.5)
	end
	task.wait(2)
	for _, model in clones do
		if model.Parent then
			model:Destroy()
		end
	end
	objectiveView = nil
	EnemyService.clear()
	DoppelgangerService.clear()
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
			local reward = math.floor(Config.MissionReward * multiplier * (bonus or 1) * currentMission().Power)
			local mission = currentMission()
			if DataService.waitFor(player, 10)
				and DataService.completeMission(player, info.Chapter, reward, info.World, mission.Index, #Config.Missions) then
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
		-- письмо-зацепка этого задания и клон Веги-подсказчица у площади
		-- (в бою с Нулём письмо — значок Кая — выпадает из него; в «Удержать канал» клон появляется в бою)
		local mission = currentMission()
		if chapterKind() == "Story" then
			if mission.Kind ~= "Boss" then
				MemoryShards.hide(`{worldId}_{mission.Index}`, groundAt)
			end
			if mission.Kind ~= "Defend" and mission.Kind ~= "RealClone" then
				VegaClone.spawn(groundAt(14, 14), Vector3.new(0, 0, 0),
					mission.Hint or Config.Story.CloneHints[math.min(mission.Index, #Config.Story.CloneHints)])
			end
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
			if briefing and chapterKind() == "Story" then
				StoryService.say("Вега (связь)", `{currentMission().Name}. {briefing}`)
			end
			failTitle = nil
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
				local kind = currentMission().Kind
				local won = true
				if kind == "Defend" then
					won = runDefend()
				elseif kind == "Hunt" then
					runHunt()
				elseif kind == "Targets" then
					runTargets(currentMission())
				elseif kind == "RealClone" then
					runRealClone()
				else
					local skipNodes = RunService:IsStudio() and ServerScriptService:GetAttribute("TestBoss") == true and isBossFight()
					if not skipNodes then
						runStory()
					end
					if isBossFight() then
						won = runBoss()
						if not won then
							failTitle = "НУЛЬ ПЕРЕЗАПИСАЛ СЕТЬ"
						end
					end
				end
				if not won then
					setState("GameOver")
				else
					setState("Victory")
					notifyAll(if isBossFight() then "Ядро свободно. Сезон «Трещина» пройден!" else "Сектор очищен!")
					-- Вега выходит на связь после задания и двигает сюжет дальше
					local debriefs = Config.Story.Debriefs[Config.getWorld(info.World).Id]
					local debrief = debriefs and debriefs[currentMission().Index]
					if debrief and debrief ~= "" then
						task.delay(2, StoryService.say, "Вега (связь)", debrief)
					end
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
