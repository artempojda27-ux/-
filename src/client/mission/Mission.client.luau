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

Remotes.get("MissionUpdate").OnClientEvent:Connect(function(view)
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
		objectiveLabel.Text = if view.Kind == "Escape"
			then `{view.Objective}: {math.floor(view.Progress / math.max(view.Total, 1) * 100)}%`
			else `{view.Objective}: {view.Progress}/{view.Total}`
		bigLabel.Visible = false
	elseif view.State == "Break" then
		objectiveLabel.Text = `Пройдено волн: {view.WavesCleared}`
		bigLabel.Text = `ВОЛНА {view.Wave} ПРОЙДЕНА\nСледующая через {view.Timer or 0}`
	elseif view.State == "GameOver" then
		local result = if view.Kind == "Escape"
			then `Пройдено пути: {math.floor(view.Progress / math.max(view.Total, 1) * 100)}%`
			else `Продержались волн: {view.WavesCleared}`
		local title = if view.Kind == "Escape" then "ВИРУС ДОГНАЛ ОТРЯД" else "ОТРЯД ПАЛ"
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
