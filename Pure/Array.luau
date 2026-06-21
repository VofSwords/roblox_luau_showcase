--!strict
local module = {}

function module.Map<T, R>(array: {T}, fn: (item: T, index: number)->R): {R}
	local newArray = {}
	for i, value in ipairs(array) do
		table.insert(newArray, fn(value, i))
	end
	return newArray
end

function module.ForEach<T>(array: {T}, fn: (item: T, index: number)->()): ()
	for i, value in ipairs(array) do
		fn(value, i)
	end
end

function module.Filter<T>(array: {T}, predicate: (item: T, index: number)->boolean): {T}
	local newArray = {}
	for i, value in ipairs(array) do
		if predicate(value, i) then
			table.insert(newArray, value)
		end
	end
	return newArray
end

function module.FindIndex<T>(array: {T}, predicate: (T)->boolean): number?
	for index, value in ipairs(array) do
		if predicate(value) then
			return index
		end
	end

	return nil
end

function module.Find<T>(array: {T}, predicate: (T)->boolean): T?
	local index = module.FindIndex(array, predicate)
	if (index == nil) then
		return nil
	end
	return array[index]
end

function module.Some<T>(array: {T}, predicate: (T)->boolean): boolean
	return module.FindIndex(array, predicate) ~= nil
end

function module.FindFirstCommonIndex<T>(array: {T}, target: {T}): number?
	for index, item in ipairs(array) do
		if table.find(target, item) then
			return index
		end
	end
	
	return nil
end

function module.FindFirstCommon<T>(array: {T}, target: {T}): T?
	local index = module.FindFirstCommonIndex(array, target)
	if (index == nil) then
		return nil
	end
	return array[index]
end

function module.GetChanges<T>(
	old: {T},
	new: {T}
): {added: {T}, removed: {T}}
	local added = {}
	local removed = {}
	local oldMap = {}
	local newMap = {}

	for _, item in ipairs(old) do
		oldMap[item] = true
	end
	for _, item in ipairs(new) do
		newMap[item] = true
	end

	for _, item in ipairs(old) do
		if not newMap[item] then
			table.insert(removed, item)
		end
	end

	for _, item in ipairs(new) do
		if not oldMap[item] then
			table.insert(added, item)
		end
	end

	return {
		added = added,
		removed = removed,
	}
end

function module.Sort<T>(array: {T}, fn: (x: T, y: T) -> boolean): {T}
	table.sort(array, fn)
	return array
end

function module.Reduce<T, R>(array: {T}, fn: (acc: R, red: T, i: number)->R, initialValue: R?): R
	local acc = initialValue or array[1]
	local start = if initialValue ~= nil then 1 else 2
	local length = #array

	for i = start, length do
		acc = fn(acc, array[i], i)
	end
	
	return acc
end

function module.Flatten<T>(array: {{T}}): {T}
	local totalLength = 0
	for _, subArray in ipairs(array) do
		totalLength += #subArray
	end
	local res = table.create(totalLength)
	local i = 1
	for _, subArray in ipairs(array) do
		for _, value in ipairs(subArray) do
			res[i] = value
			i += 1
		end
	end
	
	return res
end

return module
