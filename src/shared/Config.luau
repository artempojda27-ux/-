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
	Kind: "Story" | "Survival" | "Escape", -- сюжетная глава, бесконечные волны или побег на машинах
}

Config.Chapters = {
	{ Id = 1, Name = "Сбой в городе", Sector = "Город", Kind = "Story" },
	{ Id = 100, Name = "Выживание", Sector = "Город", Kind = "Survival" },
	{ Id = 200, Name = "Побег", Sector = "Трасса", Kind = "Escape" },
} :: { Chapter }

-- Подпись главы для интерфейса: «Глава 1: Сбой в городе» или «Выживание»
function Config.chapterTitle(chapter: Chapter): string
	return if chapter.Kind == "Story" then `Глава {chapter.Id}: {chapter.Name}` else chapter.Name
end

-- Параллельные миры: та же глава в другой версии симуляции.
-- Открываются по очереди: UnlockAfter — в каком мире нужно победить, чтобы этот открылся (nil — открыт сразу).
export type World = {
	Id: string,
	Name: string,
	EnemyHealth: number,
	EnemyDamage: number,
	DoubleRate: number, -- во сколько раз чаще появляются двойники
	UnlockAfter: string?,
}

Config.Worlds = {
	{ Id = "Neon", Name = "Неоновый город", EnemyHealth = 1, EnemyDamage = 1, DoubleRate = 1, UnlockAfter = nil },
	{ Id = "Mirror", Name = "Зеркальный город", EnemyHealth = 1.3, EnemyDamage = 1.2, DoubleRate = 2, UnlockAfter = "Neon" },
	{ Id = "Temple", Name = "Храм ветра", EnemyHealth = 1.4, EnemyDamage = 1.25, DoubleRate = 2, UnlockAfter = "Mirror" },
	{ Id = "Crystal", Name = "Кристалл семи миров", EnemyHealth = 1.5, EnemyDamage = 1.3, DoubleRate = 2.2, UnlockAfter = "Temple" },
	{ Id = "Erased", Name = "Стёртый мир", EnemyHealth = 1.6, EnemyDamage = 1.4, DoubleRate = 2.5, UnlockAfter = "Crystal" },
	{ Id = "Monolith", Name = "Монолит", EnemyHealth = 2, EnemyDamage = 1.7, DoubleRate = 3, UnlockAfter = "Erased" },
	-- седьмой мир — сердце Сети, где проснулся Нуль (docs/Saga.md)
	{ Id = "Core", Name = "Ядро", EnemyHealth = 2.4, EnemyDamage = 2, DoubleRate = 3.5, UnlockAfter = "Monolith" },
} :: { World }

-- Детальные модели для миров, сгенерированные в Studio (лежат в инвентаре владельца игры).
-- Asset — номер модели; или Mesh + Texture — номера сетки и текстуры. Пусто — собрать из деталей.
export type PropSpec = { Asset: number?, Mesh: number?, Texture: number? }

Config.WorldProps = {
	Dragon = { Mesh = 83301505869394, Texture = 125573193894382 }, -- крылатый дракон над «Храмом ветра»
	BigCrystal = { Asset = 110030899354077 }, -- большой Кристалл над площадью «Кристалла семи миров»
	Torii = { Asset = 91095988254496 }, -- ворота у площади «Храма ветра»
	StoneLantern = { Asset = 110536070250278 }, -- каменные фонари вдоль улиц «Храма ветра»
	CrystalIsland = { Asset = 110446111143040 }, -- парящие острова «Кристалла семи миров»
} :: { [string]: PropSpec }

-- Детальные модели Штаба (LobbyLook): голостол с Кристаллом, командир, арки порталов. 0 — без модели
Config.LobbyProps = {
	HoloTable = 104183115099747,
	Commander = 71573357373379,
	PortalArch = 82710245942031,
}

-- Сюжет (docs/Saga.md): Нуль — это Кай, первый Корректор. Он ушёл в Ядро один, вирус переписал его.
-- Вега — основательница Штаба и напарница Кая — узнаёт правду вместе с игроком.
-- Командор Вега: реплики по числу пройденных миров (Stages[0] — новичок, Stages[7] — после победы над Нулём).
Config.Commander = {
	Name = "Командор Вега",
	Stages = {
		[0] = {
			"Ты видишь трещины? Значит, ты один из нас. Добро пожаловать в Штаб, Корректор.",
			"Сеть — это семь миров. Их держит Кристалл — вот он, над столом. Каждый цвет — один мир.",
			"В Ядре проснулся Нуль. Он считает ошибкой всё живое и переписывает миры один за другим.",
			"Встань в портал с друзьями — до четырёх человек. Закрывайте сбои, пока вирус не сломал город.",
			"Осторожно: Нуль умеет копировать людей. Если друг мерцает — это не твой друг.",
		},
		[1] = {
			"Первый сектор чист. Хорошая работа, Корректор.",
			"В городах лежат осколки памяти — светящиеся кристаллы под столбом света. Это записи тех, кто сражался до вас.",
			"Собирай их. Следующий — Зеркальный город: там Нуль строит армию копий.",
		},
		[2] = {
			"Копии… Он всегда умел копировать. Лучше всех.",
			"Не спрашивай пока. Иди в Храм ветра — дракон-хранитель сходит с ума.",
		},
		[3] = {
			"Дракон спокоен. Кай бы гордился вами.",
			"Кай — первый Корректор. Мы вместе построили этот Штаб.",
			"Когда Нуль только проснулся, Кай ушёл в Ядро один. И не вернулся.",
		},
		[4] = {
			"В отражениях Кристалла вы видели человека в старой броне Корректора? Я тоже видела.",
			"Я думала, Кай погиб. Теперь… я не уверена.",
		},
		[5] = {
			"Стёртый мир — там Кай нашёл Нуля. Там его след и обрывается.",
			"Если найдёте его осколки памяти — читайте внимательно. Мне нужно знать правду.",
		},
		[6] = {
			"Я прочитала осколки. Нуль — это Кай.",
			"Вирус переписал его и оставил только приказ: «удалять ошибки». Он копирует людей, потому что сам — копия.",
			"Где-то внутри остался настоящий Кай. Победите Нуля в Ядре. Может, это его освободит.",
		},
		[7] = {
			"Нуль стёрт. Кай свободен. Спасибо вам, Корректоры.",
			"Его значок теперь висит над голостолом. Сеть живёт — но трещины ещё есть.",
			"Отдыхайте. Скоро вы понадобитесь снова.",
		},
	} :: { [number]: { string } },
}

-- Сюжет по мирам: связь с Вегой в начале миссии и осколок памяти (запись Кая), спрятанный в городе
Config.Story = {
	Briefings = {
		Neon = "Сбои в центре города. Закройте их, пока вирус не сломал всё.",
		Mirror = "Город отражается в небе. Это армия копий Нуля. Не доверяйте никому.",
		Temple = "Дракон-хранитель сходит с ума. Держитесь подальше от его тени.",
		Crystal = "Нуль хочет расколоть Кристалл. Если он падёт — миры рассыплются.",
		Erased = "Здесь Нуль уже стёр всё. Здесь пропал Кай. Будьте осторожны.",
		Monolith = "Глаз Нуля следит за каждым шагом. Это последний рубеж перед Ядром.",
		Core = "Это Ядро. Сердце Сети. Нуль ждёт. Закройте сбои — и он выйдет к вам.",
	} :: { [string]: string },
	-- Письма-зацепки: по одному в каждом задании (Letters[мир][номер задания]). Третье письмо мира — запись Кая.
	Letters = {
		Neon = {
			{ From = "Горожанин", Title = "Записка на стене", Text = "Вчера мой сосед вышел за хлебом и вернулся дважды. Один из них не моргает. Я запер дверь." },
			{ From = "Клон Веги", Title = "Отчёт клона №7", Text = "Оригинал приказала держать канал любой ценой. Я — её копия, но копия по своей воле. Нуль так не умеет." },
			{ From = "Кай", Title = "Запись Кая №1", Text = "Сегодня мы с Вегой закрыли первый сбой. Она смеялась, что я лезу вперёд всех. Кто-то же должен." },
		},
		Mirror = {
			{ From = "Отражение", Title = "Надпись наоборот", Text = "…ьсолавыв огокот ьтыб ястеачатз Я — это прочитано справа налево. Кто-то здесь пишет из зеркала." },
			{ From = "Клон Веги", Title = "Отчёт клона №12", Text = "Зеркальные копии Нуля носят старую броню Корректоров. Первую модель. Такую носил только Кай." },
			{ From = "Кай", Title = "Запись Кая №2", Text = "В Ядре нашлась программа-уборщик. Называет себя Нулём и задаёт странные вопросы: «Зачем ошибкам жить?»" },
		},
		Temple = {
			{ From = "Монах", Title = "Свиток у фонаря", Text = "Дракон пропустил к Ядру лишь одного человека. Тот поклонился и сказал: «Я вернусь до заката». Закат был сто дней назад." },
			{ From = "Клон Веги", Title = "Отчёт клона №19", Text = "Дракон не враг. Он охраняет вход в Ядро от Нуля. Если вы его успокоили — путь открыт и для нас." },
			{ From = "Кай", Title = "Запись Кая №3", Text = "Дракон-хранитель пропустил меня к Ядру. Сказал: «Ты вернёшься другим». Не вернусь. То есть вернусь тем же." },
		},
		Crystal = {
			{ From = "Хранитель Кристалла", Title = "Грань №4", Text = "В Кристалле семь граней — по одной на мир. Седьмая, Ядро, треснула изнутри. Трещина имеет форму человека." },
			{ From = "Клон Веги", Title = "Отчёт клона №23", Text = "Я сверила код Нуля с архивом Штаба. Совпадение с одним Корректором — 98%. Оригинал запретила мне называть имя." },
			{ From = "Кай", Title = "Запись Кая №4", Text = "Нуль научился копировать. Сначала камни, потом дома, потом меня. Я видел себя со стороны. Он улыбался моей улыбкой." },
		},
		Erased = {
			{ From = "Неизвестный", Title = "Недописанное письмо", Text = "Если найдёшь это — значит, меня уже стёрли. Мир исчезает по краям. Сначала цвет, потом звук, потом имя…" },
			{ From = "Клон Веги", Title = "Отчёт клона №31", Text = "Здесь обрывается след Кая. Я нашла его шлем. Внутри — пусто. Не тело пропало. Пропал он сам." },
			{ From = "Кай", Title = "Запись Кая №5", Text = "Мир вокруг стирается. Держусь за одно — имя. Меня зовут Кай. Меня зовут Кай. Меня зовут…" },
		},
		Monolith = {
			{ From = "Перехват Нуля", Title = "Код из глаза", Text = "ЗАДАЧА: удалить ошибки. ОШИБКА №1: Вега. ПРИЧИНА: «помнит меня». Странная причина для программы." },
			{ From = "Клон Веги", Title = "Отчёт клона №40", Text = "Глаз ищет не вас. Он ищет оригинал. Нуль боится одного — что его узнают. Значит, он ещё помнит." },
			{ From = "Кай", Title = "Запись Кая №6", Text = "Я не помню лица Веги. Помню только приказ: удалять ошибки. Если ты это читаешь — ошибка теперь я. Останови меня." },
		},
		Core = {
			{ From = "Ядро", Title = "Журнал Ядра", Text = "Обнаружен посторонний: Корректор. Попытка удаления — неудачна. Создана копия. Копия назначена хранителем. Имя копии: Нуль." },
			{ From = "Клон Веги", Title = "Последний отчёт", Text = "Это последний клон. Оригинал идёт с вами. Она хочет сказать ему одно слово. Помогите ей дожить до этого." },
			{ From = "Кай", Title = "Значок Кая", Text = "Треснутый значок первого Корректора. На обороте нацарапано: «Вега, я пытался вернуться»." },
		},
	} :: { [string]: { { From: string, Title: string, Text: string } } },
	-- Клоны Веги в городах: голограммы, которые подсказывают по заданию (Hints[номер задания])
	CloneHints = {
		"Я клон Веги. Закрывайте сбои — пока они открыты, из них лезут Пиксели. Где-то в городе спрятано письмо — ищите столб света.",
		"Я держу канал связи со Штабом. Вирус хочет меня стереть — защищайте меня, пока передача не завершится!",
		"Вирус спрятал данные по городу. Соберите все осколки, и придёт их Страж. Победите его — данные наши.",
	},
	-- Вега по связи после победы в задании (Debriefs[мир][номер]) — ведёт сюжет между письмами
	Debriefs = {
		Neon = {
			"Сбои закрыты. Ты заметил, что двойник пытался вас остановить? Нуль учится на нас.",
			"Канал держится. Мой клон выжил благодаря вам. Они — это я, только смелее.",
			"Данные расшифрованы: Нуль ищет кого-то в Штабе. Не говорите никому, что я это сказала.",
		},
		Mirror = {
			"Зеркальный город отражает не дома. Он отражает воспоминания. Чьи — я пока не знаю.",
			"В передаче был посторонний сигнал. Кто-то звал меня по имени. Старым голосом.",
			"Вы нашли меня — настоящую. Копии Нуля носили броню Кая. Первую модель. Я её сама красила.",
		},
		Temple = {
			"Храм спокоен. Монахи говорят, сюда приходил Корректор в старой броне. Сто дней назад.",
			"Хранитель передал: «Тот, кто вошёл в Ядро, ещё жив. Но он забыл своё имя».",
			"Дракон уснул. Он оставил вам знак — чешую с выжженной буквой «К».",
		},
		Crystal = {
			"Кристалл трещит изнутри. Трещина похожа на человека. Не смотрите на неё долго.",
			"Мой клон сверил код. Я не буду повторять, что он нашёл. Пока не буду.",
			"Данные Кристалла показали: седьмой мир — не мир. Это клетка. И в ней кто-то есть.",
		},
		Erased = {
			"Здесь пропал Кай. Его шлем пустой. Это значит — его не убили. Его переписали.",
			"Канал держится даже здесь, где ничего нет. Значит, и он может держаться.",
			"Цвета вернулись. Если мир можно вспомнить — то и человека можно. Правда?",
		},
		Monolith = {
			"Глаз ищет не вас. Он ищет меня. Нуль боится, что я его узнаю.",
			"Перехват: «ОШИБКА №1: Вега». Он внёс меня в список первой. Он помнит.",
			"Глаз ослеп. Путь в Ядро открыт. Я иду с вами. Мне нужно сказать ему одно слово.",
		},
		Core = {
			"Сбои Ядра закрыты. Я чувствую его. Он рядом и он… боится.",
			"Это последний клон. Дальше — только мы. Готовьтесь.",
			"",
		},
	} :: { [string]: { string } },
	-- Нуль в финальном бою
	Null = {
		Spawn = "Корректоры… Я помню это слово. Когда-то оно было моим.",
		Shield = "Вы закрываете сбои. Как я когда-то. Бесполезно.",
		Phase2 = "Я скопирую одного из вас. Посмотрим, отличите ли.",
		Phase3 = "Вега послала вас? Она всегда посылала других… Нет. Это я ушёл один.",
		Taunts = {
			"Ошибки не должны жить.",
			"Я — порядок. Вы — шум.",
			"Меня зовут… неважно.",
			"Сеть станет тихой. Идеально тихой.",
		},
		Death = "Меня… зовут… Кай.",
		Timeout = "Сеть чиста. Наконец-то тихо.",
		VegaAfter = "Кай?.. Прощай. Спасибо вам, Корректоры. Возвращайтесь в Штаб.",
	},
}

-- Письмо по номеру вида "Neon_2" (мир и номер задания)
function Config.getLetter(id: string): { From: string, Title: string, Text: string }?
	local worldId, index = string.match(id, "^(%a+)_(%d+)$")
	local letters = worldId and Config.Story.Letters[worldId]
	return letters and letters[tonumber(index) :: number] or nil
end

-- Все номера писем по порядку: миры, в каждом — задания
function Config.letterIds(): { string }
	local ids = {}
	for _, world in Config.Worlds do
		for index in Config.Story.Letters[world.Id] or {} do
			table.insert(ids, `{world.Id}_{index}`)
		end
	end
	return ids
end

-- Задания в каждом мире (сюжетная глава): идут по порядку, мир считается пройденным после третьего.
-- Kind: "Glitches" — закрыть сбои, "Defend" — защитить клона Веги, "Hunt" — собрать данные и победить Стража,
-- "Boss" — сбои и бой с Нулём (только в Ядре). С каждым заданием враги крепче (Power).
export type Mission = { Index: number, Kind: string, Name: string, Power: number, Hint: string?, Hazard: string?, Target: TargetSpec? }
Config.Missions = {
	{ Index = 1, Kind = "Glitches", Name = "Закрыть сбои", Power = 1 },
	{ Index = 2, Kind = "Defend", Name = "Удержать канал", Power = 1.2 },
	{ Index = 3, Kind = "Hunt", Name = "Охота за данными", Power = 1.4 },
} :: { Mission }
Config.DefendTime = 90 -- секунд держать канал
Config.DefendCloneHealth = 900
Config.HuntFragments = 5

-- Особые задания миров вместо общих (WorldMissions[мир][номер]). Kind:
--   "RealClone" — среди клонов Веги найти настоящую (подделки Нуля взрываются врагами);
--   "Targets" — активировать точки по городу (Target — что это за точки), пока мир мешает (Hazard):
--     "Fire" — огонь дракона бьёт в отмеченные круги, "Eye" — красный луч глаза ищет отряд.
-- Recolor — с каждой точкой мир возвращает краски (обесцвеченный Стёртый мир)
export type TargetSpec = { Count: number, Action: string, Object: string, Color: Color3, DoneColor: Color3, Hold: number, Recolor: boolean? }
Config.WorldMissions = {
	Neon = {
		[3] = {
			Kind = "Targets", Name = "Перезапуск генераторов",
			Hint = "Вирус отключил генераторы города. Запустите все пять — и сеть снова оживёт.",
			Target = { Count = 5, Action = "Запустить", Object = "Генератор", Color = Color3.fromRGB(40, 50, 60), DoneColor = Color3.fromRGB(0, 255, 200), Hold = 2 },
		},
	},
	Crystal = {
		[2] = {
			Kind = "Targets", Name = "Очистить грани", Hazard = "Shards",
			Hint = "Вирус пророс в грани Кристалла. Очистите четыре — и берегитесь падающих осколков!",
			Target = { Count = 4, Action = "Очистить", Object = "Грань", Color = Color3.fromRGB(120, 255, 90), DoneColor = Color3.fromRGB(190, 150, 255), Hold = 2.5 },
		},
		[3] = {
			Kind = "Targets", Name = "Семь граней", Hazard = "Shards",
			Hint = "Соберите семь граней — по одной на каждый мир. Тогда Кристалл выдержит удар Нуля.",
			Target = { Count = 7, Action = "Собрать", Object = "Грань мира", Color = Color3.fromRGB(90, 80, 110), DoneColor = Color3.fromRGB(255, 160, 225), Hold = 1.5 },
		},
	},
	Core = {
		[2] = {
			Kind = "Targets", Name = "Отключить защиту Ядра", Hazard = "Overload",
			Hint = "Ядро защищают четыре узла. Отключите их, пока Ядро бьёт током. Это последний шаг к Нулю.",
			Target = { Count = 4, Action = "Отключить", Object = "Узел защиты", Color = Color3.fromRGB(150, 220, 255), DoneColor = Color3.fromRGB(30, 30, 40), Hold = 3 },
		},
	},
	Mirror = {
		[2] = {
			Kind = "Targets", Name = "Разбить зеркала",
			Hint = "Нуль смотрит на нас через четыре больших зеркала. Разбейте их — и он ослепнет в этом городе.",
			Target = { Count = 4, Action = "Разбить", Object = "Зеркало", Color = Color3.fromRGB(255, 190, 200), DoneColor = Color3.fromRGB(60, 10, 20), Hold = 1.5 },
		},
		[3] = { Kind = "RealClone", Name = "Настоящая Вега", Hint = "Среди нас копии Нуля. У подделок контур чуть розовее. Проверь каждую — но осторожно." },
	},
	Temple = {
		[3] = {
			Kind = "Targets", Name = "Фонари для дракона", Hazard = "Fire",
			Hint = "Дракон видит только огни. Зажгите пять фонарей — свет успокоит его. Берегитесь огня с неба!",
			Target = { Count = 5, Action = "Зажечь", Object = "Фонарь духа", Color = Color3.fromRGB(80, 60, 50), DoneColor = Color3.fromRGB(255, 170, 60), Hold = 2 },
		},
	},
	Erased = {
		[3] = {
			Kind = "Targets", Name = "Вернуть цвета",
			Hint = "Здесь всё стёрто. В городе остались пять узлов цвета — восстановите их, и мир вспомнит себя.",
			Target = { Count = 5, Action = "Восстановить", Object = "Узел цвета", Color = Color3.fromRGB(200, 200, 205), DoneColor = Color3.fromRGB(255, 80, 180), Hold = 3, Recolor = true },
		},
	},
	Monolith = {
		[3] = {
			Kind = "Targets", Name = "Ослепить глаз", Hazard = "Eye",
			Hint = "Глаз Нуля видит всё. Отключите четыре ретранслятора — и он ослепнет. Не стойте в красном свете!",
			Target = { Count = 4, Action = "Отключить", Object = "Ретранслятор", Color = Color3.fromRGB(255, 40, 50), DoneColor = Color3.fromRGB(40, 40, 46), Hold = 3 },
		},
	},
} :: { [string]: { [number]: { [string]: any } } }

function Config.getMission(worldId: string?, index: number?): Mission
	local mission = Config.Missions[math.clamp(index or 1, 1, #Config.Missions)]
	if worldId == "Core" and mission.Index == #Config.Missions then
		return { Index = mission.Index, Kind = "Boss", Name = "Бой с Нулём", Power = mission.Power }
	end
	local special = worldId and Config.WorldMissions[worldId] and Config.WorldMissions[worldId][mission.Index]
	if special then
		return {
			Index = mission.Index,
			Kind = special.Kind,
			Name = special.Name,
			Power = mission.Power,
			Hint = special.Hint,
			Hazard = special.Hazard,
			Target = special.Target,
		} :: any
	end
	return mission
end

-- Детальные здания по наборам (модели-ассеты, надеваются на дома города — CitySkins).
-- Стёртый мир и Монолит берут набор Neon без текстур.
Config.BuildingSets = {
	Neon = { 94096090697242, 76796274916740, 90208541309645 }, -- жилой блок, техно-башня, небоскрёб
	Temple = { 103280961104061, 97921744113705 }, -- пагода, зал монастыря
	Crystal = { 71692760958193, 125411848251603 }, -- кристальная башня, кристальный дом
	Core = { 73706310770798, 71793523895856 }, -- башня-сервер, узел обработки данных
} :: { [string]: { number } }

-- Монумент на краю площади (0 — без монумента)
Config.Monuments = {
	Neon = 117185050142167, -- герой с энергоклинком
	Temple = 113200354495453, -- лев-страж
	Crystal = 0, -- у Кристалла свой большой Кристалл
	Core = 75237786712990, -- Нуль — злодей саги
} :: { [string]: number }

function Config.getWorld(id: string?): World
	for _, world in Config.Worlds do
		if world.Id == id then
			return world
		end
	end
	return Config.Worlds[1]
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

-- Детальные тела врагов (модели, сгенерированные в Studio; 0 — простая коробка со светящимся лицом)
Config.EnemyModels = {
	Pixel = 117136918311406, -- глитч-кубик с большим глазом
	Block = 74354002161797, -- голем из битых кубов
	Shooter = 97258077839938, -- страж-кристалл с глазом-пушкой
} :: { [string]: number }

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
		Key = "Thrusters",
		Id = 0,
		Name = "Реактивные сопла",
		Description = "Твоя машина подпрыгивает и делает сальто в воздухе (Shift или F)",
		Price = 199,
	},
	{
		Key = "Nitro",
		Id = 0,
		Name = "Нитро",
		Description = "Q — три секунды машина едет в 1,6 раза быстрее (раз в 10 секунд)",
		Price = 149,
	},
	{
		Key = "NeonTuning",
		Id = 0,
		Name = "Неоновый тюнинг",
		Description = "Светящийся контур и след у твоей машины, их видят все. C — сменить цвет",
		Price = 99,
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

-- Машины на воздушной подушке
export type VehicleKind = {
	Id: string,
	Name: string,
	Order: number, -- место в автосалоне
	Design: string, -- как выглядит (см. VehicleDesigns)
	Seats: number, -- вместе с водителем
	MaxSpeed: number, -- студов в секунду вперёд
	ReverseSpeed: number,
	Acceleration: number,
	TurnSpeed: number, -- радиан в секунду
	HoverHeight: number,
	Size: Vector3, -- корпус
	Color: Color3,
	GlowColor: Color3,
	AccentColor: Color3,
	-- Детальный кузов: модель-ассет, сгенерированная в Studio (0 — собирать машину из деталей)
	ShellAsset: number,
	ShellScale: number, -- во сколько раз увеличить модель
}

Config.Vehicles = {
	GlitchBike = {
		Id = "GlitchBike",
		Name = "Глитч-байк",
		Order = 1,
		Design = "Bike",
		Seats = 1,
		MaxSpeed = 95,
		ReverseSpeed = 25,
		Acceleration = 70,
		TurnSpeed = 2.6,
		HoverHeight = 1,
		Size = Vector3.new(2.6, 1.6, 7.6),
		Color = Color3.fromRGB(16, 16, 22),
		GlowColor = Color3.fromRGB(255, 40, 120),
		AccentColor = Color3.fromRGB(0, 255, 200),
		ShellAsset = 121199819788764,
		ShellScale = 1.3,
	},
	Volt = {
		Id = "Volt",
		Name = "Вольт",
		Order = 2,
		Design = "Roadster",
		Seats = 2,
		MaxSpeed = 110,
		ReverseSpeed = 30,
		Acceleration = 75,
		TurnSpeed = 2.2,
		HoverHeight = 0.8,
		Size = Vector3.new(8, 2, 12.5),
		Color = Color3.fromRGB(200, 20, 50),
		GlowColor = Color3.fromRGB(255, 70, 90),
		AccentColor = Color3.fromRGB(20, 20, 26),
		ShellAsset = 119781525088819,
		ShellScale = 1.25,
	},
	Prism = {
		Id = "Prism",
		Name = "Призма",
		Order = 3,
		Design = "Hypercar",
		Seats = 2,
		MaxSpeed = 125,
		ReverseSpeed = 30,
		Acceleration = 85,
		TurnSpeed = 2.0,
		HoverHeight = 0.8,
		Size = Vector3.new(7.8, 2, 12),
		Color = Color3.fromRGB(232, 234, 242),
		GlowColor = Color3.fromRGB(150, 80, 255),
		AccentColor = Color3.fromRGB(14, 14, 20),
		ShellAsset = 140640410532428,
		ShellScale = 1.3,
	},
	Orbit = {
		Id = "Orbit",
		Name = "Орбита",
		Order = 4,
		Design = "Roadster",
		Seats = 2,
		MaxSpeed = 115,
		ReverseSpeed = 30,
		Acceleration = 80,
		TurnSpeed = 2.3,
		HoverHeight = 0.8,
		Size = Vector3.new(7.2, 2, 12),
		Color = Color3.fromRGB(200, 204, 214),
		GlowColor = Color3.fromRGB(200, 230, 255),
		AccentColor = Color3.fromRGB(14, 14, 20),
		ShellAsset = 86566532341843,
		ShellScale = 1.4,
	},
	Transporter = {
		Id = "Transporter",
		Name = "Транспортник",
		Order = 5,
		Design = "Transporter",
		Seats = 4,
		MaxSpeed = 70,
		ReverseSpeed = 25,
		Acceleration = 45,
		TurnSpeed = 1.9,
		HoverHeight = 0.8,
		Size = Vector3.new(6.5, 4, 11.5),
		Color = Color3.fromRGB(28, 32, 48),
		GlowColor = Color3.fromRGB(0, 255, 200),
		AccentColor = Color3.fromRGB(255, 190, 40),
		ShellAsset = 139313519205735,
		ShellScale = 1.6,
	},
} :: { [string]: VehicleKind }

Config.VehicleIdleDespawn = 60 -- пустая машина исчезает через столько секунд
Config.VehicleFlipCooldown = 3 -- секунд между реактивными прыжками
Config.NitroDuration = 3
Config.NitroCooldown = 10
Config.NitroMultiplier = 1.6

-- Цвета неонового тюнинга машин
Config.CarColors = {
	Color3.fromRGB(0, 255, 200),
	Color3.fromRGB(255, 40, 120),
	Color3.fromRGB(150, 80, 255),
	Color3.fromRGB(60, 140, 255),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(255, 255, 255),
}

-- Побег: отряд на машинах уходит по трассе от стены вируса
Config.Escape = {
	Length = 2400, -- длина трассы в студах
	Vehicle = "Transporter", -- машина отряда (до 4 человек в одной)
	WallDelay = 10, -- секунд форы, прежде чем стена вируса двинется
	WallSpeed = 36, -- начальная скорость стены
	WallAcceleration = 0.8, -- на сколько стена ускоряется каждую секунду
	WallMaxSpeed = 62, -- быстрее стена не бывает (Транспортник — до 70)
	EnemyAhead = 320, -- враги у обочин появляются, когда отряд в стольких студах от них
	RewardMultiplier = 1.2, -- награда за побег относительно сюжетной главы
}

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

-- Скины — ордены борцов с Искажением (история — docs/Saga.md). Платные — это Game Pass:
-- Id из Creator Hub (0 — ещё не создан), сервер ставит атрибут "Pass_Skin_<Key>".
-- Pieces — детальные части брони, сгенерированные в Studio (ассеты в инвентаре владельца):
-- Attach — к какой части тела крепится, Fit — длинная сторона детали относительно длинной стороны
-- этой части тела, Offset — сдвиг в размерах части тела (0, 0.1, 0 — на 10% её высоты вверх),
-- Turn — поворот в градусах.
-- Effect — что строится кодом: "Visor" (полоса-визор и полоса на груди), "Glitch" (глитч-искры),
-- "Halo" (кольцо над головой), "Stars" (звёзды вокруг), "Horizon" (огненное кольцо за спиной),
-- "Rage" (чёрно-красное пламя, искры и горящие глаза).
-- Wrap = true — Fit считается по ширине части тела: наручи и ботинки обхватывают руку/ногу любой толщины.
export type SkinPiece = { Asset: number, Attach: string, Fit: number, Wrap: boolean?, Offset: Vector3?, Turn: Vector3? }
export type Skin = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Price: number, -- 0 — бесплатно
	Body: Color3, -- цвет рук, ног и тела
	Material: Enum.Material,
	Accent: Color3, -- цвет свечения
	Pieces: { SkinPiece },
	Effect: string?,
}

Config.Skins = {
	{
		Key = "Corrector",
		Id = 0,
		Name = "Корректор",
		Description = "Броня новичка Штаба: тёмный костюм и зелёная полоса кода",
		Price = 0,
		Body = Color3.fromRGB(40, 44, 52),
		Material = Enum.Material.SmoothPlastic,
		Accent = Color3.fromRGB(0, 255, 140),
		Pieces = {
			{ Asset = 72595263215233, Attach = "Head", Fit = 1.45, Offset = Vector3.new(0, 0.12, 0) },
			{ Asset = 103311878139308, Attach = "UpperTorso", Fit = 1.45, Offset = Vector3.new(0, 0.05, 0) },
		},
		Effect = "Visor",
	},
	{
		Key = "Hunter",
		Id = 0,
		Name = "Охотник за сбоями",
		Description = "Разведчик: чёрная тактическая броня с голубыми линиями, вокруг искрит глитч",
		Price = 149,
		Body = Color3.fromRGB(44, 47, 56),
		Material = Enum.Material.Fabric,
		Accent = Color3.fromRGB(0, 230, 255),
		Pieces = {
			{ Asset = 101409906455656, Attach = "Head", Fit = 1.45, Offset = Vector3.new(0, 0.12, 0) },
			{ Asset = 92296990915532, Attach = "UpperTorso", Fit = 1.45, Offset = Vector3.new(0, 0.05, 0) },
			{ Asset = 73055183611485, Attach = "LeftLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 73055183611485, Attach = "RightLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 121858509574330, Attach = "LeftLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
			{ Asset = 121858509574330, Attach = "RightLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
		},
		Effect = "Glitch",
	},
	{
		Key = "Guardian",
		Id = 0,
		Name = "Страж Протокола",
		Description = "Хранитель Кристалла: бело-золотая тяжёлая броня и кольцо из кода над головой",
		Price = 249,
		Body = Color3.fromRGB(236, 232, 222),
		Material = Enum.Material.SmoothPlastic,
		Accent = Color3.fromRGB(255, 200, 70),
		Pieces = {
			{ Asset = 123663528462870, Attach = "Head", Fit = 1.5, Offset = Vector3.new(0, 0.15, 0) },
			{ Asset = 81487080630836, Attach = "UpperTorso", Fit = 1.6, Offset = Vector3.new(0, 0.1, 0) },
			{ Asset = 119258755611818, Attach = "LeftLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 119258755611818, Attach = "RightLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 111099078951892, Attach = "LeftLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
			{ Asset = 111099078951892, Attach = "RightLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
		},
		Effect = "Halo",
	},
	{
		Key = "Wanderer",
		Id = 0,
		Name = "Звёздный странник",
		Description = "Пришелец из космоса за краем Сети: скафандр с туманностью, ранец и звёзды вокруг",
		Price = 399,
		Body = Color3.fromRGB(30, 34, 80),
		Material = Enum.Material.SmoothPlastic,
		Accent = Color3.fromRGB(170, 120, 255),
		Pieces = {
			{ Asset = 128011042274358, Attach = "Head", Fit = 1.6, Offset = Vector3.new(0, 0.15, 0) },
			{ Asset = 121103953746782, Attach = "UpperTorso", Fit = 1.5, Offset = Vector3.new(0, 0.05, 0) },
			{ Asset = 73692264592335, Attach = "UpperTorso", Fit = 1.1, Offset = Vector3.new(0, 0, 0.9) },
			{ Asset = 113375150771630, Attach = "LeftLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 113375150771630, Attach = "RightLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 74047916579618, Attach = "LeftLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
			{ Asset = 74047916579618, Attach = "RightLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
		},
		Effect = "Stars",
	},
	{
		Key = "Horizon",
		Id = 0,
		Name = "Горизонт событий",
		Description = "Вернулся из пустоты Ядра: обсидиановая броня, за спиной вращается огненное кольцо",
		Price = 599,
		Body = Color3.fromRGB(14, 12, 14),
		Material = Enum.Material.Glass,
		Accent = Color3.fromRGB(255, 80, 10), -- неон в свечении светлеет, поэтому берём темнее

		Pieces = {
			{ Asset = 74165910550599, Attach = "Head", Fit = 1.45, Offset = Vector3.new(0, 0.12, 0) },
			{ Asset = 128652350667306, Attach = "UpperTorso", Fit = 1.5, Offset = Vector3.new(0, 0.05, 0) },
			{ Asset = 89332774121080, Attach = "LeftLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 89332774121080, Attach = "RightLowerArm", Fit = 1.2, Wrap = true },
			{ Asset = 95747768995932, Attach = "LeftLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
			{ Asset = 95747768995932, Attach = "RightLowerLeg", Fit = 1.15, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
		},
		Effect = "Horizon",
	},
	{
		Key = "Berserker",
		Id = 0,
		Name = "Берсерк Ядра",
		Description = "Поглотил осколок Нуля: рогатый шлем, шипастая броня и чёрно-красное пламя",
		Price = 799,
		Body = Color3.fromRGB(26, 22, 24),
		Material = Enum.Material.Metal,
		Accent = Color3.fromRGB(255, 20, 30),
		Pieces = {
			{ Asset = 78867892221995, Attach = "Head", Fit = 1.6, Offset = Vector3.new(0, 0.15, 0) },
			{ Asset = 81163601190150, Attach = "UpperTorso", Fit = 1.75, Offset = Vector3.new(0, 0.1, 0) },
			{ Asset = 85961292843497, Attach = "LeftLowerArm", Fit = 1.3, Wrap = true },
			{ Asset = 85961292843497, Attach = "RightLowerArm", Fit = 1.3, Wrap = true },
			{ Asset = 99796752825258, Attach = "LeftLowerLeg", Fit = 1.2, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
			{ Asset = 99796752825258, Attach = "RightLowerLeg", Fit = 1.2, Wrap = true, Offset = Vector3.new(0, -0.2, 0) },
		},
		Effect = "Rage",
	},
} :: { Skin }

function Config.getSkin(key: string?): Skin?
	for _, skin in Config.Skins do
		if skin.Key == key then
			return skin
		end
	end
	return nil
end

-- Способности героя (у всех одинаковые, работают в Миссии; урон считает сервер — AbilityService):
--   Импульс (Q) — волна кода вокруг героя: урон и отбрасывание врагов рядом;
--   Рывок (F) — быстрый бросок вперёд (сквозь толпу, на полсекунды неуязвим);
--   Перезапись (G) — ультимейт: заряжается убийствами, стирает врагов вокруг огромной вспышкой.
Config.Abilities = {
	Pulse = { Key = "Q", Name = "Импульс", Cooldown = 8, Radius = 16, Damage = 60, Knockback = 70 },
	Dash = { Key = "F", Name = "Рывок", Cooldown = 5, Speed = 110, Duration = 0.25, Shield = 0.5 },
	Ultimate = { Key = "G", Name = "Перезапись", Charge = 12, Radius = 45, Damage = 400 }, -- Charge — убийств до готовности
}

-- В Studio считаем, что все бусты куплены, а разовые выдаются бесплатно:
-- так их можно проверить до публикации. В опубликованной игре это не работает.
Config.StudioOwnsAllPasses = true

Config.SpeedBoostMultiplier = 1.5

-- Награда за победу над Нулём (финал в мире «Ядро») во столько раз больше обычной
Config.BossRewardMultiplier = 3

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
