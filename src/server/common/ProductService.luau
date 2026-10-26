--!strict
-- Приём разовых покупок (Developer Product). Работает и в Штабе, и в Миссии.
-- Roblox присылает «чек» покупки; мы выдаём буст и запоминаем номер чека в сохранении,
-- чтобы при повторной доставке того же чека не выдать буст дважды.
-- Что делает каждый буст, решает место: Миссия передаёт свои обработчики в start().
-- Если обработчика нет (например, в Штабе), чек остаётся невыданным, и Roblox пришлёт его
-- снова, когда игрок окажется в Миссии.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

export type Handler = (player: Player) -> boolean -- true, если буст выдан

local ProductService = {}

local handlers: { [string]: Handler } = {}

local function productKeyById(productId: number): string?
	for _, product in Config.Products do
		if product.Id == productId and product.Id ~= 0 then
			return product.Key
		end
	end
	return nil
end

local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.waitFor(player, 10)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if data.Purchases[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- уже выдали раньше
	end

	local key = productKeyById(receipt.ProductId)
	local handler = key and handlers[key]
	if not handler then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player)
	if not ok then
		warn(`Не удалось выдать покупку {key}: {granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	data.Purchases[purchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ProductService.start(placeHandlers: { [string]: Handler })
	handlers = placeHandlers
	MarketplaceService.ProcessReceipt = processReceipt

	-- В Studio настоящие покупки не работают: выдаём буст бесплатно, чтобы его проверить
	Remotes.get("TestPurchase").OnServerEvent:Connect(function(player, key: any)
		if not RunService:IsStudio() or not Config.StudioOwnsAllPasses then
			return
		end
		local handler = typeof(key) == "string" and handlers[key]
		if handler then
			handler(player)
		end
	end)
end

return ProductService
