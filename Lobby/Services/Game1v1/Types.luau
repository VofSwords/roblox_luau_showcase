--!strict
local LobbyClass = require("../../Classes/Lobby")
local Signal = require("../../Packages/SignalPlus")

export type Place = Model & {
	Blue: Seat,
	Red: Seat,
	Status: BillboardGui & {
		Text: TextLabel,
	},
}

export type Spot = {
	pos: CFrame,
	lobby: Lobby?,
}

export type GameSeat = "Red" | "Blue"

export type LobbyData = {
	place: Place,
	seats: { [GameSeat]: Seat },
	game: Game,
	spot: Spot,
}

export type PlayerData = {
	seat: GameSeat,
}

export type Game = {
	Place: Place,
	Started: boolean,
	Destroyed: boolean,
	OnGameEnd: Signal.Signal<>,
	Play: (self: Game, redPlayer: Player, bluePlayer: Player) -> (),
	Destroy: (self: Game) -> (),
}

export type Lobby = LobbyClass.Lobby<PlayerData, LobbyData>

return {}
