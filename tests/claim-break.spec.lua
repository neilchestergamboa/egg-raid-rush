--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = Shared:WaitForChild("Rules")
local EggBreak = require(Rules:WaitForChild("EggBreak") :: ModuleScript)
local EggClaimOrder = require(Rules:WaitForChild("EggClaimOrder") :: ModuleScript)
local EggInteractionDefs = require(Shared:WaitForChild("Config"):WaitForChild("EggInteractionDefs") :: ModuleScript)
local ServerServices = ServerScriptService:WaitForChild("ServerServices")
local Internal = ServerServices:WaitForChild("Internal")
local ClaimValidation = require(Internal:WaitForChild("ClaimValidation") :: ModuleScript)
local ClaimLeaseRuntime = require(Internal:WaitForChild("ClaimLeaseRuntime") :: ModuleScript)
local PlayerRateLimiter = require(Internal:WaitForChild("PlayerRateLimiter") :: ModuleScript)
local JestGlobals = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("JestGlobals") :: ModuleScript)

JestGlobals.describe("Egg break rules", function()
    JestGlobals.it("applies damage over elapsed time and clamps health at zero", function()
        JestGlobals.expect(EggBreak.ApplyDamage(960, 960, 120, 0.5)).toBe(900)
        JestGlobals.expect(EggBreak.ApplyDamage(10, 10, 50, 1)).toBe(0)
    end)

    JestGlobals.it("maps full, 75%, 50%, and 25% health to configured crack stages", function()
        local thresholds = EggInteractionDefs.CrackHealthThresholds
        JestGlobals.expect(EggBreak.CalculateCrackStage(100, 100, thresholds)).toBe(1)
        JestGlobals.expect(EggBreak.CalculateCrackStage(75, 100, thresholds)).toBe(2)
        JestGlobals.expect(EggBreak.CalculateCrackStage(50, 100, thresholds)).toBe(3)
        JestGlobals.expect(EggBreak.CalculateCrackStage(25, 100, thresholds)).toBe(4)
        JestGlobals.expect(EggBreak.CalculateCrackStage(0, 100, thresholds)).toBe(4)
    end)
end)

JestGlobals.describe("Claim validation", function()
    local function validContext()
        return {
            EggExists = true,
            EggState = "Sealed",
            EggObjectExists = true,
            HasCharacter = true,
            IsWithinRange = true,
            IsCarryingCreature = false,
            IsFighting = false,
            HasProfile = true,
            ChampionPet = { Power = 120, KnockedOutUntil = 0 },
            Now = 100,
        }
    end

    JestGlobals.it("accepts a ready equipped pet and returns its server profile power", function()
        local code, petPower = ClaimValidation.Validate(validContext())
        JestGlobals.expect(code).toBe("Claimed")
        JestGlobals.expect(petPower).toBe(120)
    end)

    JestGlobals.it("rejects missing or unavailable eggs and missing map objects", function()
        local context = validContext()
        context.EggExists = false
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("EggNotFound")
        context = validContext()
        context.EggState = "Claimed"
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("EggUnavailable")
        context = validContext()
        context.EggObjectExists = false
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("EggObjectUnavailable")
    end)

    JestGlobals.it("blocks a second claim while the player already has an active fight", function()
        local context = validContext()
        context.IsFighting = true
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("FightInProgress")
    end)

    JestGlobals.it("rejects out-of-range, carrying, unready, unequipped, and recovering players", function()
        local context = validContext()
        context.HasCharacter = false
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("NoCharacter")
        context = validContext()
        context.IsWithinRange = false
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("TooFar")
        context = validContext()
        context.IsCarryingCreature = true
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("CarryingCreature")
        context = validContext()
        context.HasProfile = false
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("ProfileNotReady")
        context = validContext()
        context.ChampionPet = nil
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("NoPetEquipped")
        context = validContext()
        context.ChampionPet.KnockedOutUntil = 101
        JestGlobals.expect(ClaimValidation.Validate(context)).toBe("PetRecovering")
    end)
end)

JestGlobals.describe("Claim request rate limit", function()
    JestGlobals.it("limits requests per player and allows them again after the configured interval", function()
        local limiter = PlayerRateLimiter.new(EggInteractionDefs.RequestRateLimitSeconds)
        JestGlobals.expect(limiter:Allow(10, 100)).toBe(true)
        JestGlobals.expect(limiter:Allow(10, 100.1)).toBe(false)
        JestGlobals.expect(limiter:Allow(20, 100.1)).toBe(true)
        JestGlobals.expect(limiter:Allow(10, 100.25)).toBe(true)
        limiter:Forget(10)
        JestGlobals.expect(limiter:Allow(10, 100.26)).toBe(true)
    end)
end)

JestGlobals.describe("Simultaneous claim ordering", function()
    JestGlobals.it("selects the earliest server receipt timestamp", function()
        local winner, wasTie = EggClaimOrder.Resolve({
            { UserId = 10, ReceivedAt = 10.01 },
            { UserId = 20, ReceivedAt = 10.02 },
        }, 1234)
        JestGlobals.expect(winner).toBe(10)
        JestGlobals.expect(wasTie).toBe(false)
    end)

    JestGlobals.it("resolves exact server-time ties reproducibly from the logged seed", function()
        local candidates = {
            { UserId = 10, ReceivedAt = 10 },
            { UserId = 20, ReceivedAt = 10 },
            { UserId = 30, ReceivedAt = 11 },
        }
        local firstWinner, firstWasTie = EggClaimOrder.Resolve(candidates, 1234)
        local replayWinner, replayWasTie = EggClaimOrder.Resolve(candidates, 1234)
        JestGlobals.expect(firstWasTie).toBe(true)
        JestGlobals.expect(replayWasTie).toBe(true)
        JestGlobals.expect(replayWinner).toBe(firstWinner)
    end)
end)

JestGlobals.describe("Claim timeout lease", function()
    local function makeLease()
        local now = 100
        local callbacks = {}
        local expired = {}
        local lease = ClaimLeaseRuntime.new({
            Now = function()
                return now
            end,
            Schedule = function(seconds, callback)
                table.insert(callbacks, { Seconds = seconds, Callback = callback })
            end,
            OnExpired = function(eggUid, userId)
                table.insert(expired, { EggUid = eggUid, UserId = userId })
            end,
        })
        return lease, callbacks, expired, function(value)
            now = value
        end
    end

    JestGlobals.it("expires a claim after the no-damage timeout", function()
        local lease, callbacks, expired, setNow = makeLease()
        local started, startError = lease:Start("egg_z1_slot_1", 10, 160)
        JestGlobals.expect(started).toBe(true)
        JestGlobals.expect(startError).toBe(nil)
        JestGlobals.expect(callbacks[1].Seconds).toBe(EggInteractionDefs.ClaimTimeoutSeconds)
        setNow(160)
        callbacks[1].Callback()
        JestGlobals.expect(#expired).toBe(1)
        JestGlobals.expect(expired[1].EggUid).toBe("egg_z1_slot_1")
        JestGlobals.expect(expired[1].UserId).toBe(10)
    end)

    JestGlobals.it("refreshes after damage, reschedules the old timer, and expires exactly once", function()
        local lease, callbacks, expired, setNow = makeLease()
        lease:Start("egg_z1_slot_1", 10, 160)
        local refreshed, refreshError = lease:Refresh("egg_z1_slot_1", 10, 220)
        JestGlobals.expect(refreshed).toBe(true)
        JestGlobals.expect(refreshError).toBe(nil)
        setNow(160)
        callbacks[1].Callback()
        JestGlobals.expect(#expired).toBe(0)
        JestGlobals.expect(callbacks[2].Seconds).toBe(60)
        setNow(220)
        callbacks[2].Callback()
        callbacks[2].Callback()
        JestGlobals.expect(#expired).toBe(1)
        JestGlobals.expect(expired[1].UserId).toBe(10)
    end)

    JestGlobals.it("ignores stale callbacks after a lease is cancelled", function()
        local lease, callbacks, expired = makeLease()
        lease:Start("egg_z1_slot_1", 10, 160)
        JestGlobals.expect(lease:Cancel("egg_z1_slot_1", 10)).toBe(true)
        callbacks[1].Callback()
        JestGlobals.expect(#expired).toBe(0)
    end)
end)
