--!strict
-- GDD section 6: damage per second = PetPower × clamp(PetPower / RecommendedPetPower, 0.1, 1.5).
-- RecommendedPetPower is the rarity-adjusted target power for the specific egg.

local MIN_POWER_RATIO = 0.1
local MAX_POWER_RATIO = 1.5

local function calculatePowerRatio(petPower: number, recommendedPetPower: number): number
    assert(petPower > 0, "petPower must be positive.")
    assert(recommendedPetPower > 0, "recommendedPetPower must be positive.")

    return math.clamp(petPower / recommendedPetPower, MIN_POWER_RATIO, MAX_POWER_RATIO)
end

local function calculateDamagePerSecond(petPower: number, recommendedPetPower: number): number
    return petPower * calculatePowerRatio(petPower, recommendedPetPower)
end

return {
    CalculatePowerRatio = calculatePowerRatio,
    CalculateDamagePerSecond = calculateDamagePerSecond,
}
