--!strict
-- Стрельба на сервере. Клиент рисует выстрел сразу и присылает, откуда и куда стрелял,
-- а сервер сам решает, было ли попадание: проверяет патроны, скорострельность,
-- точку выстрела и разброс, затем пускает свой луч (он упирается в стены) и наносит урон.
-- Попасть можно только во врагов (тег "Enemy"): игроки друг друга не ранят.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local BoostEffects = require(script.Parent.BoostEffects)

local MAX_ORIGIN_OFFSET = 10 -- насколько точка выстрела может отличаться от головы на сервере
local RATE_TOLERANCE = 0.7 -- допускаем выстрелы чуть чаще нормы из-за задержек сети
local SPREAD_TOLERANCE = 2 -- градусов сверх разброса оружия

type PlayerState = {
	Equipped: string,
	Ammo: { [string]: number }, -- патроны в магазине; у бесконечного оружия записи нет
	LastFire: number,
	ReloadingUntil: number?,
	ReloadId: number, -- чтобы отменённая перезарядка не дозарядила магазин
}

local weaponState = Remotes.get("WeaponState")
local shotFx = Remotes.get("ShotFx")
local hitConfirm = Remotes.get("HitConfirm")

local states: { [Player]: PlayerState } = {}

local WeaponService = {}

local function newState(): PlayerState
	local ammo = {}
	for _, weapon in Weapons.List do
		if weapon.MagSize then
			ammo[weapon.Id] = weapon.MagSize
		end
	end
	return {
		Equipped = Weapons.Default,
		Ammo = ammo,
		LastFire = 0,
		ReloadingUntil = nil,
		ReloadId = 0,
	}
end

local function sendState(player: Player)
	local state = states[player]
	if not state then
		return
	end
	weaponState:FireClient(player, {
		Equipped = state.Equipped,
		Ammo = state.Ammo,
		Reloading = state.ReloadingUntil ~= nil,
	})
end

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X and value.Y == value.Y and value.Z == value.Z -- не NaN
		and math.abs(value.X) < 1e6 and math.abs(value.Y) < 1e6 and math.abs(value.Z) < 1e6
end

-- Модель врага, которой принадлежит деталь, или nil
local function enemyOf(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and CollectionService:HasTag(current, "Enemy") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function cancelReload(state: PlayerState)
	state.ReloadingUntil = nil
	state.ReloadId += 1
end

local function startReload(player: Player, state: PlayerState)
	local weapon = Weapons.get(state.Equipped)
	if not weapon or not weapon.MagSize or state.ReloadingUntil then
		return
	end
	if state.Ammo[weapon.Id] >= weapon.MagSize then
		return
	end
	state.ReloadId += 1
	local reloadId = state.ReloadId
	state.ReloadingUntil = os.clock() + weapon.ReloadTime
	sendState(player)

	task.delay(weapon.ReloadTime, function()
		if states[player] ~= state or state.ReloadId ~= reloadId then
			return
		end
		state.ReloadingUntil = nil
		state.Ammo[weapon.Id] = weapon.MagSize :: number
		sendState(player)
	end)
end

-- Пускает одну пулю: возвращает точку, где она остановилась, и задетых врагов
local function traceBullet(origin: Vector3, direction: Vector3, weapon: Weapons.Weapon, ignore: { Instance })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local hits: { Model } = {}
	local position = origin
	local left = weapon.Range
	while left > 0 and #hits < weapon.Pierce do
		local result = Workspace:Raycast(position, direction * left, params)
		if not result then
			return position + direction * left, hits
		end
		local enemy = enemyOf(result.Instance)
		if not enemy then
			return result.Position, hits -- стена или укрытие
		end
		table.insert(hits, enemy)
		table.insert(ignore, enemy)
		params.FilterDescendantsInstances = ignore
		left -= (result.Position - position).Magnitude
		position = result.Position
	end
	return position, hits
end

local function onFire(player: Player, weaponId: any, origin: any, directions: any)
	local state = states[player]
	if not state or typeof(weaponId) ~= "string" or weaponId ~= state.Equipped then
		return
	end
	local weapon = Weapons.get(weaponId)
	if not weapon or not isFiniteVector(origin) or typeof(directions) ~= "table" then
		return
	end
	if #directions ~= weapon.Pellets then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not character or not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return
	end
	if (origin - head.Position).Magnitude > MAX_ORIGIN_OFFSET then
		return
	end

	-- Все пули должны лететь примерно в одну сторону, в пределах разброса оружия
	local units: { Vector3 } = {}
	local average = Vector3.zero
	for _, direction in directions do
		if not isFiniteVector(direction) or direction.Magnitude < 0.5 then
			return
		end
		table.insert(units, direction.Unit)
		average += direction.Unit
	end
	if average.Magnitude < 0.01 then
		return
	end
	average = average.Unit
	local maxAngle = math.rad(weapon.Spread + SPREAD_TOLERANCE)
	for _, unit in units do
		if math.acos(math.clamp(unit:Dot(average), -1, 1)) > maxAngle then
			return
		end
	end

	local now = os.clock()
	if now - state.LastFire < weapon.FireInterval * RATE_TOLERANCE then
		return
	end
	if state.ReloadingUntil then
		sendState(player)
		return
	end
	if weapon.MagSize then
		if state.Ammo[weapon.Id] <= 0 then
			sendState(player)
			return
		end
		state.Ammo[weapon.Id] -= 1
	end
	state.LastFire = now

	-- Пули пролетают сквозь всех игроков
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end

	local endpoints = {}
	local damage: { [Model]: number } = {}
	for _, unit in units do
		local endpoint, hits = traceBullet(origin, unit, weapon, table.clone(ignore))
		table.insert(endpoints, endpoint)
		for _, enemy in hits do
			damage[enemy] = (damage[enemy] or 0) + weapon.Damage * BoostEffects.damageMultiplier(player)
		end
	end

	local killed = false
	local hitAny = false
	for enemy, amount in damage do
		local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
		if enemyHumanoid and enemyHumanoid.Health > 0 then
			-- По нераскрытому двойнику отметку попадания не показываем, иначе его легко вычислить
			local hiddenDouble = enemy:GetAttribute("Doppelganger") and not enemy:GetAttribute("Revealed")
			enemyHumanoid:TakeDamage(amount)
			if not hiddenDouble then
				hitAny = true
				if enemyHumanoid.Health <= 0 then
					killed = true
				end
			end
		end
	end
	if hitAny then
		hitConfirm:FireClient(player, killed)
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			shotFx:FireClient(other, player, weapon.Id, origin, endpoints)
		end
	end
end

local function onAction(player: Player, action: any, value: any)
	local state = states[player]
	if not state then
		return
	end
	if action == "Sync" then
		sendState(player)
	elseif action == "Equip" then
		if typeof(value) ~= "string" or not Weapons.get(value) or value == state.Equipped then
			return
		end
		state.Equipped = value
		cancelReload(state)
		sendState(player)
	elseif action == "Reload" then
		startReload(player, state)
	end
end

function WeaponService.start()
	local function onPlayerAdded(player: Player)
		states[player] = newState()
		player.CharacterAdded:Connect(function()
			states[player] = newState()
			sendState(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	Remotes.get("Fire").OnServerEvent:Connect(onFire)
	Remotes.get("WeaponAction").OnServerEvent:Connect(onAction)
end

return WeaponService
