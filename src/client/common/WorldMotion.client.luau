--!strict
-- Двигает детали миров с тегом "Motion" (строит сервер — WorldDetails.luau). Атрибуты:
--   Spin (Vector3, градусы в секунду по своим осям), Bob (студы, качание вверх-вниз),
--   Sway (градусы, покачивание), Phase (сдвиг, чтобы всё не качалось в такт), Pulse (true — мерцает).
-- Считается на клиенте: плавно и без нагрузки на сеть.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

type Mover = {
	Target: Instance,
	Base: CFrame,
	Spin: Vector3?,
	Bob: number?,
	Sway: number?,
	Phase: number,
	Pulse: BasePart?,
	BaseTransparency: number,
}

local movers: { [Instance]: Mover } = {}

local function pivotOf(target: Instance): CFrame?
	if target:IsA("Model") then
		return target:GetPivot()
	elseif target:IsA("BasePart") then
		return target.CFrame
	end
	return nil
end

local function add(target: Instance)
	local base = pivotOf(target)
	if not base then
		return
	end
	local spin = target:GetAttribute("Spin")
	local bob = target:GetAttribute("Bob")
	local sway = target:GetAttribute("Sway")
	local phase = target:GetAttribute("Phase")
	local pulse = target:GetAttribute("Pulse") == true and target:IsA("BasePart")
	movers[target] = {
		Target = target,
		Base = base,
		Spin = if typeof(spin) == "Vector3" then spin else nil,
		Bob = if typeof(bob) == "number" then bob else nil,
		Sway = if typeof(sway) == "number" then sway else nil,
		Phase = if typeof(phase) == "number" then phase else 0,
		Pulse = if pulse then target :: BasePart else nil,
		BaseTransparency = if target:IsA("BasePart") then target.Transparency else 0,
	}
end

for _, target in CollectionService:GetTagged("Motion") do
	add(target)
end
CollectionService:GetInstanceAddedSignal("Motion"):Connect(add)
CollectionService:GetInstanceRemovedSignal("Motion"):Connect(function(target)
	movers[target] = nil
end)

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for target, mover in movers do
		if target.Parent == nil then
			movers[target] = nil
			continue
		end
		local cf = mover.Base
		if mover.Bob then
			cf = CFrame.new(0, math.sin(t * 0.6 + mover.Phase) * mover.Bob, 0) * cf
		end
		if mover.Spin then
			local spin = mover.Spin * t
			cf *= CFrame.Angles(math.rad(spin.X), math.rad(spin.Y), math.rad(spin.Z))
		end
		if mover.Sway then
			cf *= CFrame.Angles(0, 0, math.rad(math.sin(t * 0.4 + mover.Phase) * mover.Sway))
		end
		if mover.Spin or mover.Bob or mover.Sway then
			if target:IsA("Model") then
				target:PivotTo(cf)
			elseif target:IsA("BasePart") then
				target.CFrame = cf
			end
		end
		if mover.Pulse then
			mover.Pulse.Transparency = math.clamp(mover.BaseTransparency + (0.5 + 0.5 * math.sin(t * 2.5 + mover.Phase)) * 0.35, 0, 1)
		end
	end
end)
