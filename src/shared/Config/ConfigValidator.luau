--!strict

local Config = {
    ZoneDefs = require(script.Parent:WaitForChild("ZoneDefs")),
    EggDefs = require(script.Parent:WaitForChild("EggDefs")),
    PetDefs = require(script.Parent:WaitForChild("PetDefs")),
    GuardDefs = require(script.Parent:WaitForChild("GuardDefs")),
    RarityDefs = require(script.Parent:WaitForChild("RarityDefs")),
    ConditionDefs = require(script.Parent:WaitForChild("ConditionDefs")),
    EggInteractionDefs = require(script.Parent:WaitForChild("EggInteractionDefs")),
    FightDefs = require(script.Parent:WaitForChild("FightDefs")),
}

type ConfigData = {
    ZoneDefs: any,
    EggDefs: any,
    PetDefs: any,
    GuardDefs: any,
    RarityDefs: any,
    ConditionDefs: any,
    EggInteractionDefs: any,
    FightDefs: any,
}

local function validate(config: any): (boolean, string?)
    local function fail(message: string): (boolean, string?)
        return false, "Shared config validation failed: " .. message
    end

    if type(config) ~= "table" then
        return fail("The root definition must be a table.")
    end
    for _, fieldName in ipairs({
        "ZoneDefs",
        "EggDefs",
        "PetDefs",
        "GuardDefs",
        "RarityDefs",
        "ConditionDefs",
        "EggInteractionDefs",
        "FightDefs",
    }) do
        if type(config[fieldName]) ~= "table" then
            return fail(fieldName .. " must be a table.")
        end
    end
    local fight = config.FightDefs
    for _, fieldName in ipairs({
        "TickSeconds",
        "HealthPerPower",
        "SnapshotIntervalSeconds",
        "KnockoutRecoverySeconds",
        "RetreatRateLimitSeconds",
    }) do
        if
            type(fight[fieldName]) ~= "number"
            or fight[fieldName] ~= fight[fieldName]
            or fight[fieldName] <= 0
            or fight[fieldName] == math.huge
        then
            return fail("FightDefs." .. fieldName .. " must be positive.")
        end
    end
    if
        type(fight.DamageVariance) ~= "number"
        or fight.DamageVariance ~= fight.DamageVariance
        or fight.DamageVariance < 0
        or fight.DamageVariance >= 1
        or fight.DamageVariance == math.huge
    then
        return fail("FightDefs.DamageVariance must be in [0, 1).")
    end
    if fight.SnapshotIntervalSeconds > fight.TickSeconds then
        return fail("FightDefs.SnapshotIntervalSeconds cannot exceed TickSeconds.")
    end

    local interaction = config.EggInteractionDefs
    for _, fieldName in ipairs({
        "ClaimDistanceStuds",
        "ClaimTimeoutSeconds",
        "RequestRateLimitSeconds",
        "DamageUpdateIntervalSeconds",
    }) do
        if
            type(interaction[fieldName]) ~= "number"
            or interaction[fieldName] ~= interaction[fieldName]
            or interaction[fieldName] <= 0
            or interaction[fieldName] == math.huge
        then
            return fail("EggInteractionDefs." .. fieldName .. " must be positive.")
        end
    end
    if type(interaction.CrackHealthThresholds) ~= "table" or #interaction.CrackHealthThresholds ~= 4 then
        return fail("EggInteractionDefs.CrackHealthThresholds must contain four thresholds.")
    end
    if interaction.CrackHealthThresholds[1] ~= 1 then
        return fail("EggInteractionDefs.CrackHealthThresholds must begin at 1.")
    end
    for index, threshold in ipairs(interaction.CrackHealthThresholds) do
        if
            type(threshold) ~= "number"
            or threshold ~= threshold
            or threshold <= 0
            or threshold > 1
            or threshold == math.huge
        then
            return fail("EggInteractionDefs.CrackHealthThresholds entries must be in (0, 1].")
        end
        if index > 1 and threshold >= interaction.CrackHealthThresholds[index - 1] then
            return fail("EggInteractionDefs.CrackHealthThresholds must be strictly descending.")
        end
    end

    local zone = config.ZoneDefs.Zone1
    if type(zone) ~= "table" then
        return fail("ZoneDefs.Zone1 is missing.")
    end
    if zone.Id ~= 1 or type(zone.Name) ~= "string" or zone.Name == "" then
        return fail("ZoneDefs.Zone1 must have Id 1 and a non-empty Name.")
    end
    if type(zone.RecommendedPetPower) ~= "number" or zone.RecommendedPetPower <= 0 then
        return fail("ZoneDefs.Zone1.RecommendedPetPower must be positive.")
    end
    if type(zone.EggDefIds) ~= "table" or #zone.EggDefIds ~= 6 then
        return fail("ZoneDefs.Zone1.EggDefIds must contain exactly six field eggs.")
    end
    if type(zone.GuardDefId) ~= "string" then
        return fail("ZoneDefs.Zone1.GuardDefId must be a string.")
    end

    local normalGuard = config.GuardDefs[zone.GuardDefId]
    if type(normalGuard) ~= "table" or normalGuard.ZoneId ~= zone.Id or normalGuard.IsTutorial then
        return fail("ZoneDefs.Zone1.GuardDefId must reference a non-tutorial Zone 1 guard.")
    end
    if type(normalGuard.Speed) ~= "number" or normalGuard.Speed <= 0 then
        return fail("Zone 1 guard speed must be positive.")
    end

    local conditionWeightTotal = 0
    for conditionId, condition in pairs(config.ConditionDefs) do
        if type(condition) ~= "table" then
            return fail("ConditionDefs." .. tostring(conditionId) .. " must be a table.")
        end
        if type(condition.Name) ~= "string" or condition.Name == "" then
            return fail("ConditionDefs." .. tostring(conditionId) .. ".Name is required.")
        end
        if type(condition.PowerMultiplier) ~= "number" or condition.PowerMultiplier <= 0 then
            return fail("ConditionDefs." .. tostring(conditionId) .. ".PowerMultiplier must be positive.")
        end
        if type(condition.RollWeight) ~= "number" or condition.RollWeight <= 0 then
            return fail("ConditionDefs." .. tostring(conditionId) .. ".RollWeight must be positive.")
        end
        conditionWeightTotal += condition.RollWeight
    end
    if conditionWeightTotal ~= 100 then
        return fail("ConditionDefs roll weights must total 100; got " .. tostring(conditionWeightTotal) .. ".")
    end

    local usedSlots: { [number]: boolean } = {}
    for _, eggDefId in ipairs(zone.EggDefIds) do
        if type(eggDefId) ~= "string" then
            return fail("ZoneDefs.Zone1.EggDefIds entries must be strings.")
        end

        local egg = config.EggDefs[eggDefId]
        if type(egg) ~= "table" then
            return fail("ZoneDefs.Zone1 references missing EggDefs." .. eggDefId .. ".")
        end
        if egg.ZoneId ~= zone.Id or egg.IsTutorial then
            return fail("EggDefs." .. eggDefId .. " must be a non-tutorial egg in Zone 1.")
        end
        if type(egg.Slot) ~= "number" or egg.Slot % 1 ~= 0 or egg.Slot < 1 or egg.Slot > 6 or usedSlots[egg.Slot] then
            return fail("EggDefs." .. eggDefId .. ".Slot must be a unique integer from 1 to 6.")
        end
        usedSlots[egg.Slot] = true
        if type(egg.RarityId) ~= "string" or type(egg.PetDefId) ~= "string" then
            return fail("EggDefs." .. eggDefId .. " must provide RarityId and PetDefId strings.")
        end

        local rarity = config.RarityDefs[egg.RarityId]
        if type(rarity) ~= "table" then
            return fail("EggDefs." .. eggDefId .. " references missing RarityDefs." .. egg.RarityId .. ".")
        end
        for _, numberField in ipairs({ "PowerMultiplier", "BreakSeconds", "RespawnSeconds", "BaseGps" }) do
            if type(rarity[numberField]) ~= "number" or rarity[numberField] <= 0 then
                return fail("RarityDefs." .. egg.RarityId .. "." .. numberField .. " must be positive.")
            end
        end

        local pet = config.PetDefs[egg.PetDefId]
        if type(pet) ~= "table" then
            return fail("EggDefs." .. eggDefId .. " references missing PetDefs." .. egg.PetDefId .. ".")
        end
        local guard = config.GuardDefs[egg.GuardDefId]
        if guard ~= normalGuard then
            return fail("EggDefs." .. eggDefId .. " must use ZoneDefs.Zone1.GuardDefId.")
        end
        if pet.ZoneId ~= zone.Id or pet.RarityId ~= egg.RarityId then
            return fail("EggDefs." .. eggDefId .. " and its PetDef must match Zone 1 and the same rarity.")
        end
        if pet.BodySize ~= "Small" and pet.BodySize ~= "Medium" and pet.BodySize ~= "Large" then
            return fail("PetDefs." .. egg.PetDefId .. ".BodySize must be Small, Medium, or Large.")
        end
        if type(egg.HatchlingPower) ~= "number" or type(pet.BasePower) ~= "number" then
            return fail("EggDefs." .. eggDefId .. " and PetDefs." .. egg.PetDefId .. " must define numeric power.")
        end
        if
            type(egg.BreakSeconds) ~= "number"
            or type(egg.Health) ~= "number"
            or type(egg.RespawnSeconds) ~= "number"
        then
            return fail("EggDefs." .. eggDefId .. " must define numeric health and timers.")
        end
        if type(pet.Gps) ~= "number" then
            return fail("PetDefs." .. egg.PetDefId .. ".Gps must be numeric.")
        end

        local expectedPower = zone.RecommendedPetPower * rarity.PowerMultiplier
        if egg.HatchlingPower ~= expectedPower or pet.BasePower ~= expectedPower then
            return fail(
                "EggDefs."
                    .. eggDefId
                    .. " and PetDefs."
                    .. egg.PetDefId
                    .. " power must match Zone 1 power × rarity multiplier."
            )
        end
        if egg.BreakSeconds ~= rarity.BreakSeconds or egg.RespawnSeconds ~= rarity.RespawnSeconds then
            return fail("EggDefs." .. eggDefId .. " break and respawn times must match its RarityDef.")
        end
        if egg.Health ~= egg.HatchlingPower * egg.BreakSeconds then
            return fail("EggDefs." .. eggDefId .. ".Health must equal HatchlingPower × BreakSeconds.")
        end
        if pet.Gps ~= rarity.BaseGps then
            return fail("PetDefs." .. egg.PetDefId .. ".Gps must match its RarityDef.")
        end
    end

    if type(zone.TutorialEggDefId) ~= "string" then
        return fail("ZoneDefs.Zone1.TutorialEggDefId must be a string.")
    end
    local tutorialEgg = config.EggDefs[zone.TutorialEggDefId]
    if type(tutorialEgg) ~= "table" or not tutorialEgg.IsTutorial or tutorialEgg.ZoneId ~= zone.Id then
        return fail("ZoneDefs.Zone1.TutorialEggDefId must reference a Zone 1 tutorial egg.")
    end
    if type(tutorialEgg.GuardDefId) ~= "string" then
        return fail("The tutorial egg must provide a GuardDefId string.")
    end
    local tutorialGuard = config.GuardDefs[tutorialEgg.GuardDefId]
    if type(tutorialGuard) ~= "table" or not tutorialGuard.IsTutorial then
        return fail("The tutorial egg must reference a tutorial GuardDef.")
    end
    if type(tutorialGuard.Speed) ~= "number" or type(tutorialGuard.ForgiveFirstDrop) ~= "boolean" then
        return fail("The tutorial guard must define numeric Speed and boolean ForgiveFirstDrop.")
    end
    if tutorialGuard.Speed >= normalGuard.Speed or not tutorialGuard.ForgiveFirstDrop then
        return fail("The tutorial guard must be slower than the Zone 1 guard and forgive the first drop.")
    end

    local common = config.RarityDefs.Common
    if type(common) ~= "table" or type(common.PowerMultiplier) ~= "number" or common.PowerMultiplier <= 0 then
        return fail("RarityDefs.Common.PowerMultiplier must be positive for the tutorial egg.")
    end
    if
        type(tutorialEgg.HatchlingPower) ~= "number"
        or type(tutorialEgg.BreakSeconds) ~= "number"
        or type(tutorialEgg.Health) ~= "number"
    then
        return fail("The tutorial egg must define numeric power, break time, and health.")
    end
    local tutorialPower = zone.RecommendedPetPower * common.PowerMultiplier
    if
        tutorialEgg.RarityId ~= "Common"
        or tutorialEgg.HatchlingPower ~= tutorialPower * 0.5
        or tutorialEgg.BreakSeconds ~= 4
        or tutorialEgg.Health ~= tutorialPower * tutorialEgg.BreakSeconds
    then
        return fail(
            "The tutorial egg must use a half-power Common hatchling and health equal to Common power × four seconds."
        )
    end

    return true, nil
end

return {
    Validate = function(config: ConfigData?): (boolean, string?)
        if config == nil then
            return validate(Config)
        end
        return validate(config)
    end,
}
