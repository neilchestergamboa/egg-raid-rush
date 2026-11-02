--!strict

local function applyCarrierSpeed(baseSpeed: number, multiplier: number): number
    assert(baseSpeed > 0 and baseSpeed < math.huge, "baseSpeed must be finite and positive.")
    assert(multiplier > 0 and multiplier <= 1, "multiplier must be in (0, 1].")
    return baseSpeed * multiplier
end

local function isWithinDistance(first: Vector3, second: Vector3, distance: number): boolean
    assert(distance >= 0 and distance < math.huge, "distance must be finite and non-negative.")
    return (first - second).Magnitude <= distance
end

local function isInsideGate(point: Vector3, gateCFrame: CFrame, gateSize: Vector3): boolean
    local localPoint = gateCFrame:PointToObjectSpace(point)
    local halfSize = gateSize * 0.5
    return math.abs(localPoint.X) <= halfSize.X
        and math.abs(localPoint.Y) <= halfSize.Y
        and math.abs(localPoint.Z) <= halfSize.Z
end

local function stepToward(position: Vector3, target: Vector3, speed: number, deltaSeconds: number): Vector3
    assert(speed >= 0 and speed < math.huge, "speed must be finite and non-negative.")
    assert(deltaSeconds >= 0 and deltaSeconds < math.huge, "deltaSeconds must be finite and non-negative.")
    local offset = target - position
    local distance = offset.Magnitude
    if distance == 0 or speed == 0 or deltaSeconds == 0 then
        return position
    end
    local travel = math.min(distance, speed * deltaSeconds)
    return position + offset.Unit * travel
end

return {
    ApplyCarrierSpeed = applyCarrierSpeed,
    IsWithinDistance = isWithinDistance,
    IsInsideGate = isInsideGate,
    StepToward = stepToward,
}
