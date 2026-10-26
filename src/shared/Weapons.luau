--!strict
-- Оружие: характеристики четырёх стволов первой версии.
-- Их читают и сервер (проверка выстрелов), и клиент (стрельба и интерфейс).

export type Weapon = {
	Id: string,
	Name: string,
	Slot: number, -- клавиша 1–4
	Auto: boolean, -- стреляет, пока зажата кнопка
	Damage: number, -- урон одной пули
	Pellets: number, -- пуль за выстрел (у дробовика больше одной)
	Spread: number, -- разброс в градусах
	FireInterval: number, -- секунд между выстрелами
	MagSize: number?, -- nil — бесконечные патроны
	ReloadTime: number,
	Range: number, -- дальность в студах
	Pierce: number, -- сколько врагов пробивает одна пуля
	Color: Color3, -- цвет следа от выстрела
}

local Weapons = {}

Weapons.List = {
	{
		Id = "Pistol",
		Name = "Импульсный пистолет",
		Slot = 1,
		Auto = false,
		Damage = 25,
		Pellets = 1,
		Spread = 0.5,
		FireInterval = 0.25,
		MagSize = nil,
		ReloadTime = 0,
		Range = 250,
		Pierce = 1,
		Color = Color3.fromRGB(0, 255, 200),
	},
	{
		Id = "Rifle",
		Name = "Бластер-винтовка",
		Slot = 2,
		Auto = true,
		Damage = 14,
		Pellets = 1,
		Spread = 1.5,
		FireInterval = 0.1,
		MagSize = 30,
		ReloadTime = 2,
		Range = 300,
		Pierce = 1,
		Color = Color3.fromRGB(80, 200, 255),
	},
	{
		Id = "Shotgun",
		Name = "Дробовик-рассеиватель",
		Slot = 3,
		Auto = false,
		Damage = 10,
		Pellets = 8,
		Spread = 7,
		FireInterval = 0.8,
		MagSize = 6,
		ReloadTime = 2.5,
		Range = 60,
		Pierce = 1,
		Color = Color3.fromRGB(255, 200, 60),
	},
	{
		Id = "Railgun",
		Name = "Рейлган",
		Slot = 4,
		Auto = false,
		Damage = 100,
		Pellets = 1,
		Spread = 0,
		FireInterval = 1.4,
		MagSize = 4,
		ReloadTime = 3,
		Range = 600,
		Pierce = 5,
		Color = Color3.fromRGB(255, 40, 120),
	},
} :: { Weapon }

Weapons.Default = "Pistol"

function Weapons.get(id: string): Weapon?
	for _, weapon in Weapons.List do
		if weapon.Id == id then
			return weapon
		end
	end
	return nil
end

-- Случайное направление внутри конуса разброса вокруг direction
function Weapons.spread(direction: Vector3, degrees: number, random: Random): Vector3
	if degrees <= 0 then
		return direction.Unit
	end
	local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
	local roll = random:NextNumber() * math.pi * 2
	local frame = CFrame.lookAt(Vector3.zero, direction)
	return (frame * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

return Weapons
