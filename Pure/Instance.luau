--!strict
local Array = require(script.Parent.Array)
local module = {}

module.FindChildrenByName = function(parent: Instance, name: string)	
	return Array.Filter(parent:GetChildren(), function(child: Instance)
		return child.Name == name
	end)
end

return module
