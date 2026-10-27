--!strict
-- Финальный бой: Нуль — злодей саги (docs/Saga.md), появляется в мире «Ядро» после того, как отряд
-- закрыл все сбои. Парит над площадью; попасть в него можно, как во врага (тег "Enemy"), урон — сервер.
-- Фазы по здоровью:
--   1 (100–60%): «Стирающий луч» (прыгай через него), «Нулевой дождь» (беги из красных кругов), копии-Пиксели.
--   Щит (на 60%): Нуль неуязвим, пока отряд снова не закроет три сбоя.
--   2 (60–30%): добавляется «Волна перезаписи» — кольцо по земле, через него тоже прыгают; Нуль
--     копирует одного из игроков (двойник).
--   3 (<30%): «Перегрузка» — всё быстрее, лучей два, Ядро над городом краснеет.
-- Если отряд не победит за BOSS_TIME_LIMIT секунд, Нуль перезаписывает Сеть — поражение.

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DoppelgangerService = require(script.Parent.DoppelgangerService)
local EnemyService = require(script.Parent.EnemyService)

local BASE_HEALTH = 7000
local BOSS_TIME_LIMIT = 420
local HOVER = 19 -- высота над площадью: пусть парит над головами
local BEAM_LENGTH = 95
local BEAM_DAMAGE = 18
local RAIN_DAMAGE = 35
local WAVE_DAMAGE = 30
local JUMP_CLEAR = 4.2 -- насколько выше земли должен быть игрок, чтобы луч и волна прошли под ним

local BLUE = Color3.fromRGB(120, 200, 255)
local WHITE = Color3.fromRGB(235, 245, 255)
local RED = Color3.fromRGB(255, 40, 60)

export type Context = {
	HealthMultiplier: number,
	DamageMultiplier: number,
	GroundAt: (x: number, z: number) -> Vector3,
	Notify: (text: string) -> (),
	Update: (view: { [string]: any }?) -> (), -- сообщает клиентам полоску здоровья босса (nil — убрать)
	OpenNodes: () -> (), -- снова открыть сбои на карте (для щита)
	OpenNodeCount: () -> number,
}

local BossService = {}

local random = Random.new()

local function part(props: { [string]: any }): Part
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
	return p
end

local function livingPlayers(): { { Player: Player, Root: BasePart, Humanoid: Humanoid } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(list, { Player = player, Root = root, Humanoid = humanoid })
		end
	end
	return list
end

-- Нуль: невидимая «мишень» (по ней попадают пули) + детальная статуя, ореол и свечение
local function build(position: Vector3, maxHealth: number): (Model, BasePart, Humanoid)
	local model = Instance.new("Model")
	model.Name = "Нуль"
	local root = part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(9, 20, 6),
		Position = position,
		Transparency = 1,
		CanQuery = true, -- сюда попадают выстрелы
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local ok, container = pcall(InsertService.LoadAsset, InsertService, Config.Monuments.Core or 0)
	local mesh = ok and container:FindFirstChildWhichIsA("BasePart", true)
	if mesh then
		mesh.Parent = nil
		container:Destroy()
		mesh.Name = "Body"
		mesh.Size = mesh.Size * (22 / mesh.Size.Y)
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CFrame = root.CFrame
		mesh.Parent = model
	else
		-- запасной вид: белая фигура со светящимся кругом вместо лица
		part({ Name = "Body", Size = Vector3.new(6, 16, 3), CFrame = root.CFrame, Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = model })
		part({ Name = "Face", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3, 3), CFrame = root.CFrame * CFrame.new(0, 6.5, -1.6) * CFrame.Angles(0, math.rad(90), 0), Color = BLUE, Parent = model })
	end
	-- ореол из светящихся сегментов за спиной
	for i = 1, 24 do
		local angle = (i / 24) * math.pi * 2
		part({
			Name = "Halo",
			Size = Vector3.new(0.5, 0.5, 2.1),
			CFrame = root.CFrame * CFrame.new(0, 5, 3.5) * CFrame.Angles(math.rad(90), angle, 0) * CFrame.new(8, 0, 0),
			Color = BLUE,
			Parent = model,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = BLUE
	light.Range = 40
	light.Brightness = 4
	light.Parent = root
	local aura = Instance.new("ParticleEmitter")
	aura.Color = ColorSequence.new(WHITE, BLUE)
	aura.LightEmission = 1
	aura.Size = NumberSequence.new(0.5, 0)
	aura.Lifetime = NumberRange.new(1, 2)
	aura.Rate = 40
	aura.Speed = NumberRange.new(2, 6)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Shape = Enum.ParticleEmitterShape.Box
	aura.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.DisplayName = "Нуль"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff -- своя полоска сверху экрана
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	model.PrimaryPart = root
	CollectionService:AddTag(model, "Enemy")
	model:SetAttribute("EnemyKind", "Null")
	model.Parent = Workspace
	return model, root, humanoid
end

-- Щит: пока он есть, урон не проходит (ForceField) — снимается закрытием сбоев
local function setShield(model: Model, root: BasePart, on: boolean)
	local field = model:FindFirstChild("Shield")
	local bubble = model:FindFirstChild("ShieldBubble")
	if on and not field then
		local forceField = Instance.new("ForceField")
		forceField.Name = "Shield"
		forceField.Visible = false
		forceField.Parent = model
		part({
			Name = "ShieldBubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 30,
			CFrame = root.CFrame,
			Color = BLUE,
			Material = Enum.Material.ForceField,
			Transparency = 0.1,
			Parent = model,
		})
	elseif not on then
		if field then
			field:Destroy()
		end
		if bubble then
			bubble:Destroy()
		end
	end
end

local function hurt(target: { Humanoid: Humanoid }, amount: number)
	target.Humanoid:TakeDamage(amount) -- ForceField (бессмертие за Robux) защищает и отсюда
end

---------------------------------------------------------------- Атаки

-- «Стирающий луч»: сначала тонкая линия-предупреждение, потом луч поворачивается вокруг Нуля по земле
local function beamAttack(center: Vector3, groundY: number, damage: number, count: number, fast: boolean)
	local folder = Instance.new("Folder")
	folder.Name = "NullBeam"
	folder.Parent = Workspace
	local start = random:NextNumber(0, math.pi * 2)
	local sweep = math.rad(if fast then 150 else 110) * (if random:NextNumber() < 0.5 then -1 else 1)
	local base = Vector3.new(center.X, groundY, center.Z)
	local beams = {}
	for i = 1, count do
		local angle = start + (i - 1) * math.pi
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local mid = base + dir * BEAM_LENGTH / 2 + Vector3.new(0, 1.2, 0)
		part({
			Name = "Warning",
			Size = Vector3.new(0.4, 0.15, BEAM_LENGTH),
			CFrame = CFrame.lookAt(mid, mid + dir) - Vector3.new(0, 1.1, 0),
			Color = RED,
			Transparency = 0.3,
			Parent = folder,
		})
		table.insert(beams, angle)
	end
	task.wait(if fast then 0.8 else 1.2)
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
	local parts = {}
	for i = 1, count do
		parts[i] = part({ Name = "Beam", Size = Vector3.new(3, 3, BEAM_LENGTH), Color = WHITE, Transparency = 0.05, Parent = folder })
		local glow = Instance.new("PointLight")
		glow.Color = BLUE
		glow.Range = 16
		glow.Brightness = 3
		glow.Parent = parts[i]
	end
	local duration = if fast then 2.4 else 3
	local lastHit: { [Player]: number } = {}
	local started = os.clock()
	while os.clock() - started < duration do
		local t = (os.clock() - started) / duration
		for i, startAngle in beams do
			local angle = startAngle + sweep * t
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local mid = base + dir * BEAM_LENGTH / 2 + Vector3.new(0, 1.5, 0)
			parts[i].CFrame = CFrame.lookAt(mid, mid + dir)
			for _, target in livingPlayers() do
				local offset = target.Root.Position - base
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local along = flat:Dot(dir)
				local side = (flat - dir * along).Magnitude
				local height = target.Root.Position.Y - groundY - 3 -- корень персонажа стоит ~3 студа над землёй
				if along > 0 and along < BEAM_LENGTH and side < 2.8 and height < JUMP_CLEAR then
					local last = lastHit[target.Player]
					if not last or os.clock() - last > 0.4 then
						lastHit[target.Player] = os.clock()
						hurt(target, damage)
					end
				end
			end
		end
		task.wait(0.05)
	end
	folder:Destroy()
end

-- «Нулевой дождь»: под каждым игроком — красный круг, через мгновение туда бьёт столб света
local function rainAttack(groundAt: (number, number) -> Vector3, damage: number, volleys: number)
	for _ = 1, volleys do
		local strikes = {}
		for _, target in livingPlayers() do
			local p = target.Root.Position
			local spot = groundAt(p.X + random:NextNumber(-2, 2), p.Z + random:NextNumber(-2, 2))
			local marker = part({
				Name = "RainMarker",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.12, 14, 14),
				CFrame = CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = RED,
				Transparency = 0.55,
				Parent = Workspace,
			})
			table.insert(strikes, { Spot = spot, Marker = marker })
		end
		task.wait(1.4)
		for _, strike in strikes do
			strike.Marker:Destroy()
			local pillar = part({
				Name = "RainPillar",
				Size = Vector3.new(6, 120, 6),
				Position = strike.Spot + Vector3.new(0, 60, 0),
				Color = WHITE,
				Transparency = 0.1,
				Parent = Workspace,
			})
			task.delay(0.3, function()
				pillar:Destroy()
			end)
			for _, target in livingPlayers() do
				local offset = target.Root.Position - strike.Spot
				if Vector3.new(offset.X, 0, offset.Z).Magnitude < 7 then
					hurt(target, damage)
				end
			end
		end
		task.wait(0.5)
	end
end

-- «Волна перезаписи»: светящееся кольцо расходится по земле, через него надо перепрыгнуть
local function waveAttack(center: Vector3, groundY: number, damage: number)
	local segments = {}
	local count = 40
	for i = 1, count do
		segments[i] = part({ Name = "Wave", Size = Vector3.new(1, 2.4, 1), Color = BLUE, Transparency = 0.1, Parent = Workspace })
	end
	local hit: { [Player]: boolean } = {}
	local base = Vector3.new(center.X, groundY + 1.2, center.Z)
	local started = os.clock()
	local duration = 3.2
	local maxRadius = 75
	while os.clock() - started < duration do
		local radius = 3 + (maxRadius - 3) * ((os.clock() - started) / duration)
		local length = 2 * math.pi * radius / count * 1.05
		for i, segment in segments do
			local angle = (i / count) * math.pi * 2
			segment.Size = Vector3.new(0.6, 2.4, length)
			segment.CFrame = CFrame.new(base) * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0)
		end
		for _, target in livingPlayers() do
			if not hit[target.Player] then
				local offset = target.Root.Position - base
				local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				local height = target.Root.Position.Y - groundY - 3
				if math.abs(distance - radius) < 2 and height < JUMP_CLEAR then
					hit[target.Player] = true
					hurt(target, damage)
				end
			end
		end
		task.wait(0.05)
	end
	for _, segment in segments do
		segment:Destroy()
	end
end

-- Копии: Нуль выпускает Пикселей и Стрелков по краям площади
local function summon(groundAt: (number, number) -> Vector3, healthMultiplier: number, damageMultiplier: number, count: number)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local spot = groundAt(math.cos(angle) * 30, math.sin(angle) * 30)
		EnemyService.spawn(if i % 3 == 0 then "Shooter" else "Pixel", spot, healthMultiplier, damageMultiplier)
	end
end

-- Ядро над городом краснеет в последней фазе
local function overload(on: boolean)
	local map = Workspace:FindFirstChild("MissionMap")
	local details = map and map:FindFirstChild("WorldDetails")
	if not details then
		return
	end
	for _, descendant in details:GetDescendants() do
		if descendant:IsA("BasePart") and (descendant.Name == "CoreHeart" or descendant.Name == "Segment" or descendant.Name == "CoreBeam") then
			descendant.Color = if on then RED else (if descendant.Name == "CoreHeart" then WHITE else BLUE)
		elseif descendant:IsA("PointLight") then
			descendant.Color = if on then RED else BLUE
		end
	end
end

-- Взрыв Нуля: россыпь белых кубиков и вспышка
local function shatter(position: Vector3)
	for _ = 1, 60 do
		local cube = Instance.new("Part")
		cube.Size = Vector3.one * random:NextNumber(0.6, 2)
		cube.Color = if random:NextNumber() < 0.6 then WHITE else BLUE
		cube.Material = Enum.Material.Neon
		cube.CanCollide = true
		cube.CanQuery = false
		cube.CanTouch = false
		cube.Position = position + Vector3.new(random:NextNumber(-4, 4), random:NextNumber(-8, 8), random:NextNumber(-4, 4))
		cube.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-50, 50), random:NextNumber(10, 60), random:NextNumber(-50, 50))
		cube.Parent = Workspace
		task.delay(random:NextNumber(4, 7), function()
			cube:Destroy()
		end)
	end
	local flash = part({ Name = "NullFlash", Shape = Enum.PartType.Ball, Size = Vector3.one * 8, Position = position, Color = WHITE, Parent = Workspace })
	for i = 1, 12 do
		flash.Size = Vector3.one * (8 + i * 6)
		flash.Transparency = i / 12
		task.wait(0.04)
	end
	flash:Destroy()
end

-- Осколки статуи при пробуждении
local function shatterSmall(position: Vector3)
	for _ = 1, 25 do
		local chip = Instance.new("Part")
		chip.Size = Vector3.one * random:NextNumber(0.4, 1.4)
		chip.Color = Color3.fromRGB(230, 230, 236)
		chip.Material = Enum.Material.SmoothPlastic
		chip.CanQuery = false
		chip.CanTouch = false
		chip.Position = position + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(-8, 8), random:NextNumber(-3, 3))
		chip.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-25, 25), random:NextNumber(5, 30), random:NextNumber(-25, 25))
		chip.Parent = Workspace
		task.delay(random:NextNumber(3, 5), function()
			chip:Destroy()
		end)
	end
end

---------------------------------------------------------------- Бой

-- Ведёт бой. true — Нуль побеждён, false — время вышло
function BossService.run(ctx: Context): boolean
	local ground = ctx.GroundAt(0, 0)
	local groundY = ground.Y
	local players = math.clamp(#Players:GetPlayers(), 1, 4)
	local maxHealth = math.floor(BASE_HEALTH * ctx.HealthMultiplier * (0.6 + 0.4 * players))
	local home = Vector3.new(0, groundY + HOVER, 0)
	-- появление: статуя Нуля на площади оживает — трескается и поднимается в воздух
	local map = Workspace:FindFirstChild("MissionMap")
	local statue = map and map:FindFirstChild("Monument")
	local start = if statue and statue:IsA("BasePart") then statue.Position else home + Vector3.new(0, 60, 0)
	local model, root, humanoid = build(start, maxHealth)
	if statue then
		statue:Destroy()
		shatterSmall(start)
	end
	ctx.Notify("НУЛЬ ПРОБУДИЛСЯ")
	for i = 1, 50 do
		local t = i / 50
		model:PivotTo(CFrame.new(start:Lerp(home, t * t * (3 - 2 * t))))
		task.wait(0.05)
	end

	local phase = 1
	local shieldDone = false
	local secondDoubleDone = false
	local deadline = os.clock() + BOSS_TIME_LIMIT
	local alive = true
	humanoid.Died:Connect(function()
		alive = false
	end)

	local function view()
		ctx.Update({
			Name = "НУЛЬ",
			Health = math.max(0, math.floor(humanoid.Health)),
			MaxHealth = maxHealth,
			Phase = phase,
			Shield = model:FindFirstChild("Shield") ~= nil,
			TimeLeft = math.max(0, math.floor(deadline - os.clock())),
		})
	end

	-- Нуль парит по кругу над площадью и медленно поворачивается к ближайшему игроку
	local drift = 0
	local moveConnection = RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end
		drift += dt * (if phase == 3 then 0.5 else 0.3)
		local position = home + Vector3.new(math.cos(drift) * 10, math.sin(drift * 2) * 2, math.sin(drift) * 10)
		local look = Vector3.new(0, position.Y, 1)
		local nearest, best = nil, math.huge
		for _, target in livingPlayers() do
			local distance = (target.Root.Position - position).Magnitude
			if distance < best then
				nearest, best = target.Root.Position, distance
			end
		end
		if nearest then
			look = Vector3.new(nearest.X, position.Y, nearest.Z)
		end
		model:PivotTo(CFrame.lookAt(position, look))
	end)

	-- полоска здоровья обновляется сама по себе, отдельно от атак
	local updating = true
	task.spawn(function()
		local last = -1
		while updating do
			local health = math.floor(humanoid.Health)
			if health ~= last or os.clock() % 1 < 0.25 then
				last = health
				view()
			end
			task.wait(0.25)
		end
	end)

	local attackIndex = 0
	while alive and os.clock() < deadline do
		local fraction = humanoid.Health / maxHealth
		-- щит на 60%: закройте сбои
		if not shieldDone and fraction <= 0.6 then
			shieldDone = true
			setShield(model, root, true)
			ctx.OpenNodes()
			ctx.Notify("Нуль закрылся щитом! Закройте три сбоя, чтобы его снять")
			view()
			local nextSummon = 0
			while alive and ctx.OpenNodeCount() > 0 and os.clock() < deadline do
				if os.clock() >= nextSummon and EnemyService.aliveCount() < 10 then
					nextSummon = os.clock() + 9
					summon(ctx.GroundAt, ctx.HealthMultiplier, ctx.DamageMultiplier, 4)
				end
				rainAttack(ctx.GroundAt, RAIN_DAMAGE * ctx.DamageMultiplier, 1)
				task.wait(2.5)
			end
			setShield(model, root, false)
			phase = 2
			ctx.Notify("Щит Нуля пал! Волна перезаписи — прыгайте через кольца")
			view()
			if DoppelgangerService.spawn() then
				ctx.Notify("Нуль скопировал одного из вас…")
			end
		elseif phase == 2 and fraction <= 0.3 then
			phase = 3
			overload(true)
			ctx.Notify("ПЕРЕГРУЗКА ЯДРА! Нуль в ярости")
			view()
		end

		local fast = phase == 3
		attackIndex += 1
		local pattern = attackIndex % (if phase == 1 then 3 else 4)
		local damageMultiplier = ctx.DamageMultiplier
		if pattern == 1 then
			ctx.Notify("Стирающий луч — прыгайте!")
			beamAttack(root.Position, groundY, BEAM_DAMAGE * damageMultiplier, if fast then 2 else 1, fast)
		elseif pattern == 2 then
			rainAttack(ctx.GroundAt, RAIN_DAMAGE * damageMultiplier, if fast then 3 else 2)
		elseif pattern == 3 and phase >= 2 then
			waveAttack(root.Position, groundY, WAVE_DAMAGE * damageMultiplier)
			if fast then
				task.wait(0.6)
				waveAttack(root.Position, groundY, WAVE_DAMAGE * damageMultiplier)
			end
		else
			if EnemyService.aliveCount() < 8 then
				summon(ctx.GroundAt, ctx.HealthMultiplier, ctx.DamageMultiplier, if phase == 1 then 3 else 5)
			end
			if phase == 3 and not secondDoubleDone then
				secondDoubleDone = true
				DoppelgangerService.spawn()
			end
		end
		task.wait(if fast then 1.2 else 2.2)
	end

	updating = false
	moveConnection:Disconnect()
	local won = not alive
	local position = root.Position
	if won then
		ctx.Notify("НУЛЬ СТЁРТ. СЕТЬ СПАСЕНА!")
		model:Destroy()
		shatter(position)
	else
		ctx.Notify("Нуль перезаписал Сеть…")
		model:Destroy()
	end
	overload(false)
	EnemyService.clear()
	DoppelgangerService.clear()
	ctx.Update(nil)
	return won
end

return BossService
