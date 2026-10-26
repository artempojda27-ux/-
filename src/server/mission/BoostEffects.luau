--!strict
-- Что делают разовые бусты в Миссии. Время окончания хранится в атрибутах игрока
-- (по часам сервера, workspace:GetServerTimeNow()), чтобы клиент показывал таймер:
--   InvincibleUntil   — до этого момента игрока ничто не ранит (защитное поле);
--   DamageBoostUntil  — до этого момента урон игрока удвоен (его учитывает WeaponService).
-- Повторная покупка продлевает действие.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FIELD_NAME = "InvincibleField"
local GLITCH = Color3.fromRGB(255, 40, 120)

local notify = Remotes.get("Notify")

local BoostEffects = {}

local deathPlaces: { [Player]: CFrame } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function extend(player: Player, attribute: string, seconds: number): number
	local current = player:GetAttribute(attribute)
	local from = if typeof(current) == "number" and current > now() then current else now()
	local untilTime = from + seconds
	player:SetAttribute(attribute, untilTime)
	return untilTime
end

-- Ставит защитное поле на персонажа, пока не кончится бессмертие
local function applyField(player: Player)
	local character = player.Character
	local untilTime = player:GetAttribute("InvincibleUntil")
	if not character or typeof(untilTime) ~= "number" or untilTime <= now() then
		return
	end
	if not character:FindFirstChild(FIELD_NAME) then
		local field = Instance.new("ForceField")
		field.Name = FIELD_NAME
		field.Parent = character
	end
	task.delay(untilTime - now(), function()
		local latest = player:GetAttribute("InvincibleUntil")
		if typeof(latest) == "number" and latest > now() + 0.05 then
			return -- бессмертие продлили, поле снимет следующий таймер
		end
		local field = character:FindFirstChild(FIELD_NAME)
		if field then
			field:Destroy()
		end
	end)
end

-- Где сейчас игрок; если он погиб — место гибели
local function positionOf(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root.Position
	end
	local place = deathPlaces[player]
	return if place then place.Position else nil
end

-- Расходящаяся неоновая волна — видна всем
local function shockwave(center: Vector3, radius: number)
	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = GLITCH
	sphere.Transparency = 0.3
	sphere.Size = Vector3.one * 2
	sphere.Position = center
	sphere.Parent = Workspace
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(sphere, info, { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	task.delay(0.7, function()
		sphere:Destroy()
	end)
end

function BoostEffects.damageMultiplier(player: Player): number
	local untilTime = player:GetAttribute("DamageBoostUntil")
	return if typeof(untilTime) == "number" and untilTime > now() then 2 else 1
end

BoostEffects.handlers = {
	-- Стирает всех врагов в радиусе вокруг покупателя
	Nuke = function(player: Player): boolean
		local center = positionOf(player)
		if not center then
			return false -- персонажа нет: Roblox пришлёт чек позже
		end
		shockwave(center, Config.NukeRadius)
		local count = 0
		for _, enemy in CollectionService:GetTagged("Enemy") do
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if enemy:IsA("Model") and humanoid and humanoid.Health > 0
				and (enemy:GetPivot().Position - center).Magnitude <= Config.NukeRadius then
				humanoid.Health = 0
				count += 1
			end
		end
		notify:FireAllClients(`{player.DisplayName} запустил код уничтожения: стёрто врагов — {count}!`)
		return true
	end,

	-- Бусты на весь отряд: действуют на всех игроков миссии, все видят, кто купил
	SquadDamage = function(player: Player): boolean
		for _, member in Players:GetPlayers() do
			extend(member, "DamageBoostUntil", Config.SquadDamageDuration)
		end
		notify:FireAllClients(`{player.DisplayName} включил x2 урон для всего отряда!`)
		return true
	end,

	SquadShield = function(player: Player): boolean
		for _, member in Players:GetPlayers() do
			extend(member, "InvincibleUntil", Config.InvincibleDuration)
			applyField(member)
		end
		notify:FireAllClients(`{player.DisplayName} включил бессмертие для всего отряда!`)
		return true
	end,

	Invincible = function(player: Player): boolean
		extend(player, "InvincibleUntil", Config.InvincibleDuration)
		applyField(player)
		return true
	end,

	DoubleDamage = function(player: Player): boolean
		extend(player, "DamageBoostUntil", Config.DoubleDamageDuration)
		return true
	end,

	-- Мёртвый встаёт на месте гибели; живому просто восстанавливаем здоровье
	Revive = function(player: Player): boolean
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
			return true
		end
		local place = deathPlaces[player]
		player:LoadCharacter()
		if place and player.Character then
			player.Character:PivotTo(place)
		end
		return true
	end,
}

function BoostEffects.start()
	Players.RespawnTime = Config.MissionRespawnTime

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			applyField(player) -- бессмертие, купленное до возрождения
			humanoid.Died:Connect(function()
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					deathPlaces[player] = root.CFrame + Vector3.new(0, 3, 0)
				end
			end)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		deathPlaces[player] = nil
	end)
end

return BoostEffects
