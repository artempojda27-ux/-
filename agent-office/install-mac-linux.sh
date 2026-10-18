#!/usr/bin/env bash
# Установка «офиса ИИ-агентов» на Mac / Linux одной командой:
#   curl -fsSL https://raw.githubusercontent.com/artempojda27-ux/-/main/agent-office/install-mac-linux.sh | bash
# С AI Town:
#   curl -fsSL https://raw.githubusercontent.com/artempojda27-ux/-/main/agent-office/install-mac-linux.sh | AI_TOWN=1 bash
set -e
DIR="$HOME/agent-office"
ZIP="https://github.com/artempojda27-ux/-/archive/refs/heads/main.zip"

echo "== 1/4 Скачиваю офис в $DIR =="
TMP="$(mktemp -d)"
curl -fsSL "$ZIP" -o "$TMP/office.zip"
unzip -q "$TMP/office.zip" -d "$TMP"
SRC="$(echo "$TMP"/*-main/agent-office)"
if [ -d "$DIR/data" ]; then
  echo "Офис уже есть: обновляю агентов, твои данные в data/ не трогаю"
  rm -rf "$SRC/data"
fi
mkdir -p "$DIR"
cp -R "$SRC"/. "$DIR"/
rm -rf "$TMP"

echo "== 2/4 Claude Code =="
if command -v claude >/dev/null 2>&1; then
  echo "Claude Code уже установлен"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo "== 3/4 Pixel Agents (пиксельный офис) =="
CODE="$(command -v code || true)"
[ -z "$CODE" ] && [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ] && CODE="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
if [ -n "$CODE" ]; then
  "$CODE" --install-extension pablodelucca.pixel-agents
else
  echo "!! VS Code не найден. Поставь его с https://code.visualstudio.com и запусти эту команду ещё раз."
fi

if [ -n "$AI_TOWN" ]; then
  echo "== + AI Town =="
  command -v git >/dev/null || { echo "Нужен git"; exit 1; }
  command -v npm >/dev/null || { echo "Нужен Node.js (nodejs.org)"; exit 1; }
  command -v ollama >/dev/null || echo "!! Поставь Ollama с ollama.com, потом: ollama pull llama3"
  [ -d "$HOME/ai-town" ] || git clone https://github.com/a16z-infra/ai-town.git "$HOME/ai-town"
  (cd "$HOME/ai-town" && npm install)
  echo "Запуск AI Town: cd ~/ai-town && npm run dev"
fi

echo "== 4/4 Открываю офис =="
if [ -n "$CODE" ]; then "$CODE" "$DIR"; fi
echo
echo "Готово. В VS Code внизу открой вкладку Pixel Agents → + Agent."
echo "В первый раз Claude попросит войти в аккаунт. Потом напиши:  /hunt кофейни Краков 10"
