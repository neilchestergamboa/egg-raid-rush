--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(ReplicatedStorage.DevPackages:WaitForChild("JestGlobals") :: ModuleScript)
local Runtime = require(
    ServerScriptService:WaitForChild("ServerServices"):WaitForChild("Internal"):WaitForChild("CarryRuntime") :: ModuleScript
)

local function expectResult(expected: boolean, actual: boolean, _errorCode: string?)
    JestGlobals.expect(actual).toBe(expected)
end

local function newRecord()
    return {
        CreatureUid = "creature-1",
        EggUid = "egg-1",
        DefId = "pet_jackal_pup",
        ConditionId = "Sturdy",
        State = "Carried",
        CarrierUserId = 11,
        PreviousCarrierUserId = nil,
        PickupLockoutUntil = 0,
        DropExpiresAt = nil,
        DropPosition = nil,
        PickupReservationUserId = nil,
    }
end

JestGlobals.describe("CarryRuntime", function()
    JestGlobals.it("registers a carried creature once and rejects conflicting carriers", function()
        local runtime = Runtime.new()
        expectResult(true, runtime:Register(newRecord()))
        expectResult(true, runtime:Register(newRecord()))
        local second = newRecord()
        second.EggUid = "egg-2"
        second.CreatureUid = "creature-2"
        expectResult(false, runtime:Register(second))
    end)

    JestGlobals.it("drops, reserves, cancels, and picks up without allowing duplicate pickup", function()
        local runtime = Runtime.new()
        runtime:Register(newRecord())
        local position = Vector3.new(10, 0, 0)
        expectResult(true, runtime:Drop("egg-1", 11, position, 10, 20, 3))
        local locked, lockError = runtime:ReservePickup("egg-1", 11, 11)
        JestGlobals.expect(locked).toBe(false)
        JestGlobals.expect(lockError).toBe("PickupLockedOut")
        expectResult(true, runtime:ReservePickup("egg-1", 22, 11))
        local competing = runtime:ReservePickup("egg-1", 33, 11)
        JestGlobals.expect(competing).toBe(false)
        expectResult(true, runtime:CancelPickup("egg-1", 22))
        expectResult(true, runtime:ReservePickup("egg-1", 22, 11))
        expectResult(true, runtime:CompletePickup("egg-1", 22, 12))
        expectResult(false, runtime:CompletePickup("egg-1", 22, 12))
        JestGlobals.expect(runtime:GetForUser(22).CreatureUid).toBe("creature-1")
        JestGlobals.expect(runtime:GetForUser(11)).toBe(nil)
    end)

    JestGlobals.it("rejects expired drops and returns a creature idempotently", function()
        local runtime = Runtime.new()
        expectResult(true, runtime:Register(newRecord()))
        expectResult(true, runtime:Drop("egg-1", 11, Vector3.zero, 10, 20, 3))
        local reserved, reserveError = runtime:ReservePickup("egg-1", 22, 30)
        JestGlobals.expect(reserved).toBe(false)
        JestGlobals.expect(reserveError).toBe("DropExpired")
        expectResult(true, runtime:Return("egg-1"))
        expectResult(true, runtime:Return("egg-1"))
        JestGlobals.expect(runtime:Get("egg-1").State).toBe("Returned")
    end)

    JestGlobals.it("commits banking before cleanup and treats duplicate completion safely", function()
        local runtime = Runtime.new()
        expectResult(true, runtime:Register(newRecord()))
        expectResult(true, runtime:BeginBank("egg-1", 11))
        expectResult(true, runtime:BeginBank("egg-1", 11))
        JestGlobals.expect(runtime:CompleteBank("egg-1", 11)).toBe(true)
        JestGlobals.expect(runtime:CompleteBank("egg-1", 11)).toBe(true)
        JestGlobals.expect(runtime:GetForUser(11)).toBe(nil)
    end)
end)
