--!strict
-- GDD section 4.3: PetPower = BasePower × ConditionMult.

local function calculate(basePower: number, conditionMultiplier: number): number
    assert(basePower > 0, "basePower must be positive.")
    assert(conditionMultiplier > 0, "conditionMultiplier must be positive.")

    return basePower * conditionMultiplier
end

return {
    Calculate = calculate,
}
