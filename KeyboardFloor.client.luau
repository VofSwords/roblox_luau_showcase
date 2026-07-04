--!strict
--[[
Connected Discord-GitHub
Discord: @deno_fresh
Roblox: @zxcdead_ghoul
GitHub: @VofSwords
Demo: https://www.roblox.com/games/100237147546880/Keyboard-Floor-Demo
===========================================================================
DESCRIPTION:
Turns any Block part tagged "KeysFloor" into a large grid of pressable
keyboard keys – thousands of keys per floor without lagging the client

The part's surface is subdivided into spatial chunks that stream in/out
around the player. Key models are drawn from a shared object pool, and
per-chunk random seeds keep letters and colors stable across reloads.
Presses are detected with collision-group-filtered spatial queries
against the character's parts and animated with tweens
===========================================================================
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PlayersService = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Pure = Packages:WaitForChild("Pure")
local Player = PlayersService.LocalPlayer :: Player

local Tags = require(Packages:WaitForChild("Tags"))
local PureArray = require(Pure:WaitForChild("Array"))
local PureTable = require(Pure:WaitForChild("Table"))
local PureUtils = require(Pure:WaitForChild("Utils"))
local ColorSchemes = require(ReplicatedStorage:WaitForChild("ColorSchemes"))
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))
local SoundsRS = require(ReplicatedStorage:WaitForChild("Sounds"))

local BasicKey = ReplicatedStorage:WaitForChild("BasicKey")

-- ===========================================================================
-- CONSTANTS & TYPES
-- ===========================================================================
-- Maximum grid dimension of chunk, so 8 means maximum of 8x8
local MAX_CHUNK_DIMENSION = 8
-- Chunk unload debounce in seconds
local CHUNK_UNLOAD_TIME = 1
-- Distance to load chunks in studs
local CHUNK_LOAD_DISTANCE = 128
-- Sound throttle in seconds
local SOUND_THROTTLE = 0.03
-- Number of keys to preload on start
local KEYS_PRELOAD_AMOUNT = (MAX_CHUNK_DIMENSION ^ 2) * 64

export type KeyInstance = typeof(BasicKey)
export type KeyObj = {
	instance: KeyInstance,
	sound: Sound,
	label: TextLabel,
	color: BasePart,
	Trigger: BasePart,
	Body: BasePart,
	Base: BasePart,
	pressTween: Tween,
	releaseTween: Tween,
}

export type Chunk = {
	floor: KeysFloor,
	size: Vector2,
	position: Vector3,
	radius: number,
	randomSeed: number,
	isLoaded: boolean,
	outOfRangeSince: number?,
	instance: Model,
	Load: (self: Chunk) -> (),
	Unload: (self: Chunk) -> (),
	Update: (self: Chunk, anchorPoints: { CFrame }, now: number) -> (),
}

export type KeysFloor = {
	instance: Part,
	scale: number,
	colorScheme: ColorSchemes.ColorScheme,
	keyObj: KeyObj,
	keySize: Vector3,
	chunks: { Chunk },
	Destroy: (self: KeysFloor) -> (),
	GenerateChunks: (self: KeysFloor) -> (),
	Update: (self: KeysFloor, anchorPoints: { CFrame }, now: number) -> (),
}

local pressTweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local releaseTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local QueryKeysOverlapParams = OverlapParams.new()
QueryKeysOverlapParams.CollisionGroup = Constants.CollisionGroups.QueryKeyTriggers

-- ===========================================================================
-- KEY POOL
-- ===========================================================================
local KeyPool = {
	-- List of keys that are not in use
	freeKeys = {} :: { KeyObj },
	-- List of all keys
	allKeys = {} :: { KeyObj },
	-- List of keys that are pressed
	boundingKeys = {} :: { KeyObj },
	-- Timer to throttle the sound of keys
	soundTimer = 0,
}

function KeyPool.parseKey(key: KeyInstance): KeyObj
	local sound = key.Sound.Value
	local label = key.Label.Value
	local color = key.Color.Value
	return {
		instance = key,
		sound = sound,
		label = label,
		color = color,
		Trigger = key.Trigger,
		Body = key.Body,
		Base = key.Base,
	} :: KeyObj
end

-- Sets up the key's visual state and reconstructs its tweens dynamically.
-- This must be called after the key is scaled, so that the offset math uses the updated dimensions.
function KeyPool.setupKey(key: KeyObj, random: Random, colorScheme: ColorSchemes.ColorScheme): KeyObj
	local originalCFrame = key.Body.CFrame
	local keyPressCFrameOffset = CFrame.new(0, 0.16 - key.Body.Size.Y, 0)
	key.label.Text = string.char(random:NextInteger(65, 90))
	key.color.Color = colorScheme.get(random:NextInteger(1, colorScheme.total))

	key.pressTween = TweenService:Create(key.Body, pressTweenInfo, { CFrame = originalCFrame * keyPressCFrameOffset })
	key.releaseTween = TweenService:Create(key.Body, releaseTweenInfo, { CFrame = originalCFrame })
	key.Body.Transparency = 0

	return key
end

function KeyPool.getKeys(amount: number): { KeyObj }
	-- Draws keys from a pre-instantiated pool to prevent CPU spikes from Instance.new() during gameplay.
	-- If the pool runs dry, it dynamically instantiates new keys.
	local intAmount = math.floor(math.abs(amount))
	local keys = table.create(intAmount) :: { KeyObj }
	local freeKeysAvailable = #KeyPool.freeKeys
	local remainingFreeKeys = freeKeysAvailable - math.min(intAmount, freeKeysAvailable)

	-- Take from pool
	while freeKeysAvailable > remainingFreeKeys do
		-- fill from the end
		keys[intAmount] = KeyPool.freeKeys[freeKeysAvailable]
		KeyPool.freeKeys[freeKeysAvailable] = nil
		freeKeysAvailable -= 1
		intAmount -= 1
	end

	-- Create new keys
	local allKeysNumber = #KeyPool.allKeys
	while intAmount ~= 0 do
		allKeysNumber += 1
		local key = KeyPool.parseKey(BasicKey:Clone())
		-- keys are named by their index so overlap queries can resolve
		-- a hit part back to its KeyObj without a reverse lookup table
		key.instance.Name = tostring(allKeysNumber)
		keys[intAmount] = key
		KeyPool.allKeys[allKeysNumber] = key
		intAmount -= 1
	end

	return keys
end

function KeyPool.releaseKeyToPool(keyIndex: number)
	local key = KeyPool.allKeys[keyIndex]
	if not key then
		return
	end

	-- Cleanup
	if key.pressTween and key.pressTween.PlaybackState == Enum.PlaybackState.Playing then
		key.pressTween:Cancel()
	end
	if key.releaseTween and key.releaseTween.PlaybackState == Enum.PlaybackState.Playing then
		key.releaseTween:Cancel()
	end

	if key.sound and key.sound.Playing then
		key.sound:Stop()
	end

	-- Drop from the pressed list
	local boundingIndex = table.find(KeyPool.boundingKeys, key)
	if boundingIndex then
		table.remove(KeyPool.boundingKeys, boundingIndex)
	end

	key.instance.Parent = nil
	table.insert(KeyPool.freeKeys, key)
end

function KeyPool.playKeySound(key: KeyObj)
	if (not key.sound.Playing) and (KeyPool.soundTimer <= 0) then
		KeyPool.soundTimer = SOUND_THROTTLE
		local soundParams = SoundsRS.GetSound()
		key.sound.SoundId = soundParams.soundId
		key.sound.TimePosition = soundParams.timePosition
		key.sound.Volume = soundParams.volume
		key.sound.PlaybackSpeed = soundParams.playbackSpeed
		key.sound:Play()
	end
end

function KeyPool.releaseKey(key: KeyObj)
	-- release should only play after press has completed
	if key.pressTween.PlaybackState ~= Enum.PlaybackState.Playing then
		key.releaseTween:Play()
	end
end

function KeyPool.pressKey(key: KeyObj)
	key.pressTween:Play()
	KeyPool.playKeySound(key)
	-- since release should only play after press has completed
	-- if press tween completes, and key is no longer in the bounding keys, then release it
	task.defer(function()
		-- If the press was cancelled (key returned to the pool), don't animate a pooled key
		if key.pressTween.Completed:Wait() ~= Enum.PlaybackState.Completed then
			return
		end
		if table.find(KeyPool.boundingKeys, key) then
			return
		end
		KeyPool.releaseKey(key)
	end)
end

-- Update keys state based on overlap with provided parts
function KeyPool.updateKeys(anchors: { BasePart })
	local newBoundingKeys: { KeyObj } = {}
	-- Set of keys, to filter duplicates
	local seenKeys: { [KeyObj]: true } = {}

	for _, anchor in ipairs(anchors) do
		local bound = workspace:GetPartBoundsInBox(anchor.CFrame, anchor.Size, QueryKeysOverlapParams)
		for _, part in ipairs(bound) do
			local keyModel = part.Parent
			if not keyModel then
				continue
			end
			-- key model names are their indices (see getKeys)
			local keyIndex = tonumber(keyModel.Name)
			if not keyIndex then
				continue
			end
			local keyObj = KeyPool.allKeys[keyIndex]
			if keyObj and not seenKeys[keyObj] then
				seenKeys[keyObj] = true
				table.insert(newBoundingKeys, keyObj)
			end
		end
	end

	local boundingChanges = PureArray.GetChanges(KeyPool.boundingKeys, newBoundingKeys)

	PureArray.ForEach(boundingChanges.added, function(key: KeyObj)
		KeyPool.pressKey(key)
	end)

	PureArray.ForEach(boundingChanges.removed, function(key: KeyObj)
		KeyPool.releaseKey(key)
	end)

	KeyPool.boundingKeys = newBoundingKeys
end

-- Initialize a large pool of free keys
KeyPool.freeKeys = KeyPool.getKeys(KEYS_PRELOAD_AMOUNT)

-- ===========================================================================
-- CHUNK CLASS
-- ===========================================================================
local Chunk = {}
Chunk.__index = Chunk

function Chunk.new(floor: KeysFloor, cols: number, rows: number, position: CFrame, randomSeed: number): Chunk
	local self = setmetatable({}, Chunk) :: Chunk
	-- parent
	self.floor = floor
	-- grid dimensions
	self.size = Vector2.new(cols, rows)
	-- world position
	self.position = position.Position
	-- radius of chunk in studs
	local worldSizeX = cols * floor.keySize.X
	local worldSizeZ = rows * floor.keySize.Z
	self.radius = Vector2.new(worldSizeX, worldSizeZ).Magnitude / 2
	-- seed to keep random patterns consistent between loads/unloads
	self.randomSeed = randomSeed
	-- whether chunk is loaded
	self.isLoaded = false
	-- when the chunk left load range; drives the unload debounce
	self.outOfRangeSince = nil

	self.instance = Instance.new("Model")
	self.instance.Name = "Chunk"
	self.instance:PivotTo(position)
	self.instance.Parent = floor.instance

	return self
end

function Chunk.Load(self: Chunk)
	if self.isLoaded or self.instance.Parent == nil then
		return
	end
	self.isLoaded = true

	local random = Random.new(self.randomSeed)
	local keySizeX = self.floor.keySize.X
	local keySizeZ = self.floor.keySize.Z
	local chunkPivot = self.instance:GetPivot()

	local chunkStartX = keySizeX * self.size.X / 2
	local chunkStartZ = keySizeZ * self.size.Y / 2

	local keys = KeyPool.getKeys(self.size.X * self.size.Y)

	-- populate grid with keys
	for col = 1, self.size.X do
		for row = 1, self.size.Y do
			local keyIndex = ((col - 1) * self.size.Y) + row
			local key = keys[keyIndex]
			local pos = chunkPivot
				* CFrame.new(
					(keySizeX / 2) + (keySizeX * (col - 1)) - chunkStartX,
					0,
					(keySizeZ / 2) + (keySizeZ * (row - 1)) - chunkStartZ
				)

			key.instance:PivotTo(pos)
			key.instance:ScaleTo(self.floor.scale)

			local readyKey = KeyPool.setupKey(key, random, self.floor.colorScheme)
			readyKey.instance.Parent = self.instance
		end
	end
end

function Chunk.Unload(self: Chunk)
	if not self.isLoaded then
		return
	end
	self.isLoaded = false

	for _, key in ipairs(self.instance:GetChildren()) do
		local keyIndex = tonumber(key.Name)
		if keyIndex then
			KeyPool.releaseKeyToPool(keyIndex)
		end
	end
end

function Chunk.Update(self: Chunk, anchorPoints: { CFrame }, now: number)
	-- Quick distance check
	local isInRange = false
	for i = 1, #anchorPoints do
		local distanceToChunkCenter = (self.position - anchorPoints[i].Position).Magnitude
		if (distanceToChunkCenter - self.radius) <= CHUNK_LOAD_DISTANCE then
			isInRange = true
			break
		end
	end

	if not isInRange then
		if not self.isLoaded then
			return
		end
		-- set a timer to unload the chunk
		local outOfRangeSince = self.outOfRangeSince or now
		self.outOfRangeSince = outOfRangeSince
		if (now - outOfRangeSince) <= CHUNK_UNLOAD_TIME then
			return
		end

		-- avoid blocking the current heartbeat
		task.defer(function()
			self:Unload()
		end)
		return
	end

	self.outOfRangeSince = nil
	if not self.isLoaded then
		-- avoid blocking the current heartbeat
		task.defer(function()
			self:Load()
		end)
	end
end

-- ===========================================================================
-- KEYSFLOOR CLASS
-- ===========================================================================
local KeysFloor = {}
KeysFloor.__index = KeysFloor

local activeFloors = {}

function KeysFloor.new(block: Part): KeysFloor
	local self = setmetatable({}, KeysFloor) :: KeysFloor
	self.instance = block
	local keyScale = tonumber(block:GetAttribute("KeysScale")) or 0
	self.scale = if keyScale > 0 then keyScale else 1

	local colorSchemeTag = PureArray.FindFirstCommon(block:GetTags(), ColorSchemes.Names)
	self.colorScheme = ColorSchemes.get(colorSchemeTag)

	self.keyObj = KeyPool.parseKey(BasicKey:Clone())
	self.keyObj.instance:ScaleTo(self.scale)
	self.keySize = Vector3.new(self.keyObj.Base.Size.X, 0, self.keyObj.Base.Size.Z)

	self.chunks = {}
	self:GenerateChunks()

	activeFloors[block] = self
	return self
end

function KeysFloor.Destroy(self: KeysFloor)
	for _, chunk in ipairs(self.chunks) do
		chunk:Unload()
		chunk.instance:Destroy()
	end
	self.keyObj.instance:Destroy()
	activeFloors[self.instance] = nil
end

function KeysFloor.GenerateChunks(self: KeysFloor)
	local block = self.instance
	local unitSize = self.keySize

	-- overall grid dimensions
	local totalCols = math.floor(block.Size.X / unitSize.X)
	local totalRows = math.floor(block.Size.Z / unitSize.Z)

	local colsStartOffset = -((totalCols * unitSize.X) / 2)
	local rowsStartOffset = -((totalRows * unitSize.Z) / 2)

	-- Number of chunks
	local chunkCols = math.ceil(totalCols / MAX_CHUNK_DIMENSION)
	local chunkRows = math.ceil(totalRows / MAX_CHUNK_DIMENSION)

	-- avarage chunk's grid dimensions
	local colsPerChunk = totalCols / chunkCols
	local rowsPerChunk = totalRows / chunkRows

	local baseRandomKey = `{block.Name}:{chunkCols}x{chunkRows}`

	-- keep track of how many overall columns and rows have been processed
	local colsProcessed = 0
	local rowsProcessed = 0

	for iCol = 1, chunkCols do
		-- number of columns processed (including this chunk)
		local newColsProcessed = if iCol == chunkCols then totalCols else math.floor(colsPerChunk * iCol)
		local cols = newColsProcessed - colsProcessed

		for iRow = 1, chunkRows do
			-- number of rows processed (including this chunk)
			local newRowsProcessed = if iRow == chunkRows then totalRows else math.floor(rowsPerChunk * iRow)
			local rows = newRowsProcessed - rowsProcessed

			local chunkColOffset = colsProcessed * unitSize.X
			local chunkRowOffset = rowsProcessed * unitSize.Z
			local chunkColSize = cols * unitSize.X
			local chunkRowSize = rows * unitSize.Z

			local position = block.CFrame
				* CFrame.new(
					colsStartOffset + chunkColOffset + chunkColSize / 2,
					block.Size.Y / 2,
					rowsStartOffset + chunkRowOffset + chunkRowSize / 2
				)

			local seed = PureUtils.StringToSeed(`{baseRandomKey}:{iCol}x{iRow}`)
			local chunk = Chunk.new(self, cols, rows, position, seed)
			table.insert(self.chunks, chunk)

			rowsProcessed = newRowsProcessed
		end

		rowsProcessed = 0
		colsProcessed = newColsProcessed
	end
end

function KeysFloor.Update(self: KeysFloor, anchorPoints: { CFrame }, now: number)
	for _, chunk in ipairs(self.chunks) do
		chunk:Update(anchorPoints, now)
	end
end

-- ===========================================================================
-- TAGS SETUP
-- ===========================================================================
Tags.setupTag("KeysFloor", function(block)
	if not (block:IsA("Part") and block.Shape == Enum.PartType.Block) then
		return
	end
	KeysFloor.new(block)
end)

Tags.subscribeTagRemoved("KeysFloor", function(block)
	local keysFloor = activeFloors[block :: Part]
	if keysFloor then
		keysFloor:Destroy()
	end
end)

-- ===========================================================================
-- CHARACTER INITIALIZATION & CACHING
-- ===========================================================================
-- keep track of character's parts for overlap detection

local activeCharacterParts: { BasePart } = {}
local activeHRP: BasePart? = nil
local charConnections = {}

local function ClearCharacter()
	activeHRP = nil
	table.clear(activeCharacterParts)
	for _, conn in charConnections do
		conn:Disconnect()
	end
	table.clear(charConnections)
end

local function InitCharacter(char: Model)
	ClearCharacter()

	local function addPart(inst: Instance)
		if inst:IsA("BasePart") and not inst:FindFirstAncestorOfClass("Accessory") then
			table.insert(activeCharacterParts, inst)
		end
	end

	for _, inst in ipairs(char:GetDescendants()) do
		addPart(inst)
	end

	table.insert(charConnections, char.DescendantAdded:Connect(addPart))
	table.insert(
		charConnections,
		char.DescendantRemoving:Connect(function(inst)
			local idx = table.find(activeCharacterParts, inst :: BasePart)
			if idx then
				table.remove(activeCharacterParts, idx)
			end
		end)
	)

	-- avoid blocking the main thread
	task.spawn(function()
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		-- if the character respawns before WaitForChild resolves
		if hrp and char == Player.Character then
			activeHRP = hrp :: BasePart
		end
	end)
end

Player.CharacterAdded:Connect(InitCharacter)
Player.CharacterRemoving:Connect(ClearCharacter)
if Player.Character then
	InitCharacter(Player.Character)
end

-- ===========================================================================
-- RUNSERVICE CONNECTION
-- ===========================================================================
RunService.Heartbeat:Connect(function(dt)
	KeyPool.soundTimer -= dt
	local now = os.clock()

	local chunkAnchorPoints: { CFrame } = {}
	if activeHRP then
		chunkAnchorPoints[1] = activeHRP:GetPivot()
	end

	for _, floor in pairs(activeFloors) do
		floor:Update(chunkAnchorPoints, now)
	end

	-- Cheaper opt-in alternative: one query over the whole character's bounds
	-- but less accurate when character is ragdolled or falling
	--local boxCFrame, boxSize = Player.Character:GetBoundingBox()
	--KeyPool.updateKeys({ { CFrame = boxCFrame, Size = boxSize } })
	KeyPool.updateKeys(activeCharacterParts)
end)
