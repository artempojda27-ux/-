--!strict
-- Интерфейс Миссии: задача сверху и крупные сообщения по центру.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.Parent:WaitForChild("Common"):WaitForChild("UI"))

Remotes.get("Notify").OnClientEvent:Connect(function(text: string)
	UI.toast(text)
end)

local gui = UI.screen("MissionUI")

local objective = UI.panel({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(380, 56),
	Parent = gui,
})
local chapterLabel = UI.label({
	Size = UDim2.new(1, 0, 0, 24),
	Position = UDim2.fromOffset(0, 4),
	TextSize = 14,
	TextColor3 = UI.Colors.Muted,
	Parent = objective,
})
local objectiveLabel = UI.label({
	Size = UDim2.new(1, 0, 0, 26),
	Position = UDim2.fromOffset(0, 26),
	Font = Enum.Font.GothamBold,
	TextColor3 = UI.Colors.Accent,
	Parent = objective,
})

local bigLabel = UI.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.35),
	Size = UDim2.fromOffset(700, 120),
	Font = Enum.Font.GothamBlack,
	TextSize = 44,
	TextColor3 = UI.Colors.Accent,
	TextStrokeTransparency = 0.5,
	TextWrapped = true,
	Visible = false,
	Parent = gui,
})

-- Полоска здоровья босса (Нуль в мире «Ядро»): внизу над оружием — сверху место для сообщений
local bossPanel = UI.panel({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -112),
	Size = UDim2.new(0.5, 0, 0, 44),
	Visible = false,
	Parent = gui,
})
UI.new("UISizeConstraint", { MinSize = Vector2.new(320, 44), MaxSize = Vector2.new(720, 44), Parent = bossPanel })
local bossName = UI.label({
	Position = UDim2.fromOffset(12, 2),
	Size = UDim2.new(1, -24, 0, 18),
	Font = Enum.Font.GothamBlack,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(150, 210, 255),
	Parent = bossPanel,
})
local bossTrack = UI.new("Frame", {
	Position = UDim2.fromOffset(12, 24),
	Size = UDim2.new(1, -24, 0, 12),
	BackgroundColor3 = Color3.fromRGB(30, 34, 44),
	BorderSizePixel = 0,
	Parent = bossPanel,
})
UI.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = bossTrack })
local bossFill = UI.new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(235, 245, 255),
	BorderSizePixel = 0,
	Parent = bossTrack,
})
UI.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = bossFill })

local PHASE_COLORS = {
	Color3.fromRGB(235, 245, 255),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(255, 50, 70),
}

local function showBoss(boss)
	bossPanel.Visible = boss ~= nil
	if not boss then
		return
	end
	local share = boss.Health / math.max(boss.MaxHealth, 1)
	bossFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	bossFill.BackgroundColor3 = if boss.Shield then Color3.fromRGB(90, 140, 255) else PHASE_COLORS[boss.Phase] or PHASE_COLORS[1]
	local minutes = math.floor(boss.TimeLeft / 60)
	local seconds = boss.TimeLeft % 60
	local status = if boss.Shield then " · ЩИТ — закройте сбои" elseif boss.Phase == 3 then " · ПЕРЕГРУЗКА" else ""
	bossName.Text = string.format("%s%s   %d%%   %d:%02d", boss.Name, status, math.ceil(share * 100), minutes, seconds)
end

Remotes.get("MissionUpdate").OnClientEvent:Connect(function(view)
	showBoss(view.Boss)
	chapterLabel.Text = `{view.ChapterName} · {view.DifficultyName}`
	bigLabel.Visible = true
	bigLabel.TextColor3 = UI.Colors.Accent

	if view.State == "Waiting" then
		objectiveLabel.Text = "Ждём отряд…"
		bigLabel.Visible = false
	elseif view.State == "Briefing" then
		objectiveLabel.Text = view.Objective
		if view.Kind == "Survival" then
			bigLabel.Text = `ВЫЖИВАНИЕ\nДержитесь как можно дольше!\nСтарт через {view.Timer or 0}`
		elseif view.Kind == "Escape" then
			bigLabel.Text = `ПОБЕГ\nСектор рушится — гоните к выходу!\nСтарт через {view.Timer or 0}`
		else
			bigLabel.Text = `СЕКТОР ПОВРЕЖДЁН\nСтарт через {view.Timer or 0}`
		end
	elseif view.State == "Combat" then
		objectiveLabel.Text = if view.Boss then view.Objective
			elseif view.Kind == "Escape"
			then `{view.Objective}: {math.floor(view.Progress / math.max(view.Total, 1) * 100)}%`
			else `{view.Objective}: {view.Progress}/{view.Total}`
		bigLabel.Visible = false
	elseif view.State == "Break" then
		objectiveLabel.Text = `Пройдено волн: {view.WavesCleared}`
		bigLabel.Text = `ВОЛНА {view.Wave} ПРОЙДЕНА\nСледующая через {view.Timer or 0}`
	elseif view.State == "GameOver" then
		local result = if view.Kind == "Escape"
			then `Пройдено пути: {math.floor(view.Progress / math.max(view.Total, 1) * 100)}%`
			elseif view.Kind == "Story" then "Задание провалено"
			else `Продержались волн: {view.WavesCleared}`
		local title = if view.Kind == "Escape" then "ВИРУС ДОГНАЛ ОТРЯД"
			elseif view.Kind == "Story" then (view.FailTitle or "ЗАДАНИЕ ПРОВАЛЕНО")
			else "ОТРЯД ПАЛ"
		objectiveLabel.Text = result
		bigLabel.TextColor3 = UI.Colors.Glitch
		bigLabel.Text = if view.Timer
			then `{title}\n{result}\nВозвращение в Штаб через {view.Timer}`
			else `{title}\n{result}`
	elseif view.State == "Victory" then
		objectiveLabel.Text = if view.Kind == "Escape" then "Отряд вырвался" else "Сектор очищен"
		bigLabel.Text = if view.Timer then `ПОБЕДА!\nВозвращение в Штаб через {view.Timer}` else "ПОБЕДА!"
	elseif view.State == "Returning" then
		objectiveLabel.Text = "Возвращение в Штаб"
		bigLabel.Text = "ПЕРЕНОС…"
	end
end)
