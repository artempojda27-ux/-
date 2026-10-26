--!strict
-- Мишени для проверки оружия, пока нет настоящих врагов (они появятся в неделях 5–6).
-- Мишень — враг с тегом "Enemy": по нему попадает WeaponService. После уничтожения
-- она появляется снова через несколько секунд.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local HEALTH = 200
local RESPAWN_DELAY = 3
local POSITIONS = {
	Vector3.new(-10, 1, -28),
	Vector3.new(0, 1, -28),
	Vector3.new(10, 1, -28),
}

local GLITCH = Color3.fromRGB(255, 40, 120)
local DARK = Color3.fromRGB(30, 36, 46)

local TrainingTargets = {}

local folder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function spawnTarget(position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Мишень"

	-- position — точка на полу под мишенью
	local root = part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(3, 4, 1),
		Position = position + Vector3.new(0, 3, 0),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	part({
		Name = "Head",
		Size = Vector3.new(2, 2, 1),
		Position = position + Vector3.new(0, 6, 0),
		Color = GLITCH,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = HEALTH
	humanoid.Health = HEALTH
	humanoid.DisplayName = "Мишень"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	CollectionService:AddTag(model, "Enemy")
	model.Parent = folder

	humanoid.Died:Connect(function()
		task.wait(0.2)
		model:Destroy()
		task.wait(RESPAWN_DELAY)
		spawnTarget(position)
	end)
end

function TrainingTargets.start()
	folder = Instance.new("Folder")
	folder.Name = "TrainingTargets"
	folder.Parent = Workspace
	for _, position in POSITIONS do
		spawnTarget(position)
	end
end

return TrainingTargets
