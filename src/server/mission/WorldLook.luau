--!strict
-- Внешний вид параллельного мира. «Зеркальный город»: всё в красных тонах, тревожный свет,
-- а над городом вниз головой висит его отражение — перевёрнутая копия кварталов.
-- Обычный «Неоновый город» ничего не меняет.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local MIRROR_HEIGHT = 170 -- город отражается относительно этой высоты (земля → небо)

-- Неоновые цвета обычного города → цвета Зеркального
local MIRROR_NEON = {
	Color3.fromRGB(255, 50, 70),
	Color3.fromRGB(255, 120, 40),
	Color3.fromRGB(255, 230, 230),
	Color3.fromRGB(200, 20, 60),
}

local WorldLook = {}

local function recolor(map: Instance)
	local nodes = map:FindFirstChild("GlitchNodes")
	local index = 0
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Material == Enum.Material.Neon then
				-- Сбои остаются розовыми: по ним игроки ищут цель
				if not (nodes and descendant:IsDescendantOf(nodes)) then
					index += 1
					descendant.Color = MIRROR_NEON[index % #MIRROR_NEON + 1]
				end
			elseif descendant.Name == "Body" or descendant.Name == "Tower" then
				local _, saturation, value = descendant.Color:ToHSV()
				descendant.Color = Color3.fromHSV(0.98, math.max(saturation, 0.45), value * 0.8 + 0.05)
			end
		elseif descendant:IsA("PointLight") or descendant:IsA("SurfaceLight") then
			descendant.Color = Color3.fromRGB(255, 90, 90)
		elseif descendant:IsA("TextLabel") then
			descendant.TextColor3 = Color3.fromRGB(255, 70, 80)
		end
	end
end

-- Перевёрнутая копия кварталов в небе
local function hangReflection(map: Instance)
	local reflection = Instance.new("Folder")
	reflection.Name = "Reflection"
	local flip = CFrame.new(0, MIRROR_HEIGHT, 0) * CFrame.Angles(math.pi, 0, 0) * CFrame.new(0, -MIRROR_HEIGHT, 0)
	for _, child in map:GetChildren() do
		local isCity = child:IsA("Model") and (child.Name:sub(1, 6) == "Block_" or child.Name == "Boundary" or child.Name == "Towers")
		if isCity then
			local copy = child:Clone()
			for _, descendant in copy:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.CFrame = flip * descendant.CFrame
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.CastShadow = false
				elseif descendant:IsA("Light") or descendant:IsA("ProximityPrompt") then
					descendant:Destroy()
				end
			end
			copy.Parent = reflection
		end
	end
	reflection.Parent = Workspace
end

local function mirrorLighting()
	Lighting.Ambient = Color3.new(0.3, 0.14, 0.18)
	Lighting.OutdoorAmbient = Color3.new(0.6, 0.3, 0.35)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = Color3.new(0.75, 0.22, 0.3)
		atmosphere.Decay = Color3.new(0.45, 0.05, 0.12)
		atmosphere.Density = 0.34
	end
	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if correction then
		correction.TintColor = Color3.new(1, 0.82, 0.85)
		correction.Contrast = 0.2
	end
end

-- Применяет вид мира к карте (map может быть nil, например в Побеге меняется только свет)
function WorldLook.apply(worldId: string, map: Instance?)
	if worldId ~= "Mirror" then
		return
	end
	mirrorLighting()
	if map then
		recolor(map)
		hangReflection(map)
	end
end

return WorldLook
