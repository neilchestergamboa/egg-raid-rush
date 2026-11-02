--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("JestGlobals") :: ModuleScript)
local ZoneDefs =
    require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ZoneDefs") :: ModuleScript)
local EggDefs =
    require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("EggDefs") :: ModuleScript)
local RarityDefs =
    require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RarityDefs") :: ModuleScript)
local EggSlotRuntime = require(
    ServerScriptService:WaitForChild("ServerServices"):WaitForChild("Internal"):WaitForChild("EggSlotRuntime") :: ModuleScript
)
local EggSlotAttributePublisher = require(
    ServerScriptService:WaitForChild("ServerServices")
        :WaitForChild("Internal")
        :WaitForChild("EggSlotAttributePublisher") :: ModuleScript
)

local function makeRuntime()
    local callbacks = {}
    local published = {}
    local logs = {}
    local now = 100
    local definitions = {}
    for _, eggDefId in ZoneDefs.Zone1.EggDefIds do
        local egg = EggDefs[eggDefId]
        table.insert(definitions, {
            Uid = eggDefId,
            DefId = eggDefId,
            ZoneId = egg.ZoneId,
            Slot = egg.Slot,
            RarityId = egg.RarityId,
            RespawnSeconds = RarityDefs[egg.RarityId].RespawnSeconds,
            IsTutorial = egg.IsTutorial,
        })
    end

    local runtime = EggSlotRuntime.new(definitions, {
        Now = function()
            return now
        end,
        Schedule = function(seconds, callback)
            table.insert(callbacks, { Seconds = seconds, Callback = callback })
        end,
        OnChanged = function(record, previousState, reason)
            table.insert(published, table.clone(record))
            if previousState ~= nil and previousState ~= record.State then
                table.insert(logs, { Uid = record.Uid, From = previousState, To = record.State, Reason = reason })
            end
        end,
    })
    return runtime, callbacks, published, logs, function(value)
        now = value
    end
end

JestGlobals.describe("EggSlotRuntime", function()
    JestGlobals.it("initializes six fixed field slots as sealed with their configured rarity", function()
        local runtime, _, published = makeRuntime()
        JestGlobals.expect(#runtime:GetAllSlots()).toBe(6)
        JestGlobals.expect(#published).toBe(6)
        for _, eggDefId in ZoneDefs.Zone1.EggDefIds do
            local slot = runtime:GetSlot(eggDefId)
            assert(slot ~= nil, "Configured egg slot should exist")
            JestGlobals.expect(slot.State).toBe("Sealed")
            JestGlobals.expect(slot.RarityId).toBe(EggDefs[eggDefId].RarityId)
            JestGlobals.expect(slot.RespawnSeconds).toBe(RarityDefs[slot.RarityId].RespawnSeconds)
        end
    end)

    JestGlobals.it("publishes current egg state as attributes for clients joining later", function()
        local runtime = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[1]
        local attributes = Instance.new("Folder")
        local slot = runtime:GetSlot(eggUid)
        assert(slot ~= nil, "Egg slot should exist before publishing attributes")
        EggSlotAttributePublisher.Publish(attributes, slot)
        JestGlobals.expect(attributes:GetAttribute("Uid")).toBe(eggUid)
        JestGlobals.expect(attributes:GetAttribute("DefId")).toBe(eggUid)
        JestGlobals.expect(attributes:GetAttribute("State")).toBe("Sealed")
        JestGlobals.expect(attributes:GetAttribute("RarityId")).toBe(EggDefs[eggUid].RarityId)
        JestGlobals.expect(attributes:GetAttribute("ClaimantUserId")).toBe(nil)

        runtime:TryClaim(eggUid, 101)
        slot = runtime:GetSlot(eggUid)
        assert(slot ~= nil, "Egg slot should exist after expiry update")
        EggSlotAttributePublisher.Publish(attributes, slot)
        JestGlobals.expect(attributes:GetAttribute("State")).toBe("Claimed")
        JestGlobals.expect(attributes:GetAttribute("ClaimantUserId")).toBe(101)
        attributes:Destroy()
    end)

    JestGlobals.it(
        "allows the first claim, treats a duplicate claim as idempotent, and rejects a competitor",
        function()
            local runtime, _, _, logs = makeRuntime()
            local eggUid = ZoneDefs.Zone1.EggDefIds[1]
            local firstClaim, firstError = runtime:TryClaim(eggUid, 101)
            local duplicateClaim = runtime:TryClaim(eggUid, 101)
            local competingClaim, competingError = runtime:TryClaim(eggUid, 202)

            JestGlobals.expect(firstClaim).toBe(true)
            JestGlobals.expect(firstError).toBe(nil)
            JestGlobals.expect(duplicateClaim).toBe(true)
            JestGlobals.expect(competingClaim).toBe(false)
            JestGlobals.expect(competingError).toBe("EggNotSealed")
            JestGlobals.expect(runtime:GetSlot(eggUid).ClaimantUserId).toBe(101)
            JestGlobals.expect(#logs).toBe(1)
        end
    )

    JestGlobals.it("rejects missing slots and invalid claimant ids", function()
        local runtime = makeRuntime()
        local missing, missingError = runtime:TryClaim("unknown", 101)
        local invalid, invalidError = runtime:TryClaim(ZoneDefs.Zone1.EggDefIds[1], 0)
        JestGlobals.expect(missing).toBe(false)
        JestGlobals.expect(missingError).toBe("EggNotFound")
        JestGlobals.expect(invalid).toBe(false)
        JestGlobals.expect(invalidError).toBe("InvalidClaimant")
    end)

    JestGlobals.it("replicates claim expiry updates and treats duplicate updates idempotently", function()
        local runtime, _, published = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[1]
        runtime:TryClaim(eggUid, 101)
        local afterClaimCount = #published
        local updated, updateError = runtime:SetExpiresAt(eggUid, 150)
        local duplicateUpdate = runtime:SetExpiresAt(eggUid, 150)
        local slot = runtime:GetSlot(eggUid)
        assert(slot ~= nil, "Egg slot should exist before checking expiry")

        JestGlobals.expect(updated).toBe(true)
        JestGlobals.expect(updateError).toBe(nil)
        JestGlobals.expect(duplicateUpdate).toBe(true)
        JestGlobals.expect(slot.ExpiresAt).toBe(150)
        JestGlobals.expect(#published).toBe(afterClaimCount + 1)

        local runtime2 = makeRuntime()
        local sealedUpdate, sealedError = runtime2:SetExpiresAt(eggUid, 150)
        JestGlobals.expect(sealedUpdate).toBe(false)
        JestGlobals.expect(sealedError).toBe("EggNotClaimed")
    end)

    JestGlobals.it("clears the claim expiry idempotently when a break reaches the fight", function()
        local runtime, _, published = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[1]
        runtime:TryClaim(eggUid, 101)
        runtime:SetExpiresAt(eggUid, 150)
        runtime:Transition(eggUid, "Breaking")
        runtime:Transition(eggUid, "Fighting")

        local cleared, clearError = runtime:ClearExpiresAt(eggUid)
        local duplicateClear = runtime:ClearExpiresAt(eggUid)
        local slot = runtime:GetSlot(eggUid)
        assert(slot ~= nil, "Egg slot should remain available while fighting")
        JestGlobals.expect(cleared).toBe(true)
        JestGlobals.expect(clearError).toBe(nil)
        JestGlobals.expect(duplicateClear).toBe(true)
        JestGlobals.expect(slot.ExpiresAt).toBe(nil)
        JestGlobals.expect(#published).toBe(11)
    end)

    JestGlobals.it("releases claimed and breaking eggs to sealed and tolerates duplicate releases", function()
        local runtime, _, _, logs = makeRuntime()
        local claimedUid = ZoneDefs.Zone1.EggDefIds[1]
        local breakingUid = ZoneDefs.Zone1.EggDefIds[2]
        runtime:TryClaim(claimedUid, 101)
        runtime:SetExpiresAt(claimedUid, 160)
        runtime:TryClaim(breakingUid, 202)
        runtime:Transition(breakingUid, "Breaking")

        local releasedClaim = runtime:ReleaseClaim(claimedUid, "PlayerLeft")
        local duplicateRelease = runtime:ReleaseClaim(claimedUid, "PlayerLeft")
        local releasedBreak = runtime:ReleaseClaim(breakingUid, "ClaimTimeout")

        JestGlobals.expect(releasedClaim).toBe(true)
        JestGlobals.expect(duplicateRelease).toBe(true)
        JestGlobals.expect(releasedBreak).toBe(true)
        JestGlobals.expect(runtime:GetSlot(claimedUid).State).toBe("Sealed")
        JestGlobals.expect(runtime:GetSlot(claimedUid).ClaimantUserId).toBe(nil)
        JestGlobals.expect(runtime:GetSlot(claimedUid).ExpiresAt).toBe(nil)
        JestGlobals.expect(runtime:GetSlot(breakingUid).State).toBe("Sealed")
        JestGlobals.expect(#logs).toBe(7)
        JestGlobals.expect(logs[4].To).toBe("Released")
        JestGlobals.expect(logs[5].From).toBe("Released")
        JestGlobals.expect(logs[6].To).toBe("Released")
        JestGlobals.expect(logs[7].From).toBe("Released")
    end)

    JestGlobals.it("rejects an invalid transition and a release after fighting starts", function()
        local runtime = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[1]
        local invalidTransition, invalidTransitionError = runtime:Transition(eggUid, "Fighting")
        runtime:TryClaim(eggUid, 101)
        runtime:Transition(eggUid, "Breaking")
        runtime:Transition(eggUid, "Fighting")
        local invalidRelease, invalidReleaseError = runtime:ReleaseClaim(eggUid, "PlayerLeft")
        JestGlobals.expect(invalidTransition).toBe(false)
        JestGlobals.expect(invalidTransitionError).toBe("InvalidEggStateTransition")
        JestGlobals.expect(invalidRelease).toBe(false)
        JestGlobals.expect(invalidReleaseError).toBe("EggCannotBeReleased")
    end)

    JestGlobals.it("logs the lifecycle transitions and schedules one configured respawn after banking", function()
        local runtime, callbacks, _, logs, setNow = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[1]
        runtime:TryClaim(eggUid, 101)
        runtime:Transition(eggUid, "Breaking")
        runtime:Transition(eggUid, "Fighting")
        runtime:Transition(eggUid, "Won")
        runtime:Transition(eggUid, "Carried")
        local banked = runtime:Transition(eggUid, "Banked")
        local duplicateBank = runtime:Transition(eggUid, "Banked")

        JestGlobals.expect(banked).toBe(true)
        JestGlobals.expect(duplicateBank).toBe(true)
        JestGlobals.expect(runtime:GetSlot(eggUid).State).toBe("Respawning")
        JestGlobals.expect(runtime:GetSlot(eggUid).ClaimantUserId).toBe(nil)
        JestGlobals.expect(runtime:GetSlot(eggUid).ExpiresAt).toBe(125)
        JestGlobals.expect(#callbacks).toBe(1)
        JestGlobals.expect(callbacks[1].Seconds).toBe(25)
        JestGlobals.expect(logs[#logs].From).toBe("Banked")
        JestGlobals.expect(logs[#logs].To).toBe("Respawning")

        setNow(124)
        callbacks[1].Callback()
        JestGlobals.expect(runtime:GetSlot(eggUid).State).toBe("Respawning")
        JestGlobals.expect(#callbacks).toBe(2)
        JestGlobals.expect(callbacks[2].Seconds).toBe(1)
        setNow(125)
        callbacks[2].Callback()
        JestGlobals.expect(runtime:GetSlot(eggUid).State).toBe("Sealed")
        JestGlobals.expect(runtime:GetSlot(eggUid).ExpiresAt).toBe(nil)
    end)

    JestGlobals.it("respawns after a loss and ignores a stale duplicate callback", function()
        local runtime, callbacks, _, _, setNow = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[3]
        runtime:TryClaim(eggUid, 101)
        runtime:Transition(eggUid, "Breaking")
        runtime:Transition(eggUid, "Fighting")
        runtime:Transition(eggUid, "Lost")
        local duplicateLoss = runtime:Transition(eggUid, "Lost")
        JestGlobals.expect(duplicateLoss).toBe(true)
        JestGlobals.expect(#callbacks).toBe(1)
        JestGlobals.expect(callbacks[1].Seconds).toBe(RarityDefs.Uncommon.RespawnSeconds)
        setNow(140)
        callbacks[1].Callback()
        JestGlobals.expect(runtime:GetSlot(eggUid).State).toBe("Sealed")
        callbacks[1].Callback()
        JestGlobals.expect(runtime:GetSlot(eggUid).State).toBe("Sealed")
    end)

    JestGlobals.it("assigns a stable creature id, drops it, and permits one new carrier", function()
        local runtime, _, published = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[1]
        runtime:TryClaim(eggUid, 101)
        runtime:Transition(eggUid, "Breaking")
        runtime:Transition(eggUid, "Fighting")
        runtime:Transition(eggUid, "Won")

        local creatureUid = runtime:AssignCreatureUid(eggUid, 101, "capture-abc")
        local duplicateUid = runtime:AssignCreatureUid(eggUid, 101, "capture-other")
        JestGlobals.expect(creatureUid).toBe("capture-abc")
        JestGlobals.expect(duplicateUid).toBe("capture-abc")
        JestGlobals.expect(runtime:SetCarrier(eggUid, 101, "capture-abc")).toBe(true)
        local dropped = runtime:DropCreature(eggUid, 101, Vector3.new(4, 0, 1), 130, 113)
        JestGlobals.expect(dropped).toBe(true)
        local slot = runtime:GetSlot(eggUid)
        JestGlobals.expect(slot.State).toBe("Dropped")
        JestGlobals.expect(slot.PreviousCarrierUserId).toBe(101)
        JestGlobals.expect(slot.DropPosition).toBe(Vector3.new(4, 0, 1))

        JestGlobals.expect(runtime:SetCarrier(eggUid, 202, "capture-abc")).toBe(true)
        slot = runtime:GetSlot(eggUid)
        JestGlobals.expect(slot.State).toBe("Carried")
        JestGlobals.expect(slot.CarrierUserId).toBe(202)
        JestGlobals.expect(slot.CreatureUid).toBe("capture-abc")
        JestGlobals.expect(published[#published].CarrierUserId).toBe(202)
    end)

    JestGlobals.it("returns a carried creature to the field idempotently on disconnect", function()
        local runtime = makeRuntime()
        local eggUid = ZoneDefs.Zone1.EggDefIds[1]
        runtime:TryClaim(eggUid, 101)
        runtime:Transition(eggUid, "Breaking")
        runtime:Transition(eggUid, "Fighting")
        runtime:Transition(eggUid, "Won")
        runtime:AssignCreatureUid(eggUid, 101, "capture-return")
        runtime:SetCarrier(eggUid, 101, "capture-return")

        JestGlobals.expect(runtime:ReturnCreature(eggUid)).toBe(true)
        JestGlobals.expect(runtime:ReturnCreature(eggUid)).toBe(true)
        local slot = runtime:GetSlot(eggUid)
        JestGlobals.expect(slot.State).toBe("Sealed")
        JestGlobals.expect(slot.CreatureUid).toBe(nil)
        JestGlobals.expect(slot.ConditionRoll).toBe(nil)
    end)

    JestGlobals.it(
        "keeps one player's committed condition through release and prevents another player's reroll",
        function()
            local runtime = makeRuntime()
            local eggUid = ZoneDefs.Zone1.EggDefIds[1]
            runtime:TryClaim(eggUid, 101)
            local committed = runtime:CommitHatch(eggUid, 101, "starter-101", 120, "Sturdy", 321)
            JestGlobals.expect(committed).toBe(true)
            runtime:ReleaseClaim(eggUid, "PlayerLeft")
            runtime:TryClaim(eggUid, 101)
            runtime:CommitHatch(eggUid, 101, "starter-101", 120, "Flawless", 999)
            local resumed = runtime:GetSlot(eggUid)
            JestGlobals.expect(resumed.ConditionRoll).toBe("Sturdy")
            JestGlobals.expect(resumed.ConditionSeed).toBe(321)
            runtime:ReleaseClaim(eggUid, "Timeout")
            runtime:TryClaim(eggUid, 202)
            runtime:CommitHatch(eggUid, 202, "starter-202", 120, "Cracked", 654)
            local newOwner = runtime:GetSlot(eggUid)
            JestGlobals.expect(newOwner.ConditionRoll).toBe("Cracked")
            JestGlobals.expect(newOwner.ConditionRollOwnerUserId).toBe(202)
        end
    )
end)
