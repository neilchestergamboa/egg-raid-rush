--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local ProfileSchema = require(Shared:WaitForChild("Types"):WaitForChild("ProfileSchema") :: ModuleScript)
local ProfileStoreModule =
    ServerScriptService:WaitForChild("ServerPackages"):WaitForChild("ProfileStore") :: ModuleScript
local ProfileStore = require(ProfileStoreModule) :: any
local ProfileSessionManager =
    require(script.Parent:WaitForChild("Internal"):WaitForChild("ProfileSessionManager") :: ModuleScript)

local PLAYER_STORE_NAME = "EggRaidRushPlayerData"
local PlayerStore = ProfileStore.New(PLAYER_STORE_NAME, ProfileSchema.CreateTemplate())
if RunService:IsStudio() then
    PlayerStore = PlayerStore.Mock
end

local function isPlayerConnected(player: Player): boolean
    return player:IsDescendantOf(Players)
end

local function onUnexpectedSessionEnd(player: Player)
    warn("[DataService] Profile session ended unexpectedly for user " .. tostring(player.UserId) .. ".")
    player:Kick("Your data session ended. Please rejoin so your progress stays safe.")
end

local function cloneAndFreeze(value: any): any
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = cloneAndFreeze(child)
    end
    return table.freeze(copy)
end

local SessionManager = ProfileSessionManager.new(PlayerStore, ProfileSchema, isPlayerConnected, onUnexpectedSessionEnd)
local DataService = Framework.CreateService({ Name = "DataService", Client = {} })
local loadingPlayers: { [Player]: boolean } = {}

local function loadPlayer(player: Player)
    if loadingPlayers[player] then
        return
    end
    loadingPlayers[player] = true

    task.spawn(function()
        local callOk, loaded, loadError = pcall(function()
            return SessionManager:Load(player)
        end)
        loadingPlayers[player] = nil

        if not callOk then
            loadError = tostring(loaded)
            loaded = false
        end
        if not loaded and isPlayerConnected(player) then
            warn(
                "[DataService] Could not load profile for user "
                    .. tostring(player.UserId)
                    .. ": "
                    .. tostring(loadError)
            )
            player:Kick("Your data could not load safely. Please rejoin.")
        end
    end)
end

function DataService:KnitInit()
    Players.PlayerAdded:Connect(loadPlayer)
    Players.PlayerRemoving:Connect(function(player: Player)
        local released, releaseError = SessionManager:Release(player)
        if not released and releaseError ~= "ProfileNotLoaded" then
            warn(
                "[DataService] Could not release profile for user "
                    .. tostring(player.UserId)
                    .. ": "
                    .. tostring(releaseError)
            )
        end
    end)

    for _, player in Players:GetPlayers() do
        loadPlayer(player)
    end

    game:BindToClose(function()
        for _, player in Players:GetPlayers() do
            local released, releaseError = SessionManager:Release(player)
            if not released and releaseError ~= "ProfileNotLoaded" then
                warn(
                    "[DataService] Could not release profile during shutdown for user "
                        .. tostring(player.UserId)
                        .. ": "
                        .. tostring(releaseError)
                )
            end
        end
    end)
end

function DataService:GetProfileData(player: Player): any?
    local profile = SessionManager:GetProfile(player.UserId)
    if profile == nil then
        return nil
    end
    return cloneAndFreeze(profile.Data)
end

return DataService
