--!strict
-- Анимация «утекающего кода» в трещинах стен (строит сервер — CodeLeaks.luau, тег "CodeLeak"):
-- символы бегут сверху вниз, «голова» потока светлее хвоста. Далёкие трещины не обновляем.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- «<», «>» и «&» — особые знаки разметки RichText, поэтому записаны кодами
local GLYPHS = { "0", "1", "И", "С", "К", "А", "Ж", "Е", "Н", "#", "%", "&amp;", "?", "&lt;", "&gt;", "/", "=", "+", "▓", "▒", "░", "Ø", "Δ", "Ξ" }
local TICK = 0.08
local NEAR = 160

type Stream = { Part: BasePart, Label: TextLabel, Rows: { string }, Size: number, Head: Color3, Speed: number, Skip: number }

local streams: { [BasePart]: Stream } = {}
local random = Random.new()

local function glyph(): string
	return GLYPHS[random:NextInteger(1, #GLYPHS)]
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function add(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local label = instance:FindFirstChild("Glyphs", true)
	if not label or not label:IsA("TextLabel") then
		return
	end
	local size = instance:GetAttribute("Rows")
	local head = instance:GetAttribute("Head")
	local rows = {}
	local count = if typeof(size) == "number" then size else 20
	for i = 1, count do
		rows[i] = if random:NextNumber() < 0.5 then glyph() else " "
	end
	streams[instance] = {
		Part = instance,
		Label = label,
		Rows = rows,
		Size = count,
		Head = if typeof(head) == "Color3" then head else Color3.new(1, 1, 1),
		Speed = random:NextInteger(1, 2), -- у потоков разная скорость
		Skip = 0,
	}
end

for _, instance in CollectionService:GetTagged("CodeLeak") do
	add(instance)
end
CollectionService:GetInstanceAddedSignal("CodeLeak"):Connect(add)
CollectionService:GetInstanceRemovedSignal("CodeLeak"):Connect(function(instance)
	streams[instance :: BasePart] = nil
end)

local function render(stream: Stream)
	local rows = stream.Rows
	-- сдвиг вниз: сверху новый символ или пустота (разрывы в потоке)
	table.remove(rows)
	table.insert(rows, 1, if random:NextNumber() < 0.7 then glyph() else " ")
	-- иногда символ в середине «мигает» — меняется на месте
	local flicker = random:NextInteger(1, stream.Size)
	if rows[flicker] ~= " " then
		rows[flicker] = glyph()
	end
	local headColor = hex(stream.Head)
	local lines = table.create(stream.Size)
	for i, ch in rows do
		if i <= 2 then
			lines[i] = `<font color="{headColor}">{ch}</font>`
		else
			local fade = math.clamp((i / stream.Size) * 0.85, 0, 0.85)
			lines[i] = `<font transparency="{string.format("%.2f", fade)}">{ch}</font>`
		end
	end
	stream.Label.Text = table.concat(lines, "\n")
end

while true do
	task.wait(TICK)
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	for part, stream in streams do
		if part.Parent == nil then
			streams[part] = nil
		elseif (part.Position - eye).Magnitude < NEAR then
			stream.Skip += 1
			if stream.Skip >= stream.Speed then
				stream.Skip = 0
				render(stream)
			end
		end
	end
end
