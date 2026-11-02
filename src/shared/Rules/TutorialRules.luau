--!strict

local function canClaim(ownerUserId: number?, playerUserId: number, tutorialCompleted: boolean?): boolean
    if ownerUserId == nil then
        return true
    end
    return ownerUserId == playerUserId and tutorialCompleted ~= true
end

local function shouldForgiveFirstDrop(
    isTutorialRun: boolean,
    guardAllowsForgiveness: boolean,
    alreadyForgiven: boolean
): boolean
    return isTutorialRun and guardAllowsForgiveness and not alreadyForgiven
end

local function getFightHatchlingPower(
    petPower: number,
    rolledHatchlingPower: number,
    tutorialCompleted: boolean,
    eggZoneId: number,
    eggRarityId: string,
    firstRaid: { ZoneId: number, RarityId: string, HatchlingPowerRatio: number }
): number
    assert(petPower > 0 and petPower < math.huge, "petPower must be finite and positive.")
    assert(
        rolledHatchlingPower > 0 and rolledHatchlingPower < math.huge,
        "rolledHatchlingPower must be finite and positive."
    )
    assert(type(tutorialCompleted) == "boolean", "tutorialCompleted must be a boolean.")
    assert(
        type(eggZoneId) == "number" and eggZoneId == eggZoneId and eggZoneId % 1 == 0,
        "eggZoneId must be a finite integer."
    )
    assert(type(eggRarityId) == "string" and eggRarityId ~= "", "eggRarityId must be a non-empty string.")
    assert(type(firstRaid) == "table", "firstRaid config must be a table.")
    assert(
        type(firstRaid.ZoneId) == "number" and firstRaid.ZoneId == firstRaid.ZoneId and firstRaid.ZoneId % 1 == 0,
        "firstRaid.ZoneId must be a finite integer."
    )
    assert(type(firstRaid.RarityId) == "string" and firstRaid.RarityId ~= "", "firstRaid.RarityId must be non-empty.")
    assert(
        type(firstRaid.HatchlingPowerRatio) == "number"
            and firstRaid.HatchlingPowerRatio == firstRaid.HatchlingPowerRatio
            and firstRaid.HatchlingPowerRatio > 0
            and firstRaid.HatchlingPowerRatio <= 0.5,
        "firstRaid.HatchlingPowerRatio must be in (0, 0.5]."
    )

    if not tutorialCompleted and eggZoneId == firstRaid.ZoneId and eggRarityId == firstRaid.RarityId then
        return math.min(rolledHatchlingPower, petPower * firstRaid.HatchlingPowerRatio)
    end

    return rolledHatchlingPower
end

return {
    CanClaim = canClaim,
    ShouldForgiveFirstDrop = shouldForgiveFirstDrop,
    GetFightHatchlingPower = getFightHatchlingPower,
}
