--!strict
local RunS = game:GetService("RunService")
local PlayersS = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Packages = RS:WaitForChild("Packages")
local Pure = Packages:WaitForChild("Pure")

local PureArray = require(Pure:WaitForChild("Array"))
local ColorSchemes = require(RS:WaitForChild("ColorSchemes"))
local Tags = require(Packages:WaitForChild("Tags"))
local Shared = require(script.Shared)
local Keys = require(script.Keys)
local Chunks = require(script.Chunks)

local Player = PlayersS.LocalPlayer

if not Player then
	error("Player not found")
end

local FloorTag = "KeysFloor"

local Local = {}

function Local.getChunkAnchors()
	local anchors: {Shared.Anchor} = {}

	local char = Player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = humanoid and humanoid.RootPart
	
	if hrp then
		table.insert(anchors, hrp)	
	end

	return anchors
end

function Local.getKeysAnchors()
	local anchors: {Shared.Anchor} = {}
	
	local char = Player.Character

	if char then
		for _, instance in ipairs(char:GetDescendants()) do
			if not instance:IsA("BasePart") then continue end
			if instance:FindFirstAncestorOfClass("Accessory") then continue end
			table.insert(anchors, instance)
		end
	end
	
	return anchors
end

Keys.freeKeysPool = Keys.getKeys(4096)

Chunks.onInstanceAdd.Event:Connect(Keys.addInstance)
Chunks.onInstanceRemove.Event:Connect(Keys.releaseKeyToPool)

Tags.setupTag(FloorTag, function(block)
	if  not (block:IsA("Part") and block.Shape == Enum.PartType.Block) then
		return
	end
	
	local keysScale = tonumber(block:GetAttribute("KeysScale"))
	local scaleFactor = if (keysScale and  (keysScale > 0)) then keysScale else 1

	local colorSchemeTag = PureArray.FindFirstCommon(block:GetTags(), ColorSchemes.Names)
	local colorScheme = ColorSchemes.get(colorSchemeTag)

	local scaledKey = Keys.parseKey(Keys.BasicKey:Clone())
	scaledKey.instance:ScaleTo(scaleFactor)
	
	local keysConfig: Keys.KeysConfig = {
		key = scaledKey,
		colorScheme = colorScheme,
		scale = scaleFactor,
	}
	
	local chunks = Chunks.addChunkBase(block, scaledKey.Base.Size)
	
	for _, chunk in ipairs(chunks) do
		Keys.keysChunks[chunk.instance] = {
			config = keysConfig,
			chunk = chunk.instance
		}
	end
end)
Tags.subscribeTagRemoved(FloorTag, function(block)
	for _, chunk in block:GetChildren() do
		local foundChunk = Keys.keysChunks[chunk :: Model]
		if not foundChunk then continue end
		for _, key in ipairs(chunk:GetChildren()) do
			Keys.releaseKeyToPool(key)
		end
		Keys.keysChunks[chunk :: Model] = nil
		chunk:Destroy()
	end
end)

RunS.Heartbeat:Connect(function()
	local now = os.clock()
	for _, keysChunk in pairs(Keys.keysChunks) do
		Chunks.updateChunk(keysChunk.chunk, Local.getChunkAnchors(), now)
	end
	
	Keys.updateKeys(Local.getKeysAnchors())
end)
