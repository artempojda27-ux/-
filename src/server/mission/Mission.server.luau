-- Точка входа сервера Миссии.

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

require(ServerScriptService.Common.DataService)
local PassService = require(ServerScriptService.Common.PassService)
local ProductService = require(ServerScriptService.Common.ProductService)
local BoostEffects = require(script.Parent.BoostEffects)
local DroneService = require(script.Parent.DroneService)
local EnemyService = require(script.Parent.EnemyService)
local MissionService = require(script.Parent.MissionService)
local TrainingTargets = require(script.Parent.TrainingTargets)
local WeaponService = require(script.Parent.WeaponService)

Workspace:SetAttribute("PlaceKind", "Mission") -- клиент по нему понимает, где он

PassService.start()
BoostEffects.start()
ProductService.start(BoostEffects.handlers)
EnemyService.start()
MissionService.start()
WeaponService.start()
DroneService.start()
if not MissionService.isSurvival() then
	TrainingTargets.start() -- мишени мешали бы считать врагов волны
end

print("Миссия запущена")
