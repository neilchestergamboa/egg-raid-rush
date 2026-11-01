--!strict
-- GDD section 8.1: GuardSpeed = 12 + 2.5 × (zone - 1) studs per second.

local BASE_GUARD_SPEED = 12
local SPEED_PER_ZONE = 2.5

local function calculate(zone: number): number
    assert(zone >= 1 and zone % 1 == 0, "zone must be a positive integer.")

    return BASE_GUARD_SPEED + SPEED_PER_ZONE * (zone - 1)
end

return {
    Calculate = calculate,
}
