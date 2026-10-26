--!strict
-- Общие настройки игры. Их читают и сервер, и клиент.

local Config = {}

-- ID мест (places). Заполнить после публикации игры — см. README.
Config.PlaceIds = {
	Lobby = 0,
	Mission = 0,
}

-- Отряд
Config.SquadSize = 4
Config.StartCountdown = 5 -- секунд от «Старт» до переноса
Config.OpenSquadAutoStart = 30 -- открытый отряд стартует сам через столько секунд

-- Миссия
Config.MissionWaitForSquad = 30 -- сколько сервер миссии ждёт весь отряд
Config.BriefingTime = 5
Config.ReturnDelay = 10 -- пауза после победы перед возвращением в Штаб
Config.MissionReward = 100 -- бит за главу на обычной сложности

export type Chapter = {
	Id: number,
	Name: string,
	Sector: string,
}

Config.Chapters = {
	{ Id = 1, Name = "Сбой в городе", Sector = "Город" },
} :: { Chapter }

export type Difficulty = {
	Id: string,
	Name: string,
	RewardMultiplier: number,
}

Config.Difficulties = {
	{ Id = "Normal", Name = "Обычная", RewardMultiplier = 1 },
	{ Id = "Hard", Name = "Сложная", RewardMultiplier = 1.5 },
	{ Id = "Nightmare", Name = "Кошмар", RewardMultiplier = 2.5 },
} :: { Difficulty }

-- Платные бусты навсегда (Game Pass). Id — номер пропуска из Creator Hub;
-- 0 значит «ещё не создан» (создать после публикации игры — см. README).
export type GamePass = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Price: number, -- в Robux, только для подписи в магазине; настоящая цена задаётся в Creator Hub
}

Config.GamePasses = {
	{
		Key = "Speed",
		Id = 0,
		Name = "Ускорение",
		Description = "Бегаешь в 1,5 раза быстрее и прыгаешь дважды",
		Price = 149,
	},
	{
		Key = "XRay",
		Id = 0,
		Name = "Взгляд сквозь код",
		Description = "Видишь врагов сквозь стены и укрытия",
		Price = 199,
	},
	{
		Key = "Drone",
		Id = 0,
		Name = "Дрон-помощник",
		Description = "Летает рядом в миссии и сам стреляет по врагам",
		Price = 249,
	},
	{
		Key = "VIP",
		Id = 0,
		Name = "VIP",
		Description = "x2 биты за миссии, значок VIP и неоновый след",
		Price = 399,
	},
} :: { GamePass }

-- Разовые бусты (Developer Product): покупаются каждый раз заново и действуют только в Миссии.
export type Product = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Price: number, -- в Robux, только для подписи; настоящая цена задаётся в Creator Hub
}

Config.Products = {
	{
		Key = "Nuke",
		Id = 0,
		Name = "Код уничтожения",
		Description = "Стирает всех врагов вокруг тебя",
		Price = 49,
	},
	{
		Key = "SquadDamage",
		Id = 0,
		Name = "x2 урон всему отряду",
		Description = "60 секунд весь отряд бьёт вдвое сильнее",
		Price = 79,
	},
	{
		Key = "SquadShield",
		Id = 0,
		Name = "Бессмертие всему отряду",
		Description = "15 секунд никого из отряда ничто не ранит",
		Price = 99,
	},
	{
		Key = "Invincible",
		Id = 0,
		Name = "Бессмертие",
		Description = "15 секунд тебя ничто не ранит",
		Price = 25,
	},
	{
		Key = "DoubleDamage",
		Id = 0,
		Name = "Двойной урон",
		Description = "30 секунд твои атаки бьют вдвое сильнее",
		Price = 25,
	},
	{
		Key = "Revive",
		Id = 0,
		Name = "Встать сразу",
		Description = "После гибели встаёшь на том же месте, не дожидаясь возрождения",
		Price = 15,
	},
} :: { Product }

Config.InvincibleDuration = 15
Config.DoubleDamageDuration = 30
Config.SquadDamageDuration = 60
Config.NukeRadius = 80 -- студов вокруг покупателя
Config.MissionRespawnTime = 10 -- секунд до обычного возрождения в Миссии

-- Дрон-помощник
Config.DroneDamage = 10
Config.DroneFireInterval = 0.6
Config.DroneRange = 60

Config.VipRewardMultiplier = 2

-- В Studio считаем, что все бусты куплены, а разовые выдаются бесплатно:
-- так их можно проверить до публикации. В опубликованной игре это не работает.
Config.StudioOwnsAllPasses = true

Config.SpeedBoostMultiplier = 1.5

-- Множители врагов от числа игроков в отряде (пригодится в неделях 5–6)
Config.SquadScaling = {
	[1] = { Health = 0.7, Count = 0.6 },
	[2] = { Health = 0.85, Count = 0.8 },
	[3] = { Health = 1.0, Count = 1.0 },
	[4] = { Health = 1.15, Count = 1.2 },
}

function Config.getChapter(id: number): Chapter?
	for _, chapter in Config.Chapters do
		if chapter.Id == id then
			return chapter
		end
	end
	return nil
end

function Config.getPass(key: string): GamePass?
	for _, pass in Config.GamePasses do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

function Config.getProduct(key: string): Product?
	for _, product in Config.Products do
		if product.Key == key then
			return product
		end
	end
	return nil
end

function Config.getDifficulty(id: string): Difficulty?
	for _, difficulty in Config.Difficulties do
		if difficulty.Id == id then
			return difficulty
		end
	end
	return nil
end

return Config
