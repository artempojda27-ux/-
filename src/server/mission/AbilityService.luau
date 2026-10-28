--!strict
-- Способности героя (Config.Abilities) — сервер проверяет перезарядку, считает урон и заряд ультимейта.
-- Игроку ставятся атрибуты для клиента: "PulseReadyAt", "DashReadyAt" (время сервера, когда снова можно)
-- и "UltCharge" (0–100, %). Рывок двигает сам клиент (своего персонажа двигает он), сервер только даёт
-- полсекунды неуязвимости и следит за перезарядкой.
-- Попадают способности, как и пули, только во врагов (тег "Enemy").

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BoostEffects = require(script.Parent.BoostEffects)

local AbilityService = {}

local abilityFx = Remotes.get("AbilityFx")
local kills: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and not humanoid.Sit then
		return root
	end
	return nil
end

local function setCharge(player: Player)
	local need = Config.Abilities.Ultimate.Charge
	player:SetAttribute("UltCharge", math.clamp(math.floor((kills[player] or 0) / need * 100), 0, 100))
end

-- Убийство врага игроком (пулей или способностью) заряжает ультимейт
function AbilityService.addKill(player: Player)
	kills[player] = math.min((kills[player] or 0) + 1, Config.Abilities.Ultimate.Charge)
	setCharge(player)
end

-- Урон врагам в радиусе; true — если кого-то убили. Отбрасывание — толчок от центра
local function blast(player: Player, center: Vector3, radius: number, damage: number, knockback: number?)
	local multiplier = BoostEffects.damageMultiplier(player)
	local killedAny = 0
	for _, enemy in CollectionService:GetTagged("Enemy") do
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		local root = enemy:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			local offset = root.Position - center
			if offset.Magnitude <= radius then
				humanoid:TakeDamage(damage * multiplier)
				if humanoid.Health <= 0 then
					killedAny += 1
				elseif knockback and not root.Anchored then
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local push = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
					root.AssemblyLinearVelocity = push * knockback + Vector3.new(0, knockback * 0.4, 0)
				end
			end
		end
	end
	return killedAny
end

local function onAction(player: Player, action: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local t = now()
	if action == "Pulse" then
		local spec = Config.Abilities.Pulse
		local ready = player:GetAttribute("PulseReadyAt")
		if typeof(ready) == "number" and t < ready then
			return
		end
		player:SetAttribute("PulseReadyAt", t + spec.Cooldown)
		abilityFx:FireAllClients(player, "Pulse", root.Position)
		for _ = 1, blast(player, root.Position, spec.Radius, spec.Damage, spec.Knockback) do
			AbilityService.addKill(player)
		end
	elseif action == "Dash" then
		local spec = Config.Abilities.Dash
		local ready = player:GetAttribute("DashReadyAt")
		if typeof(ready) == "number" and t < ready then
			return
		end
		player:SetAttribute("DashReadyAt", t + spec.Cooldown)
		-- короткое невидимое защитное поле на время броска
		local field = Instance.new("ForceField")
		field.Name = "DashField"
		field.Visible = false
		field.Parent = root.Parent
		task.delay(spec.Shield, function()
			field:Destroy()
		end)
		abilityFx:FireAllClients(player, "Dash", root.Position)
	elseif action == "Ultimate" then
		local spec = Config.Abilities.Ultimate
		if (kills[player] or 0) < spec.Charge then
			return
		end
		kills[player] = 0
		setCharge(player)
		abilityFx:FireAllClients(player, "Ultimate", root.Position)
		task.delay(0.4, function() -- урон — когда вспышка разлетелась
			blast(player, root.Position, spec.Radius, spec.Damage, 120)
		end)
	end
end

function AbilityService.start()
	local function onPlayerAdded(player: Player)
		kills[player] = 0
		player:SetAttribute("PulseReadyAt", 0)
		player:SetAttribute("DashReadyAt", 0)
		setCharge(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		kills[player] = nil
	end)
	Remotes.get("AbilityAction").OnServerEvent:Connect(onAction)
end

return AbilityService
