--!strict

export type ConditionDefinition = {
    Name: string,
    PowerMultiplier: number,
    RollWeight: number,
}

local UINT32_RANGE = 4_294_967_296

local function makeNextRandom(seed: number): () -> number
    local state = bit32.band(seed, 0xFFFFFFFF)
    if state == 0 then
        state = 1
    end

    return function(): number
        state = bit32.bxor(state, bit32.lshift(state, 13))
        state = bit32.bxor(state, bit32.rshift(state, 17))
        state = bit32.bxor(state, bit32.lshift(state, 5))
        return state / UINT32_RANGE
    end
end

local function roll(definitions: { [string]: ConditionDefinition }, seed: number): string
    assert(seed >= 0 and seed % 1 == 0 and seed <= 0xFFFFFFFF, "seed must be an unsigned 32-bit integer.")
    local ids = {}
    local totalWeight = 0
    for id, definition in pairs(definitions) do
        assert(definition.RollWeight > 0, "condition weights must be positive.")
        totalWeight += definition.RollWeight
        table.insert(ids, id)
    end
    assert(#ids > 0 and totalWeight > 0, "at least one weighted condition is required.")
    table.sort(ids)

    local target = makeNextRandom(seed)() * totalWeight
    local cumulativeWeight = 0
    for _, id in ids do
        cumulativeWeight += definitions[id].RollWeight
        if target < cumulativeWeight then
            return id
        end
    end
    return ids[#ids]
end

return { Roll = roll }
