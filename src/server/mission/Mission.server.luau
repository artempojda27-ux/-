-- Точка входа сервера Миссии.

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

require(ServerScriptService.Common.DataService)
local PassService = require(ServerScriptService.Common.PassService)
local ProductService = require(ServerScriptService.Common.ProductService)
local SkinService = require(ServerScriptService.Common.SkinService)
local StoryService = require(ServerScriptService.Common.StoryService)
local VehicleService = require(ServerScriptService.Common.VehicleService)
local AbilityService = require(script.Parent.AbilityService)
local BoostEffects = require(script.Parent.BoostEffects)
local DoppelgangerService = require(script.Parent.DoppelgangerService)
local DroneService = require(script.Parent.DroneService)
local EnemyService = require(script.Parent.EnemyService)
local MissionService = require(script.Parent.MissionService)
local WeaponService = require(script.Parent.WeaponService)

Workspace:SetAttribute("PlaceKind", "Mission") -- клиент по нему понимает, где он

PassService.start()
SkinService.start()
StoryService.start()
VehicleService.start()
BoostEffects.start()
ProductService.start(BoostEffects.handlers)
EnemyService.start()
DoppelgangerService.start()
MissionService.start()
WeaponService.start()
AbilityService.start()
DroneService.start()

print("Миссия запущена")
