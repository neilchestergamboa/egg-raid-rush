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

return {
    CanClaim = canClaim,
    ShouldForgiveFirstDrop = shouldForgiveFirstDrop,
}
