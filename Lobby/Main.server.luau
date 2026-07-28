local SSS = game:GetService("ServerScriptService")

local Services = SSS.Services

local Game1v1LobbyService = require(Services.Game1v1.LobbyService)
local Game1v1GameService = require(Services.Game1v1.GameService)
local GameFFALobbyService = require(Services.GameFFA.LobbyService)

Game1v1LobbyService.init(workspace.Game1v1)
Game1v1GameService.init()
GameFFALobbyService.init(workspace.GameFFA, workspace.SpawnLocation)
