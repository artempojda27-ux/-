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
	Kind: "Story" | "Survival", -- сюжетная глава или бесконечные волны
}

Config.Chapters = {
	{ Id = 1, Name = "Сбой в городе", Sector = "Город", Kind = "Story" },
	{ Id = 100, Name = "Выживание", Sector = "Город", Kind = "Survival" },
} :: { Chapter }

-- Подпись главы для интерфейса: «Глава 1: Сбой в городе» или «Выживание»
function Config.chapterTitle(chapter: Chapter): string
	return if chapter.Kind == "Survival" then chapter.Name else `Глава {chapter.Id}: {chapter.Name}`
end

-- Враги. Урон — по игрокам; Speed — скорость бега (у игрока 16).
export type EnemyKind = {
	Id: string,
	Name: string,
	Health: number,
	Speed: number,
	Damage: number,
	AttackInterval: number, -- секунд между атаками
	AttackRange: number, -- с какого расстояния бьёт
	Size: Vector3,
	Color: Color3,
	Reward: number, -- бит за уничтожение (в Выживании)
	-- Стрелок держит дистанцию и стреляет медленными снарядами
	Ranged: boolean,
	ProjectileSpeed: number?,
	-- Блок бьёт по площади: перед ударом мигает, можно отбежать
	AreaRadius: number?,
	WindUp: number?, -- секунд предупреждения перед ударом по площади
}

Config.Enemies = {
	Pixel = {
		Id = "Pixel",
		Name = "Пиксель",
		Health = 40,
		Speed = 20,
		Damage = 8,
		AttackInterval = 0.8,
		AttackRange = 4,
		Size = Vector3.new(2, 2, 2),
		Color = Color3.fromRGB(60, 255, 120),
		Reward = 1,
		Ranged = false,
	},
	Block = {
		Id = "Block",
		Name = "Блок",
		Health = 300,
		Speed = 9,
		Damage = 30,
		AttackInterval = 2.5,
		AttackRange = 7,
		Size = Vector3.new(5, 5, 5),
		Color = Color3.fromRGB(40, 200, 90),
		Reward = 5,
		Ranged = false,
		AreaRadius = 9,
		WindUp = 0.8,
	},
	Shooter = {
		Id = "Shooter",
		Name = "Стрелок",
		Health = 90,
		Speed = 12,
		Damage = 15,
		AttackInterval = 2.2,
		AttackRange = 45,
		Size = Vector3.new(2, 4, 2),
		Color = Color3.fromRGB(120, 255, 60),
		Reward = 3,
		Ranged = true,
		ProjectileSpeed = 45,
	},
} :: { [string]: EnemyKind }

-- Выживание: волны врагов
Config.Survival = {
	FirstWaveSize = 6, -- врагов в первой волне при 3 игроках
	WaveGrowth = 3, -- на сколько больше врагов в каждой следующей волне
	HealthGrowth = 0.08, -- +8% здоровья врагов за каждую волну
	BreakTime = 8, -- секунд отдыха между волнами
	SpawnInterval = 0.6, -- секунд между появлениями врагов в волне
	MaxAlive = 30, -- больше врагов одновременно не бывает (чтобы не тормозило)
	RewardPerWave = 20, -- бит за каждую пройденную волну
}

export type Difficulty = {
	Id: string,
	Name: string,
	RewardMultiplier: number,
	EnemyHealth: number, -- множитель здоровья врагов
	EnemyDamage: number, -- множитель урона врагов
}

Config.Difficulties = {
	{ Id = "Normal", Name = "Обычная", RewardMultiplier = 1, EnemyHealth = 1, EnemyDamage = 1 },
	{ Id = "Hard", Name = "Сложная", RewardMultiplier = 1.5, EnemyHealth = 1.5, EnemyDamage = 1.3 },
	{ Id = "Nightmare", Name = "Кошмар", RewardMultiplier = 2.5, EnemyHealth = 2.2, EnemyDamage = 1.7 },
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
		Key = "Scanner",
		Id = 0,
		Name = "Сканер вируса",
		Description = "Сразу видишь двойников — копии игроков, которых создаёт вирус",
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
		Key = "ScanAll",
		Id = 0,
		Name = "Скан для всего отряда",
		Description = "Показывает всем двойника; если его пока нет — сработает, когда появится",
		Price = 19,
	},
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

-- Двойник: вирус копирует одного из игроков отряда и в какой-то момент предаёт
Config.Doppelganger = {
	MinPlayers = 2, -- в одиночку двойник не появляется (в Studio — появляется для проверки)
	StoryDelay = { 30, 50 }, -- в Главе 1: через сколько секунд боя появится
	SurvivalEvery = 3, -- в Выживании: на каждой третьей волне
	BetrayAfter = { 25, 45 }, -- через сколько секунд после появления предаёт
	Health = 150,
	RevealAt = 0.6, -- если здоровье упало ниже 60%, двойник раскрыт
	BlastDamage = 40, -- урон взрыва при предательстве
	BlastRadius = 12,
	BlastPixels = 3, -- сколько Пикселей вылетает из взрыва
	KillReward = 15, -- бит всему отряду, если двойника уничтожили до предательства
}

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
