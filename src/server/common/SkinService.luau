--!strict
-- Скины — ордены борцов с Искажением (Config.Skins). Работает и в Штабе, и в Миссии.
-- Выбранный скин хранится в сохранении (SelectedSkin) и надевается при каждом появлении персонажа.
-- Сменить скин можно только в Штабе (в гардеробе): персонаж пересоздаётся на том же месте.
-- Броню собирает сервер, поэтому её видят все игроки (и двойники вируса копируют её тоже).

local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Common.DataService)

local NONE = "None" -- свой облик игрока, без скина

local SkinService = {}

local templates: { [number]: BasePart } = {}

-- Деталь брони из ассета (один раз на номер, дальше — копии)
local function template(assetId: number): BasePart?
	if assetId == 0 then
		return nil
	end
	if templates[assetId] then
		return templates[assetId]
	end
	local ok, container = pcall(InsertService.LoadAsset, InsertService, assetId)
	if not ok then
		warn(`Не загрузилась деталь скина {assetId}: {container}`)
		return nil
	end
	local mesh = container:FindFirstChildWhichIsA("BasePart", true)
	if mesh then
		mesh.Parent = nil
		templates[assetId] = mesh
	end
	container:Destroy()
	return mesh
end

function SkinService.owns(player: Player, skin: Config.Skin): boolean
	return skin.Price == 0 or player:GetAttribute(`Pass_Skin_{skin.Key}`) == true
end

-- Деталь, приваренная к части тела: без массы и столкновений, чтобы не мешать бегать
local function attach(part: BasePart, to: BasePart, cf: CFrame, character: Model)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = to.CFrame * cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
	part.Parent = character
end

local function neon(props: { Size: Vector3, Color: Color3, Shape: Enum.PartType? }): Part
	local p = Instance.new("Part")
	p.Name = "SkinPiece"
	p.Size = props.Size
	p.Color = props.Color
	p.Shape = props.Shape or Enum.PartType.Block
	p.Material = Enum.Material.Neon
	return p
end

-- Кольцо из светящихся сегментов вокруг оси Y детали holder
local function ring(holder: BasePart, radius: number, count: number, thickness: number, color: Color3)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local segment = neon({
			Size = Vector3.new(thickness, thickness, 2 * math.pi * radius / count * 1.05),
			Color = color,
		})
		segment.Massless = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CFrame = holder.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = holder
		weld.Part1 = segment
		weld.Parent = segment
		segment.Parent = holder
	end
end

local function particles(parent: BasePart, props: { [string]: any })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SkinParticles"
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
end

-- Светящиеся манжеты цвета ордена на руках и ногах: без них тело выглядит плоским
local TRIMS = { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }

local function buildTrims(character: Model, skin: Config.Skin)
	for _, name in TRIMS do
		local limb = character:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			local band = neon({
				Size = Vector3.new(limb.Size.X + 0.06, 0.1, limb.Size.Z + 0.06),
				Color = skin.Accent,
			})
			band.Transparency = 0.15
			attach(band, limb, CFrame.new(0, -limb.Size.Y * 0.3, 0), character)
		end
	end
end

-- Эффекты, которые строятся кодом поверх брони
local function buildEffect(character: Model, skin: Config.Skin)
	local head = character:FindFirstChild("Head") :: BasePart?
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if not head or not torso then
		return
	end
	local accent = skin.Accent
	if skin.Effect == "Visor" then
		-- визор и полоса уже есть на шлеме и нагруднике; от брони поднимаются редкие зелёные искры кода
		particles(torso, {
			Color = ColorSequence.new(accent),
			LightEmission = 1,
			Size = NumberSequence.new(0.1, 0),
			Lifetime = NumberRange.new(0.8, 1.4),
			Rate = 4,
			Speed = NumberRange.new(0.5, 1.2),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(30, 30),
		})
	elseif skin.Effect == "Glitch" then
		particles(torso, {
			Color = ColorSequence.new(accent),
			LightEmission = 1,
			Size = NumberSequence.new(0.12),
			Lifetime = NumberRange.new(0.3, 0.6),
			Rate = 6,
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180),
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
		})
	elseif skin.Effect == "Halo" then
		local holder = neon({ Size = Vector3.new(0.1, 0.1, 0.1), Color = accent })
		holder.Transparency = 1
		attach(holder, head, CFrame.new(0, head.Size.Y * 0.95, 0) * CFrame.Angles(math.rad(-12), 0, 0), character)
		ring(holder, head.Size.X * 0.55, 14, 0.12, accent)
	elseif skin.Effect == "Stars" then
		particles(torso, {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), accent),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(1.2, 2),
			Rate = 10,
			Speed = NumberRange.new(0.3, 1),
			SpreadAngle = Vector2.new(180, 180),
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
		})
		-- голубое пламя из сопел ранца
		local flame = neon({ Size = Vector3.new(0.1, 0.1, 0.1), Color = accent })
		flame.Transparency = 1
		attach(flame, torso, CFrame.new(0, -torso.Size.Y * 0.5, torso.Size.Z * 1.1), character)
		particles(flame, {
			Color = ColorSequence.new(Color3.fromRGB(120, 200, 255), accent),
			LightEmission = 1,
			Size = NumberSequence.new(0.35, 0),
			Lifetime = NumberRange.new(0.2, 0.35),
			Rate = 40,
			Speed = NumberRange.new(4, 6),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(10, 10),
		})
	elseif skin.Effect == "Horizon" then
		-- кольцо, как свет вокруг чёрной дыры: медленно вращается за спиной
		local hub = neon({ Size = Vector3.new(0.3, 0.3, 0.3), Color = Color3.new(0, 0, 0), Shape = Enum.PartType.Ball })
		hub.Massless = true
		hub.CanCollide = false
		hub.CanQuery = false
		hub.CanTouch = false
		hub.CFrame = torso.CFrame * CFrame.new(0, torso.Size.Y * 0.2, torso.Size.Z * 1.2) * CFrame.Angles(math.rad(90), 0, 0)
		local a0 = Instance.new("Attachment")
		a0.CFrame = torso.CFrame:ToObjectSpace(hub.CFrame)
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.Parent = hub
		local hinge = Instance.new("HingeConstraint")
		hinge.Attachment0 = a0
		hinge.Attachment1 = a1
		hinge.ActuatorType = Enum.ActuatorType.Motor
		hinge.AngularVelocity = 1.6
		hinge.MotorMaxTorque = 1e6
		hinge.Parent = hub
		-- ось шарнира — X у вложений; поворачиваем их, чтобы кольцо крутилось в своей плоскости
		a0.CFrame *= CFrame.Angles(0, 0, math.rad(90))
		a1.CFrame = CFrame.Angles(0, 0, math.rad(90))
		ring(hub, torso.Size.X * 0.85, 20, 0.16, skin.Accent)
		hub.Parent = character
		particles(hub, {
			Color = ColorSequence.new(skin.Accent, Color3.fromRGB(80, 0, 0)),
			LightEmission = 1,
			Size = NumberSequence.new(0.25, 0),
			Lifetime = NumberRange.new(0.5, 0.9),
			Rate = 18,
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
		})
	end
end

-- Надевает скин на персонажа: убирает одежду и аксессуары, красит тело, крепит броню и эффекты
function SkinService.apply(character: Model, skin: Config.Skin)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			child.Color = skin.Body
			child.Material = skin.Material
			if child:IsA("MeshPart") then
				child.TextureID = ""
			end
		end
	end
	local face = character:FindFirstChild("Head") and (character :: any).Head:FindFirstChildOfClass("Decal")
	if face and #skin.Pieces > 0 then
		face:Destroy() -- лицо под шлемом не нужно
	end

	for _, piece in skin.Pieces do
		local to = character:FindFirstChild(piece.Attach)
		local source = template(piece.Asset)
		if to and to:IsA("BasePart") and source then
			local part = source:Clone()
			part.Name = "SkinPiece"
			local longest = math.max(source.Size.X, source.Size.Y, source.Size.Z)
			local target = math.max(to.Size.X, to.Size.Y, to.Size.Z) * piece.Fit
			part.Size = source.Size * (target / longest)
			local offset = piece.Offset or Vector3.zero
			local turn = piece.Turn or Vector3.zero
			attach(part, to, CFrame.new(offset * to.Size)
				* CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z)), character)
		end
	end
	buildTrims(character, skin)
	buildEffect(character, skin)
end

local function selected(player: Player): Config.Skin?
	local data = DataService.get(player)
	local skin = data and Config.getSkin(data.SelectedSkin)
	if skin and SkinService.owns(player, skin) then
		return skin
	end
	return nil
end

local function onCharacter(player: Player, character: Model)
	if not DataService.waitFor(player, 15) then
		return
	end
	-- ждём, пока Roblox наденет аватар (иначе его одежда ляжет поверх скина)
	local deadline = os.clock() + 8
	while not player:HasAppearanceLoaded() and os.clock() < deadline do
		task.wait(0.1)
	end
	task.wait(0.1)
	if player.Character ~= character then
		return
	end
	local skin = selected(player)
	if skin then
		SkinService.apply(character, skin)
	end
end

-- Пересоздаёт персонажа на том же месте (так проще всего вернуть свой облик или сменить скин)
local function respawnInPlace(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local where = root and root.CFrame
	player:LoadCharacter()
	local newRoot = player.Character and player.Character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if newRoot and where then
		newRoot.CFrame = where
	end
end

local function onAction(player: Player, action: unknown, key: unknown)
	if action ~= "Equip" or typeof(key) ~= "string" then
		return
	end
	if Workspace:GetAttribute("PlaceKind") ~= "Lobby" then
		return -- меняем облик только в Штабе, не посреди боя
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local skin = Config.getSkin(key)
	if key ~= NONE and not (skin and SkinService.owns(player, skin)) then
		return
	end
	if data.SelectedSkin == key then
		return
	end
	-- не чаще раза в секунду: пересоздание персонажа — не бесплатная операция
	local last = player:GetAttribute("SkinChangedAt")
	if typeof(last) == "number" and os.clock() - last < 1 then
		return
	end
	player:SetAttribute("SkinChangedAt", os.clock())
	data.SelectedSkin = key
	player:SetAttribute("Skin", key)
	respawnInPlace(player)
end

function SkinService.start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
		local data = DataService.waitFor(player, 30)
		if data then
			player:SetAttribute("Skin", data.SelectedSkin)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Remotes.get("SkinAction").OnServerEvent:Connect(onAction)
end

return SkinService
