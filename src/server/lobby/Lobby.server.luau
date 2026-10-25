-- Точка входа сервера Штаба.

local ServerScriptService = game:GetService("ServerScriptService")

require(ServerScriptService.Common.DataService)
local LobbyMap = require(script.Parent.LobbyMap)
local SquadService = require(script.Parent.SquadService)

SquadService.start(LobbyMap.setup())

print("Штаб запущен")
