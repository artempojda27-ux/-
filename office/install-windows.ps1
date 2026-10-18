# Установка «офиса ИИ-агентов» на Windows.
# Запуск в PowerShell:  powershell -ExecutionPolicy Bypass -File office\install-windows.ps1
#           с AI Town:  powershell -ExecutionPolicy Bypass -File office\install-windows.ps1 -AiTown
param([switch]$AiTown)

Write-Host "== 1/3 Claude Code =="
if (Get-Command claude -ErrorAction SilentlyContinue) {
  Write-Host "Claude Code уже установлен"
} else {
  irm https://claude.ai/install.ps1 | iex
}

Write-Host "== 2/3 Pixel Agents (пиксельный офис) =="
if (Get-Command code -ErrorAction SilentlyContinue) {
  code --install-extension pablodelucca.pixel-agents
  Write-Host "Готово: открой VS Code -> нижняя панель -> вкладка Pixel Agents."
} else {
  Write-Host "VS Code не найден. Поставь его с https://code.visualstudio.com и запусти скрипт снова."
  Write-Host "Или без VS Code: в папке проекта выполни  npx pixel-agents  и открой ссылку в браузере."
}

if ($AiTown) {
  Write-Host "== 3/3 AI Town =="
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Нужен git (git-scm.com)"; exit 1 }
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Write-Host "Нужен Node.js (nodejs.org)"; exit 1 }
  if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) { Write-Host "!! Поставь Ollama с ollama.com, потом: ollama pull llama3" }
  $dir = Join-Path $HOME "ai-town"
  if (-not (Test-Path $dir)) { git clone https://github.com/a16z-infra/ai-town.git $dir }
  Set-Location $dir; npm install
  Write-Host "Запуск: cd ~\ai-town; npm run dev   (первый раз попросит войти в Convex)"
} else {
  Write-Host "== 3/3 AI Town пропущен (добавь -AiTown, если нужен) =="
}

Write-Host ""
Write-Host "Команда агентов уже лежит в .claude\agents\. Открой эту папку в терминале, запусти 'claude' и введи /agents."
