# Установка «офиса ИИ-агентов» на Windows одной командой (PowerShell):
#   irm https://raw.githubusercontent.com/artempojda27-ux/-/main/agent-office/install-windows.ps1 | iex
# С AI Town: сначала  $env:AI_TOWN=1  , потом команда выше.
$ErrorActionPreference = "Stop"
$Dir = Join-Path $HOME "agent-office"
$Zip = "https://github.com/artempojda27-ux/-/archive/refs/heads/main.zip"

Write-Host "== 1/4 Скачиваю офис в $Dir =="
$Tmp = Join-Path $env:TEMP ("office-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
Invoke-WebRequest $Zip -OutFile (Join-Path $Tmp "office.zip")
Expand-Archive (Join-Path $Tmp "office.zip") -DestinationPath $Tmp
$Src = Join-Path (Get-ChildItem $Tmp -Directory | Select-Object -First 1).FullName "agent-office"
if (Test-Path (Join-Path $Dir "data")) {
  Write-Host "Офис уже есть: обновляю агентов, твои данные в data\ не трогаю"
  Remove-Item -Recurse -Force (Join-Path $Src "data")
}
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Copy-Item -Recurse -Force (Join-Path $Src "*") $Dir
Remove-Item -Recurse -Force $Tmp

Write-Host "== 2/4 Claude Code =="
if (Get-Command claude -ErrorAction SilentlyContinue) { Write-Host "Claude Code уже установлен" }
else { irm https://claude.ai/install.ps1 | iex }

Write-Host "== 3/4 Pixel Agents (пиксельный офис) =="
$Code = (Get-Command code -ErrorAction SilentlyContinue).Source
if (-not $Code) {
  $Guess = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"
  if (Test-Path $Guess) { $Code = $Guess }
}
if ($Code) { & $Code --install-extension pablodelucca.pixel-agents }
else { Write-Host "!! VS Code не найден. Поставь его с https://code.visualstudio.com и запусти команду ещё раз." }

if ($env:AI_TOWN) {
  Write-Host "== + AI Town =="
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Нужен git (git-scm.com)"; return }
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Write-Host "Нужен Node.js (nodejs.org)"; return }
  if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) { Write-Host "!! Поставь Ollama с ollama.com, потом: ollama pull llama3" }
  $Town = Join-Path $HOME "ai-town"
  if (-not (Test-Path $Town)) { git clone https://github.com/a16z-infra/ai-town.git $Town }
  Push-Location $Town; npm install; Pop-Location
  Write-Host "Запуск AI Town: cd ~\ai-town; npm run dev"
}

Write-Host "== 4/4 Открываю офис =="
if ($Code) { & $Code $Dir }
Write-Host ""
Write-Host "Готово. В VS Code внизу открой вкладку Pixel Agents -> + Agent."
Write-Host "В первый раз Claude попросит войти в аккаунт. Потом напиши:  /hunt кофейни Краков 10"
