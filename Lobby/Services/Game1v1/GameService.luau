--!strict
local Signal = require("../../Packages/SignalPlus")
local GameTypes = require("./Types")

local ROUND_SECONDS = 5

type JumpLock = {
	humanoid: Humanoid,
	useJumpPower: boolean,
	jumpPower: number,
}

local GameService = {}

function GameService.init() end

local function resolveHumanoid(player: Player, timeout: number): Humanoid?
	local deadline = os.clock() + timeout

	repeat
		if not player.Parent then
			return nil
		end

		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			return humanoid
		end

		task.wait()
	until os.clock() >= deadline

	return nil
end

local function lockJump(humanoid: Humanoid): JumpLock
	local lock: JumpLock = {
		humanoid = humanoid,
		useJumpPower = humanoid.UseJumpPower,
		jumpPower = humanoid.JumpPower,
	}

	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0

	return lock
end

local function unlockJump(lock: JumpLock)
	lock.humanoid.UseJumpPower = lock.useJumpPower
	lock.humanoid.JumpPower = lock.jumpPower
end

local function endOnVacancy(round: GameTypes.Game, seat: Seat)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if round.Destroyed or seat.Occupant then
			return
		end

		round:Destroy()
	end)
end

function GameService.createGame(place: GameTypes.Place): GameTypes.Game
	local locks: { JumpLock } = {}

	local newGame: GameTypes.Game = {
		Place = place,
		Started = false,
		Destroyed = false,
		OnGameEnd = Signal() :: Signal.Signal<>,

		Destroy = function(self: GameTypes.Game)
			if self.Destroyed then
				return
			end
			self.Destroyed = true

			for _, lock in locks do
				unlockJump(lock)
			end
			table.clear(locks)

			self.OnGameEnd:Fire()
			self.OnGameEnd:DisconnectAll()
		end,

		Play = function(self: GameTypes.Game, redPlayer: Player, bluePlayer: Player)
			if self.Started or self.Destroyed then
				return
			end
			self.Started = true

			local statusLabel = place.Status.Text

			local redSeat = place.Red
			local blueSeat = place.Blue

			local redHumanoid = resolveHumanoid(redPlayer, 5)
			local blueHumanoid = resolveHumanoid(bluePlayer, 5)

			if self.Destroyed then
				return
			end

			if not (redHumanoid and blueHumanoid) then
				self:Destroy()
				return
			end
			if not (redSeat.Occupant and blueSeat.Occupant) then
				self:Destroy()
				return
			end

			table.insert(locks, lockJump(redHumanoid))
			table.insert(locks, lockJump(blueHumanoid))

			endOnVacancy(self, redSeat)
			endOnVacancy(self, blueSeat)

			task.spawn(function()
				for i = ROUND_SECONDS, 1, -1 do
					if self.Destroyed then
						return
					end

					statusLabel.Text = `Time left: {i}`
					task.wait(1)
				end

				self:Destroy()
			end)
		end,
	}

	return newGame
end

return GameService
