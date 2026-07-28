--!strict
-- Gathers what a game needs in order to start:
-- players, their data, game configuration
-- then seals that and hands it over through OnStart
--
-- Only an intermediary: the lobby can carry any data
-- The choice of data and payload types belongs to the consumer
local Signal = require("../Packages/SignalPlus")

export type RosterEntry<PlayerData = unknown> = {
	player: Player,
	data: PlayerData,
}
-- Members in join order
export type Roster<PlayerData = unknown> = { RosterEntry<PlayerData> }
type Prototype<PlayerData = unknown, Data = unknown> = {
	GetData: (self: Lobby<PlayerData, Data>) -> Data,
	SetData: (self: Lobby<PlayerData, Data>, data: Data) -> (),
	-- adds or updates a player; succeeds if the data was set (cannot update a locked lobby)
	-- fails when the lobby is already started or destroyed, or full for a new player
	AddPlayer: (self: Lobby<PlayerData, Data>, player: Player, data: PlayerData) -> boolean,
	-- returns success and playerData if player were found; no-op once started
	RemovePlayer: (self: Lobby<PlayerData, Data>, player: Player) -> (boolean, PlayerData?),
	HasPlayer: (self: Lobby<PlayerData, Data>, player: Player) -> boolean,
	-- returns success and playerData if player is found
	GetPlayerData: (self: Lobby<PlayerData, Data>, player: Player) -> (boolean, PlayerData?),
	GetPlayerCount: (self: Lobby<PlayerData, Data>) -> number,
	GetIsFull: (self: Lobby<PlayerData, Data>) -> boolean,
	GetIsEmpty: (self: Lobby<PlayerData, Data>) -> boolean,
	-- Shallow snapshot: entries are copies, payloads are shared.
	GetRoster: (self: Lobby<PlayerData, Data>) -> Roster<PlayerData>,
	-- Seals membership, then fires OnStart
	Start: (self: Lobby<PlayerData, Data>) -> (),

	Destroy: (self: Lobby<PlayerData, Data>) -> (),
}
type Instance<PlayerData = unknown, Data = unknown> = {
	MaxPlayers: number,

	Data: Data,
	Roster: Roster<PlayerData>,
	Started: boolean,
	Destroyed: boolean,

	OnDataChanged: Signal.Signal<Data>,
	OnPlayerAdded: Signal.Signal<Player, PlayerData>,
	-- Not fired by Destroy()
	OnPlayerRemoved: Signal.Signal<Player, PlayerData>,

	-- change event: fires the new GetIsEmpty() — false on the first join, true on the last leave
	OnEmpty: Signal.Signal<boolean>,
	-- change event: fires the new GetIsFull()
	OnFull: Signal.Signal<boolean>,

	OnStart: Signal.Signal<Roster<PlayerData>, Data>,
	-- Destroyed without ever starting.
	OnCancelled: Signal.Signal<>,

	OnDestroyed: Signal.Signal<>,
}
export type Lobby<PlayerData = unknown, Data = unknown> = Instance<PlayerData, Data> & Prototype<PlayerData, Data>

-- type-checking helper types
-- One shared prototype serves every instantiation, so it cannot be checked
-- against `Prototype<PlayerData, Data>` for all payload types — Luau has no
-- rank-2 polymorphism. Brands stand in for the real payloads: with `unknown`
-- the implementation could forge or read them, while nothing ordinary matches
-- a brand. The contract is defined first; the implementation is checked against it.
type CheckedData = { __lobbyDataBrand: "CheckedData" }
type CheckedPlayerData = { __lobbyPlayerDataBrand: "CheckedPlayerData" }
type CheckedLobby = Lobby<CheckedPlayerData, CheckedData>

local Constructor = {}

local function findPlayer(roster: Roster<CheckedPlayerData>, player: Player): number?
	for index, entry in roster do
		if entry.player == player then
			return index
		end
	end

	return nil
end

local Proto: Prototype<CheckedPlayerData, CheckedData> = {
	GetData = function(self: CheckedLobby): CheckedData
		return self.Data
	end,

	SetData = function(self: CheckedLobby, data: CheckedData)
		if self.Destroyed or self.Started then
			return
		end

		self.Data = data
		self.OnDataChanged:Fire(data)
	end,

	AddPlayer = function(self: CheckedLobby, player: Player, data: CheckedPlayerData): boolean
		if self.Destroyed or self.Started then
			return false
		end

		local playerIndex = findPlayer(self.Roster, player)
		if playerIndex then
			self.Roster[playerIndex].data = data
			return true
		end

		if self:GetIsFull() then
			return false
		end

		local wasEmpty = self:GetIsEmpty()

		table.insert(self.Roster, { player = player, data = data })
		self.OnPlayerAdded:Fire(player, data)

		if wasEmpty then
			self.OnEmpty:Fire(false)
		end
		if self:GetIsFull() then
			self.OnFull:Fire(true)
		end

		return true
	end,

	RemovePlayer = function(self: CheckedLobby, player: Player): (boolean, CheckedPlayerData?)
		if self.Destroyed or self.Started then
			return false, nil
		end

		local found = findPlayer(self.Roster, player)

		if not found then
			return false, nil
		end

		local wasFull = self:GetIsFull()

		local entry = table.remove(self.Roster, found) :: RosterEntry<CheckedPlayerData>
		self.OnPlayerRemoved:Fire(entry.player, entry.data)

		if wasFull then
			self.OnFull:Fire(false)
		end
		if self:GetIsEmpty() then
			self.OnEmpty:Fire(true)
		end

		return true, entry.data
	end,

	HasPlayer = function(self: CheckedLobby, player: Player): boolean
		return findPlayer(self.Roster, player) ~= nil
	end,

	GetPlayerData = function(self: CheckedLobby, player: Player): (boolean, CheckedPlayerData?)
		local found = findPlayer(self.Roster, player)

		if not found then
			return false, nil
		end

		return true, self.Roster[found].data
	end,

	GetPlayerCount = function(self: CheckedLobby): number
		return #self.Roster
	end,

	GetIsFull = function(self: CheckedLobby): boolean
		return #self.Roster >= self.MaxPlayers
	end,

	GetIsEmpty = function(self: CheckedLobby): boolean
		return #self.Roster == 0
	end,

	GetRoster = function(self: CheckedLobby): Roster<CheckedPlayerData>
		local roster: Roster<CheckedPlayerData> = {}

		for _, entry in self.Roster do
			table.insert(roster, table.clone(entry))
		end

		return roster
	end,

	Start = function(self: CheckedLobby)
		if self.Destroyed or self.Started then
			return
		end

		self.Started = true
		self.OnStart:Fire(self:GetRoster(), self:GetData())
	end,

	Destroy = function(self: CheckedLobby)
		if self.Destroyed then
			return
		end

		self.Destroyed = true

		if not self.Started then
			self.OnCancelled:Fire()
		end
		self.OnDestroyed:Fire()

		-- allows already fired signals to finish executing
		task.defer(function()
			self.OnDataChanged:DisconnectAll()
			self.OnPlayerAdded:DisconnectAll()
			self.OnPlayerRemoved:DisconnectAll()
			self.OnEmpty:DisconnectAll()
			self.OnFull:DisconnectAll()
			self.OnStart:DisconnectAll()
			self.OnCancelled:DisconnectAll()
			self.OnDestroyed:DisconnectAll()
		end)

		table.clear(self.Roster)
	end,
}
local ProtoMeta = { __index = Proto }

function Constructor.new<PlayerData, Data>(maxPlayers: number, data: Data): Lobby<PlayerData, Data>
	local instance: Instance<CheckedPlayerData, Data> = {
		MaxPlayers = maxPlayers,
		Data = data,
		Roster = {},
		Started = false,
		Destroyed = false,
		OnDataChanged = Signal() :: Signal.Signal<Data>,
		OnPlayerAdded = Signal() :: Signal.Signal<Player, CheckedPlayerData>,
		OnPlayerRemoved = Signal() :: Signal.Signal<Player, CheckedPlayerData>,
		OnEmpty = Signal() :: Signal.Signal<boolean>,
		OnFull = Signal() :: Signal.Signal<boolean>,
		OnStart = Signal() :: Signal.Signal<Roster<CheckedPlayerData>, Data>,
		OnCancelled = Signal() :: Signal.Signal<>,
		OnDestroyed = Signal() :: Signal.Signal<>,
	}

	local self = setmetatable(instance, ProtoMeta)

	return (self :: any) :: Lobby<PlayerData, Data>
end

return Constructor
