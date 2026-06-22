--!strict
local RS = game:GetService("ReplicatedStorage")
local TS = game:GetService("TweenService")

local Packages = RS:WaitForChild("Packages")
local Pure = Packages:WaitForChild("Pure")

local ColorSchemes = require(RS:WaitForChild("ColorSchemes"))
local Constants = require(RS:WaitForChild("Constants"))
local Shared = require(script.Parent.Shared)
local PureArray = require(Pure:WaitForChild("Array"))
local Sounds = require(RS:WaitForChild("Sounds"))

local BasicKey = RS:WaitForChild("BasicKey")

local QueryKeysOverlapParams = OverlapParams.new()
QueryKeysOverlapParams.CollisionGroup = Constants.CollisionGroups.QueryKeyTriggers

local pressTweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local releaseTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
	pressTween: Tween?,
	releaseTween: Tween?,
}
export type KeysConfig = {
	key: KeyObj,
	scale: number,
	colorScheme: ColorSchemes.ColorScheme,
}
export type KeysChunk = {
	chunk: Model,
	config: KeysConfig,
}
local Module = {
	freeKeysPool = {} :: {KeyObj},
	allKeys = {} :: {KeyObj},
	boundingKeys = {} :: {KeyObj},
	keysChunks = {} :: {[Model]: KeysChunk},
	BasicKey = BasicKey,
}


function Module.parseKey(key: KeyInstance): KeyObj
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

function Module.getKeys(amount: number): {KeyObj}
	local realAmount = tonumber(amount) or 0
	local intAmount = math.floor(math.abs(realAmount))
	local keys = table.create(intAmount) :: {KeyObj}
	local keysPoolLength = #Module.freeKeysPool
	local keysFromPool = math.min(intAmount, keysPoolLength)
	local newKeysPoolLength = keysPoolLength - keysFromPool

	while keysPoolLength ~= newKeysPoolLength do
		keys[intAmount] = Module.freeKeysPool[keysPoolLength]
		Module.freeKeysPool[keysPoolLength] = nil
		keysPoolLength -= 1
		intAmount -= 1
	end

	local allKeysNumber = #Module.allKeys

	while intAmount ~= 0 do
		allKeysNumber += 1
		local key = Module.parseKey(BasicKey:Clone())
		key.instance.Name = tostring(allKeysNumber)
		keys[intAmount] = key
		Module.allKeys[allKeysNumber] = key
		intAmount -= 1
	end

	return keys
end

function Module.releaseKeyToPool(key: Instance)
	local keyIndex = tonumber(key.Name)
	if not ((keyIndex) and (keyIndex > 0) and ((keyIndex % 1) == 0)) then
		return
	end
	local key = Module.allKeys[keyIndex]
	if not key then return end

	if key.pressTween and key.pressTween.PlaybackState == Enum.PlaybackState.Playing then
		key.pressTween:Cancel()
	end
	if key.releaseTween and key.releaseTween.PlaybackState == Enum.PlaybackState.Playing then
		key.releaseTween:Cancel()
	end

	if key.sound and key.sound.Playing then
		key.sound:Stop()
	end

	key.instance.Parent = nil

	table.insert(Module.freeKeysPool, key)
end

function Module.updateKeys(anchors: {Shared.Anchor})
	local boundingSet = {} :: {[BasePart | KeyObj]: boolean}
	local newBoundingKeys = {}
	for _, anchor in ipairs(anchors) do
		local bound = workspace:GetPartBoundsInBox(anchor.CFrame, anchor.Size, QueryKeysOverlapParams)
		for _, part in ipairs(bound) do
			if boundingSet[part] then
				continue
			end
			local keyIndex = part.Parent and tonumber(part.Parent.Name)
			if not keyIndex then
				continue
			end
			local keyObj = Module.allKeys[keyIndex]
			boundingSet[part] = true
			if keyObj and not boundingSet[keyObj] then
				table.insert(newBoundingKeys, keyObj)
				boundingSet[keyObj] = true
			end
		end
	end

	local boundingChanges = PureArray.GetChanges(Module.boundingKeys, newBoundingKeys)

	PureArray.ForEach(boundingChanges.added, function(key: KeyObj)
		if key.pressTween then
			key.pressTween:Play()
		end
		task.defer(function()
			if not key.pressTween then return end
			key.pressTween.Completed:Wait()
			if table.find(Module.boundingKeys, key) then
				return
			end

			if key.releaseTween then
				key.releaseTween:Play()
			end
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
		if key.releaseTween and key.pressTween then
			if key.pressTween.PlaybackState ~= Enum.PlaybackState.Playing then
				key.releaseTween:Play()
			end
		end
	end)

	Module.boundingKeys = newBoundingKeys
end

function Module.addInstance(chunk: Model, random: Random, pos: CFrame)
	local keysChunk = Module.keysChunks[chunk]
	local config = keysChunk and keysChunk.config
	if not config then return end
	local key = Module.getKeys(1)[0]
	key.instance:ScaleTo(config.scale)
	local originalCFrame = key.Body.CFrame
	key.label.Text = string.char(random:NextNumber(65, 90))
	key.color.Color = config.colorScheme.get(random:NextNumber(1, config.colorScheme.total))
	key.pressTween = TS:Create(key.Body, pressTweenInfo, {CFrame = originalCFrame * key.pressCFrameOffset})
	key.releaseTween = TS:Create(key.Body, releaseTweenInfo, {CFrame = originalCFrame})
	key.Body.Transparency = 0
end

return Module
