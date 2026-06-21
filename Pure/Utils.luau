local Module = {}

function Module.StringToSeed(str: string): number
	local hash = 5381
	for i = 1, #str do
		hash = bit32.band(bit32.bxor(hash * 33, string.byte(str, i)), 0x7FFFFFFF)
	end
	return hash
end

return Module
