--!strict
-- GDD section 6: simultaneous hits in 0.5-second ticks with ±10% seeded damage variance.
-- Both fighters have 10 × Power HP and deal Power damage per second.

local TICK_SECONDS = 0.5
local DAMAGE_VARIANCE = 0.10
local HEALTH_PER_POWER = 10
local TIE_BREAK_SEED_SALT = 0x1EDC6F41
local UINT32_RANGE = 4_294_967_296

export type Winner = "Pet" | "Hatchling"

export type FightResult = {
    Winner: Winner,
    DurationSeconds: number,
    Ticks: number,
    PetRemainingHp: number,
    HatchlingRemainingHp: number,
    WasTieBreak: boolean,
    Seed: number,
    TieBreakSeed: number?,
}

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

local function validateInputs(petPower: number, hatchlingPower: number, seed: number)
    assert(petPower > 0, "petPower must be positive.")
    assert(hatchlingPower > 0, "hatchlingPower must be positive.")
    assert(seed >= 0 and seed % 1 == 0 and seed <= 0xFFFFFFFF, "seed must be an unsigned 32-bit integer.")
end

local function simulate(petPower: number, hatchlingPower: number, seed: number): FightResult
    validateInputs(petPower, hatchlingPower, seed)

    local nextRandom = makeNextRandom(seed)
    local petHp = HEALTH_PER_POWER * petPower
    local hatchlingHp = HEALTH_PER_POWER * hatchlingPower
    local ticks = 0

    while petHp > 0 and hatchlingHp > 0 do
        local petDamage = petPower * TICK_SECONDS * (1 - DAMAGE_VARIANCE + nextRandom() * DAMAGE_VARIANCE * 2)
        local hatchlingDamage = hatchlingPower
            * TICK_SECONDS
            * (1 - DAMAGE_VARIANCE + nextRandom() * DAMAGE_VARIANCE * 2)

        -- Apply both hits before checking knockouts so neither fighter gets a tick-order advantage.
        petHp = math.max(0, petHp - hatchlingDamage)
        hatchlingHp = math.max(0, hatchlingHp - petDamage)
        ticks += 1
    end

    local wasTieBreak = petHp <= 0 and hatchlingHp <= 0
    local winner: Winner
    local tieBreakSeed: number? = nil

    if wasTieBreak then
        tieBreakSeed = bit32.bxor(seed, TIE_BREAK_SEED_SALT)
        winner = if makeNextRandom(tieBreakSeed)() < 0.5 then "Pet" else "Hatchling"
    elseif petHp > 0 then
        winner = "Pet"
    else
        winner = "Hatchling"
    end

    return {
        Winner = winner,
        DurationSeconds = ticks * TICK_SECONDS,
        Ticks = ticks,
        PetRemainingHp = petHp,
        HatchlingRemainingHp = hatchlingHp,
        WasTieBreak = wasTieBreak,
        Seed = seed,
        TieBreakSeed = tieBreakSeed,
    }
end

return {
    Simulate = simulate,
}
