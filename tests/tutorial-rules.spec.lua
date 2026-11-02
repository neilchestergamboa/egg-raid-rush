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

    JestGlobals.it("caps a tutorial Zone 1 Common fight at half of the player's power", function()
        local settings = { ZoneId = 1, RarityId = "Common", HatchlingPowerRatio = 0.5 }
        JestGlobals.expect(TutorialRules.GetFightHatchlingPower(120, 180, false, 1, "Common", settings)).toBe(60)
        JestGlobals.expect(TutorialRules.GetFightHatchlingPower(120, 60, false, 1, "Common", settings)).toBe(60)
    end)

    JestGlobals.it("keeps normal hatchling power after tutorial or for other eggs", function()
        local settings = { ZoneId = 1, RarityId = "Common", HatchlingPowerRatio = 0.5 }
        JestGlobals.expect(TutorialRules.GetFightHatchlingPower(120, 180, true, 1, "Common", settings)).toBe(180)
        JestGlobals.expect(TutorialRules.GetFightHatchlingPower(120, 180, false, 1, "Uncommon", settings)).toBe(180)
        JestGlobals.expect(TutorialRules.GetFightHatchlingPower(120, 180, false, 2, "Common", settings)).toBe(180)
    end)

    JestGlobals.it("rejects invalid fight power and tutorial settings", function()
        local settings = { ZoneId = 1, RarityId = "Common", HatchlingPowerRatio = 0.5 }
        local ok = pcall(function()
            TutorialRules.GetFightHatchlingPower(0, 120, false, 1, "Common", settings)
        end)
        JestGlobals.expect(ok).toBe(false)

        settings.HatchlingPowerRatio = 0.6
        local invalidRatioOk = pcall(function()
            TutorialRules.GetFightHatchlingPower(120, 180, false, 1, "Common", settings)
        end)
        JestGlobals.expect(invalidRatioOk).toBe(false)
    end)
end)
