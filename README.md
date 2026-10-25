# Игра в Roblox

Отдельный проект, не связан с офисом агентов.

## Устройство
Код игры пишется в файлах и переносится в Roblox Studio через [Rojo](https://rojo.space):
- `src/server` — серверные скрипты (ServerScriptService)
- `src/client` — клиентские скрипты (StarterPlayerScripts)
- `src/shared` — общие модули (ReplicatedStorage)

## Как открыть в Roblox Studio
1. Установи Roblox Studio и плагин Rojo.
2. В папке проекта: `rojo serve`.
3. В Studio в панели Rojo нажми Connect.

## Идея игры
«Искажение» — кооперативный шутер (без PvP) для 1–4 друзей с сюжетом по главам: команда
героев зачищает мир-симуляцию от вируса.
- Дизайн-документ: [docs/GDD.md](docs/GDD.md)
- Исследование рынка: [docs/research.md](docs/research.md)
