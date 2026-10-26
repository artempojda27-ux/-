--!strict
-- Передача настроек миссии из Штаба на сервер миссии.
-- Храним их в MemoryStore по ID закрытого сервера, а не в TeleportData:
-- TeleportData идёт через клиента, и читер может его подменить.

local MemoryStoreService = game:GetService("MemoryStoreService")

local EXPIRATION = 60 * 60 -- час: потом запись удаляется сама
local ATTEMPTS = 3

export type MissionInfo = {
	Chapter: number,
	Difficulty: string,
	Members: { number }, -- UserId участников отряда
	World: string?, -- параллельный мир (nil — Неоновый город)
}

local map: MemoryStoreHashMap? = nil

-- Берём хранилище при первом обращении: в неопубликованном месте (тест в Studio)
-- GetHashMap выдаёт ошибку, и если вызвать его сразу, не загрузится весь сервер.
local function getMap(): MemoryStoreHashMap?
	if not map then
		local ok, result = pcall(function()
			return MemoryStoreService:GetHashMap("MissionInfo_v1")
		end)
		if not ok then
			warn(`MissionStore недоступен: {result}`)
			return nil
		end
		map = result
	end
	return map
end

local MissionStore = {}

function MissionStore.save(privateServerId: string, info: MissionInfo): boolean
	local store = getMap()
	if not store then
		return false
	end
	for attempt = 1, ATTEMPTS do
		local ok, err = pcall(function()
			store:SetAsync(privateServerId, info, EXPIRATION)
		end)
		if ok then
			return true
		end
		warn(`MissionStore.save, попытка {attempt}: {err}`)
		task.wait(attempt)
	end
	return false
end

function MissionStore.load(privateServerId: string): MissionInfo?
	local store = getMap()
	if not store then
		return nil
	end
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function()
			return store:GetAsync(privateServerId)
		end)
		if ok then
			return result
		end
		warn(`MissionStore.load, попытка {attempt}: {result}`)
		task.wait(attempt)
	end
	return nil
end

return MissionStore
