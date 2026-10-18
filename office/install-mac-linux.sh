#!/usr/bin/env bash
# Установка «офиса ИИ-агентов» на Mac / Linux.
# Запуск:  bash office/install-mac-linux.sh            — Claude Code + Pixel Agents
#          bash office/install-mac-linux.sh --ai-town  — плюс AI Town
set -e

echo "== 1/3 Claude Code =="
if command -v claude >/dev/null 2>&1; then
  echo "Claude Code уже установлен: $(claude --version)"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo "== 2/3 Pixel Agents (пиксельный офис) =="
if command -v code >/dev/null 2>&1; then
  code --install-extension pablodelucca.pixel-agents
  echo "Готово: открой VS Code → нижняя панель → вкладка Pixel Agents."
else
  echo "VS Code не найден (или нет команды 'code')."
  echo "  Mac: открой VS Code → Cmd+Shift+P → 'Shell Command: Install code command in PATH', потом запусти скрипт снова."
  echo "  Или без VS Code: в папке проекта выполни  npx pixel-agents  и открой ссылку в браузере."
fi

if [ "$1" = "--ai-town" ]; then
  echo "== 3/3 AI Town =="
  command -v git >/dev/null || { echo "Нужен git"; exit 1; }
  command -v npm >/dev/null || { echo "Нужен Node.js (nodejs.org)"; exit 1; }
  command -v ollama >/dev/null || echo "!! Поставь Ollama с ollama.com, потом: ollama pull llama3"
  [ -d "$HOME/ai-town" ] || git clone https://github.com/a16z-infra/ai-town.git "$HOME/ai-town"
  cd "$HOME/ai-town" && npm install
  echo "Запуск: cd ~/ai-town && npm run dev   (первый раз попросит войти в Convex)"
else
  echo "== 3/3 AI Town пропущен (добавь --ai-town, если нужен) =="
fi

echo
echo "Команда агентов уже лежит в .claude/agents/. Открой эту папку в терминале, запусти 'claude' и введи /agents."
