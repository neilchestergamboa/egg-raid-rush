--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("JestGlobals") :: ModuleScript)
local TutorialRules = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"):WaitForChild("TutorialRules") :: ModuleScript
)

JestGlobals.describe("TutorialRules", function()
    JestGlobals.it("allows all players to claim a shared Zone 1 egg", function()
        JestGlobals.expect(TutorialRules.CanClaim(nil, 12)).toBe(true)
        JestGlobals.expect(TutorialRules.CanClaim(nil, 12, true)).toBe(true)
    end)

    JestGlobals.it("forgives the first tutorial-run drop on the configured slow Guard", function()
        JestGlobals.expect(TutorialRules.ShouldForgiveFirstDrop(true, true, false)).toBe(true)
        JestGlobals.expect(TutorialRules.ShouldForgiveFirstDrop(true, true, true)).toBe(false)
        JestGlobals.expect(TutorialRules.ShouldForgiveFirstDrop(false, true, false)).toBe(false)
        JestGlobals.expect(TutorialRules.ShouldForgiveFirstDrop(true, false, false)).toBe(false)
    end)
end)
