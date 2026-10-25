-- Точка входа сервера Миссии.

local ServerScriptService = game:GetService("ServerScriptService")

require(ServerScriptService.Common.DataService)
local MissionService = require(script.Parent.MissionService)

MissionService.start()

print("Миссия запущена")
