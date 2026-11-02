--!strict
-- Pure egg health and crack-stage math. Thresholds are supplied by Config.

local function isFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

local function applyDamage(
    currentHealth: number,
    maxHealth: number,
    damagePerSecond: number,
    elapsedSeconds: number
): number
    assert(isFinite(currentHealth) and currentHealth >= 0, "currentHealth must be finite and non-negative.")
    assert(isFinite(maxHealth) and maxHealth > 0, "maxHealth must be finite and positive.")
    assert(currentHealth <= maxHealth, "currentHealth cannot exceed maxHealth.")
    assert(isFinite(damagePerSecond) and damagePerSecond > 0, "damagePerSecond must be finite and positive.")
    assert(isFinite(elapsedSeconds) and elapsedSeconds >= 0, "elapsedSeconds must be finite and non-negative.")

    return math.max(0, currentHealth - damagePerSecond * elapsedSeconds)
end

local function calculateCrackStage(health: number, maxHealth: number, thresholds: { number }): number
    assert(isFinite(health) and health >= 0, "health must be finite and non-negative.")
    assert(isFinite(maxHealth) and maxHealth > 0, "maxHealth must be finite and positive.")
    assert(health <= maxHealth, "health cannot exceed maxHealth.")
    assert(#thresholds > 0, "thresholds must not be empty.")

    local healthRatio = health / maxHealth
    local stage = 1
    for index = 2, #thresholds do
        if healthRatio <= thresholds[index] then
            stage = index
        else
            break
        end
    end
    return stage
end

return {
    ApplyDamage = applyDamage,
    CalculateCrackStage = calculateCrackStage,
}
