--!strict
local RS = game:GetService("ReplicatedStorage")

local Packages = RS:WaitForChild("Packages")
local Pure = Packages:WaitForChild("Pure")

local Config = require(script.Parent.Config)
local Shared = require(script.Parent.Shared)
local PureUtils = require(Pure:WaitForChild("Utils"))
local PureArray = require(Pure:WaitForChild("Array"))

export type Chunk = {
	instance: Model,
	size: Vector3,
	randomSeed: number,
	unloadedTime: number?,
	isLoaded: boolean,
	unitSize: Vector3,
}

local Module = {
	chunksByInstance = {} :: {[Model]: Chunk},
	onInstanceAdd = Instance.new("BindableEvent"),
	onInstanceRemove = Instance.new("BindableEvent"),
}

function Module.addChunkBase(base: Part, unitSize: Vector3)
	-- Compute the number of whole units that fit on each axis
	local totalCols = math.floor(base.Size.X / unitSize.X)
	local totalRows = math.floor(base.Size.Z / unitSize.Z)
	-- Center the grid inside the base; any leftover space becomes padding.
	local colsStartOffset = -((totalCols * unitSize.X)/2)
	local rowsStartOffset = -((totalRows * unitSize.Z)/2)
	-- Split the grid into chunk-sized regions
	local chunkCols = math.ceil(totalCols / Config.MAX_CHUNK_SIZE)
	local chunkRows = math.ceil(totalRows / Config.MAX_CHUNK_SIZE)
	-- Compute how many units each chunk spans
	local colsPerChunk = totalCols / chunkCols
	local rowsPerChunk = totalRows / chunkRows
	
	local baseRandomKey = `{base.Name}:{chunkCols}x{chunkRows}`
	
	-- Results
	local chunks: {Chunk} = {}

	-- Track the starting position of each chunk
	local colsProcessed = 0
	local rowsProcessed = 0
	-- Create each chunk
	for iCol = 1, chunkCols do
		-- Compute the number of units in this chunk
		local newColsProcessed = if iCol == chunkCols then totalCols else math.floor(colsPerChunk * iCol)
		local cols = newColsProcessed - colsProcessed
		for iRow = 1, chunkRows do
			-- Compute the number of units in this chunk
			local newRowsProcessed = if iRow == chunkRows then totalRows else math.floor(rowsPerChunk * iRow)
			local rows = newRowsProcessed - rowsProcessed

			-- Convert chunk-local counts into world-space offsets
			local chunkColOffset = colsProcessed * unitSize.X
			local chunkRowOffset = rowsProcessed * unitSize.Z
			local chunkColSize = cols * unitSize.X
			local chunkRowSize = rows * unitSize.Z
			
			-- Place the chunk at its center within the base
			local position = base.CFrame * CFrame.new(
				colsStartOffset + chunkColOffset + chunkColSize / 2,
				base.Size.Y / 2,
				rowsStartOffset + chunkRowOffset + chunkRowSize / 2
			)
			local chunk = Instance.new("Model", base)
			chunk:PivotTo(position)
			local newChunkObj: Chunk = {
				instance = chunk,
				size = Vector3.new(cols, 1, rows),
				randomSeed = PureUtils.StringToSeed(`{baseRandomKey}:{iCol}x{iRow}`),
				isLoaded = false,
				unloadedTime = nil,
				unitSize = unitSize,
			}
			table.insert(chunks, newChunkObj)
			Module.chunksByInstance[chunk] = newChunkObj
			rowsProcessed = newRowsProcessed
		end
		
		rowsProcessed = 0
		colsProcessed = newColsProcessed
	end
	
	return chunks
end
function Module.removeChunkBase()
	
end

function Module.updateChunk(chunkInstance: Model, anchorPoints: {Shared.Anchor}, now: number)
	local chunk = Module.chunksByInstance[chunkInstance]
	local isInRange = PureArray.Some<<Shared.Anchor>>(anchorPoints, function(anchorPoint)
		local distanceToChunkCenter = (chunk.instance:GetPivot().Position - anchorPoint.CFrame.Position).Magnitude
		local chunkSize = chunk.size.Magnitude
		return (distanceToChunkCenter - chunkSize) <= Config.CHUNK_LOAD_DISTANCE
	end)

	if not isInRange then
		if not chunk.isLoaded then
			return
		end

		if chunk.unloadedTime == nil then
			chunk.unloadedTime = now
			return
		end

		if (now - chunk.unloadedTime) <= Config.UNLOAD_TIME then
			return
		end

		task.defer(function()
			if not (chunk and chunk.instance) then
				return
			end

			for _, key in ipairs(chunk.instance:GetChildren()) do
				Module.onInstanceRemove:Fire(key)
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

		Module.populateChunk(chunk)

		chunk.isLoaded = true
	end)
end

function Module.populateChunk(chunk: Chunk)
	local instance = chunk and chunk.instance
	if not instance then
		return
	end

	local random = Random.new(chunk.randomSeed)
	local chunkPivot = instance:GetPivot()
	local unitSize = chunk.unitSize
	local chunkStartX = unitSize.X*chunk.size.X/2
	local chunkStartZ = unitSize.Z*chunk.size.Y/2

	for col = 0, chunk.size.X - 1 do
		for row = 0, chunk.size.Y - 1 do
			local pos = chunkPivot * CFrame.new(
				(unitSize.X/2) + (unitSize.X*col) - chunkStartX,
				0,
				(unitSize.Z/2) + (unitSize.Z*row) - chunkStartZ
			)
			Module.onInstanceAdd:Fire(chunk, random, pos)
		end
	end
end

return Module
