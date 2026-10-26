--!strict
-- Платные бусты, которые видны только самому игроку:
-- «Ускорение» — второй прыжок в воздухе (скорость бега ставит сервер),
-- «Взгляд сквозь код» — подсветка врагов сквозь стены,
-- «Сканер вируса» — подсветка двойников.
-- Купленные бусты сервер отмечает атрибутами игрока "Pass_<Key>".

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local DOUBLE_JUMP_DELAY = 0.2 -- первый прыжок не должен сразу съесть второй

local GLITCH = Color3.fromRGB(255, 40, 120)
local SCANNER = Color3.fromRGB(255, 30, 60)

local player = Players.LocalPlayer

local function owns(key: string): boolean
	return player:GetAttribute(`Pass_{key}`) == true
end

-- Двойной прыжок
local humanoid: Humanoid? = nil
local airborne = false
local canDoubleJump = false
local leftGroundAt = 0

local function watchCharacter(character: Model)
	local current = character:WaitForChild("Humanoid") :: Humanoid
	humanoid = current
	airborne = false
	canDoubleJump = false
	current.StateChanged:Connect(function(_, state)
		if state == Enum.HumanoidStateType.Landed or state == Enum.HumanoidStateType.Running then
			airborne = false
			canDoubleJump = false
		elseif (state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall) and not airborne then
			airborne = true
			canDoubleJump = true
			leftGroundAt = os.clock()
		end
	end)
end

if player.Character then
	task.spawn(watchCharacter, player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

UserInputService.JumpRequest:Connect(function()
	local current = humanoid
	if not current or not owns("Speed") or not canDoubleJump then
		return
	end
	if os.clock() - leftGroundAt < DOUBLE_JUMP_DELAY then
		return
	end
	if current:GetState() ~= Enum.HumanoidStateType.Freefall then
		return
	end
	canDoubleJump = false
	current:ChangeState(Enum.HumanoidStateType.Jumping)
end)

-- Подсветка врагов сквозь стены. Двойника «Взгляд сквозь код» не выдаёт — для этого есть «Сканер вируса»,
-- он подсвечивает двойника красным.
local function addHighlight(enemy: Model, name: string, color: Color3)
	if enemy:FindFirstChild(name) then
		return
	end
	local h = Instance.new("Highlight")
	h.Name = name
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor = color
	h.FillTransparency = 0.6
	h.OutlineColor = color
	h.Parent = enemy
end

local function highlight(enemy: Instance)
	if not enemy:IsA("Model") then
		return
	end
	if enemy:GetAttribute("Doppelganger") then
		if owns("Scanner") then
			addHighlight(enemy, "ScannerHighlight", SCANNER)
		end
	elseif owns("XRay") then
		addHighlight(enemy, "XRayHighlight", GLITCH)
	end
end

local function highlightAll()
	for _, enemy in CollectionService:GetTagged("Enemy") do
		highlight(enemy)
	end
end

-- Значок [VIP] перед именем в чате
TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("Pass_VIP") == true then
		properties.PrefixText = `<font color="#FFBE28">[VIP]</font> {message.PrefixText}`
	end
	return properties
end

CollectionService:GetInstanceAddedSignal("Enemy"):Connect(highlight)
player:GetAttributeChangedSignal("Pass_XRay"):Connect(highlightAll)
player:GetAttributeChangedSignal("Pass_Scanner"):Connect(highlightAll)
highlightAll()
