-- Точка входа сервера Штаба.

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

require(ServerScriptService.Common.DataService)
local PassService = require(ServerScriptService.Common.PassService)
local ProductService = require(ServerScriptService.Common.ProductService)
local LobbyMap = require(script.Parent.LobbyMap)
local SquadService = require(script.Parent.SquadService)

Workspace:SetAttribute("PlaceKind", "Lobby") -- клиент по нему понимает, где он

PassService.start()
ProductService.start({}) -- разовые бусты действуют только в Миссии
SquadService.start(LobbyMap.setup())

print("Штаб запущен")
