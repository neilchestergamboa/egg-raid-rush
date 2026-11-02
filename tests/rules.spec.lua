--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RulesFolder = Shared:WaitForChild("Rules")
local DevPackages = ReplicatedStorage:WaitForChild("DevPackages")
local JestGlobalsModule = DevPackages:WaitForChild("JestGlobals") :: ModuleScript
local JestGlobals = require(JestGlobalsModule)

local PetPower = require(RulesFolder:WaitForChild("PetPower") :: ModuleScript)
local EggDamage = require(RulesFolder:WaitForChild("EggDamage") :: ModuleScript)
local FightSim = require(RulesFolder:WaitForChild("FightSim") :: ModuleScript)
local GuardSpeed = require(RulesFolder:WaitForChild("GuardSpeed") :: ModuleScript)
local SpeedRank = require(RulesFolder:WaitForChild("SpeedRank") :: ModuleScript)
local ConditionRoll = require(RulesFolder:WaitForChild("ConditionRoll") :: ModuleScript)
local ConditionDefs = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ConditionDefs") :: ModuleScript
)

local function expectError(callback: () -> ())
    local ok = pcall(callback)
    JestGlobals.expect(ok).toBe(false)
end

JestGlobals.describe("PetPower", function()
    JestGlobals.it("applies the condition multiplier to base power", function()
        JestGlobals.expect(PetPower.Calculate(120, 1)).toBe(120)
        JestGlobals.expect(PetPower.Calculate(120, 0.7)).toBe(84)
    end)

    JestGlobals.it("rejects non-positive inputs", function()
        expectError(function()
            PetPower.Calculate(0, 1)
        end)
        expectError(function()
            PetPower.Calculate(120, 0)
        end)
    end)
end)

JestGlobals.describe("EggDamage", function()
    JestGlobals.it("uses parity damage when pet power matches the egg target", function()
        JestGlobals.expect(EggDamage.CalculatePowerRatio(120, 120)).toBe(1)
        JestGlobals.expect(EggDamage.CalculateDamagePerSecond(120, 120)).toBe(120)
    end)

    JestGlobals.it("clamps weak pets to the minimum power ratio", function()
        JestGlobals.expect(EggDamage.CalculatePowerRatio(1, 120)).toBe(0.1)
        JestGlobals.expect(EggDamage.CalculateDamagePerSecond(1, 120)).toBe(0.1)
    end)

    JestGlobals.it("clamps strong pets to the maximum power ratio", function()
        JestGlobals.expect(EggDamage.CalculatePowerRatio(240, 120)).toBe(1.5)
        JestGlobals.expect(EggDamage.CalculateDamagePerSecond(240, 120)).toBe(360)
    end)

    JestGlobals.it("rejects non-positive power inputs", function()
        expectError(function()
            EggDamage.CalculatePowerRatio(0, 120)
        end)
        expectError(function()
            EggDamage.CalculatePowerRatio(120, 0)
        end)
    end)
end)

JestGlobals.describe("FightSim", function()
    JestGlobals.it("produces a parity fight lasting about ten seconds", function()
        local result = FightSim.Simulate(120, 120, 20261102)
        JestGlobals.expect(result.DurationSeconds >= 9.5 and result.DurationSeconds <= 10.5).toBe(true)
        JestGlobals.expect(result.Ticks).toBe(result.DurationSeconds / 0.5)
        JestGlobals.expect(#result.History).toBe(result.Ticks)
        JestGlobals.expect(result.History[#result.History].ElapsedSeconds).toBe(result.DurationSeconds)
    end)

    JestGlobals.it("gives a half-power pet a loss in about five seconds", function()
        local result = FightSim.Simulate(60, 120, 20261102)
        JestGlobals.expect(result.Winner).toBe("Hatchling")
        JestGlobals.expect(result.DurationSeconds >= 4.5 and result.DurationSeconds <= 5.5).toBe(true)
    end)

    JestGlobals.it("gives a double-power pet a win in about five seconds", function()
        local result = FightSim.Simulate(240, 120, 20261102)
        JestGlobals.expect(result.Winner).toBe("Pet")
        JestGlobals.expect(result.DurationSeconds >= 4.5 and result.DurationSeconds <= 5.5).toBe(true)
    end)

    JestGlobals.it("replays the same result from the same seed", function()
        local first = FightSim.Simulate(120, 120, 20261102)
        local replay = FightSim.Simulate(120, 120, 20261102)
        JestGlobals.expect(replay.Winner).toBe(first.Winner)
        JestGlobals.expect(replay.DurationSeconds).toBe(first.DurationSeconds)
        JestGlobals.expect(replay.PetRemainingHp).toBe(first.PetRemainingHp)
        JestGlobals.expect(replay.HatchlingRemainingHp).toBe(first.HatchlingRemainingHp)
        JestGlobals.expect(replay.TieBreakSeed).toBe(first.TieBreakSeed)
    end)

    JestGlobals.it("uses a reproducible seeded coin toss for simultaneous knockouts", function()
        local tieSeed: number? = nil
        for seed = 1, 100 do
            local result = FightSim.Simulate(120, 120, seed)
            if result.WasTieBreak then
                tieSeed = seed
                break
            end
        end

        JestGlobals.expect(tieSeed ~= nil).toBe(true)
        local first = FightSim.Simulate(120, 120, tieSeed :: number)
        local replay = FightSim.Simulate(120, 120, tieSeed :: number)
        JestGlobals.expect(first.WasTieBreak).toBe(true)
        JestGlobals.expect(replay.Winner).toBe(first.Winner)
        JestGlobals.expect(replay.TieBreakSeed).toBe(first.TieBreakSeed)
    end)

    JestGlobals.it("rejects non-positive power and invalid seeds", function()
        expectError(function()
            FightSim.Simulate(0, 120, 1)
        end)
        expectError(function()
            FightSim.Simulate(120, 120, -1)
        end)
    end)
end)

JestGlobals.describe("ConditionRoll", function()
    JestGlobals.it("replays the same condition from a seed and produces configured conditions", function()
        local counts = {}
        local seeds = { 1, 5632, 6144, 7680, 12393 }
        for _, seed in seeds do
            local first = ConditionRoll.Roll(ConditionDefs, seed)
            local replay = ConditionRoll.Roll(ConditionDefs, seed)
            JestGlobals.expect(replay).toBe(first)
            JestGlobals.expect(ConditionDefs[first] ~= nil).toBe(true)
            counts[first] = (counts[first] or 0) + 1
        end
        for conditionId in pairs(ConditionDefs) do
            JestGlobals.expect(counts[conditionId] > 0).toBe(true)
        end
    end)

    JestGlobals.it("rejects invalid seeds and empty condition definitions", function()
        expectError(function()
            ConditionRoll.Roll(ConditionDefs, -1)
        end)
        expectError(function()
            ConditionRoll.Roll({}, 1)
        end)
    end)
end)

JestGlobals.describe("GuardSpeed", function()
    JestGlobals.it("returns GDD speeds for all six zones", function()
        local expectedSpeeds = { 12, 14.5, 17, 19.5, 22, 24.5 }
        for zone = 1, #expectedSpeeds do
            JestGlobals.expect(GuardSpeed.Calculate(zone)).toBe(expectedSpeeds[zone])
        end
    end)

    JestGlobals.it("rejects invalid zone numbers", function()
        expectError(function()
            GuardSpeed.Calculate(0)
        end)
        expectError(function()
            GuardSpeed.Calculate(1.5)
        end)
    end)
end)

JestGlobals.describe("SpeedRank", function()
    JestGlobals.it("maps point thresholds to the expected ranks", function()
        JestGlobals.expect(SpeedRank.GetRank(0)).toBe(0)
        JestGlobals.expect(SpeedRank.GetRank(99)).toBe(0)
        JestGlobals.expect(SpeedRank.GetRank(100)).toBe(1)
        JestGlobals.expect(SpeedRank.GetRank(399)).toBe(1)
        JestGlobals.expect(SpeedRank.GetRank(400)).toBe(2)
        JestGlobals.expect(SpeedRank.GetRank(26_214_400)).toBe(10)
    end)

    JestGlobals.it("returns the threshold for each rank", function()
        JestGlobals.expect(SpeedRank.GetThresholdForRank(1)).toBe(100)
        JestGlobals.expect(SpeedRank.GetThresholdForRank(2)).toBe(400)
        JestGlobals.expect(SpeedRank.GetThresholdForRank(10)).toBe(26_214_400)
    end)

    JestGlobals.it("calculates walk and carrier speeds by rank", function()
        JestGlobals.expect(SpeedRank.GetWalkSpeed(0)).toBe(16)
        JestGlobals.expect(SpeedRank.GetCarrierSpeed(0)).toBe(14.4)
        JestGlobals.expect(SpeedRank.GetCarrierSpeed(1)).toBe(15.48)
        JestGlobals.expect(SpeedRank.GetCarrierSpeed(10)).toBe(25.2)
    end)

    JestGlobals.it("returns the minimum rank that strictly outruns each guard", function()
        local expectedRanks = { 0, 1, 3, 5, 8, 10 }
        for zone, expectedRank in ipairs(expectedRanks) do
            JestGlobals.expect(SpeedRank.GetMinimumRankToOutrun(GuardSpeed.Calculate(zone))).toBe(expectedRank)
        end
    end)

    JestGlobals.it("rejects invalid points and ranks", function()
        expectError(function()
            SpeedRank.GetRank(-1)
        end)
        expectError(function()
            SpeedRank.GetWalkSpeed(11)
        end)
        expectError(function()
            SpeedRank.GetThresholdForRank(0)
        end)
    end)
end)
