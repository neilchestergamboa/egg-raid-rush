--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local Config = Shared:WaitForChild("Config")
local EggDefs = require(Config:WaitForChild("EggDefs") :: ModuleScript)
local ZoneDefs = require(Config:WaitForChild("ZoneDefs") :: ModuleScript)
local CarryDefs = require(Config:WaitForChild("CarryDefs") :: ModuleScript)
local GuardDefs = require(Config:WaitForChild("GuardDefs") :: ModuleScript)
local CarryRules = require(Shared:WaitForChild("Rules"):WaitForChild("CarryRules") :: ModuleScript)
local TutorialRules = require(Shared:WaitForChild("Rules"):WaitForChild("TutorialRules") :: ModuleScript)
local Internal = script.Parent:WaitForChild("Internal")
local CarryRuntime = require(Internal:WaitForChild("CarryRuntime") :: ModuleScript)
local PlayerRateLimiter = require(Internal:WaitForChild("PlayerRateLimiter") :: ModuleScript)
local Network = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("server") :: ModuleScript)

type PickupResultCode =
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

local CarryService = Framework.CreateService({ Name = "CarryService", Client = {} })
local carryRuntime = CarryRuntime.new()
local pickupLimiter = PlayerRateLimiter.new(CarryDefs.RuntimeUpdateIntervalSeconds)
local eggService: any = nil
local dataService: any = nil
local guardService: any = nil
local carriedVisualByUserId: { [number]: Part } = {}
local droppedVisualByEggUid: { [string]: Part } = {}
local savedWalkSpeedByUserId: { [number]: number } = {}
local deathConnectionByUserId: { [number]: RBXScriptConnection } = {}
local elapsedSinceUpdate = 0

local function getCharacterState(player: Player): (Model?, Humanoid?, BasePart?)
    local character = player.Character
    if character == nil then
        return nil, nil, nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return character, humanoid, nil
    end
    return character, humanoid, root
end

local function findSafeGate(): BasePart?
    for _, instance in Workspace:GetDescendants() do
        if instance:IsA("BasePart") and (instance.Name == "SafeGate" or instance:GetAttribute("SafeGate") == true) then
            return instance
        end
    end
    return nil
end

local function isPlayerInsideSafeGate(player: Player): boolean
    local _, _, root = getCharacterState(player)
    local gate = findSafeGate()
    return root ~= nil and gate ~= nil and CarryRules.IsInsideGate(root.Position, gate.CFrame, gate.Size)
end

local function setCarryAttributes(player: Player, record: any)
    player:SetAttribute("IsCarryingCreature", true)
    player:SetAttribute("CarriedCreatureUid", record.CreatureUid)
    player:SetAttribute("CarriedPetDefId", record.DefId)
    player:SetAttribute("CarriedCondition", record.ConditionId)
    player:SetAttribute("CarrySpeedMultiplier", CarryDefs.CarrierSpeedMultiplier)
end

local function clearCarryAttributes(player: Player)
    player:SetAttribute("IsCarryingCreature", false)
    player:SetAttribute("CarriedCreatureUid", nil)
    player:SetAttribute("CarriedPetDefId", nil)
    player:SetAttribute("CarriedCondition", nil)
    player:SetAttribute("CarrySpeedMultiplier", nil)
end

local function removeCarriedVisual(userId: number)
    local visual = carriedVisualByUserId[userId]
    carriedVisualByUserId[userId] = nil
    if visual ~= nil then
        visual:Destroy()
    end
end

local function removeDroppedVisual(eggUid: string)
    local visual = droppedVisualByEggUid[eggUid]
    droppedVisualByEggUid[eggUid] = nil
    if visual ~= nil then
        visual:Destroy()
    end
end

local function restoreCarrierSpeed(player: Player)
    local originalSpeed = savedWalkSpeedByUserId[player.UserId]
    savedWalkSpeedByUserId[player.UserId] = nil
    local _, humanoid = getCharacterState(player)
    if originalSpeed ~= nil and humanoid ~= nil then
        humanoid.WalkSpeed = originalSpeed
    end
    clearCarryAttributes(player)
end

local function attachCreatureVisual(player: Player, record: any): boolean
    local character, humanoid, root = getCharacterState(player)
    if character == nil or humanoid == nil or root == nil then
        return false
    end
    removeCarriedVisual(player.UserId)
    local visual = Instance.new("Part")
    visual.Name = "CarriedCreaturePlaceholder"
    visual.Shape = Enum.PartType.Ball
    visual.Size = Vector3.one * CarryDefs.CarryVisualSize
    visual.Material = Enum.Material.Neon
    visual.Color = Color3.fromRGB(255, 224, 112)
    visual.Massless = true
    visual.CanCollide = false
    visual.CanTouch = false
    visual.CanQuery = false
    visual.Anchored = false
    visual.CFrame = root.CFrame * CFrame.new(CarryDefs.CarryVisualOffset)
    visual:SetAttribute("CreatureUid", record.CreatureUid)
    visual:SetAttribute("PetDefId", record.DefId)
    visual:SetAttribute("Condition", record.ConditionId)
    visual.Parent = character
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root
    weld.Part1 = visual
    weld.Parent = visual
    carriedVisualByUserId[player.UserId] = visual
    if savedWalkSpeedByUserId[player.UserId] == nil then
        savedWalkSpeedByUserId[player.UserId] = humanoid.WalkSpeed
    end
    humanoid.WalkSpeed =
        CarryRules.ApplyCarrierSpeed(savedWalkSpeedByUserId[player.UserId], CarryDefs.CarrierSpeedMultiplier)
    setCarryAttributes(player, record)
    return true
end

local function createDroppedVisual(record: any)
    removeDroppedVisual(record.EggUid)
    local position = record.DropPosition
    if position == nil then
        return
    end
    local visual = Instance.new("Part")
    visual.Name = "DroppedCreaturePlaceholder"
    visual.Shape = Enum.PartType.Ball
    visual.Size = Vector3.one * CarryDefs.DropVisualSize
    visual.Material = Enum.Material.Neon
    visual.Color = Color3.fromRGB(255, 224, 112)
    visual.Anchored = true
    visual.CanCollide = false
    visual.CanTouch = false
    visual.CanQuery = true
    visual.Position = position
    visual:SetAttribute("EggUid", record.EggUid)
    visual:SetAttribute("CreatureUid", record.CreatureUid)
    visual:SetAttribute("PetDefId", record.DefId)
    visual:SetAttribute("Condition", record.ConditionId)
    visual:SetAttribute("DropExpiresAt", record.DropExpiresAt)
    visual.Parent = Workspace
    droppedVisualByEggUid[record.EggUid] = visual
end

local function startGuardAfterGrace(record: any)
    task.delay(CarryDefs.GuardWakeGraceSeconds, function()
        local current = carryRuntime:Get(record.EggUid)
        if current == nil or current.State ~= "Carried" or current.CarrierUserId ~= record.CarrierUserId then
            return
        end
        local slot = eggService:GetSlot(record.EggUid)
        local egg = if slot == nil then nil else EggDefs[slot.DefId]
        if type(egg) ~= "table" or type(egg.GuardDefId) ~= "string" then
            warn("[CarryService] Guard definition missing for " .. record.EggUid)
            return
        end
        local carrier = Players:GetPlayerByUserId(record.CarrierUserId)
        if carrier == nil then
            return
        end
        local guardDefId = egg.GuardDefId
        local profile = dataService:GetProfileData(carrier)
        if profile ~= nil and profile.TutorialCompleted ~= true then
            for _, zone in ZoneDefs do
                if zone.Id == egg.ZoneId then
                    guardDefId = zone.TutorialGuardDefId or guardDefId
                    break
                end
            end
        end
        local started, startError = guardService:StartChase(record.EggUid, guardDefId, carrier)
        if not started then
            warn("[CarryService] Guard could not wake for " .. record.EggUid .. ": " .. tostring(startError))
        end
    end)
end

local function clearCreatureToField(eggUid: string)
    local record = carryRuntime:Get(eggUid)
    if record == nil then
        return false
    end
    guardService:StopChase(eggUid)
    removeDroppedVisual(eggUid)
    if record.CarrierUserId ~= nil then
        local player = Players:GetPlayerByUserId(record.CarrierUserId)
        removeCarriedVisual(record.CarrierUserId)
        if player ~= nil then
            restoreCarrierSpeed(player)
        end
    end
    local returned, returnError = eggService:ReturnCreature(eggUid)
    if not returned then
        warn("[CarryService] Could not return " .. eggUid .. " to the field: " .. tostring(returnError))
        return false
    end
    carryRuntime:Return(eggUid)
    carryRuntime:Forget(eggUid)
    return true
end

local function dropCreature(eggUid: string, userId: number, position: Vector3): boolean
    local record = carryRuntime:Get(eggUid)
    if record == nil or record.CarrierUserId ~= userId then
        return false
    end
    if record.State == "Banking" then
        carryRuntime:CancelBank(eggUid, userId)
        record = carryRuntime:Get(eggUid)
    end
    if record == nil or record.State ~= "Carried" then
        return false
    end
    local now = Workspace:GetServerTimeNow()
    local dropped, dropError = eggService:DropCreature(
        eggUid,
        userId,
        position,
        now + CarryDefs.DropLifetimeSeconds,
        now + CarryDefs.PreviousCarrierLockoutSeconds
    )
    if not dropped then
        warn("[CarryService] Could not mark " .. eggUid .. " dropped: " .. tostring(dropError))
        return false
    end
    local runtimeDropped, runtimeError = carryRuntime:Drop(
        eggUid,
        userId,
        position,
        now,
        CarryDefs.DropLifetimeSeconds,
        CarryDefs.PreviousCarrierLockoutSeconds
    )
    if not runtimeDropped then
        eggService:SetCarrier(eggUid, userId, record.CreatureUid)
        warn("[CarryService] Could not update carry runtime for " .. eggUid .. ": " .. tostring(runtimeError))
        return false
    end
    removeCarriedVisual(userId)
    local player = Players:GetPlayerByUserId(userId)
    if player ~= nil then
        restoreCarrierSpeed(player)
    end
    local droppedRecord = carryRuntime:Get(eggUid)
    if droppedRecord ~= nil then
        createDroppedVisual(droppedRecord)
    end
    return true
end

local function connectCharacter(player: Player, character: Model)
    local previous = deathConnectionByUserId[player.UserId]
    if previous ~= nil then
        previous:Disconnect()
    end
    local humanoid = character:WaitForChild("Humanoid", 10)
    if humanoid == nil or not humanoid:IsA("Humanoid") then
        return
    end
    deathConnectionByUserId[player.UserId] = humanoid.Died:Connect(function()
        local record = carryRuntime:GetForUser(player.UserId)
        if record == nil then
            return
        end
        local root = character:FindFirstChild("HumanoidRootPart")
        local position = if root ~= nil and root:IsA("BasePart") then root.Position else record.DropPosition
        if position == nil then
            clearCreatureToField(record.EggUid)
            return
        end
        if dropCreature(record.EggUid, player.UserId, position) then
            guardService:StopChase(record.EggUid)
        end
    end)
end

local function startWonCarry(slot: any)
    local userId = slot.ClaimantUserId
    if type(userId) ~= "number" then
        return
    end
    local player = Players:GetPlayerByUserId(userId)
    local egg = EggDefs[slot.DefId]
    if player == nil or type(egg) ~= "table" or type(slot.ConditionRoll) ~= "string" then
        eggService:ReturnCreature(slot.Uid)
        return
    end
    if carryRuntime:Get(slot.Uid) ~= nil then
        return
    end
    local _, humanoid, root = getCharacterState(player)
    if humanoid == nil or root == nil then
        eggService:ReturnCreature(slot.Uid)
        return
    end
    local proposedUid = HttpService:GenerateGUID(false)
    local creatureUid = eggService:AssignCreatureUid(slot.Uid, userId, proposedUid)
    if creatureUid == nil then
        return
    end
    local record = {
        CreatureUid = creatureUid,
        EggUid = slot.Uid,
        DefId = egg.PetDefId,
        ConditionId = slot.ConditionRoll,
        State = "Carried",
        CarrierUserId = userId,
        PreviousCarrierUserId = nil,
        PickupLockoutUntil = 0,
        DropExpiresAt = nil,
        DropPosition = nil,
        PickupReservationUserId = nil,
    }
    local registered, registerError = carryRuntime:Register(record)
    if not registered then
        warn("[CarryService] Could not register won creature " .. slot.Uid .. ": " .. tostring(registerError))
        return
    end
    local carried, carryError = eggService:SetCarrier(slot.Uid, userId, creatureUid)
    if not carried then
        carryRuntime:Return(slot.Uid)
        warn("[CarryService] Could not assign winner as carrier for " .. slot.Uid .. ": " .. tostring(carryError))
        return
    end
    if not attachCreatureVisual(player, record) then
        clearCreatureToField(slot.Uid)
        return
    end
    startGuardAfterGrace(record)
end

local function validatePickup(player: Player, eggUid: string): (PickupResultCode, any?)
    local record = carryRuntime:Get(eggUid)
    if record == nil then
        return "CreatureNotFound", nil
    end
    if record.State ~= "Dropped" then
        return "CreatureUnavailable", nil
    end
    local _, humanoid, root = getCharacterState(player)
    if humanoid == nil or root == nil then
        return "NoCharacter", nil
    end
    if player:GetAttribute("IsCarryingCreature") == true or carryRuntime:GetForUser(player.UserId) ~= nil then
        return "CarryingCreature", nil
    end
    if
        record.DropPosition == nil
        or not CarryRules.IsWithinDistance(root.Position, record.DropPosition, CarryDefs.PickupDistanceStuds)
    then
        return "TooFar", nil
    end
    local reserved, reserveError = carryRuntime:ReservePickup(eggUid, player.UserId, Workspace:GetServerTimeNow())
    if not reserved then
        if reserveError == "PickupLockedOut" then
            return "PickupLockedOut", nil
        elseif reserveError == "DropExpired" then
            return "DropExpired", nil
        end
        return "CreatureUnavailable", nil
    end
    return "PickedUp", record
end

local function handlePickup(player: Player, eggUid: string): PickupResultCode
    if type(eggUid) ~= "string" or #eggUid == 0 or #eggUid > 64 then
        return "CreatureNotFound"
    end
    if not pickupLimiter:Allow(player.UserId, Workspace:GetServerTimeNow()) then
        return "RateLimited"
    end
    local validationCode, record = validatePickup(player, eggUid)
    if validationCode ~= "PickedUp" or record == nil then
        return validationCode
    end
    local characterAtStart = player.Character
    task.wait(CarryDefs.PickupHoldSeconds)
    local current = carryRuntime:Get(eggUid)
    local _, humanoid, root = getCharacterState(player)
    local now = Workspace:GetServerTimeNow()
    if
        player.Character ~= characterAtStart
        or not player:IsDescendantOf(Players)
        or humanoid == nil
        or root == nil
        or current == nil
        or current.State ~= "PickupPending"
        or current.PickupReservationUserId ~= player.UserId
    then
        carryRuntime:CancelPickup(eggUid, player.UserId)
        return "CreatureUnavailable"
    end
    if current.DropExpiresAt == nil or now >= current.DropExpiresAt then
        carryRuntime:CancelPickup(eggUid, player.UserId)
        return "DropExpired"
    end
    if
        current.DropPosition == nil
        or not CarryRules.IsWithinDistance(root.Position, current.DropPosition, CarryDefs.PickupDistanceStuds)
    then
        carryRuntime:CancelPickup(eggUid, player.UserId)
        return "TooFar"
    end
    local slotCarried, slotError = eggService:SetCarrier(eggUid, player.UserId, current.CreatureUid)
    if not slotCarried then
        carryRuntime:CancelPickup(eggUid, player.UserId)
        warn("[CarryService] Could not set picked-up creature carrier: " .. tostring(slotError))
        return "ServerError"
    end
    local pickedUp, pickupError = carryRuntime:CompletePickup(eggUid, player.UserId, now)
    if not pickedUp then
        eggService:ReturnCreature(eggUid)
        carryRuntime:CancelPickup(eggUid, player.UserId)
        carryRuntime:Return(eggUid)
        carryRuntime:Forget(eggUid)
        removeDroppedVisual(eggUid)
        warn("[CarryService] Pickup commit failed: " .. tostring(pickupError))
        return "ServerError"
    end
    removeDroppedVisual(eggUid)
    local updatedRecord = carryRuntime:Get(eggUid)
    if updatedRecord == nil or not attachCreatureVisual(player, updatedRecord) then
        clearCreatureToField(eggUid)
        return "ServerError"
    end
    startGuardAfterGrace(updatedRecord)
    return "PickedUp"
end

local function bankCreature(player: Player, record: any)
    local started, startError = carryRuntime:BeginBank(record.EggUid, player.UserId)
    if not started then
        warn("[CarryService] Could not begin bank for " .. record.EggUid .. ": " .. tostring(startError))
        return
    end
    if record.GrantCommitted ~= true then
        local granted, grantError =
            dataService:GrantCapturedPet(player, record.CreatureUid, record.DefId, record.ConditionId)
        if not granted then
            carryRuntime:CancelBank(record.EggUid, player.UserId)
            warn("[CarryService] Bank grant failed for " .. record.EggUid .. ": " .. tostring(grantError))
            return
        end
        if not carryRuntime:MarkGrantCommitted(record.EggUid, player.UserId) then
            warn("[CarryService] Grant committed but bank record could not be marked: " .. record.EggUid)
            return
        end
    end
    local banked, bankError = eggService:Transition(record.EggUid, "Banked")
    if not banked then
        warn("[CarryService] Pet grant committed; bank transition will retry: " .. tostring(bankError))
        return
    end
    carryRuntime:CompleteBank(record.EggUid, player.UserId)
    carryRuntime:Forget(record.EggUid)
    local completed, completeError = dataService:CompleteTutorial(player)
    if not completed then
        warn("[CarryService] Could not save first-bank tutorial completion: " .. tostring(completeError))
    end
    removeCarriedVisual(player.UserId)
    removeDroppedVisual(record.EggUid)
    restoreCarrierSpeed(player)
    guardService:StopChase(record.EggUid)
end

local function updateRuntime(deltaSeconds: number)
    elapsedSinceUpdate += deltaSeconds
    if elapsedSinceUpdate < CarryDefs.RuntimeUpdateIntervalSeconds then
        return
    end
    local now = Workspace:GetServerTimeNow()
    elapsedSinceUpdate = 0
    for _, slot in eggService:GetAllSlots() do
        if slot.State == "Won" then
            startWonCarry(slot)
        end
    end
    for _, record in carryRuntime:GetDropped() do
        if record.DropExpiresAt ~= nil and now >= record.DropExpiresAt then
            clearCreatureToField(record.EggUid)
        end
    end
    for _, player in Players:GetPlayers() do
        local record = carryRuntime:GetForUser(player.UserId)
        if
            record ~= nil
            and (
                (record.State == "Banking" and record.GrantCommitted == true)
                or (record.State == "Carried" and isPlayerInsideSafeGate(player))
            )
        then
            bankCreature(player, record)
        end
    end
end

function CarryService:KnitStart()
    eggService = Framework.GetService("EggService")
    dataService = Framework.GetService("DataService")
    guardService = Framework.GetService("GuardService")
    Network.PickupCreature.SetCallback(function(player: Player, eggUid: string): PickupResultCode
        local ok, result = pcall(handlePickup, player, eggUid)
        if not ok then
            warn("[CarryService] Pickup request failed: " .. tostring(result))
            return "ServerError"
        end
        return result
    end)
    Players.PlayerAdded:Connect(function(player: Player)
        player.CharacterAdded:Connect(function(character: Model)
            connectCharacter(player, character)
        end)
        if player.Character ~= nil then
            connectCharacter(player, player.Character)
        end
    end)
    for _, player in Players:GetPlayers() do
        player.CharacterAdded:Connect(function(character: Model)
            connectCharacter(player, character)
        end)
        if player.Character ~= nil then
            connectCharacter(player, player.Character)
        end
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        pickupLimiter:Forget(player.UserId)
        local connection = deathConnectionByUserId[player.UserId]
        deathConnectionByUserId[player.UserId] = nil
        if connection ~= nil then
            connection:Disconnect()
        end
        local record = carryRuntime:GetForUser(player.UserId)
        if record ~= nil then
            if record.State == "Banking" and record.GrantCommitted == true then
                local banked = eggService:Transition(record.EggUid, "Banked")
                if banked then
                    carryRuntime:CompleteBank(record.EggUid, player.UserId)
                    carryRuntime:Forget(record.EggUid)
                end
                removeCarriedVisual(player.UserId)
                removeDroppedVisual(record.EggUid)
                guardService:StopChase(record.EggUid)
                savedWalkSpeedByUserId[player.UserId] = nil
                return
            elseif record.State == "Banking" then
                carryRuntime:CancelBank(record.EggUid, player.UserId)
            end
            clearCreatureToField(record.EggUid)
        end
        removeCarriedVisual(player.UserId)
        savedWalkSpeedByUserId[player.UserId] = nil
    end)
    RunService.Heartbeat:Connect(updateRuntime)
end

function CarryService:OnGuardTagged(eggUid: string, userId: number, position: Vector3): boolean
    local slot = eggService:GetSlot(eggUid)
    local egg = if slot == nil then nil else EggDefs[slot.DefId]
    local tutorialGuard = GuardDefs[ZoneDefs.Zone1.TutorialGuardDefId]
    local player = Players:GetPlayerByUserId(userId)
    if slot ~= nil and player ~= nil and type(egg) == "table" and type(tutorialGuard) == "table" then
        local profile = dataService:GetProfileData(player)
        local isTutorialRun = profile ~= nil and profile.TutorialCompleted ~= true
        local alreadyForgiven = profile ~= nil and profile.TutorialFirstDropForgiven == true
        if TutorialRules.ShouldForgiveFirstDrop(isTutorialRun, tutorialGuard.ForgiveFirstDrop, alreadyForgiven) then
            local forgiven, forgiveError = dataService:ConsumeTutorialFirstDropForgiveness(player)
            if forgiven then
                return true
            end
            if forgiveError ~= "AlreadyForgiven" then
                warn("[CarryService] Could not consume tutorial Guard forgiveness: " .. tostring(forgiveError))
            end
        end
    end
    return dropCreature(eggUid, userId, position)
end

return CarryService
