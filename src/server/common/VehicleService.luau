--!strict
-- Машины на воздушной подушке. Работает и в Штабе, и в Миссии.
-- Машина парит над землёй на заданной высоте: сервер каждый кадр смотрит, где земля под ней,
-- и толкает её вверх-вниз, а газ и руль берёт из сиденья водителя (VehicleSeat).
-- Поэтому машина не переворачивается и не застревает на бордюрах.
-- Водитель управляет W/S и A/D (на телефоне — джойстиком), выходит прыжком.
-- Пассажиры садятся на свободные сиденья, просто подойдя к ним.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PassService = require(script.Parent.PassService)
local VehicleDesigns = require(script.Parent.VehicleDesigns)

local MAX_VEHICLES = 6 -- больше машин на сервере не бывает
local LEAN = 0.12 -- наклон в повороте, радиан
local GROUND_RAY = 30
local FALL_SPEED = 40
-- Реактивный прыжок с сальто: взлёт, полный оборот в воздухе, посадка
local FLIP_TIME = 1.5
local FLIP_UP = 40 -- начальная скорость вверх
local FLIP_GRAVITY = 53
local FLIP_SPIN = 1.2 -- за сколько секунд машина делает полный оборот
local FLAME_TIME = 0.6

type Vehicle = {
	Model: Model,
	Chassis: BasePart,
	Seat: VehicleSeat,
	Kind: Config.VehicleKind,
	Owner: Player,
	Speed: number,
	Yaw: number,
	Velocity: LinearVelocity,
	Align: AlignOrientation,
	EmptySince: number?,
	FlipStart: number?,
	LastFlip: number,
	Flame: ParticleEmitter?,
	NitroUntil: number,
	LastNitro: number,
}

local VehicleService = {}

local applyTuning: (Player, Model) -> ()

local vehicles: { [Model]: Vehicle } = {}
local folder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Прячет или показывает персонажа (в детальном кузове седок не торчит из крыши)
local function setHidden(character: Model, hidden: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			if hidden then
				if descendant:GetAttribute("RideTransparency") == nil then
					descendant:SetAttribute("RideTransparency", descendant.Transparency)
				end
				descendant.Transparency = 1
			else
				local original = descendant:GetAttribute("RideTransparency")
				if typeof(original) == "number" then
					descendant.Transparency = original
					descendant:SetAttribute("RideTransparency", nil)
				end
			end
		end
	end
end

-- Корпус по дизайну, подсветка снизу и сиденья. display = true — витринная копия без сидений и физики
local function build(kind: Config.VehicleKind, cf: CFrame, display: boolean?): (Model, BasePart, VehicleSeat?)
	local model = Instance.new("Model")
	model.Name = kind.Name
	local size = kind.Size

	local chassis = part({
		Name = "Chassis",
		Size = size,
		CFrame = cf,
		Color = kind.Color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
		CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, 0.2),
		Anchored = display == true,
		CanCollide = display ~= true, -- сквозь витрину можно пройти к подсказке
		Parent = model,
	})

	-- Деталь-украшение, приваренная к корпусу; offset — относительно корпуса
	local function piece(className: string, pieceSize: Vector3, offset: CFrame, props: { [string]: any }?): BasePart
		local p = Instance.new(className) :: BasePart
		p.Size = pieceSize
		p.CFrame = cf * offset
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Anchored = display == true
		if props then
			for key, value in props do
				(p :: any)[key] = value
			end
		end
		p.Parent = model
		if not display then
			weld(chassis, p)
		end
		return p
	end

	local design = (VehicleDesigns :: any)[kind.Design] or VehicleDesigns.Transporter
	local shell = VehicleDesigns.findShell(kind.Id)
	local seatSpots: { Vector3 }
	if shell then
		-- Детальный кузов-модель: корпус становится невидимым, детали из кода не нужны (берём только места сидений)
		chassis.Transparency = 1
		seatSpots = design(VehicleDesigns.noPiece, kind)
		-- В детальном кузове садимся пониже, чтобы игрок был внутри, а не на крыше
		for i, spot in seatSpots do
			seatSpots[i] = Vector3.new(spot.X, -size.Y / 2 + 0.6, spot.Z)
		end
		VehicleDesigns.attachShell(shell, chassis, kind, display == true, weld)
	else
		seatSpots = design(piece, kind)
	end

	-- Подсветка снизу
	local glow = piece("Part", Vector3.new(size.X * 0.8, 0.2, size.Z * 0.8), CFrame.new(0, -size.Y / 2 - 0.15, 0), {
		Name = "Underglow",
		Color = kind.GlowColor,
		Material = Enum.Material.Neon,
		Transparency = if shell then 0.75 else 0.3,
	})
	local light = Instance.new("PointLight")
	light.Color = kind.GlowColor
	light.Range = 14
	light.Brightness = if shell then 0.8 else 2
	light.Parent = glow

	-- Сиденья (невидимые): первое — водителя
	local driver: VehicleSeat? = nil
	if not display then
		for i = 1, math.min(kind.Seats, #seatSpots) do
			local spot = seatSpots[i]
			local seat: Seat | VehicleSeat
			if i == 1 then
				local vehicleSeat = Instance.new("VehicleSeat")
				vehicleSeat.Name = "DriverSeat"
				vehicleSeat.HeadsUpDisplay = false
				vehicleSeat.MaxSpeed = 0
				vehicleSeat.Torque = 0
				driver = vehicleSeat
				seat = vehicleSeat
			else
				seat = Instance.new("Seat")
				seat.Name = `Seat{i}`
			end
			seat.Size = Vector3.new(2, 1, 2)
			seat.CFrame = cf * CFrame.new(spot)
			seat.Transparency = 1 -- сиденья не видны, сидеть на них можно
			seat.Massless = true
			seat.Parent = model
			weld(chassis, seat)
			if shell then
				local rider: Model? = nil
				seat:GetPropertyChangedSignal("Occupant"):Connect(function()
					if rider then
						setHidden(rider, false)
						rider = nil
					end
					local occupant = seat.Occupant
					if occupant and occupant.Parent and occupant.Parent:IsA("Model") then
						rider = occupant.Parent :: Model
						setHidden(rider :: Model, true)
					end
				end)
			end
		end
	end

	model.PrimaryPart = chassis
	return model, chassis, driver
end

local function destroy(vehicle: Vehicle)
	vehicles[vehicle.Model] = nil
	vehicle.Model:Destroy()
end

local function groundBelow(vehicle: Vehicle): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(vehicle.Chassis.Position, Vector3.new(0, -GROUND_RAY, 0), params)
	return if hit then hit.Position.Y else nil
end

local function update(vehicle: Vehicle, dt: number, now: number)
	local kind = vehicle.Kind
	local seat = vehicle.Seat
	local occupied = seat.Occupant ~= nil
	local throttle = if occupied then seat.ThrottleFloat else 0
	local steer = if occupied then seat.SteerFloat else 0

	-- Упала с карты — исчезает
	if vehicle.Chassis.Position.Y < Workspace.FallenPartsDestroyHeight + 50 or vehicle.Chassis.Position.Y < -60 then
		destroy(vehicle)
		return
	end

	-- Пустая машина со временем исчезает
	local anyone = occupied
	for _, child in vehicle.Model:GetChildren() do
		if child:IsA("Seat") and child.Occupant then
			anyone = true
		end
	end
	if anyone then
		vehicle.EmptySince = nil
	elseif not vehicle.EmptySince then
		vehicle.EmptySince = now
	elseif now - vehicle.EmptySince > Config.VehicleIdleDespawn then
		destroy(vehicle)
		return
	end

	-- Скорость плавно стремится к нужной; тормозит вдвое резче
	local nitro = now < vehicle.NitroUntil
	local maxSpeed = if nitro then kind.MaxSpeed * Config.NitroMultiplier else kind.MaxSpeed
	local target = if throttle > 0 then throttle * maxSpeed elseif throttle < 0 then throttle * kind.ReverseSpeed else 0
	local braking = target == 0 or (target > 0) ~= (vehicle.Speed > 0)
	local step = kind.Acceleration * dt * (if braking then 2 elseif nitro then 2.5 else 1)
	if math.abs(target - vehicle.Speed) <= step then
		vehicle.Speed = target
	else
		vehicle.Speed += if target > vehicle.Speed then step else -step
	end

	-- Упёрлись в стену — скорость падает до настоящей
	local forward = CFrame.Angles(0, vehicle.Yaw, 0).LookVector
	local actual = vehicle.Chassis.AssemblyLinearVelocity:Dot(forward)
	if math.abs(actual) < math.abs(vehicle.Speed) - 15 then
		vehicle.Speed = actual
	end

	-- Руль: на месте почти не поворачивает, задом — в обратную сторону
	local turnFactor = math.clamp(math.abs(vehicle.Speed) / 15, 0, 1)
	local direction = if vehicle.Speed < 0 then -1 else 1
	vehicle.Yaw -= steer * kind.TurnSpeed * dt * turnFactor * direction
	forward = CFrame.Angles(0, vehicle.Yaw, 0).LookVector

	-- Реактивный прыжок: летим по дуге и делаем полный оборот
	if vehicle.FlipStart then
		local t = now - vehicle.FlipStart
		if t < FLIP_TIME then
			local pitch = math.pi * 2 * math.min(t / FLIP_SPIN, 1)
			vehicle.Velocity.VectorVelocity = forward * vehicle.Speed + Vector3.new(0, FLIP_UP - FLIP_GRAVITY * t, 0)
			vehicle.Align.CFrame = CFrame.Angles(0, vehicle.Yaw, 0) * CFrame.Angles(pitch, 0, 0)
			if vehicle.Flame then
				vehicle.Flame.Enabled = t < FLAME_TIME
			end
			return
		end
		vehicle.FlipStart = nil
		vehicle.Align.Responsiveness = 25
	end
	if vehicle.Flame then
		vehicle.Flame.Enabled = nitro
	end

	-- Парение: держим высоту над землёй, без земли — падаем
	local groundY = groundBelow(vehicle)
	local vertical = -FALL_SPEED
	if groundY then
		local wanted = groundY + kind.HoverHeight + kind.Size.Y / 2
		vertical = math.clamp((wanted - vehicle.Chassis.Position.Y) * 5, -FALL_SPEED, FALL_SPEED)
	end

	vehicle.Velocity.VectorVelocity = forward * vehicle.Speed + Vector3.new(0, vertical, 0)
	vehicle.Align.CFrame = CFrame.Angles(0, vehicle.Yaw, 0) * CFrame.Angles(0, 0, steer * LEAN * turnFactor)
end

local function count(): number
	local n = 0
	for _ in vehicles do
		n += 1
	end
	return n
end

-- Неоновый тюнинг: светящийся контур и след за машиной цвета, выбранного владельцем
local function tuningColor(player: Player): Color3
	local index = player:GetAttribute("CarColor")
	return Config.CarColors[if typeof(index) == "number" then index else 1] or Config.CarColors[1]
end

applyTuning = function(player: Player, model: Model)
	local chassis = model.PrimaryPart
	if not chassis or not PassService.owns(player, "NeonTuning") then
		return
	end
	local color = tuningColor(player)
	local outline = model:FindFirstChild("TuningOutline") :: Highlight?
	if not outline then
		local created = Instance.new("Highlight")
		created.Name = "TuningOutline"
		created.FillTransparency = 1
		created.DepthMode = Enum.HighlightDepthMode.Occluded
		created.Parent = model
		outline = created
	end
	(outline :: Highlight).OutlineColor = color

	local trail = chassis:FindFirstChild("TuningTrail") :: Trail?
	if not trail then
		local size = chassis.Size
		local left = Instance.new("Attachment")
		left.Name = "TrailLeft"
		left.Position = Vector3.new(-size.X / 2, -size.Y / 2, size.Z / 2)
		left.Parent = chassis
		local right = Instance.new("Attachment")
		right.Name = "TrailRight"
		right.Position = Vector3.new(size.X / 2, -size.Y / 2, size.Z / 2)
		right.Parent = chassis
		local created = Instance.new("Trail")
		created.Name = "TuningTrail"
		created.Attachment0 = left
		created.Attachment1 = right
		created.Lifetime = 0.6
		created.LightEmission = 1
		created.Transparency = NumberSequence.new(0.2, 1)
		created.Parent = chassis
		trail = created
	end
	(trail :: Trail).Color = ColorSequence.new(color)
end

-- Вызывает машину игрока в точку cf (старая машина этого игрока исчезает).
-- Возвращает модель или nil и причину.
function VehicleService.spawnFor(player: Player, kindId: string, cf: CFrame): (Model?, string?)
	local kind = Config.Vehicles[kindId]
	if not kind then
		return nil, "Такой машины нет."
	end
	for _, vehicle in vehicles do
		if vehicle.Owner == player then
			destroy(vehicle)
		end
	end
	if count() >= MAX_VEHICLES then
		return nil, "На трассе уже слишком много машин. Попробуй позже."
	end

	local model, chassis, seat = build(kind, cf)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Root"
	attachment.Parent = chassis

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = 400000
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = chassis

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = 10000000
	align.Responsiveness = 25
	align.CFrame = cf.Rotation
	align.Parent = chassis

	model:SetAttribute("Owner", player.UserId)
	model.Parent = folder
	chassis:SetNetworkOwner(nil) -- машину считает сервер: так её нельзя «разогнать» читами

	-- Огонь из сопел для реактивного прыжка (горит только во время взлёта)
	local nozzle = Instance.new("Attachment")
	nozzle.Name = "Nozzle"
	nozzle.Position = Vector3.new(0, 0, kind.Size.Z / 2)
	nozzle.Parent = chassis
	local flame = Instance.new("ParticleEmitter")
	flame.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), kind.GlowColor)
	flame.LightEmission = 1
	flame.Size = NumberSequence.new(1.6, 0)
	flame.Transparency = NumberSequence.new(0, 1)
	flame.Lifetime = NumberRange.new(0.25, 0.4)
	flame.Rate = 250
	flame.Speed = NumberRange.new(25, 35)
	flame.SpreadAngle = Vector2.new(12, 12)
	flame.EmissionDirection = Enum.NormalId.Back
	flame.Enabled = false
	flame.Parent = nozzle

	local look = cf.LookVector
	vehicles[model] = {
		Model = model,
		Chassis = chassis,
		Seat = seat :: VehicleSeat,
		Kind = kind,
		Owner = player,
		Speed = 0,
		Yaw = math.atan2(-look.X, -look.Z),
		Velocity = velocity,
		Align = align,
		EmptySince = nil,
		FlipStart = nil,
		LastFlip = 0,
		Flame = flame,
		NitroUntil = 0,
		LastNitro = 0,
	}
	applyTuning(player, model)

	-- Кнопка «Сесть»: сиденья невидимые и спрятаны в кузове, на телефоне в них не попасть — сажаем по кнопке
	-- (водитель первым, остальные — на свободные места)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Enter"
	prompt.ActionText = "Сесть"
	prompt.ObjectText = kind.Name
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = chassis
	prompt.Triggered:Connect(function(rider)
		local humanoid = rider.Character and rider.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then
			return
		end
		local seats: { Seat | VehicleSeat } = {}
		for _, child in model:GetChildren() do
			if (child:IsA("VehicleSeat") or child:IsA("Seat")) and not child.Occupant then
				table.insert(seats, child)
			end
		end
		table.sort(seats, function(a, b)
			return a:IsA("VehicleSeat") and not b:IsA("VehicleSeat")
		end)
		if seats[1] then
			seats[1]:Sit(humanoid)
		end
	end)
	-- кнопка видна только тем, кто ещё не сидит в этой машине
	local function refreshPrompt()
		local free = false
		for _, child in model:GetChildren() do
			if (child:IsA("VehicleSeat") or child:IsA("Seat")) and not child.Occupant then
				free = true
			end
		end
		prompt.Enabled = free
	end
	for _, child in model:GetChildren() do
		if child:IsA("VehicleSeat") or child:IsA("Seat") then
			child:GetPropertyChangedSignal("Occupant"):Connect(refreshPrompt)
		end
	end

	-- Тот, кто вызвал машину, сразу садится за руль
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and not humanoid.SeatPart and seat then
		task.defer(function()
			if seat.Parent and not seat.Occupant then
				seat:Sit(humanoid)
			end
		end)
	end
	return model, nil
end

-- Убирает машину (например, её догнала стена вируса)
function VehicleService.despawn(model: Model)
	local vehicle = vehicles[model]
	if vehicle then
		destroy(vehicle)
	end
end

-- Убирает все машины
function VehicleService.clear()
	for _, vehicle in vehicles do
		destroy(vehicle)
	end
end

-- Все машины на сервере
function VehicleService.all(): { Model }
	local list = {}
	for model in vehicles do
		table.insert(list, model)
	end
	return list
end

-- Неподвижная витринная копия машины (для автосалона)
function VehicleService.buildDisplay(kindId: string, cf: CFrame): Model?
	local kind = Config.Vehicles[kindId]
	if not kind then
		return nil
	end
	local model = build(kind, cf, true)
	return model
end

function VehicleService.start()
	VehicleDesigns.loadShells()
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = Workspace

	Players.PlayerRemoving:Connect(function(player)
		for _, vehicle in vehicles do
			if vehicle.Owner == player then
				destroy(vehicle)
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, vehicle in vehicles do
			update(vehicle, dt, now)
		end
	end)

	-- Реактивный прыжок: только водитель, только с пропуском, только с земли и не чаще перезарядки
	local notify = Remotes.get("Notify")
	Remotes.get("VehicleAction").OnServerEvent:Connect(function(player, action: any)
		if action == "Color" then
			if not PassService.owns(player, "NeonTuning") then
				notify:FireClient(player, "Цвет машины меняется с пропуском «Неоновый тюнинг».")
				return
			end
			local index = player:GetAttribute("CarColor")
			local nextIndex = (if typeof(index) == "number" then index else 1) % #Config.CarColors + 1
			player:SetAttribute("CarColor", nextIndex)
			for _, vehicle in vehicles do
				if vehicle.Owner == player then
					applyTuning(player, vehicle.Model)
				end
			end
			return
		end
		if action == "Nitro" then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			for _, vehicle in vehicles do
				if humanoid and vehicle.Seat.Occupant == humanoid then
					if not PassService.owns(player, "Nitro") then
						notify:FireClient(player, "Нитро — в магазине.")
						return
					end
					local now = os.clock()
					if now - vehicle.LastNitro >= Config.NitroCooldown then
						vehicle.LastNitro = now
						vehicle.NitroUntil = now + Config.NitroDuration
					end
					return
				end
			end
			return
		end
		if action ~= "Flip" then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		for _, vehicle in vehicles do
			if humanoid and vehicle.Seat.Occupant == humanoid then
				if not PassService.owns(player, "Thrusters") then
					notify:FireClient(player, "Реактивный прыжок — в магазине: «Реактивные сопла».")
					return
				end
				local now = os.clock()
				if vehicle.FlipStart or now - vehicle.LastFlip < Config.VehicleFlipCooldown then
					return
				end
				local groundY = groundBelow(vehicle)
				local height = groundY and vehicle.Chassis.Position.Y - groundY
				if not height or height > vehicle.Kind.HoverHeight + vehicle.Kind.Size.Y / 2 + 1.5 then
					return -- уже в воздухе
				end
				vehicle.FlipStart = now
				vehicle.LastFlip = now
				vehicle.Align.Responsiveness = 200
				return
			end
		end
	end)
end

return VehicleService
