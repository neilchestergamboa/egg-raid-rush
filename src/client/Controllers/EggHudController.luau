--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local EggDefs = require(ConfigFolder:WaitForChild("EggDefs") :: ModuleScript)
local PetDefs = require(ConfigFolder:WaitForChild("PetDefs") :: ModuleScript)
local ConditionDefs = require(ConfigFolder:WaitForChild("ConditionDefs") :: ModuleScript)
local EggInteractionDefs = require(ConfigFolder:WaitForChild("EggInteractionDefs") :: ModuleScript)
local CarryDefs = require(ConfigFolder:WaitForChild("CarryDefs") :: ModuleScript)
local CarryRules = require(Shared:WaitForChild("Rules"):WaitForChild("CarryRules") :: ModuleScript)

local Network = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("client") :: ModuleScript)

local ClientRoot = script.Parent.Parent
local UIFolder = ClientRoot:WaitForChild("UI")
local EggScreenHud = require(UIFolder:WaitForChild("EggScreenHud") :: ModuleScript)
local EggWorldHud = require(UIFolder:WaitForChild("EggWorldHud") :: ModuleScript)
local FightRisingCue = require(UIFolder:WaitForChild("FightRisingCue") :: ModuleScript)
local HudTheme = require(UIFolder:WaitForChild("HudTheme") :: ModuleScript)

local STATE_ROOT_NAME = "EggSlotStates"

type EggActionResult =
    "Claimed"
    | "ClaimLostRace"
    | "EggNotFound"
    | "EggUnavailable"
    | "EggObjectUnavailable"
    | "NoCharacter"
    | "TooFar"
    | "CarryingCreature"
    | "ProfileNotReady"
    | "NoPetEquipped"
    | "PetRecovering"
    | "FightInProgress"
    | "InvalidPet"
    | "RateLimited"
    | "ServerError"

type FightActionResult = "Retreated" | "FightNotActive" | "RateLimited" | "ServerError"

type SlotView = {
    Uid: string,
    State: string?,
    ClaimantUserId: number?,
    Health: number?,
    MaxHealth: number?,
    CrackStage: number?,
    PetHp: number?,
    PetMaxHp: number?,
    HatchlingHp: number?,
    HatchlingMaxHp: number?,
    FightStatus: string?,
    ConditionRoll: string?,
    Folder: Folder,
}

local RESULT_STATUS: { [string]: string } = {
    Claimed = "Your pet is breaking the egg.",
    ClaimLostRace = "Someone else claimed it first.",
    EggNotFound = "That egg isn't here.",
    EggUnavailable = "That egg can't be claimed right now.",
    EggObjectUnavailable = "The egg isn't in the world yet.",
    NoCharacter = "You need to spawn in first.",
    TooFar = "Get closer to the egg.",
    CarryingCreature = "You can't break an egg while carrying.",
    ProfileNotReady = "Still loading your pets.",
    NoPetEquipped = "Equip a Champion pet first.",
    PetRecovering = "Your pet is still recovering.",
    FightInProgress = "Your pet is already in a fight.",
    InvalidPet = "Your Champion pet isn't ready.",
    ServerError = "Something went wrong. Try again.",
    Retreated = "Your pet retreated.",
    FightNotActive = "There's no fight to retreat from.",
}

local EggHudController = {
    Name = "EggHudController",
}

local hasStarted = false
local busy = false
local statusExpireAt = 0
local nearestActionUid: string? = nil
local nearestFightUid: string? = nil
local adornees: { [string]: BasePart } = {}

local function asString(value: unknown): string?
    return if type(value) == "string" and value ~= "" then value else nil
end

local function asNumber(value: unknown): number?
    return if type(value) == "number" then value else nil
end

local function getLocalPlayer(): Player
    local player = Players.LocalPlayer
    assert(player ~= nil, "LocalPlayer is required for the egg HUD.")
    return player
end

local function getRootPart(player: Player): BasePart?
    local character = player.Character
    if character == nil then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil
    end
    return root
end

local function getAdorneePart(instance: Instance): BasePart?
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Model") then
        local primary = instance.PrimaryPart
        if primary ~= nil then
            return primary
        end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function considerWorldInstance(instance: Instance)
    local uid = asString(instance:GetAttribute("EggUid"))
    if uid == nil and EggDefs[instance.Name] ~= nil then
        uid = instance.Name
    end
    if uid == nil then
        return
    end
    local part = getAdorneePart(instance)
    if part ~= nil then
        adornees[uid] = part
    end
end

local function forgetWorldInstance(instance: Instance)
    local uid = asString(instance:GetAttribute("EggUid"))
    if uid == nil and EggDefs[instance.Name] ~= nil then
        uid = instance.Name
    end
    if uid == nil then
        return
    end
    if adornees[uid] == instance or (instance:IsA("Model") and instance.PrimaryPart == adornees[uid]) then
        adornees[uid] = nil
    end
end

local function collectSlots(root: Folder): { SlotView }
    local slots = {}
    for _, zoneFolder in root:GetChildren() do
        if not zoneFolder:IsA("Folder") then
            continue
        end
        for _, slotFolder in zoneFolder:GetChildren() do
            if not slotFolder:IsA("Folder") then
                continue
            end
            table.insert(slots, {
                Uid = slotFolder.Name,
                State = asString(slotFolder:GetAttribute("State")),
                ClaimantUserId = asNumber(slotFolder:GetAttribute("ClaimantUserId")),
                Health = asNumber(slotFolder:GetAttribute("Health")),
                MaxHealth = asNumber(slotFolder:GetAttribute("MaxHealth")),
                CrackStage = asNumber(slotFolder:GetAttribute("CrackStage")),
                PetHp = asNumber(slotFolder:GetAttribute("PetHp")),
                PetMaxHp = asNumber(slotFolder:GetAttribute("PetMaxHp")),
                HatchlingHp = asNumber(slotFolder:GetAttribute("HatchlingHp")),
                HatchlingMaxHp = asNumber(slotFolder:GetAttribute("HatchlingMaxHp")),
                FightStatus = asString(slotFolder:GetAttribute("FightStatus")),
                ConditionRoll = asString(slotFolder:GetAttribute("ConditionRoll")),
                Folder = slotFolder,
            })
        end
    end
    return slots
end

local function hatchlingName(eggUid: string, conditionId: string?): string
    local egg = EggDefs[eggUid]
    local petName = "Hatchling"
    if type(egg) == "table" then
        local pet = PetDefs[egg.PetDefId]
        if type(pet) == "table" then
            petName = pet.Name
        end
    end
    if conditionId ~= nil then
        local condition = ConditionDefs[conditionId]
        if type(condition) == "table" then
            return petName .. " (" .. condition.Name .. ")"
        end
    end
    return petName
end

local function claimantName(userId: number?): string
    if userId == nil then
        return "Champion"
    end
    local player = Players:GetPlayerByUserId(userId)
    if player == nil then
        return "Champion"
    end
    return player.DisplayName
end

local function isTouchLayout(): boolean
    return UserInputService.TouchEnabled
end

local function isTyping(): boolean
    return UserInputService:GetFocusedTextBox() ~= nil
end

local function isNearDroppedCreature(root: BasePart): boolean
    for _, child in Workspace:GetChildren() do
        if child.Name == "DroppedCreaturePlaceholder" and child:IsA("BasePart") then
            if CarryRules.IsWithinDistance(root.Position, child.Position, CarryDefs.PickupDistanceStuds) then
                return true
            end
        end
    end
    return false
end

local function showStatus(hud: EggScreenHud.EggScreenHud, code: string)
    local message = RESULT_STATUS[code]
    if message == nil then
        return
    end
    hud:SetStatus(message)
    statusExpireAt = os.clock() + 2.5
end

local function requestEgg(hud: EggScreenHud.EggScreenHud, eggUid: string)
    if busy then
        return
    end
    busy = true
    task.spawn(function()
        local ok, result = pcall(function(): EggActionResult
            return Network.RequestEgg.Call(eggUid)
        end)
        busy = false
        if not ok then
            warn("[EggHudController] RequestEgg failed: " .. tostring(result))
            showStatus(hud, "ServerError")
            return
        end
        showStatus(hud, result)
    end)
end

local function retreatEgg(hud: EggScreenHud.EggScreenHud, eggUid: string)
    if busy then
        return
    end
    busy = true
    task.spawn(function()
        local ok, result = pcall(function(): FightActionResult
            return Network.RetreatEgg.Call(eggUid)
        end)
        busy = false
        if not ok then
            warn("[EggHudController] RetreatEgg failed: " .. tostring(result))
            showStatus(hud, "ServerError")
            return
        end
        showStatus(hud, result)
    end)
end

function EggHudController:KnitStart()
    if hasStarted then
        return
    end
    hasStarted = true

    local player = getLocalPlayer()
    local playerGui = player:WaitForChild("PlayerGui")
    assert(playerGui:IsA("PlayerGui"), "PlayerGui must be a PlayerGui.")

    local screenHud: EggScreenHud.EggScreenHud
    screenHud = EggScreenHud.Create(playerGui, {
        OnAction = function()
            local eggUid = nearestActionUid
            if eggUid ~= nil then
                requestEgg(screenHud, eggUid)
            end
        end,
        OnRetreat = function()
            local eggUid = nearestFightUid
            if eggUid ~= nil then
                retreatEgg(screenHud, eggUid)
            end
        end,
    })
    local worldHud = EggWorldHud.Create()
    local risingCue = FightRisingCue.Create()

    for _, instance in Workspace:GetDescendants() do
        considerWorldInstance(instance)
    end
    Workspace.DescendantAdded:Connect(considerWorldInstance)
    Workspace.DescendantRemoving:Connect(forgetWorldInstance)

    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed or isTyping() then
            return
        end
        if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
            local eggUid = nearestActionUid
            if eggUid ~= nil then
                requestEgg(screenHud, eggUid)
            end
        elseif input.KeyCode == Enum.KeyCode.R then
            local eggUid = nearestFightUid
            if eggUid ~= nil then
                retreatEgg(screenHud, eggUid)
            end
        end
    end)

    local function refresh(deltaSeconds: number)
        local stateRoot = Workspace:FindFirstChild(STATE_ROOT_NAME)
        local slots: { SlotView } = if stateRoot ~= nil and stateRoot:IsA("Folder") then collectSlots(stateRoot) else {}
        local rootPart = getRootPart(player)
        local carrying = player:GetAttribute("IsCarryingCreature") == true
        local crackCount = #EggInteractionDefs.CrackHealthThresholds

        local worldViews = {}
        local closestSealed: SlotView? = nil
        local closestSealedDistance = math.huge
        local closestInfo: SlotView? = nil
        local closestInfoDistance = math.huge
        local localFight: SlotView? = nil
        local fightIntensity = 0
        local fightAudible = false

        for _, slot in slots do
            local adornee = adornees[slot.Uid]
            table.insert(worldViews, {
                Uid = slot.Uid,
                State = slot.State,
                ClaimantUserId = slot.ClaimantUserId,
                Health = slot.Health,
                MaxHealth = slot.MaxHealth,
                CrackStage = slot.CrackStage,
                CrackStageCount = crackCount,
                PetHp = slot.PetHp,
                PetMaxHp = slot.PetMaxHp,
                HatchlingHp = slot.HatchlingHp,
                HatchlingMaxHp = slot.HatchlingMaxHp,
                PetName = claimantName(slot.ClaimantUserId),
                HatchlingName = hatchlingName(slot.Uid, slot.ConditionRoll),
                Adornee = adornee,
            })

            local position = if adornee ~= nil then adornee.Position else nil
            local distance = if rootPart ~= nil and position ~= nil
                then (rootPart.Position - position).Magnitude
                else math.huge

            if slot.State == "Fighting" and slot.ClaimantUserId == player.UserId then
                localFight = slot
            end
            if slot.State == "Fighting" and distance <= HudTheme.NearbyAudioStuds then
                fightAudible = true
                local petRatio = if slot.PetHp ~= nil
                        and slot.PetMaxHp ~= nil
                        and slot.PetMaxHp > 0
                    then slot.PetHp / slot.PetMaxHp
                    else 1
                local hatchRatio = if slot.HatchlingHp ~= nil
                        and slot.HatchlingMaxHp ~= nil
                        and slot.HatchlingMaxHp > 0
                    then slot.HatchlingHp / slot.HatchlingMaxHp
                    else 1
                fightIntensity = math.max(fightIntensity, 1 - math.clamp(math.min(petRatio, hatchRatio), 0, 1))
            end

            if rootPart ~= nil and distance <= EggInteractionDefs.ClaimDistanceStuds then
                if distance < closestInfoDistance then
                    closestInfoDistance = distance
                    closestInfo = slot
                end
                if slot.State == "Sealed" and distance < closestSealedDistance then
                    closestSealedDistance = distance
                    closestSealed = slot
                end
            end
        end

        worldHud:Sync(worldViews)
        risingCue:Update(deltaSeconds, fightIntensity, fightAudible)

        nearestActionUid = nil
        nearestFightUid = nil
        local showKey = UserInputService.KeyboardEnabled
        local showTouch = isTouchLayout()
        local promptText: string? = nil
        local showAction = false
        local actionText = "Break"

        local pickupBlocksClaim = rootPart ~= nil and isNearDroppedCreature(rootPart)

        if localFight ~= nil then
            nearestFightUid = localFight.Uid
            promptText = if showKey then "Fighting  ·  Retreat" else "Fighting"
        elseif pickupBlocksClaim then
            promptText = nil
        elseif not carrying and closestSealed ~= nil then
            nearestActionUid = closestSealed.Uid
            promptText = if showKey then "E  Break egg" else "Break egg"
            showAction = showTouch
        elseif closestInfo ~= nil then
            if closestInfo.State == "Breaking" and closestInfo.ClaimantUserId == player.UserId then
                promptText = "Your pet is breaking the egg"
            elseif closestInfo.ClaimantUserId ~= nil and closestInfo.ClaimantUserId ~= player.UserId then
                promptText = "Claimed by " .. claimantName(closestInfo.ClaimantUserId)
            elseif closestInfo.State == "Sealed" and carrying then
                promptText = "Can't break an egg while carrying"
            end
        end

        screenHud:SetPrompt({
            PromptText = promptText,
            ShowKeyPrompt = promptText ~= nil and (showKey or not showAction),
            ShowActionButton = showAction,
            ActionText = actionText,
        })

        if localFight ~= nil then
            screenHud:SetFight({
                Visible = true,
                PetName = "Champion",
                HatchlingName = hatchlingName(localFight.Uid, localFight.ConditionRoll),
                PetHp = localFight.PetHp or 0,
                PetMaxHp = localFight.PetMaxHp or 1,
                HatchlingHp = localFight.HatchlingHp or 0,
                HatchlingMaxHp = localFight.HatchlingMaxHp or 1,
                ShowRetreat = true,
            })
        else
            screenHud:SetFight({
                Visible = false,
                PetName = "",
                HatchlingName = "",
                PetHp = 0,
                PetMaxHp = 1,
                HatchlingHp = 0,
                HatchlingMaxHp = 1,
                ShowRetreat = false,
            })
        end

        if statusExpireAt > 0 and os.clock() >= statusExpireAt then
            statusExpireAt = 0
            screenHud:SetStatus(nil)
        end
    end

    RunService.Heartbeat:Connect(refresh)
end

Framework.CreateController(EggHudController)

return EggHudController
