--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ValidatorModule = ConfigFolder:WaitForChild("ConfigValidator") :: ModuleScript
local Validator = require(ValidatorModule)
local JestGlobalsModule = ReplicatedStorage.DevPackages:WaitForChild("JestGlobals") :: ModuleScript
local JestGlobals = require(JestGlobalsModule)

local function copyConfig()
    local config = {
        ZoneDefs = table.clone(require(ConfigFolder:WaitForChild("ZoneDefs"))),
        EggDefs = table.clone(require(ConfigFolder:WaitForChild("EggDefs"))),
        PetDefs = table.clone(require(ConfigFolder:WaitForChild("PetDefs"))),
        GuardDefs = table.clone(require(ConfigFolder:WaitForChild("GuardDefs"))),
        RarityDefs = table.clone(require(ConfigFolder:WaitForChild("RarityDefs"))),
        ConditionDefs = table.clone(require(ConfigFolder:WaitForChild("ConditionDefs"))),
        EggInteractionDefs = table.clone(require(ConfigFolder:WaitForChild("EggInteractionDefs"))),
        FightDefs = table.clone(require(ConfigFolder:WaitForChild("FightDefs"))),
        CarryDefs = table.clone(require(ConfigFolder:WaitForChild("CarryDefs"))),
        TutorialDefs = table.clone(require(ConfigFolder:WaitForChild("TutorialDefs"))),
    }
    config.ZoneDefs.Zone1 = table.clone(config.ZoneDefs.Zone1)
    config.ZoneDefs.Zone1.EggDefIds = table.clone(config.ZoneDefs.Zone1.EggDefIds)
    config.EggInteractionDefs = table.clone(config.EggInteractionDefs)
    config.EggInteractionDefs.CrackHealthThresholds = table.clone(config.EggInteractionDefs.CrackHealthThresholds)
    config.CarryDefs = table.clone(config.CarryDefs)
    config.TutorialDefs = table.clone(config.TutorialDefs)
    config.TutorialDefs.FirstRaid = table.clone(config.TutorialDefs.FirstRaid)
    return config
end

JestGlobals.describe("Zone 1 shared config validation", function()
    JestGlobals.it("accepts the complete Zone 1 definitions", function()
        local isValid, message = Validator.Validate()
        JestGlobals.expect(isValid).toBe(true)
        JestGlobals.expect(message).toBe(nil)
    end)

    JestGlobals.it("reports a missing egg definition clearly", function()
        local config = copyConfig()
        config.EggDefs.egg_z1_slot_1 = nil

        local isValid, message = Validator.Validate(config)
        JestGlobals.expect(isValid).toBe(false)
        JestGlobals.expect(message)
            .toBe("Shared config validation failed: ZoneDefs.Zone1 references missing EggDefs.egg_z1_slot_1.")
    end)

    JestGlobals.it("rejects mismatched egg health", function()
        local config = copyConfig()
        config.EggDefs.egg_z1_slot_1 = table.clone(config.EggDefs.egg_z1_slot_1)
        config.EggDefs.egg_z1_slot_1.Health = 1

        local isValid, message = Validator.Validate(config)
        JestGlobals.expect(isValid).toBe(false)
        JestGlobals.expect(message)
            .toBe("Shared config validation failed: EggDefs.egg_z1_slot_1.Health must equal HatchlingPower × BreakSeconds.")
    end)

    JestGlobals.it("rejects condition weights that do not total 100", function()
        local config = copyConfig()
        config.ConditionDefs = table.clone(config.ConditionDefs)
        config.ConditionDefs.Cracked = table.clone(config.ConditionDefs.Cracked)
        config.ConditionDefs.Cracked.RollWeight = 34

        local isValid, message = Validator.Validate(config)
        JestGlobals.expect(isValid).toBe(false)
        JestGlobals.expect(message)
            .toBe("Shared config validation failed: ConditionDefs roll weights must total 100; got 99.")
    end)

    JestGlobals.it("rejects a tutorial guard that is not slower", function()
        local config = copyConfig()
        config.GuardDefs = table.clone(config.GuardDefs)
        config.GuardDefs.guard_pride_king_tutorial = table.clone(config.GuardDefs.guard_pride_king_tutorial)
        config.GuardDefs.guard_pride_king_tutorial.Speed = 12

        local isValid, message = Validator.Validate(config)
        JestGlobals.expect(isValid).toBe(false)
        JestGlobals.expect(message).toBe(
            "Shared config validation failed: The tutorial guard must be slower than the Zone 1 guard and forgive the first drop."
        )
    end)

    JestGlobals.it("rejects a non-positive egg interaction range", function()
        local config = copyConfig()
        config.EggInteractionDefs.ClaimDistanceStuds = 0

        local isValid, message = Validator.Validate(config)
        JestGlobals.expect(isValid).toBe(false)
        JestGlobals.expect(message)
            .toBe("Shared config validation failed: EggInteractionDefs.ClaimDistanceStuds must be positive.")
    end)

    JestGlobals.it("rejects a carry speed penalty multiplier above one", function()
        local config = copyConfig()
        config.CarryDefs.CarrierSpeedMultiplier = 1.1

        local isValid, message = Validator.Validate(config)
        JestGlobals.expect(isValid).toBe(false)
        JestGlobals.expect(message)
            .toBe("Shared config validation failed: CarryDefs.CarrierSpeedMultiplier must be in (0, 1].")
    end)

    JestGlobals.it("rejects a tutorial catch-up ratio above one half", function()
        local config = copyConfig()
        config.TutorialDefs.FirstRaid.HatchlingPowerRatio = 0.6

        local isValid, message = Validator.Validate(config)
        JestGlobals.expect(isValid).toBe(false)
        JestGlobals.expect(message)
            .toBe("Shared config validation failed: TutorialDefs.FirstRaid.HatchlingPowerRatio must be in (0, 0.5].")
    end)
end)
