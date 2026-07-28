--!strict
local PlayersS = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local LobbyClass = require("../../Classes/Lobby")
local GameService = require("./GameService")
local GameTypes = require("./Types")

type Place = GameTypes.Place
type GameSeat = GameTypes.GameSeat
type LobbyData = GameTypes.LobbyData
type PlayerData = GameTypes.PlayerData
type Lobby = GameTypes.Lobby
type Spot = GameTypes.Spot

local SPOT_SPACING = 8
local MAX_SPOTS = 1024

export type GameFolder = Folder & {
	PlaceTemplate: Place,
	CreateLobby: Part & { ProximityPrompt: ProximityPrompt },
}

local gameFolder: GameFolder
local placesFolder: Folder
local placeTemplate: Place
local placePositionStart: CFrame

local spots: { Spot } = {}
local LobbyService = {}

function LobbyService.getEmptySpot(): Spot?
	for _, spot in spots do
		if spot.lobby == nil then
			return spot
		end
	end

	if #spots >= MAX_SPOTS then
		return nil
	end

	local newSpot: Spot = {
		pos = placePositionStart * CFrame.new(SPOT_SPACING * #spots, 0, 0),
		lobby = nil,
	}

	table.insert(spots, newSpot)

	return newSpot
end

function LobbyService.parseRoster(roster: LobbyClass.Roster<PlayerData>)
	local res: { [GameTypes.GameSeat]: Player? } = {}

	for _, entry in roster do
		res[entry.data.seat] = entry.player
	end

	return res
end

function LobbyService.updateStatusText(lobby: Lobby)
	local isEmpty = lobby:GetIsEmpty()
	local statusLabel = lobby.Data.place.Status.Text
	local statusText = if isEmpty then "Idle" else "Waiting for players"
	statusLabel.Text = statusText
end

function LobbyService.getPlayerFromOccupant(occupant: Humanoid?): Player?
	if (not occupant) or not occupant.Parent or (not occupant.Parent:IsA("Model")) then
		return nil
	end

	return PlayersS:GetPlayerFromCharacter(occupant.Parent)
end

function LobbyService.updateRoster(lobby: Lobby)
	local oldRoster = LobbyService.parseRoster(lobby:GetRoster())
	local newRoster: { [GameSeat]: Player? } = {}
	local data = lobby:GetData()

	for seatName, seat in data.seats do
		local newPlayer = LobbyService.getPlayerFromOccupant(seat.Occupant)
		local oldPlayer = oldRoster[seatName]

		if newPlayer == oldPlayer then
			continue
		end

		if oldPlayer then
			lobby:RemovePlayer(oldPlayer)
		end

		newRoster[seatName] = newPlayer
	end

	for seatName, player in newRoster do
		lobby:AddPlayer(player, { seat = seatName })
	end
end

function LobbyService.handleSeat(seat: Seat, lobby: Lobby)
	return seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if lobby.Started or lobby.Destroyed then
			return
		end
		LobbyService.updateRoster(lobby)
	end)
end

function LobbyService.createLobby(): Lobby?
	local spot = LobbyService.getEmptySpot()
	if not spot then
		return nil
	end

	local place = placeTemplate:Clone()
	place:PivotTo(spot.pos)

	local newGame = GameService.createGame(place)

	local lobby = LobbyClass.new<<PlayerData, LobbyData>>(2, {
		place = place,
		seats = {
			Red = place.Red,
			Blue = place.Blue,
		},
		game = newGame,
		spot = spot,
	})
	spot.lobby = lobby

	lobby.OnEmpty:Connect(function()
		LobbyService.updateStatusText(lobby)
	end)
	LobbyService.updateStatusText(lobby)

	lobby.OnFull:Connect(function(isFull)
		if isFull then
			lobby:Start()
		end
	end)
	lobby.OnStart:Connect(function(roster)
		local parsedRoster = LobbyService.parseRoster(roster)
		local redPlayer = parsedRoster.Red
		local bluePlayer = parsedRoster.Blue

		if not (redPlayer and bluePlayer) then
			newGame:Destroy()
			return
		end

		local ok = pcall(newGame.Play, newGame, redPlayer, bluePlayer)
		if not ok then
			newGame:Destroy()
		end
	end)
	lobby.OnDestroyed:Connect(function()
		place:Destroy()
		spot.lobby = nil
	end)
	newGame.OnGameEnd:Connect(function()
		lobby:Destroy()
	end)

	LobbyService.handleSeat(place.Blue, lobby)
	LobbyService.handleSeat(place.Red, lobby)

	place.Parent = placesFolder

	return lobby
end

function LobbyService.init(folder: GameFolder)
	gameFolder = folder

	placesFolder = Instance.new("Folder")
	placesFolder.Name = "Places"
	placesFolder.Parent = gameFolder

	placeTemplate = folder.PlaceTemplate
	placePositionStart = placeTemplate:GetPivot()
	placeTemplate.Parent = ServerStorage

	folder.CreateLobby.ProximityPrompt.Triggered:Connect(function()
		LobbyService.createLobby()
	end)
end

return LobbyService
