--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local Config = Shared:WaitForChild("Config")
local EggDefs = require(Config:WaitForChild("EggDefs") :: ModuleScript)
local ConditionDefs = require(Config:WaitForChild("ConditionDefs") :: ModuleScript)
local FightDefs = require(Config:WaitForChild("FightDefs") :: ModuleScript)
local Rules = Shared:WaitForChild("Rules")
local ConditionRoll = require(Rules:WaitForChild("ConditionRoll") :: ModuleScript)
local FightSim = require(Rules:WaitForChild("FightSim") :: ModuleScript)
local Internal = script.Parent:WaitForChild("Internal")
local PlayerRateLimiter = require(Internal:WaitForChild("PlayerRateLimiter") :: ModuleScript)
local FightRuntime = require(Internal:WaitForChild("FightRuntime") :: ModuleScript)
local Network = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("server") :: ModuleScript)

type FightResultCode = "Retreated" | "FightNotActive" | "RateLimited" | "ServerError"
type ActiveFight = {
    UserId: number,
    PetUid: string,
    PetPower: number,
    HatchlingPower: number,
    Seed: number,
    StartedAt: number,
    Simulated: any,
    Retreated: boolean,
    ProvisionalKnockout: boolean,
}

local FightService = Framework.CreateService({ Name = "FightService", Client = {} })
local eggService: any = nil
local dataService: any = nil
local fightRuntime = FightRuntime.new()
local retreatLimiter = PlayerRateLimiter.new(FightDefs.RetreatRateLimitSeconds)

local function newSeed(): number
    return Random.new():NextInteger(1, 2_000_000_000)
end

local function findEggDef(eggUid: string): any?
    return EggDefs[eggUid]
end

local function interpolate(
    history: { any },
    elapsedSeconds: number,
    petMaxHp: number,
    hatchlingMaxHp: number
): (number, number)
    local previousTime = 0
    local previousPetHp = petMaxHp
    local previousHatchlingHp = hatchlingMaxHp
    for _, snapshot in history do
        if elapsedSeconds <= snapshot.ElapsedSeconds then
            local span = snapshot.ElapsedSeconds - previousTime
            local alpha = if span <= 0 then 1 else math.clamp((elapsedSeconds - previousTime) / span, 0, 1)
            local petHp = previousPetHp + (snapshot.PetHp - previousPetHp) * alpha
            local hatchlingHp = previousHatchlingHp + (snapshot.HatchlingHp - previousHatchlingHp) * alpha
            return math.max(0, petHp), math.max(0, hatchlingHp)
        end
        previousTime = snapshot.ElapsedSeconds
        previousPetHp = snapshot.PetHp
        previousHatchlingHp = snapshot.HatchlingHp
    end
    local last = history[#history]
    return last.PetHp, last.HatchlingHp
end

local function publishFight(eggUid: string, fight: ActiveFight, elapsed: number, status: string, result: string?)
    local petMaxHp = FightDefs.HealthPerPower * fight.PetPower
    local hatchlingMaxHp = FightDefs.HealthPerPower * fight.HatchlingPower
    local petHp, hatchlingHp = interpolate(fight.Simulated.History, elapsed, petMaxHp, hatchlingMaxHp)
    local updated, updateError = eggService:SetFightSnapshot(eggUid, {
        ElapsedSeconds = math.min(elapsed, fight.Simulated.DurationSeconds),
        DurationSeconds = fight.Simulated.DurationSeconds,
        PetHp = petHp,
        PetMaxHp = petMaxHp,
        HatchlingHp = hatchlingHp,
        HatchlingMaxHp = hatchlingMaxHp,
        Seed = fight.Seed,
        Status = status,
        Result = result,
    })
    if not updated then
        warn("[FightService] Could not publish fight snapshot for " .. eggUid .. ": " .. tostring(updateError))
    end
end

local function runFight(eggUid: string, fight: ActiveFight)
    while fightRuntime:Get(eggUid) == fight do
        local slot = eggService:GetSlot(eggUid)
        if fight.Retreated or slot == nil or slot.State ~= "Fighting" then
            fightRuntime:Finish(eggUid, fight)
            return
        end
        local elapsed = Workspace:GetServerTimeNow() - fight.StartedAt
        if elapsed >= fight.Simulated.DurationSeconds then
            break
        end
        publishFight(eggUid, fight, elapsed, "Fighting", nil)
        task.wait(FightDefs.SnapshotIntervalSeconds)
    end

    if fightRuntime:Get(eggUid) ~= fight or fight.Retreated then
        return
    end
    local winner = fight.Simulated.Winner
    if winner == "Hatchling" then
        local player = Players:GetPlayerByUserId(fight.UserId)
        if player ~= nil then
            local knockedOutUntil = fight.StartedAt
                + fight.Simulated.DurationSeconds
                + FightDefs.KnockoutRecoverySeconds
            local saved, saveError = dataService:SetPetKnockedOutUntil(player, fight.PetUid, knockedOutUntil)
            if not saved then
                warn("[FightService] Could not persist pet recovery for " .. eggUid .. ": " .. tostring(saveError))
                player:Kick("Your pet recovery could not be saved safely. Please rejoin.")
            end
        end
    end

    local resultState = if winner == "Pet" then "Won" else "Lost"
    publishFight(eggUid, fight, fight.Simulated.DurationSeconds, resultState, winner)
    fightRuntime:Finish(eggUid, fight)
    local cleared, clearError = dataService:ClearHatchRoll(fight.UserId, eggUid)
    if not cleared and clearError ~= "ProfileNotLoaded" then
        warn("[FightService] Could not clear committed hatch roll for " .. eggUid .. ": " .. tostring(clearError))
    end
    local transitioned, transitionError = eggService:Transition(eggUid, resultState)
    if not transitioned then
        warn("[FightService] Could not finish fight for " .. eggUid .. ": " .. tostring(transitionError))
    end
    warn(
        "[FightService] Completed "
            .. eggUid
            .. "; winner="
            .. winner
            .. "; seed="
            .. tostring(fight.Seed)
            .. "; duration="
            .. tostring(fight.Simulated.DurationSeconds)
            .. "; simultaneousKnockout="
            .. tostring(fight.Simulated.WasTieBreak)
            .. "; tieBreakSeed="
            .. tostring(fight.Simulated.TieBreakSeed)
    )
end

local function handleRetreat(player: Player, eggUid: string): FightResultCode
    local now = Workspace:GetServerTimeNow()
    if not retreatLimiter:Allow(player.UserId, now) then
        return "RateLimited"
    end
    local fight = fightRuntime:Get(eggUid) :: ActiveFight?
    if fight == nil or fight.UserId ~= player.UserId or fight.Retreated then
        return "FightNotActive"
    end
    local retreatedFight = fightRuntime:Retreat(eggUid, player.UserId) :: ActiveFight?
    if retreatedFight == nil then
        return "FightNotActive"
    end
    if fight.ProvisionalKnockout then
        local playerPetReset, resetError = dataService:SetPetKnockedOutUntil(player, fight.PetUid, 0)
        if not playerPetReset then
            warn("[FightService] Could not clear provisional recovery after retreat: " .. tostring(resetError))
        end
    end
    local transitioned, transitionError = eggService:Transition(eggUid, "Lost")
    if not transitioned then
        warn("[FightService] Retreat transition failed for " .. eggUid .. ": " .. tostring(transitionError))
        return "ServerError"
    end
    dataService:ClearHatchRoll(player.UserId, eggUid)
    return "Retreated"
end

function FightService:KnitStart()
    eggService = Framework.GetService("EggService")
    dataService = Framework.GetService("DataService")
    Network.RetreatEgg.SetCallback(function(player: Player, eggUid: string): FightResultCode
        if type(eggUid) ~= "string" or #eggUid == 0 or #eggUid > 64 then
            return "FightNotActive"
        end
        local ok, result = pcall(handleRetreat, player, eggUid)
        if not ok then
            warn("[FightService] Retreat remote failed: " .. tostring(result))
            return "ServerError"
        end
        return result
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        retreatLimiter:Forget(player.UserId)
    end)
end

function FightService:CommitCondition(eggUid: string, userId: number): (boolean, string?)
    local slot = eggService:GetSlot(eggUid)
    local egg = findEggDef(eggUid)
    if slot == nil or type(egg) ~= "table" or slot.State ~= "Claimed" or slot.ClaimantUserId ~= userId then
        return false, "EggNotClaimedByPlayer"
    end
    local player = Players:GetPlayerByUserId(userId)
    if player == nil then
        return false, "PlayerNotConnected"
    end
    local profile = dataService:GetProfileData(player)
    local petUid = if profile == nil then nil else profile.ChampionPetUid
    local pet = if type(petUid) == "string" and type(profile.Pets) == "table" then profile.Pets[petUid] else nil
    if type(pet) ~= "table" or type(pet.Power) ~= "number" then
        return false, "ChampionPetUnavailable"
    end
    local proposedSeed = slot.ConditionSeed or newSeed()
    local proposedCondition = slot.ConditionRoll or ConditionRoll.Roll(ConditionDefs, proposedSeed)
    local persistentRoll, rollError = dataService:GetOrCreateHatchRoll(player, eggUid, proposedCondition, proposedSeed)
    if persistentRoll == nil then
        return false, rollError
    end
    local conditionId = persistentRoll.ConditionId
    local conditionSeed = persistentRoll.Seed
    local committed, commitError = eggService:CommitHatch(eggUid, userId, petUid, pet.Power, conditionId, conditionSeed)
    if not committed then
        return false, commitError
    end
    if slot.ConditionRollOwnerUserId ~= userId then
        warn(
            "[FightService] Committed hatch condition for "
                .. eggUid
                .. "; condition="
                .. conditionId
                .. "; seed="
                .. tostring(conditionSeed)
        )
    end
    return true, nil
end

function FightService:IsUserFighting(userId: number): boolean
    return fightRuntime:GetForUser(userId) ~= nil
end

function FightService:StartFight(eggUid: string, userId: number): (boolean, string?)
    if fightRuntime:Get(eggUid) ~= nil then
        return false, "FightAlreadyRunning"
    end
    if fightRuntime:GetForUser(userId) ~= nil then
        return false, "PlayerAlreadyFighting"
    end
    local slot = eggService:GetSlot(eggUid)
    local egg = findEggDef(eggUid)
    if slot == nil or type(egg) ~= "table" or slot.State ~= "Fighting" or slot.ClaimantUserId ~= userId then
        return false, "EggNotReadyForFight"
    end
    local petUid = slot.ClaimedPetUid
    local petPower = slot.ClaimedPetPower
    if slot.ConditionRoll == nil or petUid == nil or petPower == nil then
        return false, "HatchDataNotCommitted"
    end
    local condition = ConditionDefs[slot.ConditionRoll]
    if type(condition) ~= "table" then
        return false, "ConditionConfigMissing"
    end
    local hatchlingPower = egg.HatchlingPower * condition.PowerMultiplier
    local seed = newSeed()
    local simulation = FightSim.Simulate(petPower, hatchlingPower, seed, {
        TickSeconds = FightDefs.TickSeconds,
        DamageVariance = FightDefs.DamageVariance,
        HealthPerPower = FightDefs.HealthPerPower,
    })
    local startedAt = Workspace:GetServerTimeNow()
    if simulation.Winner == "Hatchling" then
        local player = Players:GetPlayerByUserId(userId)
        if player == nil then
            return false, "PlayerNotConnected"
        end
        local knockedOutUntil = startedAt + simulation.DurationSeconds + FightDefs.KnockoutRecoverySeconds
        local saved, saveError = dataService:SetPetKnockedOutUntil(player, petUid, knockedOutUntil)
        if not saved then
            return false, saveError
        end
    end
    local fight: ActiveFight = {
        UserId = userId,
        PetUid = petUid,
        PetPower = petPower,
        HatchlingPower = hatchlingPower,
        Seed = seed,
        StartedAt = startedAt,
        Simulated = simulation,
        Retreated = false,
        ProvisionalKnockout = simulation.Winner == "Hatchling",
    }
    local started, startError = fightRuntime:Start(eggUid, fight)
    if not started then
        if fight.ProvisionalKnockout then
            local player = Players:GetPlayerByUserId(userId)
            if player ~= nil then
                dataService:SetPetKnockedOutUntil(player, petUid, 0)
            end
        end
        return false, startError
    end
    publishFight(eggUid, fight, 0, "Fighting", nil)
    warn(
        "[FightService] Started "
            .. eggUid
            .. "; petPower="
            .. tostring(fight.PetPower)
            .. "; hatchlingPower="
            .. tostring(hatchlingPower)
            .. "; seed="
            .. tostring(seed)
    )
    task.spawn(runFight, eggUid, fight)
    return true, nil
end

return FightService
