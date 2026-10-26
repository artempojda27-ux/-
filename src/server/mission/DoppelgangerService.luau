--!strict
-- Двойник: вирус копирует одного из игроков отряда — тот же вид и тот же ник.
-- Двойник ходит рядом с отрядом как свой, а через 25–45 секунд предаёт: взрывается рядом
-- с игроком и выпускает Пикселей (в Главе 1 ещё и снова открывает закрытый сбой).
-- Как его вычислить бесплатно: он иногда мерцает и у него на миг сбиваются буквы в нике;
-- враги его не трогают; если в него стрелять, после потери 40% здоровья он раскрывается.
-- «Сканер вируса» (Game Pass) сразу подсвечивает двойника тому, кто купил;
-- «Скан для всего отряда» (разовый) раскрывает двойника всем.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Common.DataService)
local PassService = require(ServerScriptService.Common.PassService)
local EnemyService = require(script.Parent.EnemyService)

local THINK_INTERVAL = 0.3
local FOLLOW_DISTANCE = 12
local RED = Color3.fromRGB(255, 30, 60)
local GLITCH_CHARS = { "#", "%", "@", "&", "0", "1", "?" }
-- Стандартные анимации R15: ходьба и стойка
local WALK_ANIMATION = "rbxassetid://507777826"
local IDLE_ANIMATION = "rbxassetid://507766388"

type Double = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Name: string, -- ник копии
	Offset: Vector3, -- где держится относительно игрока
	Revealed: boolean,
	Betraying: boolean,
	BetrayAt: number,
	NextTell: number,
	Walk: AnimationTrack?,
	Idle: AnimationTrack?,
}

local DoppelgangerService = {}

local doubles: { [Model]: Double } = {}
local pendingScans = 0
local betrayHandler: (() -> ())? = nil
local random = Random.new()
local notify = Remotes.get("Notify")

local function livingPlayers(): { BasePart }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(list, root)
		end
	end
	return list
end

local function nearestPlayer(from: Vector3): (BasePart?, number)
	local best, bestDistance = nil, math.huge
	for _, root in livingPlayers() do
		local distance = (root.Position - from).Magnitude
		if distance < bestDistance then
			best, bestDistance = root, distance
		end
	end
	return best, bestDistance
end

-- Ник со сбитой буквой: «Artem» → «Ar%em»
local function glitchName(name: string): string
	local chars = {}
	for _, code in utf8.codes(name) do
		table.insert(chars, utf8.char(code))
	end
	if #chars == 0 then
		return name
	end
	chars[random:NextInteger(1, #chars)] = GLITCH_CHARS[random:NextInteger(1, #GLITCH_CHARS)]
	return table.concat(chars)
end

-- Бесплатная подсказка: на миг мерцает и сбивает ник
local function tell(double: Double)
	local original: { [BasePart]: number } = {}
	for _, descendant in double.Model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.5 and descendant.Name ~= "HumanoidRootPart" then
			original[descendant] = descendant.Transparency
			descendant.Transparency = 0.6
		end
	end
	double.Humanoid.DisplayName = glitchName(double.Name)
	task.delay(0.15, function()
		for p, transparency in original do
			p.Transparency = transparency
		end
	end)
	task.delay(0.6, function()
		if not double.Revealed then
			double.Humanoid.DisplayName = double.Name
		end
	end)
end

local function reveal(double: Double, message: string)
	if double.Revealed then
		return
	end
	double.Revealed = true
	double.Model:SetAttribute("Revealed", true)
	double.Humanoid.DisplayName = "ДВОЙНИК"
	local highlight = Instance.new("Highlight")
	highlight.Name = "RevealHighlight"
	highlight.FillColor = RED
	highlight.OutlineColor = RED
	highlight.FillTransparency = 0.5
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = double.Model
	notify:FireAllClients(message)
end

local function remove(double: Double)
	doubles[double.Model] = nil
	double.Model:Destroy()
end

-- Предательство: подбегает к игроку и взрывается
local function betray(double: Double)
	double.Betraying = true
	reveal(double, `Двойник {double.Name} предал отряд!`)
	local deadline = os.clock() + 4
	while os.clock() < deadline and doubles[double.Model] do
		local target, distance = nearestPlayer(double.Root.Position)
		if not target or distance < 6 then
			break
		end
		double.Humanoid:MoveTo(target.Position)
		task.wait(0.2)
	end
	if not doubles[double.Model] then
		return -- успели уничтожить
	end

	local center = double.Root.Position
	local blast = Instance.new("Part")
	blast.Shape = Enum.PartType.Ball
	blast.Anchored = true
	blast.CanCollide = false
	blast.CanQuery = false
	blast.CanTouch = false
	blast.Material = Enum.Material.Neon
	blast.Color = RED
	blast.Size = Vector3.one * 2
	blast.Position = center
	blast.Parent = Workspace
	local radius = Config.Doppelganger.BlastRadius
	TweenService:Create(blast, TweenInfo.new(0.4), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	task.delay(0.45, function()
		blast:Destroy()
	end)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and (root.Position - center).Magnitude <= radius then
			humanoid:TakeDamage(Config.Doppelganger.BlastDamage)
		end
	end
	for _ = 1, Config.Doppelganger.BlastPixels do
		EnemyService.spawn("Pixel", center + Vector3.new(random:NextNumber(-4, 4), -2, random:NextNumber(-4, 4)))
	end
	if betrayHandler then
		betrayHandler()
	end
	remove(double)
end

local function think(double: Double, now: number)
	if double.Betraying then
		return
	end
	if now >= double.BetrayAt then
		task.spawn(betray, double)
		return
	end
	if not double.Revealed and now >= double.NextTell then
		double.NextTell = now + random:NextNumber(5, 9)
		tell(double)
	end

	local buddy, distance = nearestPlayer(double.Root.Position)
	if buddy and distance > FOLLOW_DISTANCE then
		double.Humanoid:MoveTo(buddy.Position + double.Offset)
	end
	local moving = double.Root.AssemblyLinearVelocity.Magnitude > 1
	if double.Walk and double.Idle then
		if moving and not double.Walk.IsPlaying then
			double.Idle:Stop()
			double.Walk:Play()
		elseif not moving and not double.Idle.IsPlaying then
			double.Walk:Stop()
			double.Idle:Play()
		end
	end
end

-- Точная копия персонажа игрока, без его скриптов
local function copyCharacter(player: Player): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = wasArchivable
	if not clone then
		return nil
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ForceField") or descendant:IsA("Highlight") then
			descendant:Destroy()
		end
	end
	return clone
end

local function playersForDouble(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

-- Создаёт двойника одного из игроков. true, если получилось
function DoppelgangerService.spawn(): boolean
	local candidates = playersForDouble()
	local enough = #candidates >= Config.Doppelganger.MinPlayers or (RunService:IsStudio() and #candidates >= 1)
	if not enough then
		return false
	end
	local original = candidates[random:NextInteger(1, #candidates)]
	-- Появляется рядом с другим игроком, чтобы настоящий не стоял рядом с копией
	local anchor = original
	if #candidates > 1 then
		repeat
			anchor = candidates[random:NextInteger(1, #candidates)]
		until anchor ~= original
	end
	local anchorRoot = anchor.Character and anchor.Character:FindFirstChild("HumanoidRootPart")
	local model = copyCharacter(original)
	if not model or not anchorRoot or not anchorRoot:IsA("BasePart") then
		return false
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return false
	end
	humanoid.MaxHealth = Config.Doppelganger.Health
	humanoid.Health = Config.Doppelganger.Health
	humanoid.DisplayName = original.DisplayName
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	model.Name = original.Name
	model:SetAttribute("Doppelganger", true)
	model:SetAttribute("CopyOf", original.UserId)
	CollectionService:AddTag(model, "Enemy")
	local side = if random:NextNumber() < 0.5 then -1 else 1
	model:PivotTo(anchorRoot.CFrame * CFrame.new(side * 5, 0, 4))
	model.Parent = Workspace
	root:SetNetworkOwner(nil)

	local double: Double = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Name = original.DisplayName,
		Offset = Vector3.new(side * 6, 0, 5),
		Revealed = false,
		Betraying = false,
		BetrayAt = os.clock() + random:NextNumber(Config.Doppelganger.BetrayAfter[1], Config.Doppelganger.BetrayAfter[2]),
		NextTell = os.clock() + random:NextNumber(4, 7),
		Walk = nil,
		Idle = nil,
	}
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator and humanoid.RigType == Enum.HumanoidRigType.R15 then
		local walk = Instance.new("Animation")
		walk.AnimationId = WALK_ANIMATION
		local idle = Instance.new("Animation")
		idle.AnimationId = IDLE_ANIMATION
		double.Walk = animator:LoadAnimation(walk)
		double.Idle = animator:LoadAnimation(idle)
		if double.Idle then
			double.Idle.Looped = true
			double.Idle:Play()
		end
		if double.Walk then
			double.Walk.Looped = true
		end
	end
	doubles[model] = double

	-- Подстрелили — раскрылся
	humanoid.HealthChanged:Connect(function(health)
		if not double.Revealed and health > 0 and health < humanoid.MaxHealth * Config.Doppelganger.RevealAt then
			reveal(double, `Это не {double.Name}! Двойник раскрыт!`)
		end
	end)
	humanoid.Died:Connect(function()
		if not doubles[model] or double.Betraying then
			return
		end
		doubles[model] = nil
		notify:FireAllClients(`Двойник {double.Name} уничтожен! +{Config.Doppelganger.KillReward} бит отряду`)
		for _, player in Players:GetPlayers() do
			DataService.addBits(player, Config.Doppelganger.KillReward)
		end
		task.delay(0.3, function()
			model:Destroy()
		end)
	end)

	-- Сканер у кого-то из отряда: предупреждаем владельца
	for _, player in Players:GetPlayers() do
		if PassService.owns(player, "Scanner") then
			notify:FireClient(player, `Сканер: среди вас двойник — копия {double.Name}!`)
		end
	end
	if pendingScans > 0 then
		pendingScans -= 1
		reveal(double, `Скан сработал: двойник — копия {double.Name}!`)
	end
	return true
end

-- Разовый «Скан для всего отряда»: раскрывает двойников, а если их нет — сработает позже
function DoppelgangerService.scanAll(buyer: Player): boolean
	local found = false
	for _, double in doubles do
		if not double.Revealed then
			found = true
			reveal(double, `{buyer.DisplayName} просканировал отряд: двойник — копия {double.Name}!`)
		end
	end
	if not found then
		pendingScans += 1
		notify:FireAllClients(`{buyer.DisplayName} включил скан: двойник раскроется, как только появится`)
	end
	return true
end

-- Что делать при предательстве (например, Глава 1 снова открывает сбой)
function DoppelgangerService.setBetrayHandler(handler: (() -> ())?)
	betrayHandler = handler
end

function DoppelgangerService.clear()
	for _, double in doubles do
		remove(double)
	end
end

function DoppelgangerService.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < THINK_INTERVAL then
			return
		end
		elapsed = 0
		local now = os.clock()
		for _, double in doubles do
			think(double, now)
		end
	end)
end

return DoppelgangerService
