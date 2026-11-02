--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("JestGlobals") :: ModuleScript)
local FightRuntime = require(
    ServerScriptService:WaitForChild("ServerServices"):WaitForChild("Internal"):WaitForChild("FightRuntime") :: ModuleScript
)

JestGlobals.describe("FightRuntime", function()
    JestGlobals.it("allows one active fight per player and rejects duplicates", function()
        local runtime = FightRuntime.new()
        local fight = { UserId = 101, Retreated = false }
        local started = runtime:Start("egg_z1_slot_1", fight)
        local duplicateEgg, duplicateEggError = runtime:Start("egg_z1_slot_1", { UserId = 202, Retreated = false })
        local duplicatePlayer, duplicatePlayerError =
            runtime:Start("egg_z1_slot_2", { UserId = 101, Retreated = false })
        JestGlobals.expect(started).toBe(true)
        JestGlobals.expect(duplicateEgg).toBe(false)
        JestGlobals.expect(duplicateEggError).toBe("FightAlreadyRunning")
        JestGlobals.expect(duplicatePlayer).toBe(false)
        JestGlobals.expect(duplicatePlayerError).toBe("PlayerAlreadyFighting")
        JestGlobals.expect(runtime:GetForUser(101)).toBe("egg_z1_slot_1")
    end)

    JestGlobals.it("authenticates retreat, consumes the fight once, and tolerates duplicate retreat", function()
        local runtime = FightRuntime.new()
        local fight = { UserId = 101, Retreated = false }
        runtime:Start("egg_z1_slot_1", fight)
        local wrongOwner, wrongOwnerError = runtime:Retreat("egg_z1_slot_1", 202)
        JestGlobals.expect(wrongOwner).toBe(nil)
        JestGlobals.expect(wrongOwnerError).toBe("FightNotActive")
        local retreated = runtime:Retreat("egg_z1_slot_1", 101)
        local duplicate, duplicateError = runtime:Retreat("egg_z1_slot_1", 101)
        JestGlobals.expect(retreated).toBe(fight)
        JestGlobals.expect(fight.Retreated).toBe(true)
        JestGlobals.expect(duplicate).toBe(nil)
        JestGlobals.expect(duplicateError).toBe("FightNotActive")
        JestGlobals.expect(runtime:GetForUser(101)).toBe(nil)
    end)

    JestGlobals.it("finishes only the current fight and treats duplicate finish idempotently", function()
        local runtime = FightRuntime.new()
        local fight = { UserId = 101, Retreated = false }
        runtime:Start("egg_z1_slot_1", fight)
        local firstFinish = runtime:Finish("egg_z1_slot_1", fight)
        local duplicateFinish = runtime:Finish("egg_z1_slot_1", fight)
        JestGlobals.expect(firstFinish).toBe(true)
        JestGlobals.expect(duplicateFinish).toBe(false)
        JestGlobals.expect(runtime:Get("egg_z1_slot_1")).toBe(nil)
        JestGlobals.expect(runtime:GetForUser(101)).toBe(nil)
    end)
end)
