--!strict
-- GDD sections 4.2 and 8.1: rank thresholds, walk-speed growth, and carrier slowdown.

local FIRST_RANK_POINTS = 100
local POINTS_MULTIPLIER_PER_RANK = 4
local MAX_RANK = 10
local BASE_WALK_SPEED = 16
local SPEED_INCREASE_PER_RANK = 0.075
local CARRY_SPEED_MULTIPLIER = 0.90

local function validateRank(rank: number)
    assert(rank >= 0 and rank % 1 == 0 and rank <= MAX_RANK, "rank must be an integer from 0 to 10.")
end

local function getThresholdForRank(rank: number): number
    assert(rank >= 1 and rank % 1 == 0 and rank <= MAX_RANK, "rank must be an integer from 1 to 10.")

    return FIRST_RANK_POINTS * POINTS_MULTIPLIER_PER_RANK ^ (rank - 1)
end

local function getRank(speedPoints: number): number
    assert(speedPoints >= 0, "speedPoints must be non-negative.")

    local rank = 0
    for candidateRank = 1, MAX_RANK do
        if speedPoints < getThresholdForRank(candidateRank) then
            break
        end
        rank = candidateRank
    end

    return rank
end

local function getWalkSpeed(rank: number): number
    validateRank(rank)

    return BASE_WALK_SPEED * (1 + SPEED_INCREASE_PER_RANK * rank)
end

local function getCarrierSpeed(rank: number): number
    return getWalkSpeed(rank) * CARRY_SPEED_MULTIPLIER
end

local function getMinimumRankToOutrun(guardSpeed: number): number?
    assert(guardSpeed >= 0, "guardSpeed must be non-negative.")

    for rank = 0, MAX_RANK do
        if getCarrierSpeed(rank) > guardSpeed then
            return rank
        end
    end

    return nil
end

return {
    GetThresholdForRank = getThresholdForRank,
    GetRank = getRank,
    GetWalkSpeed = getWalkSpeed,
    GetCarrierSpeed = getCarrierSpeed,
    GetMinimumRankToOutrun = getMinimumRankToOutrun,
}
