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
}

local map = MemoryStoreService:GetHashMap("MissionInfo_v1")

local MissionStore = {}

function MissionStore.save(privateServerId: string, info: MissionInfo): boolean
	for attempt = 1, ATTEMPTS do
		local ok, err = pcall(function()
			map:SetAsync(privateServerId, info, EXPIRATION)
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
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function()
			return map:GetAsync(privateServerId)
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
