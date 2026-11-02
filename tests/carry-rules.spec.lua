--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarryRules = require(Shared:WaitForChild("Rules"):WaitForChild("CarryRules") :: ModuleScript)
local JestGlobals = require(ReplicatedStorage.DevPackages:WaitForChild("JestGlobals") :: ModuleScript)

JestGlobals.describe("CarryRules", function()
    JestGlobals.it("applies the configured carrier speed multiplier", function()
        JestGlobals.expect(CarryRules.ApplyCarrierSpeed(16, 0.9)).toBe(14.4)
    end)

    JestGlobals.it("checks pickup and Guard tag distances inclusively", function()
        JestGlobals.expect(CarryRules.IsWithinDistance(Vector3.zero, Vector3.new(3, 4, 0), 5)).toBe(true)
        JestGlobals.expect(CarryRules.IsWithinDistance(Vector3.zero, Vector3.new(3, 4, 0), 4.9)).toBe(false)
    end)

    JestGlobals.it("checks a point against the oriented Safe Gate volume", function()
        local gate = CFrame.new(10, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
        JestGlobals.expect(CarryRules.IsInsideGate(Vector3.new(10, 0, 0), gate, Vector3.new(4, 6, 8))).toBe(true)
        JestGlobals.expect(CarryRules.IsInsideGate(Vector3.new(20, 0, 0), gate, Vector3.new(4, 6, 8))).toBe(false)
    end)

    JestGlobals.it("steps toward the carrier by at most speed times elapsed time", function()
        local result = CarryRules.StepToward(Vector3.zero, Vector3.new(10, 0, 0), 12, 0.5)
        JestGlobals.expect(result).toBe(Vector3.new(6, 0, 0))
        JestGlobals.expect(CarryRules.StepToward(Vector3.zero, Vector3.new(2, 0, 0), 12, 1)).toBe(Vector3.new(2, 0, 0))
    end)

    JestGlobals.it("rejects invalid speed and distance inputs", function()
        local validSpeed = pcall(CarryRules.ApplyCarrierSpeed, 0, 0.9)
        local validDistance = pcall(CarryRules.IsWithinDistance, Vector3.zero, Vector3.zero, -1)
        JestGlobals.expect(validSpeed).toBe(false)
        JestGlobals.expect(validDistance).toBe(false)
    end)
end)
