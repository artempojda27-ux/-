--!strict
-- Стрельба игрока: клавиши 1–4 — выбор оружия, левая кнопка мыши — огонь, R — перезарядка.
-- На телефоне: большая кнопка «ОГОНЬ» (зажать — автомат стреляет очередью), «R» — перезарядка,
-- целятся центром экрана (там прицел) с помощью прицеливания: пуля летит в ближайшего к прицелу врага;
-- оружие выбирают нажатием на слот внизу.
-- Выстрел рисуется сразу, а попадание и урон считает сервер (WeaponService).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Hud = require(script.Parent:WaitForChild("Hud"))
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

local AIM_DISTANCE = 1000

local player = Players.LocalPlayer
local fireRemote = Remotes.get("Fire")
local weaponAction = Remotes.get("WeaponAction")

local equipped = Weapons.Default
local ammo: { [string]: number } = {}
local reloading = false
local lastFire = 0
local triggerHeld = false
local random = Random.new()

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

local function currentWeapon(): Weapons.Weapon
	return Weapons.get(equipped) or Weapons.List[1]
end

local function refreshHud()
	local weapon = currentWeapon()
	Hud.setWeapon(weapon, ammo[weapon.Id], reloading)
end

-- Луч, который не задевает игроков: пули пролетают сквозь своих
local function playerFilter(): RaycastParams
	local ignore = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

-- Откуда вылетает след: из правой руки, если она есть
local function muzzleOf(character: Model): Vector3?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("Head")
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	return nil
end

local function drawTracer(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(0.12, 0.12, length)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = Workspace.CurrentCamera
	TweenService:Create(beam, TweenInfo.new(0.15), { Transparency = 1 }):Play()
	task.delay(0.15, function()
		beam:Destroy()
	end)
end

local function requestReload()
	local weapon = currentWeapon()
	if not weapon.MagSize or reloading or ammo[weapon.Id] == weapon.MagSize then
		return
	end
	reloading = true
	refreshHud()
	weaponAction:FireServer("Reload")
end

local function equip(weaponId: string)
	if weaponId == equipped or not Weapons.get(weaponId) then
		return
	end
	equipped = weaponId
	reloading = false
	triggerHeld = false
	refreshHud()
	weaponAction:FireServer("Equip", weaponId)
end

-- Помощь в прицеливании на телефоне: пальцем точно не навести, поэтому выстрел летит в ближайшего к прицелу
-- видимого врага (в пределах круга вокруг центра экрана). Без врагов рядом — просто в центр экрана
local ASSIST_RADIUS = 0.22 -- доля меньшей стороны экрана
local function assistTarget(camera: Camera, origin: Vector3, params: RaycastParams, range: number): Vector3?
	local viewport = camera.ViewportSize
	local center = viewport / 2
	local limit = math.min(viewport.X, viewport.Y) * ASSIST_RADIUS
	local best: Vector3? = nil
	local bestScore = math.huge
	for _, enemy in CollectionService:GetTagged("Enemy") do
		local root = enemy:FindFirstChild("HumanoidRootPart")
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local point, onScreen = camera:WorldToViewportPoint(root.Position)
			local distance = (root.Position - origin).Magnitude
			if onScreen and distance <= range then
				local offset = (Vector2.new(point.X, point.Y) - center).Magnitude
				if offset <= limit then
					local hit = Workspace:Raycast(origin, root.Position - origin, params)
					local visible = not hit or hit.Instance:IsDescendantOf(enemy)
					local score = offset + distance * 0.5 -- ближе к прицелу и ближе к герою — важнее
					if visible and score < bestScore then
						best, bestScore = root.Position, score
					end
				end
			end
		end
	end
	return best
end

local function fire()
	local weapon = currentWeapon()
	local now = os.clock()
	if reloading or now - lastFire < weapon.FireInterval then
		return
	end
	if weapon.MagSize and (ammo[weapon.Id] or 0) <= 0 then
		requestReload()
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not character or not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return
	end
	lastFire = now

	-- Куда смотрит курсор: луч из камеры через точку под мышью
	local camera = Workspace.CurrentCamera
	local aimPoint = if UI.isTouch then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local aimRay = camera:ViewportPointToRay(aimPoint.X, aimPoint.Y)
	local params = playerFilter()
	local aimHit = Workspace:Raycast(aimRay.Origin, aimRay.Direction * AIM_DISTANCE, params)
	local target = if aimHit then aimHit.Position else aimRay.Origin + aimRay.Direction * AIM_DISTANCE

	local origin = head.Position
	if UI.isTouch then
		target = assistTarget(camera, origin, params, weapon.Range) or target
	end
	local aim = target - origin
	if aim.Magnitude < 0.1 then
		return
	end

	local directions = {}
	local muzzle = muzzleOf(character) or origin
	for _ = 1, weapon.Pellets do
		local direction = Weapons.spread(aim.Unit, weapon.Spread, random)
		table.insert(directions, direction)
		local result = Workspace:Raycast(origin, direction * weapon.Range, params)
		drawTracer(muzzle, if result then result.Position else origin + direction * weapon.Range, weapon.Color)
	end
	fireRemote:FireServer(weapon.Id, origin, directions)

	if weapon.MagSize then
		ammo[weapon.Id] -= 1
		refreshHud()
		if ammo[weapon.Id] <= 0 then
			requestReload()
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = true
		fire()
	elseif input.KeyCode == Enum.KeyCode.R then
		requestReload()
	else
		local slot = SLOT_KEYS[input.KeyCode]
		if slot then
			for _, weapon in Weapons.List do
				if weapon.Slot == slot then
					equip(weapon.Id)
				end
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = false
	end
end)

-- Автоматическое оружие стреляет, пока зажата кнопка
RunService.RenderStepped:Connect(function()
	if triggerHeld and currentWeapon().Auto then
		fire()
	end
end)

-- Телефон — как в мобильных шутерах: камера из-за правого плеча, герой всегда смотрит туда же, куда камера
-- (джойстиком ходишь, пальцем справа целишься), и автоогонь — когда враг попадает в круг прицела, герой
-- стреляет сам. Кнопка «ОГОНЬ» остаётся для стрельбы по своему желанию. В машине всё выключается.
if UI.isTouch then
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") then
			return
		end
		-- в машине (SeatPart) не трогаем героя: поворот выдернул бы его из сиденья
		local combat = humanoid.Health > 0 and not humanoid.Sit and humanoid.SeatPart == nil
		humanoid.CameraOffset = if combat then Vector3.new(1.8, 0.6, 0) else Vector3.zero
		humanoid.AutoRotate = not combat
		if not combat then
			return
		end
		local camera = Workspace.CurrentCamera
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
		-- автоогонь по врагу в круге прицела
		local head = character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local weapon = currentWeapon()
			if assistTarget(camera, head.Position, playerFilter(), weapon.Range) then
				fire()
			end
		end
	end)
end

Hud.onSlotClicked(equip)

-- Кнопки для телефона: огонь (зажимать) и перезарядка
if UI.isTouch then
	local touchGui = UI.screen("TouchCombatUI")
	local fireButton = UI.button({
		Name = "FireButton",
		AnchorPoint = Vector2.new(1, 1),
		-- левее стандартной кнопки прыжка Roblox (она в самом углу справа)
		Position = UDim2.new(1, -200, 1, -24),
		Size = UDim2.fromOffset(104, 104),
		Text = "ОГОНЬ",
		TextSize = 20,
		BackgroundColor3 = UI.Colors.Glitch,
		TextColor3 = UI.Colors.Text,
		Parent = touchGui,
	}, function() end)
	UI.round(fireButton)
	fireButton.MouseButton1Down:Connect(function()
		triggerHeld = true
		fire()
	end)
	fireButton.MouseButton1Up:Connect(function()
		triggerHeld = false
	end)
	fireButton.MouseLeave:Connect(function()
		triggerHeld = false
	end)
	local reloadButton = UI.button({
		Name = "ReloadButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -224, 1, -142),
		Size = UDim2.fromOffset(56, 56),
		Text = "R",
		TextSize = 22,
		Parent = touchGui,
	}, requestReload)
	UI.round(reloadButton)
end

-- Сервер — главный: его данные о патронах заменяют наши
Remotes.get("WeaponState").OnClientEvent:Connect(function(state)
	equipped = state.Equipped
	ammo = state.Ammo
	reloading = state.Reloading
	refreshHud()
end)

Remotes.get("HitConfirm").OnClientEvent:Connect(function(killed: boolean)
	Hud.showHit(killed)
end)

-- Выстрелы других игроков
Remotes.get("ShotFx").OnClientEvent:Connect(function(shooter: Player, weaponId: string, origin: Vector3, endpoints: { Vector3 })
	local weapon = Weapons.get(weaponId)
	if not weapon or shooter == player then
		return
	end
	local from = if shooter.Character then muzzleOf(shooter.Character) or origin else origin
	for _, endpoint in endpoints do
		drawTracer(from, endpoint, weapon.Color)
	end
end)

refreshHud()
weaponAction:FireServer("Sync")
