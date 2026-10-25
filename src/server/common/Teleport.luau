--!strict
-- Переносы между Штабом и Миссией с повторными попытками.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ATTEMPTS = 3
local RETRIES_AFTER_FAIL = 2

local notify = Remotes.get("Notify")
local retriesLeft: { [Player]: number } = {}

local Teleport = {}

-- Можно ли сейчас переносить на это место. Если нет — вторым значением причина.
function Teleport.check(placeId: number): (boolean, string?)
	if RunService:IsStudio() then
		return false, "Перенос между Штабом и Миссией работает только в опубликованной игре."
	end
	if placeId == 0 then
		return false, "Не указан ID места в Config.PlaceIds."
	end
	return true, nil
end

-- Создаёт закрытый сервер. Возвращает код доступа и ID сервера.
function Teleport.reserveServer(placeId: number): (string?, string?)
	for attempt = 1, ATTEMPTS do
		local ok, code, serverId = pcall(function()
			return TeleportService:ReserveServer(placeId)
		end)
		if ok then
			return code, serverId
		end
		warn(`ReserveServer, попытка {attempt}: {code}`)
		task.wait(attempt)
	end
	return nil, nil
end

-- Переносит группу игроков вместе. options можно не передавать.
function Teleport.send(placeId: number, players: { Player }, options: TeleportOptions?): boolean
	for _, player in players do
		retriesLeft[player] = RETRIES_AFTER_FAIL
	end
	for attempt = 1, ATTEMPTS do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true
		end
		warn(`TeleportAsync, попытка {attempt}: {err}`)
		task.wait(attempt * 2)
	end
	return false
end

-- Если перенос сорвался уже после запуска — пробуем ещё раз для этого игрока
TeleportService.TeleportInitFailed:Connect(function(player, result, message, placeId, options)
	local left = retriesLeft[player] or 0
	if result == Enum.TeleportResult.Flooded or left <= 0 then
		retriesLeft[player] = nil
		notify:FireClient(player, "Не получилось перенести. Попробуй ещё раз.")
		warn(`Перенос {player.Name} не удался: {result.Name} {message}`)
		return
	end
	retriesLeft[player] = left - 1
	task.wait(2)
	pcall(function()
		TeleportService:TeleportAsync(placeId, { player }, options)
	end)
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	retriesLeft[player] = nil
end)

return Teleport
