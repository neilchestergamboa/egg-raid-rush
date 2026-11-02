--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local CarryDefs = require(ConfigFolder:WaitForChild("CarryDefs") :: ModuleScript)
local PetDefs = require(ConfigFolder:WaitForChild("PetDefs") :: ModuleScript)
local ConditionDefs = require(ConfigFolder:WaitForChild("ConditionDefs") :: ModuleScript)
local GuardDefs = require(ConfigFolder:WaitForChild("GuardDefs") :: ModuleScript)
local CarryRules = require(Shared:WaitForChild("Rules"):WaitForChild("CarryRules") :: ModuleScript)
local Network = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("client") :: ModuleScript)

local ClientRoot = script.Parent.Parent
local UIFolder = ClientRoot:WaitForChild("UI")
local ChaseScreenHud = require(UIFolder:WaitForChild("ChaseScreenHud") :: ModuleScript)
local DropWorldHud = require(UIFolder:WaitForChild("DropWorldHud") :: ModuleScript)
local ChaseBankingEffect = require(UIFolder:WaitForChild("ChaseBankingEffect") :: ModuleScript)
local HudTheme = require(UIFolder:WaitForChild("HudTheme") :: ModuleScript)

local STATE_ROOT_NAME = "EggSlotStates"
local DROPPED_NAME = "DroppedCreaturePlaceholder"
local GUARD_PREFIX = "RaidGuard_"

type PickupResult =
    "PickedUp"
    | "CreatureNotFound"
    | "CreatureUnavailable"
    | "NoCharacter"
    | "TooFar"
    | "CarryingCreature"
    | "PickupLockedOut"
    | "DropExpired"
    | "RateLimited"
    | "ServerError"

type DroppedCreature = {
    Part: BasePart,
    EggUid: string,
    CreatureUid: string?,
    PetDefId: string?,
    ConditionId: string?,
    DropExpiresAt: number?,
}

type SlotSnapshot = {
    Uid: string,
    State: string?,
    CarrierUserId: number?,
    CreatureUid: string?,
    PreviousCarrierUserId: number?,
    PickupLockoutUntil: number?,
}

local PICKUP_STATUS: { [string]: string } = {
    PickedUp = "You picked up the creature.",
    CreatureNotFound = "That creature isn't here.",
    CreatureUnavailable = "That creature can't be picked up.",
    NoCharacter = "You need to spawn in first.",
    TooFar = "Get closer to pick it up.",
    CarryingCreature = "You're already carrying a creature.",
    PickupLockedOut = "You can't pick that up yet.",
    DropExpired = "The creature returned to the field.",
    ServerError = "Something went wrong. Try again.",
}

local ChaseHudController = {
    Name = "ChaseHudController",
}

local function asString(value: unknown): string?
    return if type(value) == "string" and value ~= "" then value else nil
end

local function asNumber(value: unknown): number?
    return if type(value) == "number" then value else nil
end

local function getLocalPlayer(): Player
    local player = Players.LocalPlayer
    assert(player ~= nil, "LocalPlayer is required for the chase HUD.")
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

local function creatureLabel(petDefId: string?, conditionId: string?): string
    local petName = "Creature"
    if petDefId ~= nil then
        local pet = PetDefs[petDefId]
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

local function guardName(guardDefId: string?): string
    if guardDefId ~= nil then
        local definition = GuardDefs[guardDefId]
        if type(definition) == "table" then
            return definition.Name
        end
    end
    return "Guard"
end

local function collectSlots(): { SlotSnapshot }
    local slots = {}
    local root = Workspace:FindFirstChild(STATE_ROOT_NAME)
    if root == nil or not root:IsA("Folder") then
        return slots
    end
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
                CarrierUserId = asNumber(slotFolder:GetAttribute("CarrierUserId")),
                CreatureUid = asString(slotFolder:GetAttribute("CreatureUid")),
                PreviousCarrierUserId = asNumber(slotFolder:GetAttribute("PreviousCarrierUserId")),
                PickupLockoutUntil = asNumber(slotFolder:GetAttribute("PickupLockoutUntil")),
            })
        end
    end
    return slots
end

local function findSafeGate(): BasePart?
    for _, instance in Workspace:GetDescendants() do
        if instance:IsA("BasePart") and (instance.Name == "SafeGate" or instance:GetAttribute("SafeGate") == true) then
            return instance
        end
    end
    return nil
end

local function readDropped(part: BasePart): DroppedCreature?
    local eggUid = asString(part:GetAttribute("EggUid"))
    if eggUid == nil then
        return nil
    end
    return {
        Part = part,
        EggUid = eggUid,
        CreatureUid = asString(part:GetAttribute("CreatureUid")),
        PetDefId = asString(part:GetAttribute("PetDefId")),
        ConditionId = asString(part:GetAttribute("Condition")),
        DropExpiresAt = asNumber(part:GetAttribute("DropExpiresAt")),
    }
end

function ChaseHudController:KnitStart()
    local player = getLocalPlayer()
    local playerGui = player:WaitForChild("PlayerGui")
    assert(playerGui:IsA("PlayerGui"), "PlayerGui must be a PlayerGui.")

    local connections: { RBXScriptConnection } = {}
    local function track(connection: RBXScriptConnection): RBXScriptConnection
        table.insert(connections, connection)
        return connection
    end

    local droppedByPart: { [BasePart]: DroppedCreature } = {}
    local chasingGuards: { [BasePart]: BasePart } = {}
    local safeGate: BasePart? = nil
    local nearestPickupUid: string? = nil
    local pickupBusy = false
    local pickupStartedAt: number? = nil
    local statusExpireAt = 0
    local watchedEggUid: string? = nil
    local watchedCreatureUid: string? = nil
    local wasCarrying = false
    local bankWatchUntil = 0

    local screenHud: ChaseScreenHud.ChaseScreenHud
    local function requestPickup()
        local eggUid = nearestPickupUid
        if eggUid == nil or pickupBusy then
            return
        end
        pickupBusy = true
        pickupStartedAt = os.clock()
        task.spawn(function()
            local ok, result = pcall(function(): PickupResult
                return Network.PickupCreature.Call(eggUid)
            end)
            pickupBusy = false
            pickupStartedAt = nil
            if not ok then
                warn("[ChaseHudController] PickupCreature failed: " .. tostring(result))
                screenHud:SetStatus(PICKUP_STATUS.ServerError)
                statusExpireAt = os.clock() + 2.5
                return
            end
            local message = PICKUP_STATUS[result]
            if message ~= nil then
                screenHud:SetStatus(message)
                statusExpireAt = os.clock() + 2.5
            end
        end)
    end

    screenHud = ChaseScreenHud.Create(playerGui, {
        OnPickup = function()
            requestPickup()
        end,
    })
    local dropWorldHud = DropWorldHud.Create()
    local bankingEffect = ChaseBankingEffect.Create()

    local function considerInstance(instance: Instance)
        if not instance:IsA("BasePart") then
            return
        end
        if instance.Name == DROPPED_NAME then
            local dropped = readDropped(instance)
            if dropped ~= nil then
                droppedByPart[instance] = dropped
            end
        elseif string.sub(instance.Name, 1, #GUARD_PREFIX) == GUARD_PREFIX then
            chasingGuards[instance] = instance
        elseif instance.Name == "SafeGate" or instance:GetAttribute("SafeGate") == true then
            safeGate = instance
        end
    end

    local function forgetInstance(instance: Instance)
        if instance:IsA("BasePart") then
            droppedByPart[instance] = nil
            chasingGuards[instance] = nil
            if safeGate == instance then
                safeGate = nil
            end
        end
    end

    for _, instance in Workspace:GetDescendants() do
        considerInstance(instance)
    end
    track(Workspace.DescendantAdded:Connect(considerInstance))
    track(Workspace.DescendantRemoving:Connect(forgetInstance))

    track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
            return
        end
        if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
            requestPickup()
        end
    end))

    local function cleanup()
        for _, connection in connections do
            connection:Disconnect()
        end
        table.clear(connections)
        screenHud:Destroy()
        dropWorldHud:Destroy()
        bankingEffect:Destroy()
    end

    track(player.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            cleanup()
        end
    end))

    track(RunService.Heartbeat:Connect(function()
        local now = Workspace:GetServerTimeNow()
        local rootPart = getRootPart(player)
        local carrying = player:GetAttribute("IsCarryingCreature") == true
        local carriedUid = asString(player:GetAttribute("CarriedCreatureUid"))
        local carriedPetDefId = asString(player:GetAttribute("CarriedPetDefId"))
        local carriedCondition = asString(player:GetAttribute("CarriedCondition"))
        local slots = collectSlots()
        local gate = safeGate or findSafeGate()
        if gate ~= nil then
            safeGate = gate
        end

        local carriedEggUid: string? = nil
        for _, slot in slots do
            if slot.CarrierUserId == player.UserId and slot.State == "Carried" then
                carriedEggUid = slot.Uid
                break
            end
        end

        if carrying then
            wasCarrying = true
            watchedEggUid = carriedEggUid or watchedEggUid
            watchedCreatureUid = carriedUid or watchedCreatureUid
            bankWatchUntil = 0
            screenHud:SetCarry({
                Visible = true,
                Title = "Carrying",
                Detail = creatureLabel(carriedPetDefId, carriedCondition),
            })
            local insideGate = rootPart ~= nil
                and gate ~= nil
                and CarryRules.IsInsideGate(rootPart.Position, gate.CFrame, gate.Size)
            bankingEffect:SetApproaching(if insideGate then gate else nil)
        else
            screenHud:SetCarry({
                Visible = false,
                Title = "Carrying",
                Detail = "",
            })
            bankingEffect:SetApproaching(nil)
            if wasCarrying then
                wasCarrying = false
                bankWatchUntil = now + CarryDefs.RuntimeUpdateIntervalSeconds * 4
            end
        end

        if bankWatchUntil > 0 then
            local matchingDrop = false
            for _, dropped in droppedByPart do
                if dropped.EggUid == watchedEggUid or dropped.CreatureUid == watchedCreatureUid then
                    matchingDrop = true
                    break
                end
            end
            local watchedState: string? = nil
            for _, slot in slots do
                if slot.Uid == watchedEggUid then
                    watchedState = slot.State
                    break
                end
            end
            if watchedState == "Banked" or watchedState == "Respawning" then
                bankingEffect:PlaySuccess(gate)
                screenHud:PlayBankFlash()
                screenHud:SetStatus("Banked at the Safe Gate.")
                statusExpireAt = os.clock() + 2.5
                watchedEggUid = nil
                watchedCreatureUid = nil
                bankWatchUntil = 0
            elseif matchingDrop or watchedState == "Dropped" or now >= bankWatchUntil then
                bankWatchUntil = 0
            end
        end

        local closestGuardDistance = math.huge
        local closestGuardDef: string? = nil
        for part in chasingGuards do
            if carrying and asNumber(part:GetAttribute("TargetUserId")) == player.UserId then
                local distance = if rootPart ~= nil then (part.Position - rootPart.Position).Magnitude else 0
                if distance < closestGuardDistance then
                    closestGuardDistance = distance
                    closestGuardDef = asString(part:GetAttribute("GuardDefId"))
                end
            end
        end
        if closestGuardDef ~= nil then
            local isClose = closestGuardDistance <= CarryDefs.GuardTagDistanceStuds
            local text = if isClose
                then guardName(closestGuardDef) .. " is right behind you!"
                else guardName(closestGuardDef) .. " is chasing you!"
            screenHud:SetGuard({
                Visible = true,
                Text = text,
                IsClose = isClose,
            })
        else
            screenHud:SetGuard({
                Visible = false,
                Text = "",
                IsClose = false,
            })
        end

        local worldDrops = {}
        local nearestDrop: DroppedCreature? = nil
        local nearestDistance = math.huge
        local nearestRemaining = 0
        for _, dropped in droppedByPart do
            local expiresAt = dropped.DropExpiresAt or asNumber(dropped.Part:GetAttribute("DropExpiresAt"))
            if expiresAt == nil then
                continue
            end
            local remaining = expiresAt - now
            if remaining <= 0 then
                continue
            end
            table.insert(worldDrops, {
                EggUid = dropped.EggUid,
                Adornee = dropped.Part,
                RemainingSeconds = remaining,
            })
            if rootPart ~= nil then
                local distance = (dropped.Part.Position - rootPart.Position).Magnitude
                local nearby = CarryRules.IsWithinDistance(
                    rootPart.Position,
                    dropped.Part.Position,
                    CarryDefs.PickupDistanceStuds
                ) or distance <= HudTheme.BillboardMaxDistance
                if nearby and distance < nearestDistance then
                    nearestDistance = distance
                    nearestDrop = dropped
                    nearestRemaining = remaining
                end
            end
        end
        dropWorldHud:Sync(worldDrops)

        local inPickupRange = nearestDrop ~= nil
            and rootPart ~= nil
            and CarryRules.IsWithinDistance(rootPart.Position, nearestDrop.Part.Position, CarryDefs.PickupDistanceStuds)

        if nearestDrop ~= nil and (inPickupRange or nearestDistance <= HudTheme.BillboardMaxDistance) then
            screenHud:SetDrop({
                Visible = true,
                Text = string.format("Loose creature  %.1fs", nearestRemaining),
            })
        else
            screenHud:SetDrop({
                Visible = false,
                Text = "",
            })
        end

        nearestPickupUid = nil
        local promptText: string? = nil
        local showAction = false
        local showKey = UserInputService.KeyboardEnabled
        local holdProgress: number? = nil
        if pickupStartedAt ~= nil then
            holdProgress = math.clamp((os.clock() - pickupStartedAt) / CarryDefs.PickupHoldSeconds, 0, 1)
        end

        if inPickupRange and nearestDrop ~= nil and not carrying then
            local lockoutUntil = 0
            for _, slot in slots do
                if slot.Uid == nearestDrop.EggUid then
                    lockoutUntil = slot.PickupLockoutUntil or 0
                    if slot.PreviousCarrierUserId ~= player.UserId then
                        lockoutUntil = 0
                    end
                    break
                end
            end
            if now < lockoutUntil then
                promptText = string.format("Wait  %.1fs", lockoutUntil - now)
            else
                nearestPickupUid = nearestDrop.EggUid
                promptText = if showKey then "Hold E  Pick up" else "Pick up"
                showAction = UserInputService.TouchEnabled
            end
        end

        screenHud:SetPickup({
            PromptText = promptText,
            ShowKeyPrompt = promptText ~= nil and (showKey or not showAction),
            ShowActionButton = showAction,
            ActionText = "Pick up",
            HoldProgress = holdProgress,
        })

        if statusExpireAt > 0 and os.clock() >= statusExpireAt then
            statusExpireAt = 0
            screenHud:SetStatus(nil)
        end
    end))
end

Framework.CreateController(ChaseHudController)

return ChaseHudController
