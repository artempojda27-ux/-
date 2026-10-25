--!strict
-- Сетевые события между сервером и клиентом.
-- Сервер создаёт их при первом require, клиент ждёт готовые.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Notify", -- сервер → клиент: короткое сообщение (text)
	"SquadUpdate", -- сервер → клиент: состояние отряда игрока или nil
	"SquadAction", -- клиент → сервер: действие лидера (action, value)
	"MissionUpdate", -- сервер → клиент: состояние миссии
}

local folder: Instance
if RunService:IsServer() then
	local created = Instance.new("Folder")
	created.Name = "Remotes"
	for _, name in NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = created
	end
	created.Parent = ReplicatedStorage
	folder = created
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local Remotes = {}

function Remotes.get(name: string): RemoteEvent
	assert(table.find(NAMES, name), `Неизвестное событие {name}`)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
