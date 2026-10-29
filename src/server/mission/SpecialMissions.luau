--!strict
-- Особые задания, непохожие на «дойди и подержи кнопку» (вызывает MissionService):
--   «Подъём» (Climb) — паркур: по парящим платформам вокруг самого высокого дома забраться на крышу и включить
--     маяк. Часть платформ глитчит — на секунду исчезает. Каждая шестая — точка сохранения: кто сорвался, тот
--     возвращается на последнюю. Снизу по карабкающимся стреляют Стрелки.
--   «Прятки» (Hide) — ужастик: по улицам бродят бессмертные Стиратели с красными прожекторами. Нужно собрать
--     данные и добраться до эвакуации на площади. Кто попал в свет Стирателя — за тем погоня; спастись можно
--     в укрытии (светящаяся капсула), там Стиратели не видят.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local EnemyService = require(script.Parent.EnemyService)

export type Context = {
	GroundAt: (x: number, z: number) -> Vector3,
	Notify: (text: string) -> (),
	Say: (speaker: string, text: string) -> (),
	SetObjective: (text: string, progress: number, total: number) -> (),
	HealthMultiplier: number,
	DamageMultiplier: number,
	Color: Color3, -- цвет мира для платформ и маяков
}

local STREETS = { -90, -30, 30, 90 }

local SpecialMissions = {}

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

local function living(): { { Player: Player, Root: BasePart, Humanoid: Humanoid } }
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

local function holdPrompt(parent: Instance, action: string, object: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

---------------------------------------------------------------- Подъём

-- Самый высокий дом города (без стены по краю карты)
local function tallestBuilding(map: Instance): BasePart?
	local best: BasePart? = nil
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == "Building" and not descendant:FindFirstAncestor("Boundary") then
			local body = descendant:FindFirstChild("Body")
			if body and body:IsA("BasePart") and (not best or body.Size.Y > best.Size.Y) then
				best = body
			end
		end
	end
	return best
end

function SpecialMissions.climb(ctx: Context, map: Instance)
	local body = tallestBuilding(map)
	if not body then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClimbRoute"
	folder.Parent = Workspace

	local base = body.Position - Vector3.new(0, body.Size.Y / 2, 0)
	local top = base.Y + body.Size.Y
	local radius = math.max(body.Size.X, body.Size.Z) / 2 + 6
	local stepHeight = 4.5
	local count = math.max(8, math.floor((body.Size.Y + 2) / stepHeight))
	local checkpoints: { BasePart } = {}
	local glitchy: { BasePart } = {}
	local angle = random:NextNumber(0, math.pi * 2)
	local angleStep = 6 / radius -- около 6 студов по кругу между платформами — легко допрыгнуть и с телефона

	for i = 1, count do
		angle += angleStep
		local y = base.Y + i * stepHeight
		local position = Vector3.new(base.X + math.cos(angle) * radius, y, base.Z + math.sin(angle) * radius)
		local isCheckpoint = i % 6 == 0
		local platform = part({
			Name = if isCheckpoint then "Checkpoint" else "Step",
			Size = if isCheckpoint then Vector3.new(8, 1, 8) else Vector3.new(5.5, 1, 5.5),
			CFrame = CFrame.lookAt(position, Vector3.new(base.X, y, base.Z)),
			Color = if isCheckpoint then Color3.fromRGB(80, 255, 120) else Color3.fromRGB(30, 34, 46),
			Material = if isCheckpoint then Enum.Material.Neon else Enum.Material.Metal,
			CanCollide = true,
			CanQuery = true,
			Parent = folder,
		})
		-- светящийся край у каждой ступени, чтобы путь было видно издалека
		part({
			Name = "Edge",
			Size = Vector3.new(platform.Size.X + 0.2, 0.15, platform.Size.Z + 0.2),
			CFrame = platform.CFrame * CFrame.new(0, 0.5, 0),
			Color = ctx.Color,
			Transparency = 0.3,
			Parent = platform,
		})
		if isCheckpoint then
			table.insert(checkpoints, platform)
		elseif i > 3 and random:NextNumber() < 0.3 then
			table.insert(glitchy, platform)
		end
	end
	-- крыша: широкая площадка и маяк
	local roof = part({
		Name = "Roof",
		Size = Vector3.new(12, 1, 12),
		Position = Vector3.new(base.X, top + 1, base.Z),
		Color = Color3.fromRGB(30, 34, 46),
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	local beacon = part({
		Name = "Beacon",
		Size = Vector3.new(2, 6, 2),
		Position = roof.Position + Vector3.new(0, 3.5, 0),
		Color = ctx.Color,
		CanCollide = true,
		Parent = folder,
	})
	local beam = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(200, 2, 2),
		CFrame = CFrame.new(beacon.Position + Vector3.new(0, 100, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ctx.Color,
		Transparency = 0.7,
		Parent = folder,
	})
	-- последняя ступень к крыше
	local lastAngle = angle + angleStep
	part({
		Name = "Step",
		Size = Vector3.new(5.5, 1, 5.5),
		Position = Vector3.new(base.X + math.cos(lastAngle) * (radius - 3), top - 1.5, base.Z + math.sin(lastAngle) * (radius - 3)),
		Color = Color3.fromRGB(30, 34, 46),
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})

	local done = false
	local prompt = holdPrompt(beacon, "Запустить маяк", "Маяк", 2)
	prompt.Triggered:Connect(function(player)
		if done then
			return
		end
		done = true
		beam.Transparency = 0.2
		ctx.Notify(`{player.DisplayName} запустил маяк на крыше!`)
	end)

	-- начало маршрута: светящийся круг на земле под первой ступенью
	local firstAngle = angle - angleStep * count
	local start = ctx.GroundAt(base.X + math.cos(firstAngle) * radius, base.Z + math.sin(firstAngle) * radius)
	part({
		Name = "Start",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 9, 9),
		CFrame = CFrame.new(start + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 255, 120),
		Transparency = 0.3,
		Parent = folder,
	})
	-- точка возврата у каждого игрока — самая высокая достигнутая контрольная площадка
	local reached: { [Player]: number } = {}
	ctx.Notify("Поднимайтесь по платформам на крышу! Зелёные — точки сохранения")

	local glitchPhase = 0
	local lastShooter = 0
	local best = 0
	while not done do
		-- глитч-платформы мигают: полторы секунды из каждых четырёх их нет
		glitchPhase = (glitchPhase + 0.25) % 4
		for _, platform in glitchy do
			local gone = glitchPhase >= 2.5
			platform.CanCollide = not gone
			platform.Transparency = if gone then 0.85 else (if glitchPhase >= 2 then 0.4 else 0)
			platform.Color = if glitchPhase >= 2 then Color3.fromRGB(255, 60, 160) else Color3.fromRGB(30, 34, 46)
		end
		for _, target in living() do
			local y = target.Root.Position.Y
			for index, checkpoint in checkpoints do
				local offset = target.Root.Position - checkpoint.Position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude < 5 and math.abs(offset.Y - 3) < 3 and index > (reached[target.Player] or 0) then
					reached[target.Player] = index
					if index > best then
						best = index
					end
				end
			end
			-- сорвался ниже своей точки — обратно на неё (или к началу маршрута)
			local index = reached[target.Player] or 0
			local floor = if index > 0 then checkpoints[index].Position.Y - 10 else -50
			if index > 0 and y < floor then
				target.Root.CFrame = CFrame.new(checkpoints[index].Position + Vector3.new(0, 4, 0))
				target.Root.AssemblyLinearVelocity = Vector3.zero
			end
		end
		-- Стрелки снизу мешают, но не толпой
		if os.clock() - lastShooter > 9 and EnemyService.aliveCount() < 4 then
			lastShooter = os.clock()
			local streetAngle = random:NextNumber(0, math.pi * 2)
			EnemyService.spawn("Shooter", ctx.GroundAt(base.X + math.cos(streetAngle) * (radius + 14), base.Z + math.sin(streetAngle) * (radius + 14)),
				ctx.HealthMultiplier, ctx.DamageMultiplier * 0.6)
		end
		ctx.SetObjective("Поднимитесь на крышу · точки", best, #checkpoints)
		task.wait(0.25)
	end
	task.wait(2)
	folder:Destroy()
	EnemyService.clear()
end

---------------------------------------------------------------- Прятки

-- Стиратель: высокая чёрная фигура без лица с красной полосой-визором и прожектором вперёд. Бессмертен —
-- не тег "Enemy", пули сквозь него не считаются
local function buildEraser(position: Vector3): (Model, BasePart, Humanoid, SpotLight)
	local model = Instance.new("Model")
	model.Name = "Стиратель"
	local root = part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(2.5, 5, 1.6),
		Position = position + Vector3.new(0, 7.5, 0),
		Color = Color3.fromRGB(8, 8, 10),
		Material = Enum.Material.SmoothPlastic,
		Anchored = false,
		CanCollide = true,
		Parent = model,
	})
	local head = part({
		Name = "Head",
		Size = Vector3.new(1.6, 1.8, 1.6),
		CFrame = root.CFrame * CFrame.new(0, 3.4, 0),
		Color = Color3.fromRGB(8, 8, 10),
		Material = Enum.Material.SmoothPlastic,
		Anchored = false,
		Massless = true,
		Parent = model,
	})
	local visor = part({
		Name = "Visor",
		Size = Vector3.new(1.4, 0.3, 0.1),
		CFrame = head.CFrame * CFrame.new(0, 0.2, -0.82),
		Color = Color3.fromRGB(255, 30, 40),
		Anchored = false,
		Massless = true,
		Parent = model,
	})
	for _, piece in { head, visor } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = piece
		weld.Parent = piece
	end
	-- тёмная дымка вокруг — видно издалека, что это не обычный враг
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(10, 10, 12))
	smoke.Size = NumberSequence.new(2, 4)
	smoke.Transparency = NumberSequence.new(0.6, 1)
	smoke.Lifetime = NumberRange.new(1, 1.6)
	smoke.Rate = 14
	smoke.Speed = NumberRange.new(0.5, 1)
	smoke.Parent = root
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 55
	light.Range = 40
	light.Brightness = 6
	light.Color = Color3.fromRGB(255, 40, 50)
	light.Parent = head
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = "Стиратель"
	humanoid.WalkSpeed = 12
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	-- парит высоко: проплывает над барьерами и укрытиями на улицах, а не застревает в них (и выглядит жутче)
	humanoid.HipHeight = 4.5
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = Workspace
	root:SetNetworkOwner(nil)
	return model, root, humanoid, light
end

-- Перекрёсток рядом: Стиратели ходят только по улицам, от перекрёстка к соседнему
local function neighbourCrossing(current: Vector2): Vector2
	local options = {}
	local ix = table.find(STREETS, current.X) or 1
	local iz = table.find(STREETS, current.Y) or 1
	for _, d in { -1, 1 } do
		if STREETS[ix + d] then
			table.insert(options, Vector2.new(STREETS[ix + d], current.Y))
		end
		if STREETS[iz + d] then
			table.insert(options, Vector2.new(current.X, STREETS[iz + d]))
		end
	end
	return options[random:NextInteger(1, #options)]
end

local function canSee(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(from, to - from, params)
	return hit == nil
end

function SpecialMissions.hide(ctx: Context, erasers: number, fragments: number)
	local folder = Instance.new("Folder")
	folder.Name = "HideMission"
	folder.Parent = Workspace

	-- укрытия: тёмные капсулы со светящимся контуром на тротуарах у перекрёстков
	local shelters: { Vector3 } = {}
	for _, x in STREETS do
		for _, z in STREETS do
			if random:NextNumber() < 0.6 then
				local spot = ctx.GroundAt(x + 9, z + 9)
				local pod = part({
					Name = "Shelter",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(7, 6, 6),
					CFrame = CFrame.new(spot + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(20, 40, 60),
					Material = Enum.Material.ForceField,
					Transparency = 0.2,
					Parent = folder,
				})
				local glow = Instance.new("PointLight")
				glow.Color = Color3.fromRGB(80, 200, 255)
				glow.Range = 10
				glow.Parent = pod
				table.insert(shelters, spot)
			end
		end
	end

	-- данные по городу
	local found = 0
	for i = 1, fragments do
		local street = STREETS[random:NextInteger(1, #STREETS)]
		local along = random:NextNumber(-110, 110)
		local x, z = street + random:NextNumber(-4, 4), along
		if i % 2 == 0 then
			x, z = z, x
		end
		local spot = ctx.GroundAt(x, z)
		local cube = part({
			Name = "Data",
			Size = Vector3.one * 1.4,
			CFrame = CFrame.new(spot + Vector3.new(0, 2.5, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			Color = Color3.fromRGB(80, 200, 255),
			Parent = folder,
		})
		cube:SetAttribute("Spin", Vector3.new(30, 60, 0))
		CollectionService:AddTag(cube, "Motion")
		local prompt = holdPrompt(cube, "Забрать", "Данные", 1)
		prompt.Triggered:Connect(function(player)
			if cube.Parent then
				cube:Destroy()
				found += 1
				ctx.Notify(`{player.DisplayName} забрал данные ({found}/{fragments})`)
			end
		end)
	end

	-- Стиратели на дальних перекрёстках
	type Eraser = { Model: Model, Root: BasePart, Humanoid: Humanoid, Light: SpotLight, Target: Vector2, Chasing: Player?, LastHit: number }
	local list: { Eraser } = {}
	for _ = 1, erasers do
		local crossing = Vector2.new(STREETS[random:NextInteger(1, #STREETS)], ({ -90, 90 })[random:NextInteger(1, 2)])
		local model, root, humanoid, light = buildEraser(ctx.GroundAt(crossing.X, crossing.Y))
		model.Parent = folder
		table.insert(list, { Model = model, Root = root, Humanoid = humanoid, Light = light, Target = neighbourCrossing(crossing), Chasing = nil, LastHit = 0 })
	end
	ctx.Say("Вега (связь)", "Стиратели не умирают. Не попадайся в их свет. Прячься в капсулах — там они тебя не видят.")

	local function sheltered(position: Vector3): boolean
		for _, spot in shelters do
			local offset = position - spot
			if Vector3.new(offset.X, 0, offset.Z).Magnitude < 4 then
				return true
			end
		end
		return false
	end

	-- точка эвакуации на площади появляется, когда собраны все данные
	local evacuated = false
	local evac: BasePart? = nil
	while not evacuated do
		local players = living()
		for _, target in players do
			target.Player:SetAttribute("Hidden", sheltered(target.Root.Position))
		end
		for _, eraser in list do
			local position = eraser.Root.Position
			local look = eraser.Root.CFrame.LookVector
			-- кого видит: в конусе прожектора, близко, не в укрытии, без стен между
			local seen: Player? = nil
			local seenRoot: BasePart? = nil
			for _, target in players do
				local offset = target.Root.Position - position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local inCone = flat.Magnitude < 4 or (flat.Magnitude < 38 and flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) > 0.55)
				if inCone and not target.Player:GetAttribute("Hidden") and canSee(position, target.Root.Position, { eraser.Model, target.Root.Parent :: Instance }) then
					seen, seenRoot = target.Player, target.Root
				end
			end
			if seen and seenRoot then
				if eraser.Chasing ~= seen then
					ctx.Notify(`Стиратель заметил {seen.DisplayName}! Беги в укрытие!`)
				end
				eraser.Chasing = seen
				eraser.Humanoid.WalkSpeed = 19
				eraser.Light.Brightness = 12
				eraser.Humanoid:MoveTo(seenRoot.Position)
				-- поймал — сильный удар и отбрасывание
				if Vector3.new(seenRoot.Position.X - position.X, 0, seenRoot.Position.Z - position.Z).Magnitude < 5 and os.clock() - eraser.LastHit > 1.2 then
					eraser.LastHit = os.clock()
					local humanoid = seenRoot.Parent and (seenRoot.Parent :: Instance):FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid:TakeDamage(35 * ctx.DamageMultiplier)
					end
					local push = Vector3.new(seenRoot.Position.X - position.X, 0, seenRoot.Position.Z - position.Z)
					if push.Magnitude > 0.1 then
						seenRoot.AssemblyLinearVelocity = push.Unit * 60 + Vector3.new(0, 30, 0)
					end
				end
			else
				-- потерял из виду — обратно в обход по улицам
				if eraser.Chasing then
					eraser.Chasing = nil
					local here = Vector2.new(position.X, position.Z)
					local nearest = eraser.Target
					local best = math.huge
					for _, x in STREETS do
						for _, z in STREETS do
							local d = (Vector2.new(x, z) - here).Magnitude
							if d < best then
								nearest, best = Vector2.new(x, z), d
							end
						end
					end
					eraser.Target = nearest
				end
				eraser.Humanoid.WalkSpeed = 12
				eraser.Light.Brightness = 6
				local goal = ctx.GroundAt(eraser.Target.X, eraser.Target.Y)
				if Vector3.new(goal.X - position.X, 0, goal.Z - position.Z).Magnitude < 3 then
					eraser.Target = neighbourCrossing(eraser.Target)
				end
				eraser.Humanoid:MoveTo(goal)
			end
		end

		if found >= fragments and not evac then
			local spot = ctx.GroundAt(0, 0)
			local pad = part({
				Name = "Evac",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 10, 10),
				CFrame = CFrame.new(spot + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(80, 255, 140),
				CanCollide = true,
				Parent = folder,
			})
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(120, 3, 3),
				CFrame = CFrame.new(spot + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(80, 255, 140),
				Transparency = 0.6,
				Parent = folder,
			})
			evac = pad
			ctx.Notify("Все данные собраны! Бегите на площадь и встаньте в зелёный круг")
		end
		-- эвакуация: кто-то из отряда встал в зелёный круг
		if evac then
			for _, target in players do
				local offset = target.Root.Position - evac.Position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude < 5 and not evacuated then
					evacuated = true
					ctx.Notify(`{target.Player.DisplayName} добрался до эвакуации!`)
				end
			end
		end
		if evac then
			ctx.SetObjective("Встаньте в зелёный круг на площади", fragments, fragments)
		else
			ctx.SetObjective("Соберите данные, не попадаясь Стирателям", found, fragments)
		end
		task.wait(0.25)
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Hidden", nil)
	end
	task.wait(1.5)
	folder:Destroy()
end

return SpecialMissions
