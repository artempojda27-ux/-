--!strict
-- Враги вируса и их поведение (всё на сервере):
--   Пиксель — маленький и быстрый, бежит к ближайшему игроку и кусает вблизи;
--   Блок — медленный и крепкий, перед ударом по площади мигает (можно отбежать);
--   Стрелок — держит дистанцию и стреляет медленными снарядами (от них можно увернуться).
-- Враг — модель с тегом "Enemy": по нему попадают оружие, дрон и «Код уничтожения».
-- При гибели враг рассыпается на зелёные пиксели.
-- Если игрок виден, враг бежит к нему напрямую; если мешают дома — ищет путь по улицам.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local THINK_INTERVAL = 0.15
local SHOOTER_MIN_DISTANCE = 22 -- ближе Стрелок отступает
local PROJECTILE_LIFETIME = 4
local PATH_REFRESH = 1.5 -- секунд, через сколько путь пересчитывается
local MAX_PATH_JOBS = 4 -- сколько путей считается одновременно (чтобы сервер не тормозил)
local WAYPOINT_REACHED = 4
local HOVER_HEIGHT = 1.5
local FLASH = Color3.fromRGB(255, 255, 255)
local SHARD = Color3.fromRGB(60, 255, 120)

type Enemy = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Kind: Config.EnemyKind,
	DamageMultiplier: number,
	LastAttack: number,
	Busy: boolean, -- Блок замахивается и стоит на месте
	-- Путь в обход домов
	Waypoints: { PathWaypoint }?,
	WaypointIndex: number,
	PathAt: number,
	Computing: boolean,
}

type Projectile = {
	Part: BasePart,
	Velocity: Vector3,
	Damage: number,
	DiesAt: number,
}

local EnemyService = {}

local enemies: { [Model]: Enemy } = {}
local projectiles: { Projectile } = {}
local folder: Folder
local pathJobs = 0
local diedEvent = Instance.new("BindableEvent")

-- Срабатывает при гибели врага: EnemyService.Died:Connect(function(kindId) end)
EnemyService.Died = diedEvent.Event

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Живые игроки: корневая деталь и Humanoid
local function livingPlayers(): { { Root: BasePart, Humanoid: Humanoid } }
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

-- Рассыпается на зелёные пиксели
local function shatter(position: Vector3, size: Vector3)
	local random = Random.new()
	for _ = 1, 8 do
		local shard = part({
			Size = Vector3.one * random:NextNumber(0.3, 0.7),
			Position = position + Vector3.new(
				random:NextNumber(-1, 1) * size.X / 2,
				random:NextNumber(-1, 1) * size.Y / 2,
				random:NextNumber(-1, 1) * size.Z / 2
			),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = SHARD,
			Parent = folder,
		})
		local target = shard.Position + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(2, 6), random:NextNumber(-3, 3))
		TweenService:Create(shard, TweenInfo.new(0.7), { Position = target, Transparency = 1, Size = Vector3.one * 0.1 }):Play()
		task.delay(0.75, function()
			shard:Destroy()
		end)
	end
end

local function build(kind: Config.EnemyKind, position: Vector3, healthMultiplier: number): (Model, BasePart, Humanoid)
	local model = Instance.new("Model")
	model.Name = kind.Name

	local root = part({
		Name = "HumanoidRootPart",
		Size = kind.Size,
		Position = position + Vector3.new(0, kind.Size.Y / 2 + HOVER_HEIGHT, 0),
		Color = Color3.fromRGB(14, 30, 20),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	-- Светящееся «лицо» вируса
	local face = part({
		Name = "Face",
		Size = Vector3.new(kind.Size.X * 0.7, kind.Size.Y * 0.25, 0.2),
		CFrame = root.CFrame * CFrame.new(0, kind.Size.Y * 0.15, -kind.Size.Z / 2 - 0.1),
		Color = kind.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Massless = true,
		Parent = model,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = face
	weld.Parent = face
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- чтобы работала HipHeight у модели без ног
	humanoid.HipHeight = HOVER_HEIGHT -- вирус парит над землёй и так перебирается через бордюры
	humanoid.MaxHealth = kind.Health * healthMultiplier
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = kind.Speed
	humanoid.DisplayName = kind.Name
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	CollectionService:AddTag(model, "Enemy")
	model:SetAttribute("EnemyKind", kind.Id)
	model.Parent = folder
	root:SetNetworkOwner(nil) -- физику врага считает сервер
	return model, root, humanoid
end

local function fireProjectile(enemy: Enemy, target: Vector3)
	local kind = enemy.Kind
	local from = enemy.Root.Position + Vector3.new(0, kind.Size.Y * 0.2, 0)
	local direction = (target - from).Unit
	local ball = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.2,
		Position = from + direction * 2,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.Neon,
		Color = kind.Color,
		Parent = folder,
	})
	table.insert(projectiles, {
		Part = ball,
		Velocity = direction * (kind.ProjectileSpeed or 40),
		Damage = kind.Damage * enemy.DamageMultiplier,
		DiesAt = os.clock() + PROJECTILE_LIFETIME,
	})
end

-- Блок замахивается, мигает и бьёт всех рядом
local function areaAttack(enemy: Enemy)
	local kind = enemy.Kind
	enemy.Busy = true
	enemy.Humanoid:MoveTo(enemy.Root.Position)
	local face = enemy.Model:FindFirstChild("Face") :: BasePart?
	if face then
		face.Color = FLASH
	end
	task.delay(kind.WindUp or 0.8, function()
		if not enemies[enemy.Model] then
			return
		end
		if face then
			face.Color = kind.Color
		end
		local center = enemy.Root.Position
		local wave = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 2, 2),
			CFrame = CFrame.new(center - Vector3.new(0, kind.Size.Y / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.Neon,
			Color = kind.Color,
			Transparency = 0.3,
			Parent = folder,
		})
		local radius = kind.AreaRadius or 8
		TweenService:Create(wave, TweenInfo.new(0.3), { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }):Play()
		task.delay(0.35, function()
			wave:Destroy()
		end)
		for _, target in livingPlayers() do
			if (target.Root.Position - center).Magnitude <= radius then
				target.Humanoid:TakeDamage(kind.Damage * enemy.DamageMultiplier)
			end
		end
		enemy.Busy = false
	end)
end

-- Видит ли враг точку: между ними нет домов и укрытий
local function canSee(enemy: Enemy, target: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local from = enemy.Root.Position
	return Workspace:Raycast(from, target - from, params) == nil
end

local function computePath(enemy: Enemy, target: Vector3)
	if enemy.Computing or pathJobs >= MAX_PATH_JOBS then
		return
	end
	enemy.Computing = true
	pathJobs += 1
	task.spawn(function()
		local size = enemy.Kind.Size
		local path = PathfindingService:CreatePath({
			AgentRadius = math.max(size.X, size.Z) / 2 + 0.5,
			AgentHeight = size.Y + 1,
			AgentCanJump = false,
		})
		local ok = pcall(function()
			path:ComputeAsync(enemy.Root.Position, target)
		end)
		pathJobs -= 1
		enemy.Computing = false
		enemy.PathAt = os.clock()
		if ok and path.Status == Enum.PathStatus.Success then
			enemy.Waypoints = path:GetWaypoints()
			enemy.WaypointIndex = 2
		else
			enemy.Waypoints = nil
		end
	end)
end

-- Идёт к цели: напрямую, если видно, иначе по найденному пути
local function moveToward(enemy: Enemy, target: Vector3, now: number)
	if canSee(enemy, target) then
		enemy.Waypoints = nil
		enemy.Humanoid:MoveTo(target)
		return
	end
	if not enemy.Waypoints or now - enemy.PathAt > PATH_REFRESH then
		computePath(enemy, target)
	end
	local waypoints = enemy.Waypoints
	if not waypoints then
		enemy.Humanoid:MoveTo(target) -- пути пока нет: хотя бы двигаемся в сторону цели
		return
	end
	local waypoint = waypoints[enemy.WaypointIndex]
	if not waypoint then
		enemy.Waypoints = nil
		return
	end
	local offset = waypoint.Position - enemy.Root.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude < WAYPOINT_REACHED then
		enemy.WaypointIndex += 1
		waypoint = waypoints[enemy.WaypointIndex] or waypoint
	end
	enemy.Humanoid:MoveTo(waypoint.Position)
end

local function think(enemy: Enemy, now: number)
	if enemy.Busy then
		return
	end
	local kind = enemy.Kind
	local position = enemy.Root.Position

	local nearest, nearestDistance = nil, math.huge
	for _, target in livingPlayers() do
		local distance = (target.Root.Position - position).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = target, distance
		end
	end
	if not nearest then
		enemy.Humanoid:MoveTo(position)
		return
	end
	local targetPosition = nearest.Root.Position

	if kind.Ranged then
		local visible = nearestDistance <= kind.AttackRange and canSee(enemy, targetPosition)
		if not visible then
			moveToward(enemy, targetPosition, now)
		elseif nearestDistance < SHOOTER_MIN_DISTANCE then
			local away = position - targetPosition
			away = Vector3.new(away.X, 0, away.Z)
			if away.Magnitude > 0.1 then
				enemy.Humanoid:MoveTo(position + away.Unit * 10)
			end
		else
			enemy.Humanoid:MoveTo(position)
		end
		if visible and now - enemy.LastAttack >= kind.AttackInterval then
			enemy.LastAttack = now
			fireProjectile(enemy, targetPosition)
		end
		return
	end

	-- Ближний бой
	moveToward(enemy, targetPosition, now)
	if nearestDistance <= kind.AttackRange and now - enemy.LastAttack >= kind.AttackInterval then
		enemy.LastAttack = now
		if kind.AreaRadius then
			areaAttack(enemy)
		else
			nearest.Humanoid:TakeDamage(kind.Damage * enemy.DamageMultiplier)
		end
	end
end

local function updateProjectiles(dt: number)
	if #projectiles == 0 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local now = os.clock()

	for i = #projectiles, 1, -1 do
		local projectile = projectiles[i]
		local from = projectile.Part.Position
		local step = projectile.Velocity * dt
		local hit = Workspace:Raycast(from, step, params)
		local done = now >= projectile.DiesAt
		if hit then
			done = true
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			if model and humanoid and Players:GetPlayerFromCharacter(model) then
				humanoid:TakeDamage(projectile.Damage)
			end
		else
			projectile.Part.Position = from + step
		end
		if done then
			projectile.Part:Destroy()
			table.remove(projectiles, i)
		end
	end
end

-- Создаёт врага. healthMultiplier и damageMultiplier — от сложности, размера отряда и номера волны.
function EnemyService.spawn(kindId: string, position: Vector3, healthMultiplier: number?, damageMultiplier: number?): Model?
	local kind = Config.Enemies[kindId]
	if not kind then
		warn(`Неизвестный враг {kindId}`)
		return nil
	end
	local model, root, humanoid = build(kind, position, healthMultiplier or 1)
	local enemy: Enemy = {
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Kind = kind,
		DamageMultiplier = damageMultiplier or 1,
		LastAttack = os.clock(),
		Busy = false,
		Waypoints = nil,
		WaypointIndex = 1,
		PathAt = 0,
		Computing = false,
	}
	enemies[model] = enemy

	humanoid.Died:Connect(function()
		if not enemies[model] then
			return
		end
		enemies[model] = nil
		shatter(root.Position, kind.Size)
		diedEvent:Fire(kind.Id)
		task.delay(0.05, function()
			model:Destroy()
		end)
	end)
	return model
end

function EnemyService.aliveCount(): number
	local count = 0
	for _ in enemies do
		count += 1
	end
	return count
end

-- Убирает всех врагов и снаряды (например, после поражения)
function EnemyService.clear()
	for model in enemies do
		enemies[model] = nil
		model:Destroy()
	end
	for _, projectile in projectiles do
		projectile.Part:Destroy()
	end
	table.clear(projectiles)
end

function EnemyService.start()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		updateProjectiles(dt)
		elapsed += dt
		if elapsed < THINK_INTERVAL then
			return
		end
		elapsed = 0
		local now = os.clock()
		for _, enemy in enemies do
			think(enemy, now)
		end
	end)
end

return EnemyService
