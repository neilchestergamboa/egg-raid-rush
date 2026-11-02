--!strict
-- Resolves claims using server arrival times, with seeded ties.

export type Candidate = {
    UserId: number,
    ReceivedAt: number,
}

local function resolve(candidates: { Candidate }, seed: number): (number?, boolean)
    assert(#candidates > 0, "At least one claim candidate is required.")
    assert(seed == seed and seed % 1 == 0, "seed must be a finite integer.")

    local earliestTime = math.huge
    for _, candidate in candidates do
        assert(candidate.UserId > 0 and candidate.UserId % 1 == 0, "UserId must be a positive integer.")
        assert(
            candidate.ReceivedAt == candidate.ReceivedAt
                and candidate.ReceivedAt > -math.huge
                and candidate.ReceivedAt < math.huge,
            "ReceivedAt must be finite."
        )
        if candidate.ReceivedAt < earliestTime then
            earliestTime = candidate.ReceivedAt
        end
    end

    local earliestUserIds = {}
    for _, candidate in candidates do
        if candidate.ReceivedAt == earliestTime then
            table.insert(earliestUserIds, candidate.UserId)
        end
    end
    table.sort(earliestUserIds)

    if #earliestUserIds == 1 then
        return earliestUserIds[1], false
    end

    local random = Random.new(seed)
    return earliestUserIds[random:NextInteger(1, #earliestUserIds)], true
end

return { Resolve = resolve }
