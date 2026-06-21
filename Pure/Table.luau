--!strict
local module = {}

function module.Keys<T>(t: {[T]: any}): {T}
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	return keys
end

function module.Values<T>(t: {[T]: any}): {T}
	local values = {}
	for _, value in pairs(t) do
		table.insert(values, value)
	end
	return values
end

function module.DeepFreeze<T>(t: T): T
	if type(t) == 'table' then
		for _, v in pairs(t) do
			module.DeepFreeze(v)
		end
		table.freeze(t)
	end


	return t
end

function module.DeepCopy<T>(t: T): T
	if type(t) ~= 'table' then
		return t
	end
	local res = {}
	for k, v in pairs(t) do
		res[k] = module.DeepCopy(v)
	end

	return res
end

function module.Merge<T>(...: T): T
	local result = {}
	for _, obj in ipairs({...}) do
		for key, value in pairs(obj) do
			result[key] = value
		end
	end
	return result
end

return module
