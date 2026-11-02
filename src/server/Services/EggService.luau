--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local ZoneDefs = require(ConfigFolder:WaitForChild("ZoneDefs") :: ModuleScript)
local EggDefs = require(ConfigFolder:WaitForChild("EggDefs") :: ModuleScript)
local RarityDefs = require(ConfigFolder:WaitForChild("RarityDefs") :: ModuleScript)
local EggSlotRuntime = require(script.Parent:WaitForChild("Internal"):WaitForChild("EggSlotRuntime") :: ModuleScript)
local EggSlotAttributePublisher =
    require(script.Parent:WaitForChild("Internal"):WaitForChild("EggSlotAttributePublisher") :: ModuleScript)

local STATE_ROOT_NAME = "EggSlotStates"
local EggService = Framework.CreateService({ Name = "EggService", Client = {} })
local runtime: any = nil

local function getOrCreateFolder(parent: Instance, name: string): Folder
    local existing = parent:FindFirstChild(name)
    if existing ~= nil then
        assert(existing:IsA("Folder"), name .. " must be a Folder.")
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function getSortedKeys(definitions: { [string]: any }): { string }
    local keys = {}
    for key in definitions do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

local function createSlotDefinitions(): { any }
    local slotDefinitions = {}
    for _, zoneKey in getSortedKeys(ZoneDefs) do
        local zone = ZoneDefs[zoneKey]
        for _, eggDefId in zone.EggDefIds do
            local egg = EggDefs[eggDefId]
            local rarity = RarityDefs[egg.RarityId]
            table.insert(slotDefinitions, {
                Uid = eggDefId,
                DefId = eggDefId,
                ZoneId = egg.ZoneId,
                Slot = egg.Slot,
                RarityId = egg.RarityId,
                RespawnSeconds = rarity.RespawnSeconds,
                IsTutorial = egg.IsTutorial,
            })
        end

        local tutorialEggDefId = zone.TutorialEggDefId
        local tutorialEgg = EggDefs[tutorialEggDefId]
        local tutorialRarity = RarityDefs[tutorialEgg.RarityId]
        table.insert(slotDefinitions, {
            Uid = tutorialEggDefId,
            DefId = tutorialEggDefId,
            ZoneId = tutorialEgg.ZoneId,
            Slot = tutorialEgg.Slot,
            RarityId = tutorialEgg.RarityId,
            RespawnSeconds = tutorialRarity.RespawnSeconds,
            IsTutorial = tutorialEgg.IsTutorial,
        })
    end
    return slotDefinitions
end

local function publishSlot(record: any, previousState: string?, reason: string)
    local zoneFolder =
        getOrCreateFolder(getOrCreateFolder(Workspace, STATE_ROOT_NAME), "Zone" .. tostring(record.ZoneId))
    local slotFolder = getOrCreateFolder(zoneFolder, record.Uid)
    EggSlotAttributePublisher.Publish(slotFolder, record)

    if previousState ~= nil then
        if previousState ~= record.State then
            warn(
                "[EggService] "
                    .. record.Uid
                    .. ": "
                    .. previousState
                    .. " -> "
                    .. record.State
                    .. " ("
                    .. reason
                    .. ")"
            )
        end
    end
end

function EggService:KnitInit()
    local slotDefinitions = createSlotDefinitions()
    runtime = EggSlotRuntime.new(slotDefinitions, {
        Now = function()
            return Workspace:GetServerTimeNow()
        end,
        Schedule = function(seconds: number, callback: () -> ())
            task.delay(seconds, callback)
        end,
        OnChanged = publishSlot,
    })
end

function EggService:GetSlot(eggUid: string): any?
    if runtime == nil then
        return nil
    end
    return runtime:GetSlot(eggUid)
end

function EggService:GetAllSlots(): { any }
    if runtime == nil then
        return {}
    end
    return runtime:GetAllSlots()
end

function EggService:TryClaim(eggUid: string, claimantUserId: number): (boolean, string?)
    if runtime == nil then
        return false, "EggServiceNotReady"
    end
    return runtime:TryClaim(eggUid, claimantUserId)
end

function EggService:SetExpiresAt(eggUid: string, expiresAt: number): (boolean, string?)
    if runtime == nil then
        return false, "EggServiceNotReady"
    end
    return runtime:SetExpiresAt(eggUid, expiresAt)
end

function EggService:ReleaseClaim(eggUid: string, reason: string): (boolean, string?)
    if runtime == nil then
        return false, "EggServiceNotReady"
    end
    return runtime:ReleaseClaim(eggUid, reason)
end

function EggService:Transition(eggUid: string, targetState: any): (boolean, string?)
    if runtime == nil then
        return false, "EggServiceNotReady"
    end
    return runtime:Transition(eggUid, targetState)
end

return EggService
