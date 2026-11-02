--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local EggDefs = require(ConfigFolder:WaitForChild("EggDefs") :: ModuleScript)
local EggInteractionDefs = require(ConfigFolder:WaitForChild("EggInteractionDefs") :: ModuleScript)
local RulesFolder = Shared:WaitForChild("Rules")
local EggClaimOrder = require(RulesFolder:WaitForChild("EggClaimOrder") :: ModuleScript)
local TutorialRules = require(RulesFolder:WaitForChild("TutorialRules") :: ModuleScript)
local Internal = script.Parent:WaitForChild("Internal")
local ClaimLeaseRuntime = require(Internal:WaitForChild("ClaimLeaseRuntime") :: ModuleScript)
local ClaimValidation = require(Internal:WaitForChild("ClaimValidation") :: ModuleScript)
local PlayerRateLimiter = require(Internal:WaitForChild("PlayerRateLimiter") :: ModuleScript)
local Network = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("server") :: ModuleScript)

type ResultCode =
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

type PendingClaim = {
    Player: Player,
    ReceivedAt: number,
    Response: BindableEvent,
}

local ClaimService = Framework.CreateService({ Name = "ClaimService", Client = {} })
local eggService: any = nil
local eggBreakService: any = nil
local fightService: any = nil
local dataService: any = nil
local rateLimiter = PlayerRateLimiter.new(EggInteractionDefs.RequestRateLimitSeconds)
local pendingByEggUid: { [string]: { PendingClaim } } = {}
local batchScheduledByEggUid: { [string]: boolean } = {}
local activeEggsByUserId: { [number]: { [string]: boolean } } = {}
local leases = ClaimLeaseRuntime.new({
    Now = function()
        return Workspace:GetServerTimeNow()
    end,
    Schedule = function(seconds: number, callback: () -> ())
        task.delay(seconds, callback)
    end,
    OnExpired = function(eggUid: string, userId: number)
        ClaimService:CancelClaim(eggUid, userId, "ClaimTimeout")
    end,
})

local function findEggObjectPosition(eggUid: string): Vector3?
    for _, instance in Workspace:GetDescendants() do
        if instance:GetAttribute("EggUid") == eggUid then
            if instance:IsA("BasePart") then
                return instance.Position
            elseif instance:IsA("Model") then
                return instance:GetPivot().Position
            end
        end
    end
    return nil
end

local function getCharacterRoot(player: Player): (BasePart?, boolean)
    local character = player.Character
    if character == nil then
        return nil, false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil, false
    end
    return root, true
end

local function getChampionPet(profile: any): any?
    if type(profile) ~= "table" or type(profile.Pets) ~= "table" then
        return nil
    end
    local championUid = profile.ChampionPetUid
    if type(championUid) ~= "string" or championUid == "" then
        return nil
    end
    return profile.Pets[championUid]
end

local function validateRequest(player: Player, eggUid: string): (ResultCode, number?)
    local slot = eggService:GetSlot(eggUid)
    local egg = if slot == nil then nil else EggDefs[slot.DefId]
    local profile = dataService:GetProfileData(player)
    if
        slot ~= nil
        and not TutorialRules.CanClaim(
            slot.OwnerUserId,
            player.UserId,
            slot.IsTutorial and profile ~= nil and profile.TutorialCompleted == true
        )
    then
        return "EggUnavailable", nil
    end
    local eggExists = slot ~= nil and type(egg) == "table"
    local eggPosition = if eggExists then findEggObjectPosition(eggUid) else nil
    local root, hasCharacter = getCharacterRoot(player)
    local isWithinRange = false
    if root ~= nil and eggPosition ~= nil then
        isWithinRange = (root.Position - eggPosition).Magnitude <= EggInteractionDefs.ClaimDistanceStuds
    end
    local code, petPower = ClaimValidation.Validate({
        EggExists = eggExists,
        EggState = if slot == nil then nil else slot.State,
        EggObjectExists = eggPosition ~= nil,
        HasCharacter = hasCharacter,
        IsWithinRange = isWithinRange,
        IsCarryingCreature = player:GetAttribute("IsCarryingCreature") == true,
        IsFighting = fightService:IsUserFighting(player.UserId),
        HasProfile = profile ~= nil,
        ChampionPet = getChampionPet(profile),
        Now = Workspace:GetServerTimeNow(),
    })
    return code, petPower
end

local function trackClaim(player: Player, eggUid: string)
    local eggs = activeEggsByUserId[player.UserId]
    if eggs == nil then
        eggs = {}
        activeEggsByUserId[player.UserId] = eggs
    end
    eggs[eggUid] = true
end

local function untrackClaim(userId: number, eggUid: string)
    local eggs = activeEggsByUserId[userId]
    if eggs == nil then
        return
    end
    eggs[eggUid] = nil
    if next(eggs) == nil then
        activeEggsByUserId[userId] = nil
    end
end

local function startClaim(player: Player, eggUid: string): ResultCode
    local validationCode, petPower = validateRequest(player, eggUid)
    if validationCode ~= "Claimed" or petPower == nil then
        return validationCode
    end

    local slot = eggService:GetSlot(eggUid)
    if slot == nil or slot.State ~= "Sealed" then
        return "EggUnavailable"
    end

    local claimed, claimError = eggService:TryClaim(eggUid, player.UserId)
    if not claimed then
        warn("[ClaimService] Claim rejected for " .. eggUid .. ": " .. tostring(claimError))
        return "EggUnavailable"
    end

    trackClaim(player, eggUid)
    local hatchCommitted, hatchError = fightService:CommitCondition(eggUid, player.UserId)
    if not hatchCommitted then
        eggService:ReleaseClaim(eggUid, "HatchConditionCommitFailed")
        untrackClaim(player.UserId, eggUid)
        warn("[ClaimService] Could not commit hatch roll for " .. eggUid .. ": " .. tostring(hatchError))
        return "ServerError"
    end
    local expiresAt = Workspace:GetServerTimeNow() + EggInteractionDefs.ClaimTimeoutSeconds
    local leaseStarted, leaseError = leases:Start(eggUid, player.UserId, expiresAt)
    if not leaseStarted then
        eggService:ReleaseClaim(eggUid, "ClaimLeaseStartFailed")
        untrackClaim(player.UserId, eggUid)
        warn("[ClaimService] Could not start timeout for " .. eggUid .. ": " .. tostring(leaseError))
        return "ServerError"
    end
    local expiryUpdated, expiryError = eggService:SetExpiresAt(eggUid, expiresAt)
    if not expiryUpdated then
        leases:Cancel(eggUid, player.UserId)
        eggService:ReleaseClaim(eggUid, "ClaimExpiryUpdateFailed")
        untrackClaim(player.UserId, eggUid)
        warn("[ClaimService] Could not publish timeout for " .. eggUid .. ": " .. tostring(expiryError))
        return "ServerError"
    end

    local breakStarted, breakError = eggBreakService:StartBreak(player, eggUid, petPower)
    if not breakStarted then
        leases:Cancel(eggUid, player.UserId)
        eggService:ReleaseClaim(eggUid, "BreakStartFailed")
        untrackClaim(player.UserId, eggUid)
        warn("[ClaimService] Could not start break for " .. eggUid .. ": " .. tostring(breakError))
        return "ServerError"
    end

    warn(
        "[ClaimService] User "
            .. tostring(player.UserId)
            .. " claimed "
            .. eggUid
            .. " at server time "
            .. tostring(expiresAt - EggInteractionDefs.ClaimTimeoutSeconds)
    )
    return "Claimed"
end

local function makeTieSeed(): number
    return Random.new():NextInteger(1, 2_000_000_000)
end

local function processPending(eggUid: string)
    batchScheduledByEggUid[eggUid] = nil
    local requests = pendingByEggUid[eggUid]
    pendingByEggUid[eggUid] = nil
    if requests == nil or #requests == 0 then
        return
    end

    local candidates = {}
    for _, request in requests do
        table.insert(candidates, { UserId = request.Player.UserId, ReceivedAt = request.ReceivedAt })
    end
    local seed = makeTieSeed()
    local winnerUserId, wasTie = EggClaimOrder.Resolve(candidates, seed)
    if winnerUserId == nil then
        for _, request in requests do
            request.Response:Fire("ServerError")
        end
        return
    end

    if wasTie then
        warn(
            "[ClaimService] Simultaneous claim tie for "
                .. eggUid
                .. "; seed="
                .. tostring(seed)
                .. "; winnerUserId="
                .. tostring(winnerUserId)
        )
    end

    local winnerResult: ResultCode = "EggUnavailable"
    for _, request in requests do
        if request.Player.UserId == winnerUserId then
            local ok, result = pcall(startClaim, request.Player, eggUid)
            if ok then
                winnerResult = result
            else
                warn("[ClaimService] Request failed for " .. eggUid .. ": " .. tostring(result))
                winnerResult = "ServerError"
            end
            break
        end
    end

    for _, request in requests do
        if request.Player.UserId == winnerUserId then
            request.Response:Fire(winnerResult)
        else
            request.Response:Fire("ClaimLostRace")
        end
    end
end

local function enqueueClaim(player: Player, eggUid: string, receivedAt: number): ResultCode
    local requests = pendingByEggUid[eggUid]
    if requests == nil then
        requests = {}
        pendingByEggUid[eggUid] = requests
    end

    local response = Instance.new("BindableEvent")
    table.insert(requests, { Player = player, ReceivedAt = receivedAt, Response = response })
    if not batchScheduledByEggUid[eggUid] then
        batchScheduledByEggUid[eggUid] = true
        task.defer(processPending, eggUid)
    end

    local result = response.Event:Wait() :: ResultCode
    response:Destroy()
    return result
end

local function handleRequest(player: Player, eggUid: string): ResultCode
    local receivedAt = Workspace:GetServerTimeNow()
    if not rateLimiter:Allow(player.UserId, receivedAt) then
        return "RateLimited"
    end
    if type(eggUid) ~= "string" or #eggUid == 0 or #eggUid > 64 then
        return "EggNotFound"
    end

    local validationCode, petPower = validateRequest(player, eggUid)
    if validationCode ~= "Claimed" or petPower == nil then
        return validationCode
    end
    return enqueueClaim(player, eggUid, receivedAt)
end

function ClaimService:KnitStart()
    eggService = Framework.GetService("EggService")
    eggBreakService = Framework.GetService("EggBreakService")
    fightService = Framework.GetService("FightService")
    dataService = Framework.GetService("DataService")

    Network.RequestEgg.SetCallback(function(player: Player, eggUid: string): ResultCode
        local ok, result = pcall(handleRequest, player, eggUid)
        if not ok then
            warn("[ClaimService] Remote request failed: " .. tostring(result))
            return "ServerError"
        end
        return result
    end)

    Players.PlayerRemoving:Connect(function(player: Player)
        rateLimiter:Forget(player.UserId)
        local claimedEggs = activeEggsByUserId[player.UserId]
        if claimedEggs == nil then
            return
        end
        local eggUids = {}
        for eggUid in claimedEggs do
            table.insert(eggUids, eggUid)
        end
        for _, eggUid in eggUids do
            self:CancelClaim(eggUid, player.UserId, "PlayerLeft")
        end
    end)
end

function ClaimService:OnEggDamaged(eggUid: string, userId: number, expiresAt: number): (boolean, string?)
    local refreshed, refreshError = leases:Refresh(eggUid, userId, expiresAt)
    if not refreshed then
        return false, refreshError
    end
    return eggService:SetExpiresAt(eggUid, expiresAt)
end

function ClaimService:OnEggHatched(eggUid: string, userId: number)
    leases:Cancel(eggUid, userId)
    eggService:ClearExpiresAt(eggUid)
    untrackClaim(userId, eggUid)
end

function ClaimService:CancelClaim(eggUid: string, userId: number, reason: string): (boolean, string?)
    local slot = eggService:GetSlot(eggUid)
    if slot == nil then
        leases:Cancel(eggUid, userId)
        untrackClaim(userId, eggUid)
        return false, "EggNotFound"
    end
    if slot.ClaimantUserId ~= userId or (slot.State ~= "Claimed" and slot.State ~= "Breaking") then
        leases:Cancel(eggUid, userId)
        untrackClaim(userId, eggUid)
        return true, nil
    end

    leases:Cancel(eggUid, userId)
    eggBreakService:StopBreak(eggUid)
    untrackClaim(userId, eggUid)
    return eggService:ReleaseClaim(eggUid, reason)
end

return ClaimService
