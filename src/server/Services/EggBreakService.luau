--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local ConfigFolder = Shared:WaitForChild("Config")
local ZoneDefs = require(ConfigFolder:WaitForChild("ZoneDefs") :: ModuleScript)
local EggDefs = require(ConfigFolder:WaitForChild("EggDefs") :: ModuleScript)
local RarityDefs = require(ConfigFolder:WaitForChild("RarityDefs") :: ModuleScript)
local EggInteractionDefs = require(ConfigFolder:WaitForChild("EggInteractionDefs") :: ModuleScript)
local RulesFolder = Shared:WaitForChild("Rules")
local EggDamage = require(RulesFolder:WaitForChild("EggDamage") :: ModuleScript)
local EggBreak = require(RulesFolder:WaitForChild("EggBreak") :: ModuleScript)

local EggBreakService = Framework.CreateService({ Name = "EggBreakService", Client = {} })
local eggService: any = nil
local claimService: any = nil
local activeBreaks: { [string]: any } = {}

local function findZoneRecommendedPetPower(zoneId: number): number?
    for _, zone in pairs(ZoneDefs) do
        if zone.Id == zoneId then
            return zone.RecommendedPetPower
        end
    end
    return nil
end

local function runBreak(eggUid: string, run: any)
    local accumulatedSeconds = 0
    while activeBreaks[eggUid] == run do
        local deltaSeconds = RunService.Heartbeat:Wait()
        if activeBreaks[eggUid] ~= run then
            break
        end

        local slot = eggService:GetSlot(eggUid)
        if slot == nil or slot.State ~= "Breaking" or slot.ClaimantUserId ~= run.Player.UserId then
            break
        end
        if not run.Player:IsDescendantOf(Players) then
            claimService:CancelClaim(eggUid, run.Player.UserId, "PlayerLeft")
            break
        end

        accumulatedSeconds += deltaSeconds
        if accumulatedSeconds < EggInteractionDefs.DamageUpdateIntervalSeconds then
            continue
        end

        local elapsedSeconds = accumulatedSeconds
        accumulatedSeconds = 0
        run.Health = EggBreak.ApplyDamage(run.Health, run.MaxHealth, run.DamagePerSecond, elapsedSeconds)
        local crackStage =
            EggBreak.CalculateCrackStage(run.Health, run.MaxHealth, EggInteractionDefs.CrackHealthThresholds)
        local progressUpdated, progressError =
            eggService:SetBreakProgress(eggUid, run.Health, run.MaxHealth, crackStage)
        if not progressUpdated then
            warn("[EggBreakService] Could not publish break progress for " .. eggUid .. ": " .. tostring(progressError))
            break
        end

        local newExpiresAt = Workspace:GetServerTimeNow() + EggInteractionDefs.ClaimTimeoutSeconds
        local leaseRefreshed, leaseError = claimService:OnEggDamaged(eggUid, run.Player.UserId, newExpiresAt)
        if not leaseRefreshed then
            warn("[EggBreakService] Could not refresh claim timeout for " .. eggUid .. ": " .. tostring(leaseError))
            break
        end

        if run.Health <= 0 then
            local transitioned, transitionError = eggService:Transition(eggUid, "Fighting")
            if not transitioned then
                warn("[EggBreakService] Could not hatch " .. eggUid .. ": " .. tostring(transitionError))
                break
            end
            claimService:OnEggHatched(eggUid, run.Player.UserId)
            break
        end
    end

    if activeBreaks[eggUid] == run then
        activeBreaks[eggUid] = nil
    end
end

function EggBreakService:KnitStart()
    eggService = Framework.GetService("EggService")
    claimService = Framework.GetService("ClaimService")
end

function EggBreakService:StartBreak(player: Player, eggUid: string, petPower: number): (boolean, string?)
    if activeBreaks[eggUid] ~= nil then
        return false, "EggBreakAlreadyRunning"
    end
    local slot = eggService:GetSlot(eggUid)
    local egg = EggDefs[eggUid]
    if slot == nil or type(egg) ~= "table" then
        return false, "EggNotFound"
    end
    if slot.State ~= "Claimed" or slot.ClaimantUserId ~= player.UserId then
        return false, "EggNotClaimedByPlayer"
    end
    if type(petPower) ~= "number" or petPower <= 0 or petPower ~= petPower or petPower == math.huge then
        return false, "InvalidPetPower"
    end

    local zonePower = findZoneRecommendedPetPower(slot.ZoneId)
    local rarity = RarityDefs[egg.RarityId]
    if zonePower == nil or type(rarity) ~= "table" then
        return false, "EggConfigMissing"
    end
    local recommendedPetPower = zonePower * rarity.PowerMultiplier
    local damagePerSecond = EggDamage.CalculateDamagePerSecond(petPower, recommendedPetPower)
    local transitioned, transitionError = eggService:Transition(eggUid, "Breaking")
    if not transitioned then
        return false, transitionError
    end

    local run = {
        Player = player,
        Health = egg.Health,
        MaxHealth = egg.Health,
        DamagePerSecond = damagePerSecond,
    }
    activeBreaks[eggUid] = run
    local initialized, initializeError = eggService:SetBreakProgress(
        eggUid,
        run.Health,
        run.MaxHealth,
        EggBreak.CalculateCrackStage(run.Health, run.MaxHealth, EggInteractionDefs.CrackHealthThresholds)
    )
    if not initialized then
        activeBreaks[eggUid] = nil
        eggService:ReleaseClaim(eggUid, "BreakInitializationFailed")
        return false, initializeError
    end

    task.spawn(runBreak, eggUid, run)
    return true, nil
end

function EggBreakService:StopBreak(eggUid: string)
    activeBreaks[eggUid] = nil
end

return EggBreakService
