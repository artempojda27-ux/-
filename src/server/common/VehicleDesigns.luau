--!strict
-- Внешний вид машин: «арт-хаус суперкары будущего» из граней — клинья, тонированное стекло,
-- неон и парящие диски вместо колёс. Каждая функция обвешивает корпус (chassis) деталями
-- и возвращает, где стоят сиденья (по порядку, первое — водитель).
-- Оси корпуса: −Z — вперёд, +Y — вверх. Клин (WedgePart) по умолчанию опускается вперёд.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Piece = (className: string, size: Vector3, offset: CFrame, props: { [string]: any }?) -> BasePart

local GLASS = Color3.fromRGB(16, 18, 26)
local HEADLIGHT = Color3.fromRGB(230, 240, 255)
local TAILLIGHT = Color3.fromRGB(255, 40, 60)

local VehicleDesigns = {}

-- Детальные кузова: модели, сгенерированные в Studio и сохранённые как ассеты в инвентаре
-- владельца игры (номера — Config.Vehicles[…].ShellAsset). Сервер загружает их при запуске
-- в ServerStorage.VehicleShells. Если кузов не загрузился, машина собирается из деталей ниже.
function VehicleDesigns.loadShells()
	local folder = ServerStorage:FindFirstChild("VehicleShells")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "VehicleShells"
		folder.Parent = ServerStorage
	end
	for _, kind in Config.Vehicles do
		if kind.ShellAsset ~= 0 and not folder:FindFirstChild(kind.Id) then
			local ok, result = pcall(InsertService.LoadAsset, InsertService, kind.ShellAsset)
			local model = ok and result:FindFirstChildWhichIsA("Model")
			if model then
				model.Name = kind.Id
				model.Parent = folder
			else
				warn(`Не загрузился кузов {kind.Id} ({kind.ShellAsset}): {if ok then "в ассете нет модели" else result}`)
			end
			if ok then
				result:Destroy()
			end
		end
	end
end

function VehicleDesigns.findShell(kindId: string): Model?
	local shells = ServerStorage:FindFirstChild("VehicleShells")
	local shell = shells and shells:FindFirstChild(kindId)
	return if shell and shell:IsA("Model") then shell else nil
end

-- Заглушка для дизайна, когда нужны только места сидений
function VehicleDesigns.noPiece(className: string, _size: Vector3, _offset: CFrame, _props: { [string]: any }?): BasePart
	return Instance.new(className) :: BasePart
end

-- Надевает копию кузова на корпус: по центру, низом к низу корпуса
function VehicleDesigns.attachShell(shell: Model, chassis: BasePart, kind: Config.VehicleKind, display: boolean, weld: (BasePart, BasePart) -> ())
	local copy = shell:Clone()
	copy:ScaleTo(kind.ShellScale)
	local turn = CFrame.identity
	-- Сначала ставим кузов в начало координат с нужным поворотом, чтобы узнать его размеры
	copy:PivotTo(turn)
	local boxCFrame, boxSize = copy:GetBoundingBox()
	local offset = boxCFrame.Position - copy:GetPivot().Position
	local target = chassis.CFrame * CFrame.new(0, -kind.Size.Y / 2 + boxSize.Y / 2 - 0.3, 0)
	copy:PivotTo(CFrame.new(target.Position - chassis.CFrame:VectorToWorldSpace(offset)) * chassis.CFrame.Rotation * turn)
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.Anchored = display
			if not display then
				weld(chassis, descendant)
			end
		end
	end
	copy.Name = "Shell"
	copy.Parent = chassis.Parent
end

local function glass(): { [string]: any }
	return { Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.3 }
end

local function neon(color: Color3): { [string]: any }
	return { Color = color, Material = Enum.Material.Neon }
end

-- Четыре парящих диска снизу по углам — вместо колёс
local function hoverPads(piece: Piece, kind: Config.VehicleKind, inset: number)
	local size = kind.Size
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			piece("Part", Vector3.new(0.25, 2.2, 2.2),
				CFrame.new(sx * (size.X / 2 - 1.2), -size.Y / 2 - 0.15, sz * (size.Z / 2 - inset)) * CFrame.Angles(0, 0, math.rad(90)),
				{ Shape = Enum.PartType.Cylinder, Color = kind.GlowColor, Material = Enum.Material.Neon })
		end
	end
end

-- Неоновая линия снизу по бокам
local function sideLines(piece: Piece, kind: Config.VehicleKind, color: Color3)
	local size = kind.Size
	for _, side in { -1, 1 } do
		piece("Part", Vector3.new(0.15, 0.15, size.Z * 0.92), CFrame.new(side * (size.X / 2 + 0.05), -size.Y / 2 + 0.15, 0), neon(color))
	end
end

-- «Вольт»: длинный низкий электрородстер с каплевидным стеклом
function VehicleDesigns.Roadster(piece: Piece, kind: Config.VehicleKind): { Vector3 }
	local s = kind.Size
	local top = s.Y / 2
	local body = { Color = kind.Color, Material = Enum.Material.SmoothPlastic, Reflectance = 0.15 }
	piece("WedgePart", Vector3.new(s.X, s.Y, 4), CFrame.new(0, 0, -s.Z / 2 - 2), body) -- нос
	piece("Part", Vector3.new(s.X + 0.4, 0.2, 2), CFrame.new(0, -top, -s.Z / 2 - 3), { Color = kind.AccentColor })
	piece("Part", Vector3.new(s.X * 0.8, 0.15, 0.15), CFrame.new(0, -top + 0.35, -s.Z / 2 - 3.6), neon(HEADLIGHT))
	piece("WedgePart", Vector3.new(s.X * 0.65, 0.6, 5), CFrame.new(0, top + 0.3, -s.Z * 0.3), body) -- выпуклый капот
	-- Капля стекла: передний клин вниз к носу, задний — вниз к корме
	piece("WedgePart", Vector3.new(s.X * 0.72, 1.4, 3.5), CFrame.new(0, top + 0.7, -0.25), glass())
	piece("WedgePart", Vector3.new(s.X * 0.72, 1.4, 4), CFrame.new(0, top + 0.7, 3.5) * CFrame.Angles(0, math.rad(180), 0), glass())
	piece("Part", Vector3.new(s.X * 0.95, 0.4, 2.6), CFrame.new(0, top + 0.2, s.Z / 2 - 1.4), body) -- задняя палуба
	piece("Part", Vector3.new(s.X * 0.9, 0.5, 1), CFrame.new(0, -top + 0.2, s.Z / 2 - 0.3), { Color = kind.AccentColor }) -- диффузор
	piece("Part", Vector3.new(s.X * 0.95, 0.22, 0.2), CFrame.new(0, top - 0.1, s.Z / 2 + 0.05), neon(TAILLIGHT)) -- фонарь во всю ширину
	sideLines(piece, kind, kind.GlowColor)
	hoverPads(piece, kind, 2.5)
	return { Vector3.new(-s.X * 0.18, top + 0.5, 0.6), Vector3.new(s.X * 0.18, top + 0.5, 0.6) }
end

-- «Призма»: острый белый гиперкар с узкой кабиной, боковыми гранями и килями сзади
function VehicleDesigns.Hypercar(piece: Piece, kind: Config.VehicleKind): { Vector3 }
	local s = kind.Size
	local top = s.Y / 2
	local body = { Color = kind.Color, Material = Enum.Material.SmoothPlastic, Reflectance = 0.2 }
	local dark = { Color = kind.AccentColor, Material = Enum.Material.SmoothPlastic }
	piece("WedgePart", Vector3.new(s.X, s.Y, 5), CFrame.new(0, 0, -s.Z / 2 - 2.5), body) -- длинный нос
	piece("Part", Vector3.new(s.X + 0.6, 0.15, 2.5), CFrame.new(0, -top, -s.Z / 2 - 3.8), dark) -- передний «нож»
	piece("Part", Vector3.new(s.X * 0.7, 0.12, 0.12), CFrame.new(0, -top + 0.3, -s.Z / 2 - 4.7), neon(kind.GlowColor))
	-- Узкая кабина-призма
	piece("WedgePart", Vector3.new(3.6, 1.6, 4), CFrame.new(0, top + 0.8, -1), glass())
	piece("WedgePart", Vector3.new(3.6, 1.6, 5), CFrame.new(0, top + 0.8, 3.5) * CFrame.Angles(0, math.rad(180), 0), glass())
	-- Боковые грани: клинья, опускающиеся наружу
	for _, side in { -1, 1 } do
		piece("WedgePart", Vector3.new(7, 1.2, 2.2),
			CFrame.new(side * (s.X / 2 - 1.1), top + 0.6, 2) * CFrame.Angles(0, math.rad(-90 * side), 0), dark)
		piece("Part", Vector3.new(0.15, 0.15, 6.5), CFrame.new(side * (s.X / 2 - 0.05), top + 0.1, 2), neon(kind.GlowColor))
	end
	-- Кили сзади, слегка наружу, с неоновой кромкой
	for _, side in { -1, 1 } do
		local fin = CFrame.new(side * (s.X / 2 - 1), top + 1.3, s.Z / 2 - 1.8) * CFrame.Angles(0, 0, math.rad(-12 * side))
		piece("Part", Vector3.new(0.3, 2.6, 3.4), fin, body)
		piece("Part", Vector3.new(0.34, 0.15, 3.4), fin * CFrame.new(0, 1.3, 0), neon(kind.GlowColor))
	end
	piece("Part", Vector3.new(s.X * 0.9, 0.2, 0.2), CFrame.new(0, top - 0.1, s.Z / 2 + 0.05), neon(kind.GlowColor)) -- задний фонарь
	sideLines(piece, kind, kind.GlowColor)
	hoverPads(piece, kind, 2.5)
	return { Vector3.new(-s.X * 0.13, top + 0.5, 0.8), Vector3.new(s.X * 0.13, top + 0.5, 0.8) }
end

-- «Глитч-байк»: узкий корпус между двумя светящимися кольцами
function VehicleDesigns.Bike(piece: Piece, kind: Config.VehicleKind): { Vector3 }
	local s = kind.Size
	local top = s.Y / 2
	local body = { Color = kind.Color, Material = Enum.Material.SmoothPlastic, Reflectance = 0.2 }
	for _, z in { -s.Z / 2 + 0.3, s.Z / 2 - 0.3 } do
		-- кольцо: светящийся диск, закрытый с боков тёмными дисками поменьше
		piece("Part", Vector3.new(0.5, 3.6, 3.6), CFrame.new(0, -0.2, z), { Shape = Enum.PartType.Cylinder, Color = kind.GlowColor, Material = Enum.Material.Neon })
		piece("Part", Vector3.new(0.6, 2.8, 2.8), CFrame.new(0, -0.2, z), { Shape = Enum.PartType.Cylinder, Color = kind.Color })
	end
	piece("WedgePart", Vector3.new(1.8, 1, 3), CFrame.new(0, top + 0.5, -1.4), body) -- обтекатель
	piece("Part", Vector3.new(0.2, 0.12, 2.6), CFrame.new(0, top + 1.02, -1.2), neon(kind.AccentColor))
	piece("WedgePart", Vector3.new(1.6, 0.8, 2), CFrame.new(0, top + 0.4, 2.3) * CFrame.Angles(0, math.rad(180), 0), body) -- хвост
	piece("Part", Vector3.new(1.4, 0.15, 0.15), CFrame.new(0, top + 0.1, 3.35), neon(TAILLIGHT))
	sideLines(piece, kind, kind.AccentColor)
	return { Vector3.new(0, top + 0.5, 0.6) }
end

-- «Транспортник»: фургон на четверых с кабиной, бортами и спойлером
function VehicleDesigns.Transporter(piece: Piece, kind: Config.VehicleKind): { Vector3 }
	local s = kind.Size
	local top = s.Y / 2
	local body = { Color = kind.Color, Material = Enum.Material.SmoothPlastic }
	piece("WedgePart", Vector3.new(s.X, s.Y, s.Z * 0.25), CFrame.new(0, 0, -s.Z / 2 - s.Z * 0.125), body) -- нос
	piece("Part", Vector3.new(s.X * 0.8, 1.6, s.Z * 0.28), CFrame.new(0, top + 0.8, -s.Z * 0.38), glass()) -- кабина
	for _, side in { -1, 1 } do
		piece("Part", Vector3.new(0.6, 1.2, s.Z * 0.75), CFrame.new(side * (s.X / 2 - 0.3), top + 0.6, s.Z * 0.05), body) -- борт
		piece("Part", Vector3.new(1.4, 0.6, 0.2), CFrame.new(side * s.X * 0.32, -top + 0.5, -s.Z / 2 - s.Z * 0.25), neon(HEADLIGHT)) -- фара
		piece("Part", Vector3.new(0.6, 1.6, 1.6), CFrame.new(side * s.X * 0.28, 0, s.Z / 2 + 0.3) * CFrame.Angles(0, math.rad(90), 0),
			{ Shape = Enum.PartType.Cylinder, Color = kind.GlowColor, Material = Enum.Material.Neon }) -- сопло
		piece("Part", Vector3.new(0.4, 1.6, 0.6), CFrame.new(side * s.X * 0.35, top + 1, s.Z / 2 - 1), body) -- стойка спойлера
	end
	piece("Part", Vector3.new(s.X * 1.05, 0.4, 2), CFrame.new(0, top + 2, s.Z / 2 - 1), body) -- спойлер
	piece("Part", Vector3.new(s.X * 1.05, 0.15, 0.2), CFrame.new(0, top + 2.25, s.Z / 2), neon(kind.AccentColor))
	sideLines(piece, kind, kind.GlowColor)
	hoverPads(piece, kind, 3)
	return {
		Vector3.new(-s.X * 0.22, top + 0.5, -s.Z * 0.2),
		Vector3.new(s.X * 0.22, top + 0.5, -s.Z * 0.2),
		Vector3.new(-s.X * 0.22, top + 0.5, s.Z * 0.2),
		Vector3.new(s.X * 0.22, top + 0.5, s.Z * 0.2),
	}
end

return VehicleDesigns
