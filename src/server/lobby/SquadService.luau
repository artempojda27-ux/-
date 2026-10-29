--!strict
-- Отряды на порталах Штаба.
-- Игрок встаёт на портал → попадает в отряд. Первый — лидер: выбирает главу,
-- сложность, режим и жмёт «Старт». Потом весь отряд уходит на закрытый сервер миссии.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Common.DataService)
local MissionStore = require(ServerScriptService.Common.MissionStore)
local Teleport = require(ServerScriptService.Common.Teleport)

local TICK = 0.25
local LAUNCH_TIMEOUT = 20 -- если за это время отряд не ушёл, перенос не удался
local ACTION_COOLDOWN = 0.2

type Mode = "Open" | "Friends"

type Squad = {
	Index: number,
	Pad: BasePart,
	Members: { Player },
	Chapter: number,
	Difficulty: string,
	Mode: Mode,
	World: string,
	Mission: number, -- номер задания в мире (Config.Missions)
	LaunchAt: number?, -- когда стартует отсчёт до переноса
	AutoStartAt: number?, -- когда открытый отряд стартует сам
	LaunchingSince: number?, -- идёт перенос
}

local notify = Remotes.get("Notify")
local squadUpdate = Remotes.get("SquadUpdate")
local squadAction = Remotes.get("SquadAction")

local squads: { Squad } = {}
local lastSent: { [Player]: string } = {}
local lastAction: { [Player]: number } = {}
local refused: { [Player]: boolean } = {} -- уже сказали «нельзя», не спамим
local friendCache: { [string]: boolean } = {}
local friendPending: { [string]: boolean } = {}

local SquadService = {}

local function leaderOf(squad: Squad): Player?
	return squad.Members[1]
end

local function squadOf(player: Player): Squad?
	for _, squad in squads do
		if table.find(squad.Members, player) then
			return squad
		end
	end
	return nil
end

local function resetSquad(squad: Squad)
	squad.Members = {}
	squad.Chapter = Config.Chapters[1].Id
	squad.Difficulty = Config.Difficulties[1].Id
	squad.Mode = "Open"
	squad.World = Config.Worlds[1].Id
	squad.Mission = 1
	squad.LaunchAt = nil
	squad.AutoStartAt = nil
	squad.LaunchingSince = nil
end

local function isOnPad(player: Player, pad: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return false
	end
	local offset = root.Position - pad.Position
	local radius = math.max(pad.Size.X, pad.Size.Y, pad.Size.Z) / 2
	return Vector2.new(offset.X, offset.Z).Magnitude <= radius and offset.Y > -2 and offset.Y < 10
end

-- Сдвигаем игрока с портала, если в отряд нельзя
local function pushOff(player: Player, pad: BasePart)
	local character = player.Character
	if not character then
		return
	end
	local away = Vector3.new(-pad.Position.X, 0, -pad.Position.Z)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	local radius = math.max(pad.Size.X, pad.Size.Y, pad.Size.Z) / 2
	local target = pad.Position + away * (radius + 5) + Vector3.new(0, 4, 0)
	character:PivotTo(CFrame.lookAt(target, target + away))
end

-- Дружба проверяется через веб-запрос, поэтому кэшируем и не блокируем цикл
local function isFriend(leader: Player, player: Player): boolean?
	local key = `{leader.UserId}:{player.UserId}`
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	if not friendPending[key] then
		friendPending[key] = true
		task.spawn(function()
			local ok, result = pcall(player.IsFriendsWithAsync, player, leader.UserId)
			friendCache[key] = ok and result == true
			friendPending[key] = nil
		end)
	end
	return nil
end

local function canJoin(squad: Squad, player: Player): (boolean?, string?)
	if #squad.Members >= Config.SquadSize then
		return false, "Отряд заполнен."
	end
	local leader = leaderOf(squad)
	if squad.Mode == "Friends" and leader then
		local friend = isFriend(leader, player)
		if friend == nil then
			return nil, nil -- ещё проверяем
		elseif not friend then
			return false, `Отряд только для друзей {leader.DisplayName}.`
		end
	end
	return true, nil
end

local function launch(squad: Squad)
	squad.LaunchAt = nil
	squad.AutoStartAt = nil
	local members = table.clone(squad.Members)

	local available, reason = Teleport.check(Config.PlaceIds.Mission)
	if not available then
		for _, player in members do
			notify:FireClient(player, reason)
		end
		return
	end

	squad.LaunchingSince = os.clock()
	task.spawn(function()
		local code, serverId = Teleport.reserveServer(Config.PlaceIds.Mission)
		local saved = false
		if code and serverId then
			local userIds = {}
			for _, player in members do
				table.insert(userIds, player.UserId)
			end
			saved = MissionStore.save(serverId, {
				Chapter = squad.Chapter,
				Difficulty = squad.Difficulty,
				Members = userIds,
				World = squad.World,
				Mission = squad.Mission,
			})
		end

		local sent = false
		if code and saved then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			sent = Teleport.send(Config.PlaceIds.Mission, members, options)
		end

		if not sent then
			squad.LaunchingSince = nil
			for _, player in members do
				notify:FireClient(player, "Не удалось запустить миссию. Попробуй ещё раз.")
			end
		end
	end)
end

-- Обновляет состав отрядов по тому, кто стоит на порталах
local function updateMembership()
	for _, squad in squads do
		if squad.LaunchingSince then
			continue -- во время переноса состав не меняем
		end

		local oldLeader = leaderOf(squad)

		for i = #squad.Members, 1, -1 do
			local player = squad.Members[i]
			if player.Parent ~= Players or not isOnPad(player, squad.Pad) then
				table.remove(squad.Members, i)
			end
		end

		if #squad.Members == 0 then
			resetSquad(squad)
		elseif leaderOf(squad) ~= oldLeader then
			squad.LaunchAt = nil -- лидер ушёл — отсчёт отменяется
		end

		for _, player in Players:GetPlayers() do
			if squadOf(player) or not isOnPad(player, squad.Pad) then
				continue
			end
			local allowed, reason = canJoin(squad, player)
			if allowed then
				table.insert(squad.Members, player)
				refused[player] = nil
				if #squad.Members == 1 and squad.Mode == "Open" then
					squad.AutoStartAt = os.clock() + Config.OpenSquadAutoStart
				end
			elseif allowed == false then
				if not refused[player] then
					refused[player] = true
					notify:FireClient(player, reason)
				end
				pushOff(player, squad.Pad)
			end
		end
	end

	-- Сошёл со всех порталов — в следующий раз снова скажем причину отказа
	for player in refused do
		local onAnyPad = false
		for _, squad in squads do
			if isOnPad(player, squad.Pad) then
				onAnyPad = true
				break
			end
		end
		if not onAnyPad then
			refused[player] = nil
		end
	end
end

local function updateTimers()
	local now = os.clock()
	for _, squad in squads do
		if squad.LaunchingSince then
			if now - squad.LaunchingSince > LAUNCH_TIMEOUT then
				squad.LaunchingSince = nil
			end
			continue
		end
		if #squad.Members == 0 then
			continue
		end
		-- Полный отряд стартует сам
		if #squad.Members >= Config.SquadSize and not squad.LaunchAt then
			squad.LaunchAt = now + Config.StartCountdown
		end
		if squad.AutoStartAt and now >= squad.AutoStartAt and not squad.LaunchAt then
			squad.AutoStartAt = nil
			squad.LaunchAt = now + Config.StartCountdown
		end
		if squad.LaunchAt and now >= squad.LaunchAt then
			launch(squad)
		end
	end
end

local function secondsLeft(at: number?): number?
	return if at then math.max(0, math.ceil(at - os.clock())) else nil
end

local function viewFor(player: Player, squad: Squad)
	local chapter = Config.getChapter(squad.Chapter)
	local difficulty = Config.getDifficulty(squad.Difficulty)
	local names = {}
	for _, member in squad.Members do
		table.insert(names, member.DisplayName)
	end
	return {
		Portal = squad.Index,
		Members = names,
		MaxMembers = Config.SquadSize,
		IsLeader = leaderOf(squad) == player,
		Chapter = squad.Chapter,
		ChapterName = if chapter then Config.chapterTitle(chapter) else "?",
		Difficulty = squad.Difficulty,
		DifficultyName = if difficulty then difficulty.Name else "?",
		Mode = squad.Mode,
		World = squad.World,
		WorldName = Config.getWorld(squad.World).Name,
		MissionName = (function()
			local mission = Config.getMission(squad.World, squad.Mission)
			return `Задание {mission.Index}/{#Config.Missions}: {mission.Name}`
		end)(),
		IsStory = (Config.getChapter(squad.Chapter) :: any).Kind == "Story",
		Countdown = secondsLeft(squad.LaunchAt),
		AutoStart = if squad.LaunchAt then nil else secondsLeft(squad.AutoStartAt),
		Launching = squad.LaunchingSince ~= nil,
	}
end

local function broadcast()
	for _, squad in squads do
		local label = squad.Pad:FindFirstChild("Label")
		local text = label and label:FindFirstChild("Text")
		if text and text:IsA("TextLabel") then
			local difficulty = Config.getDifficulty(squad.Difficulty)
			local mode = if squad.Mode == "Friends" then "друзья" else "открыт"
			text.Text = if #squad.Members == 0
				then `ПОРТАЛ {squad.Index}\nсвободен`
				else `ПОРТАЛ {squad.Index}\n{#squad.Members}/{Config.SquadSize} · {difficulty and difficulty.Name} · {mode}`
		end
	end

	for _, player in Players:GetPlayers() do
		local squad = squadOf(player)
		local view = if squad then viewFor(player, squad) else nil
		local encoded = if view then HttpService:JSONEncode(view) else ""
		if lastSent[player] ~= encoded then
			lastSent[player] = encoded
			squadUpdate:FireClient(player, view)
		end
	end
end

-- Все задания открытого мира доступны сразу — можно выбрать, что по душе (после теста владельца: одно задание
-- казалось «игра из одной миссии»). Следующий мир по-прежнему открывается, только когда пройдены все три.
local function openMissions(_player: Player?, _worldId: string): number
	return #Config.Missions
end

-- Следующее непройденное задание мира (или последнее, если всё пройдено)
local function nextMission(player: Player?, worldId: string): number
	local data = player and DataService.get(player)
	local done = if data then data.WorldMissions[worldId] or 0 else 0
	return math.clamp(done + 1, 1, #Config.Missions)
end

local function cycle<T>(list: { T }, current: T, step: number): T
	local index = table.find(list, current) or 1
	return list[(index - 1 + step) % #list + 1]
end

local function onAction(player: Player, action: unknown, value: unknown)
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now

	local squad = squadOf(player)
	if not squad or leaderOf(squad) ~= player or squad.LaunchingSince then
		return
	end
	if typeof(action) ~= "string" then
		return
	end

	local step = if value == -1 then -1 else 1
	if action == "Chapter" then
		local ids = {}
		for _, chapter in Config.Chapters do
			table.insert(ids, chapter.Id)
		end
		squad.Chapter = cycle(ids, squad.Chapter, step)
	elseif action == "Difficulty" then
		local ids = {}
		for _, difficulty in Config.Difficulties do
			table.insert(ids, difficulty.Id)
		end
		squad.Difficulty = cycle(ids, squad.Difficulty, step)
	elseif action == "World" then
		-- Только открытые лидеру миры; в Studio открыты все
		local ids = {}
		local data = DataService.get(player)
		for _, world in Config.Worlds do
			local after = world.UnlockAfter
			local unlocked = after == nil or RunService:IsStudio()
				or (data ~= nil and (data.WorldsCompleted[after] == true
					-- победы до появления миров засчитываются Неоновому городу
					or (after == "Neon" and data.ChaptersCompleted["1"] == true)))
			if unlocked then
				table.insert(ids, world.Id)
			end
		end
		if #ids < #Config.Worlds then
			notify:FireClient(player, "Миры открываются по очереди: победи в последнем открытом мире, чтобы попасть в следующий.")
		end
		squad.World = cycle(ids, squad.World, step)
		squad.Mission = nextMission(player, squad.World)
	elseif action == "Mission" then
		local ids = {}
		for index = 1, openMissions(player, squad.World) do
			table.insert(ids, index)
		end
		squad.Mission = cycle(ids, squad.Mission, step)
	elseif action == "Mode" then
		squad.Mode = if squad.Mode == "Open" then "Friends" else "Open"
		squad.AutoStartAt = if squad.Mode == "Open" then now + Config.OpenSquadAutoStart else nil
	elseif action == "Start" then
		if not squad.LaunchAt then
			squad.LaunchAt = now + Config.StartCountdown
		end
	elseif action == "Cancel" then
		squad.LaunchAt = nil
		squad.AutoStartAt = nil
	end
end

function SquadService.start(pads: { BasePart })
	for index, pad in pads do
		local squad: Squad = {
			Index = index,
			Pad = pad,
			Members = {},
			Chapter = 0,
			Difficulty = "",
			Mode = "Open",
			World = "",
			Mission = 1,
		}
		resetSquad(squad)
		table.insert(squads, squad)
	end

	squadAction.OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
		lastAction[player] = nil
		refused[player] = nil
	end)

	task.spawn(function()
		while true do
			updateMembership()
			updateTimers()
			broadcast()
			task.wait(TICK)
		end
	end)
end

return SquadService
