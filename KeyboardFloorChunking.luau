local RS = game:GetService("ReplicatedStorage")
local RunS = game:GetService("RunService")
local PlayersS = game:GetService("Players")
local TS = game:GetService("TweenService")

local Packages = RS:WaitForChild("Packages")
local Pure = Packages:WaitForChild("Pure")
local Player = PlayersS.LocalPlayer

local Tags = require(Packages:WaitForChild("Tags"))
local PureArray = require(Pure:WaitForChild("Array"))
local PureTable = require(Pure:WaitForChild("Table"))
local PureUtils = require(Pure:WaitForChild("Utils"))
local ColorSchemes = require(RS:WaitForChild("ColorSchemes"))
local Constants = require(RS:WaitForChild("Constants"))
local Sounds = require(RS:WaitForChild("Sounds"))

local BasicKey = RS:WaitForChild("BasicKey")

local MAX_CHUNK_SIZE = 8
local UNLOAD_TIME = 2
local CHUNK_LOAD_DISTANCE = 192

local Local = {}

export type Anchor = {
	CFrame: CFrame,
	Size: Vector3
}

export type Chunk = {
	instance: Model,
	size: Vector2,
	randomSeed: number,
	unloadedTime: number?,
	isLoaded: boolean,
}
export type KeyInstance = typeof(BasicKey)
export type KeyObj = {
	instance: KeyInstance,
	sound: Sound,
	label: TextLabel,
	color: BasePart,
	Trigger: BasePart,
	Body: BasePart,
	Base: BasePart,
	pressCFrameOffset: CFrame,
	pressTween: Tween,
	releaseTween: Tween,
}
export type FloorInstance = Part
export type KeysFloor = {
	floor: FloorInstance,
	chunks: {Chunk},
	key: KeyObj,
	scale: number,
	colorScheme: ColorSchemes.ColorScheme,
}

local freeKeysPool: {KeyObj} = {}
local allKeys: {KeyObj} = {}
local boundingKeys: {KeyObj} = {}
local keysFloors: {[FloorInstance]: KeysFloor} = {}

local pressTweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local releaseTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Local.parseKey(key: KeyInstance)
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
		pressCFrameOffset = CFrame.new(0, 0.16 - key.Body.Size.Y, 0),
	}
end

function Local.getKeys(amount: number): {KeyObj}
	local realAmount = tonumber(amount) or 0
	local intAmount = math.floor(math.abs(realAmount))
	local keys = table.create(intAmount)
	local keysPoolLength = #freeKeysPool
	local keysFromPool = math.min(intAmount, keysPoolLength)
	local newKeysPoolLength = keysPoolLength - keysFromPool
	
	while keysPoolLength ~= newKeysPoolLength do
		keys[intAmount] = freeKeysPool[keysPoolLength]
		freeKeysPool[keysPoolLength] = nil
		keysPoolLength -= 1
		intAmount -= 1
	end
	
	local allKeysNumber = #allKeys
	
	while intAmount ~= 0 do
		allKeysNumber += 1
		local key = Local.parseKey(BasicKey:Clone())
		key.instance.Name = allKeysNumber
		keys[intAmount] = key
		allKeys[allKeysNumber] = key
		intAmount -= 1
	end

	return keys
end

function Local.releaseKeyToPool(keyIndex: number)
	local key = allKeys[keyIndex]
	if not key then return end

	-- Cancel any active tweens to avoid stale animations
	if key.pressTween and key.pressTween.PlaybackState == Enum.PlaybackState.Playing then
		key.pressTween:Cancel()
	end
	if key.releaseTween and key.releaseTween.PlaybackState == Enum.PlaybackState.Playing then
		key.releaseTween:Cancel()
	end

	-- Stop sound if playing
	if key.sound and key.sound.Playing then
		key.sound:Stop()
	end

	-- Unparent from chunk so it's no longer in the scene
	key.instance.Parent = nil

	table.insert(freeKeysPool, key)
end

function Local.populateChunk(chunk: Chunk, floor: KeysFloor)
	local instance = chunk and chunk.instance
	if not instance then
		return
	end
	if (not floor) or (not floor.key) then
		return
	end
	
	local random = Random.new(chunk.randomSeed)
	local keySizeX = floor.key.Base.Size.X
	local keySizeZ = floor.key.Base.Size.Z
	local chunkPivot = instance:GetPivot()
	local chunkStartX = keySizeX*chunk.size.X/2
	local chunkStartZ = keySizeZ*chunk.size.Y/2
	
	local colorScheme = floor.colorScheme
	local keys = Local.getKeys(chunk.size.X*chunk.size.Y)
	
	for col = 0, chunk.size.X - 1 do
		for row = 0, chunk.size.Y - 1 do
			local key = keys[(col*chunk.size.Y) + row + 1]
			local pos = chunkPivot * CFrame.new(
				(keySizeX/2) + (keySizeX*col) - chunkStartX,
				0,
				(keySizeZ/2) + (keySizeZ*row) - chunkStartZ
			)
			key.instance:PivotTo(pos)
			key.instance:ScaleTo(floor.scale)
			local originalCFrame = key.Body.CFrame
			key.label.Text = string.char(random:NextNumber(65, 90))
			key.color.Color = colorScheme.get(random:NextNumber(1, colorScheme.total))
			key.pressTween = TS:Create(key.Body, pressTweenInfo, {CFrame = originalCFrame * key.pressCFrameOffset})
			key.releaseTween = TS:Create(key.Body, releaseTweenInfo, {CFrame = originalCFrame})
			key.Body.Transparency = 0
			key.instance.Parent = instance
		end
	end
end

function Local.updateChunk(chunk: Chunk, anchorPoints: {CFrame}, now: number, floor: KeysFloor)
	local isInRange = PureArray.Some<<CFrame>>(anchorPoints, function(anchorPoint)
		local distanceToChunkCenter = (chunk.instance:GetPivot().Position - anchorPoint.Position).Magnitude
		local chunkSize = chunk.size.Magnitude
		return (distanceToChunkCenter - chunkSize) <= CHUNK_LOAD_DISTANCE
	end)
	
	if not isInRange then
		if not chunk.isLoaded then
			return
		end

		if chunk.unloadedTime == nil then
			chunk.unloadedTime = now
			return
		end
		
		if (now - chunk.unloadedTime) <= UNLOAD_TIME then
			return
		end
		
		task.defer(function()
			if not (chunk and chunk.instance) then
				return
			end

			for _, key in ipairs(chunk.instance:GetChildren()) do
				local keyIndex = tonumber(key.Name)
				if (keyIndex) and (keyIndex > 0) and ((keyIndex % 1) == 0) then
					Local.releaseKeyToPool(keyIndex)
				end
			end
			chunk.isLoaded = false
		end)
		return
	end

	chunk.unloadedTime = nil

	if chunk.isLoaded then
		return
	end

	
	task.defer(function()
		if chunk.isLoaded then
			return
		end
		
		Local.populateChunk(chunk, floor)

		chunk.isLoaded = true
	end)
end

function Local.updateAllChunks(anchorPoints: {CFrame})
	local now = os.clock()
	for _, keysFloor in pairs(keysFloors) do
		for _, chunk in pairs(keysFloor.chunks) do
			Local.updateChunk(chunk, anchorPoints, now, keysFloor)
		end
	end
end

local QueryKeysOverlapParams = OverlapParams.new()
QueryKeysOverlapParams.CollisionGroup = Constants.CollisionGroups.QueryKeyTriggers
function Local.updateKeys(anchors: {Anchor})
	local boundingSet = {}
	local newBoundingKeys = {}
	for _, anchor in ipairs(anchors) do
		local bound = workspace:GetPartBoundsInBox(anchor.CFrame, anchor.Size, QueryKeysOverlapParams)
		for _, part in ipairs(bound) do
			if boundingSet[part] then
				continue
			end
			local keyObj = allKeys[tonumber(part.Parent.Name)]
			boundingSet[part] = true
			if keyObj and not boundingSet[keyObj] then
				table.insert(newBoundingKeys, keyObj)
				boundingSet[keyObj] = true
			end
		end
	end

	local boundingChanges = PureArray.GetChanges(boundingKeys, newBoundingKeys)

	PureArray.ForEach(boundingChanges.added, function(key: KeyObj)
		key.pressTween:Play()
		task.defer(function()
			key.pressTween.Completed:Wait()
			if table.find(boundingKeys, key) then
				return
			end
			
			key.releaseTween:Play()
		end)

		if not key.sound.Playing then
			local soundParams = Sounds.GetSound()
			key.sound.SoundId = soundParams.soundId
			key.sound.TimePosition = soundParams.timePosition
			key.sound.Volume = soundParams.volume
			key.sound.PlaybackSpeed = soundParams.playbackSpeed
			key.sound:Play()
		end
	end)
	PureArray.ForEach(boundingChanges.removed, function(key: KeyObj)
		if key.pressTween.PlaybackState ~= Enum.PlaybackState.Playing then
			key.releaseTween:Play()
		end
	end)
	
	boundingKeys = newBoundingKeys
end

freeKeysPool = Local.getKeys(4096)

Tags.setupTag("KeysFloor", function(block)
	if  not (block:IsA("Part") and block.Shape == Enum.PartType.Block) then
		return
	end
	
	local keysScale = tonumber(block:GetAttribute("KeysScale"))
	local scaleFactor = if (keysScale and  (keysScale > 0)) then keysScale else 1
	
	local colorSchemeTag = PureArray.FindFirstCommon(block:GetTags(), ColorSchemes.Names)
	local colorScheme = ColorSchemes.get(colorSchemeTag)
	
	local scaledKey = Local.parseKey(BasicKey:Clone())
	scaledKey.instance:ScaleTo(scaleFactor)
	
	local keySizeX = scaledKey.Base.Size.X
	local keySizeZ = scaledKey.Base.Size.Z
	

	local spawnSizeX = block.Size.X
	local spawnSizeZ = block.Size.Z
	local spawnSizeY = block.Size.Y
	
	local floorCols = math.floor(spawnSizeX / keySizeX)
	local floorRows = math.floor(spawnSizeZ / keySizeX)
	
	local colsStart = -((floorCols * keySizeX)/2)
	local rowsStart = -((floorRows * keySizeZ)/2)
	
	local colChunks = math.ceil(floorCols / MAX_CHUNK_SIZE)
	local rowChunks = math.ceil(floorRows / MAX_CHUNK_SIZE)
	local colsPerChunk = floorCols / colChunks
	local rowsPerChunk = floorRows / rowChunks
	
	local chunks = {}
	local xSizes = {}
	local zSizes = {}
	local xSizesSum = {}
	local zSizesSum = {}	
	local prev = 0
	for iCol = 1, colChunks do
		local sizeXSum = if iCol == colChunks then floorCols else math.floor(colsPerChunk * iCol)
		xSizes[iCol] = sizeXSum - prev
		xSizesSum[iCol] = prev
		prev = sizeXSum
	end
	prev = 0
	for iRow = 1, rowChunks do
		local sizeZSum = if iRow == rowChunks then floorRows else math.floor(rowsPerChunk * iRow)
		zSizes[iRow] = sizeZSum - prev
		zSizesSum[iRow] = prev
		prev = sizeZSum
	end
	
	local floorRandomKey = `{block.Name}:{colChunks}x{rowChunks}`
	
	for iCol = 1, colChunks do
		local colsBefore = iCol
		for iRow = 1, rowChunks do
			local size = Vector2.new(xSizes[iCol], zSizes[iRow])
			local pos = block.CFrame * CFrame.new(
				colsStart + (xSizesSum[iCol] + (size.X/2))*keySizeX,
				spawnSizeY/2,
				rowsStart + (zSizesSum[iRow] + (size.Y/2))*keySizeZ
			)
			
			local chunk = Instance.new("Model", block)
			chunk.Name = "Chunk"
			chunk:PivotTo(pos)
			
			table.insert(chunks, {
				instance = chunk,
				size = size,
				randomSeed = PureUtils.StringToSeed(`{floorRandomKey}:{iCol}x{iRow}`),
				isLoaded = false,
				unloadedTime = nil,
			})
		end
	end
	
	keysFloors[block] = {
		floor = block,
		chunks = chunks,
		key = scaledKey,
		scale = scaleFactor,
		colorScheme = colorScheme,
	}
end)
--TODO: test for chunk unload during teleport
Tags.subscribeTagRemoved("KeysFloor", function(block)
	local keysFloor = keysFloors[block]
	if not keysFloor then return end
	
	for _, chunk in ipairs(keysFloor.chunks) do
		for _, key in ipairs(chunk.instance:GetChildren()) do
			local keyIndex = tonumber(key.Name)
			if (keyIndex) and (keyIndex > 0) and ((keyIndex % 1) == 0) then
				Local.releaseKeyToPool(keyIndex)
			end
		end
		chunk.instance:Destroy()
	end
	keysFloors[block] = nil
end)

RunS.Heartbeat:Connect(function()
	local char = Player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	local chunkAnchorPoints: {CFrame} = {}
	
	local hrpPoint = hrp and hrp:IsA("PVInstance") and hrp:GetPivot()
	if hrpPoint then
		chunkAnchorPoints[1] = hrpPoint
	end
	
	local keyAnchors: {Anchor} = {}
	
	--local boxCFrame, boxSize = char:GetBoundingBox()
	--keyAnchors[1] = { CFrame = boxCFrame, Size = boxSize }

	if char then
		for _, inst in ipairs(char:GetDescendants()) do
			if inst:IsA("BasePart") then
				if not inst:FindFirstAncestorOfClass("Accessory") then
					table.insert(keyAnchors, inst)
				end
			end
		end
	end
	
	Local.updateAllChunks(chunkAnchorPoints)
	Local.updateKeys(keyAnchors)
end)
