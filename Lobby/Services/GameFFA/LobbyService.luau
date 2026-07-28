--!strict
local PlayersS = game:GetService("Players")

local LobbyClass = require("../../Classes/Lobby")

type FullPlayer = {
	player: Player,
	char: Model,
	hum: Humanoid,
	hrp: BasePart,
}

export type GameFolder = Folder & {
	ForceField: Folder,
	Pad: Part & {
		Leave: Attachment & { Prompt: ProximityPrompt },
		Status: BillboardGui & { Text: TextLabel },
		Capacity: BillboardGui & { Text: TextLabel },
	},
}
type PlayerConnections = {
	died: RBXScriptConnection,
	characterRemoving: RBXScriptConnection,
}
export type Lobby = LobbyClass.Lobby<PlayerConnections, nil>

local MATCH_SECONDS = 5

local gameFolder: GameFolder
local exitPart: BasePart

local LobbyService = {
	lobby = nil :: Lobby?,
	timer = nil :: thread?,
}

local function getFullPlayer(player: Player): FullPlayer?
	local char = player.Character
	if not char then
		return nil
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil
	end

	return {
		player = player,
		char = char,
		hum = humanoid,
		hrp = rootPart,
	}
end

local function teleportPlayer(player: FullPlayer, part: BasePart)
	local partCFrame = part.CFrame
	local yOffset = (part.Size.Y / 2) + (player.hrp.Size.Y / 2) + player.hum.HipHeight
	local targetCFrame = partCFrame * CFrame.new(0, yOffset, 0)

	task.spawn(function()
		player.player:RequestStreamAroundAsync(targetCFrame.Position)
		player.hrp.CFrame = targetCFrame
	end)
end

function LobbyService.updateStatus(status: string)
	gameFolder.Pad.Status.Text.Text = status
end

function LobbyService.setUIVisible(visible: boolean)
	gameFolder.Pad.Leave.Prompt.Enabled = visible
	gameFolder.Pad.Capacity.Enabled = visible
end

function LobbyService.updateCount()
	local lobby = LobbyService.lobby
	if not lobby then
		return
	end

	gameFolder.Pad.Capacity.Text.Text = `Players: {lobby:GetPlayerCount()}/{lobby.MaxPlayers}`
end

function LobbyService.clearConnections(connections: PlayerConnections)
	connections.died:Disconnect()
	connections.characterRemoving:Disconnect()
end

function LobbyService.handleForceFieldTouch(hit: BasePart)
	local lobby = LobbyService.lobby
	if not lobby then
		return
	end
	if not (hit and hit.Parent and hit.Parent:IsA("Model")) then
		return
	end
	local player = PlayersS:GetPlayerFromCharacter(hit.Parent)
	if not player then
		return
	end

	if lobby:HasPlayer(player) then
		return
	end

	local fullPlayer = getFullPlayer(player)
	if not fullPlayer then
		return
	end

	local connections: PlayerConnections = {
		died = fullPlayer.hum.Died:Once(function()
			LobbyService.removePlayer(player)
		end),
		characterRemoving = player.CharacterRemoving:Once(function()
			LobbyService.removePlayer(player)
		end),
	}

	if not lobby:AddPlayer(player, connections) then
		LobbyService.clearConnections(connections)
		return
	end
end

function LobbyService.removePlayer(player: Player)
	if not LobbyService.lobby then
		return
	end

	LobbyService.lobby:RemovePlayer(player)
end

function LobbyService.handlePlayerAdded(player: Player)
	LobbyService.updateCount()

	local fullPlayer = getFullPlayer(player)
	if not fullPlayer then
		return
	end
	teleportPlayer(fullPlayer, gameFolder.Pad)
end

function LobbyService.handlePlayerRemoved(player: Player, connections: PlayerConnections)
	LobbyService.clearConnections(connections)
	LobbyService.updateCount()

	local fullPlayer = getFullPlayer(player)
	if not fullPlayer then
		return
	end
	teleportPlayer(fullPlayer, exitPart)
end

function LobbyService.clearCountdown()
	LobbyService.updateStatus("Waiting for players")

	if not LobbyService.timer then
		return
	end
	task.cancel(LobbyService.timer)
	LobbyService.timer = nil
end

function LobbyService.startCountdown()
	if LobbyService.timer then
		return
	end
	local lobby = LobbyService.lobby
	if not lobby then
		return
	end

	LobbyService.timer = task.spawn(function()
		for i = 20, 1, -1 do
			LobbyService.updateStatus(`Starting in {i}`)
			task.wait(1)
		end

		LobbyService.timer = nil

		if LobbyService.lobby == lobby then
			lobby:Start()
		end
	end)
end

function LobbyService.handleEmpty(isEmpty: boolean)
	if isEmpty then
		LobbyService.clearCountdown()
		return
	end

	LobbyService.startCountdown()
end

function LobbyService.releaseRoster(roster: LobbyClass.Roster<PlayerConnections>)
	for _, entry in roster do
		pcall(function()
			LobbyService.handlePlayerRemoved(entry.player, entry.data)
		end)
	end
end

function LobbyService.runMatch()
	LobbyService.setUIVisible(false)
	LobbyService.updateStatus("Game in progress!")
	task.wait(MATCH_SECONDS)
end

function LobbyService.recreateLobby()
	local lobby = LobbyClass.new<<PlayerConnections, nil>>(16)
	LobbyService.lobby = lobby
	lobby.OnPlayerAdded:Connect(LobbyService.handlePlayerAdded)
	lobby.OnPlayerRemoved:Connect(LobbyService.handlePlayerRemoved)
	lobby.OnEmpty:Connect(LobbyService.handleEmpty)

	LobbyService.setUIVisible(true)
	LobbyService.updateCount()
	LobbyService.clearCountdown()

	lobby.OnStart:Connect(function(roster)
		lobby:Destroy()
		LobbyService.lobby = nil

		pcall(LobbyService.runMatch)

		LobbyService.releaseRoster(roster)
		LobbyService.recreateLobby()
	end)
end

function LobbyService.init(folder: GameFolder, exit: BasePart)
	gameFolder = folder
	exitPart = exit

	local leavePrompt = gameFolder.Pad.Leave.Prompt
	leavePrompt.Triggered:Connect(LobbyService.removePlayer)
	PlayersS.PlayerRemoving:Connect(LobbyService.removePlayer)

	LobbyService.recreateLobby()

	for _, child in gameFolder.ForceField:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end

		child.Touched:Connect(LobbyService.handleForceFieldTouch)
	end
end

return LobbyService
