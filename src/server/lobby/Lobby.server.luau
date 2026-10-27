-- Точка входа сервера Штаба.

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

require(ServerScriptService.Common.DataService)
local PassService = require(ServerScriptService.Common.PassService)
local ProductService = require(ServerScriptService.Common.ProductService)
local SkinService = require(ServerScriptService.Common.SkinService)
local VehicleService = require(ServerScriptService.Common.VehicleService)
local Garage = require(script.Parent.Garage)
local LobbyMap = require(script.Parent.LobbyMap)
local SquadService = require(script.Parent.SquadService)

Workspace:SetAttribute("PlaceKind", "Lobby") -- клиент по нему понимает, где он

PassService.start()
SkinService.start()
ProductService.start({}) -- разовые бусты действуют только в Миссии
VehicleService.start()
SquadService.start(LobbyMap.setup())
Garage.start(LobbyMap.garage())

print("Штаб запущен")
