--!strict
-- T03 pacing simulation for Egg Raid Rush.
-- Values and combat rules are from GDD v0.11 sections 2.1, 4.2, 4.3, 5.1, 6, and 8.1.
-- This is a balance simulation only; it does not run in a gameplay service.
-- Tutorial assumption: the starter is a Sturdy Zone 1 Common pet (condition multiplier 1.00x).
-- If the starter condition differs, scale tutorial egg power and hatchling power from its effective power.
-- Simultaneous knockouts use a seeded coin toss. Runtime logs should store the fight seed and tie tick.

local TRIALS = 1_000_000
local TICK_SECONDS = 0.5
local DAMAGE_VARIANCE = 0.10
local TIE_BREAK_SEED_SALT = 0x1EDC6F41
local ZONE_ONE_RECOMMENDED_POWER = 300
local COMMON_POWER_MULTIPLIER = 0.40
local ZONE_ONE_COMMON_POWER = ZONE_ONE_RECOMMENDED_POWER * COMMON_POWER_MULTIPLIER
local TUTORIAL_BREAK_SECONDS = 4
local TUTORIAL_HATCHLING_POWER_RATIO = 0.5
local TUTORIAL_GUARD_SPEED = 8
local BASE_WALK_SPEED = 16
local CARRY_SPEED_MULTIPLIER = 0.90
local SPEED_PER_RANK = 0.075
local TUTORIAL_EGG_DISTANCE = 60
local GUARD_GRACE_SECONDS = 1.5

type Guard = {
    zone: number,
    name: string,
    speed: number,
}

type FightSummary = {
    wins: number,
    losses: number,
    tieBreaks: number,
    meanSeconds: number,
    firstTieTrial: number,
    firstTieTick: number,
    firstTieSeed: number,
    firstTieWinner: string,
}

local guards: { Guard } = {
    { zone = 1, name = "Pride King", speed = 12.0 },
    { zone = 2, name = "Gator King", speed = 14.5 },
    { zone = 3, name = "Rover-9000", speed = 17.0 },
    { zone = 4, name = "Sir Crumbsalot", speed = 19.5 },
    { zone = 5, name = "Captain Barnacle", speed = 22.0 },
    { zone = 6, name = "Grumblefire", speed = 24.5 },
}

local function makeSeededRandom(seed: number): () -> number
    local state = bit32.band(seed, 0xFFFFFFFF)
    if state == 0 then
        state = 1
    end

    return function(): number
        state = bit32.bxor(state, bit32.lshift(state, 13))
        state = bit32.bxor(state, bit32.rshift(state, 17))
        state = bit32.bxor(state, bit32.lshift(state, 5))
        return state / 4_294_967_296
    end
end

local function simulateFight(powerRatio: number, seed: number): FightSummary
    local nextRandom = makeSeededRandom(seed)
    local wins = 0
    local losses = 0
    local tieBreaks = 0
    local totalTicks = 0
    local firstTieTrial = 0
    local firstTieTick = 0
    local firstTieSeed = 0
    local firstTieWinner = ""

    for trialIndex = 1, TRIALS do
        -- GDD: each fighter has 10x its own power in HP and deals its power per second.
        local petPower = powerRatio
        local hatchlingPower = 1
        local petHp = 10 * petPower
        local hatchlingHp = 10 * hatchlingPower
        local ticks = 0

        while petHp > 0 and hatchlingHp > 0 do
            local petDamage = petPower * TICK_SECONDS * (1 - DAMAGE_VARIANCE + nextRandom() * DAMAGE_VARIANCE * 2)
            local hatchlingDamage = hatchlingPower
                * TICK_SECONDS
                * (1 - DAMAGE_VARIANCE + nextRandom() * DAMAGE_VARIANCE * 2)

            -- Apply both hits together so neither fighter gets a tick-order advantage.
            petHp -= hatchlingDamage
            hatchlingHp -= petDamage
            ticks += 1
        end

        totalTicks += ticks
        if petHp > 0 then
            wins += 1
        elseif hatchlingHp > 0 then
            losses += 1
        else
            -- Keep tie randomness independent so it cannot change later damage rolls.
            tieBreaks += 1
            local tieSeed = bit32.bxor(seed, bit32.bxor(trialIndex, TIE_BREAK_SEED_SALT))
            local tieRoll = makeSeededRandom(tieSeed)()
            if firstTieTrial == 0 then
                firstTieTrial = trialIndex
                firstTieTick = ticks
                firstTieSeed = tieSeed
                firstTieWinner = if tieRoll < 0.5 then "pet" else "hatchling"
            end
            if tieRoll < 0.5 then
                wins += 1
            else
                losses += 1
            end
        end
    end

    return {
        wins = wins,
        losses = losses,
        tieBreaks = tieBreaks,
        meanSeconds = totalTicks * TICK_SECONDS / TRIALS,
        firstTieTrial = firstTieTrial,
        firstTieTick = firstTieTick,
        firstTieSeed = firstTieSeed,
        firstTieWinner = firstTieWinner,
    }
end

local function carrierSpeed(rank: number): number
    return BASE_WALK_SPEED * (1 + SPEED_PER_RANK * rank) * CARRY_SPEED_MULTIPLIER
end

local function requiredRank(guardSpeed: number): number
    for rank = 0, 10 do
        if carrierSpeed(rank) > guardSpeed then
            return rank
        end
    end
    return -1
end

print("Fight simulation: " .. TRIALS .. " fights per power ratio")
for _, case in ipairs({
    { ratio = 0.5, seed = 3_865_616_673, label = "half-power pet" },
    { ratio = 1.0, seed = 3_866_116_673, label = "parity" },
    { ratio = 2.0, seed = 3_867_116_673, label = "double-power pet" },
}) do
    local result = simulateFight(case.ratio, case.seed)
    print(
        string.format(
            "%s: mean %.3fs; wins %.2f%%; losses %.2f%%; seeded tie-breaks %.2f%%",
            case.label,
            result.meanSeconds,
            result.wins / TRIALS * 100,
            result.losses / TRIALS * 100,
            result.tieBreaks / TRIALS * 100
        )
    )
    if result.firstTieTrial > 0 then
        print(
            string.format(
                "First tie replay: base seed %d; trial %d; tick %d; tie seed %d; winner %s",
                case.seed,
                result.firstTieTrial,
                result.firstTieTick,
                result.firstTieSeed,
                result.firstTieWinner
            )
        )
    end
end

print("Carrier speed and minimum outrun rank")
for _, guard in ipairs(guards) do
    local rank = requiredRank(guard.speed)
    print(
        string.format(
            "Zone %d %s: guard %.1f studs/s; rank %d; carrier %.2f studs/s",
            guard.zone,
            guard.name,
            guard.speed,
            rank,
            carrierSpeed(rank)
        )
    )
end

local tutorialHatchlingPower = ZONE_ONE_COMMON_POWER * TUTORIAL_HATCHLING_POWER_RATIO
local tutorialPowerRatio = ZONE_ONE_COMMON_POWER / tutorialHatchlingPower
local tutorialFight = simulateFight(tutorialPowerRatio, 3_867_116_673)
local tutorialBreakHealth = ZONE_ONE_COMMON_POWER * TUTORIAL_BREAK_SECONDS
local tutorialBreakDamagePerSecond = ZONE_ONE_COMMON_POWER
    * math.clamp(ZONE_ONE_COMMON_POWER / ZONE_ONE_COMMON_POWER, 0.1, 1.5)
local walkToEggSeconds = TUTORIAL_EGG_DISTANCE / BASE_WALK_SPEED
local runHomeSeconds = TUTORIAL_EGG_DISTANCE / carrierSpeed(0)
local tutorialFromSpawnSeconds = walkToEggSeconds
    + TUTORIAL_BREAK_SECONDS
    + tutorialFight.meanSeconds
    + GUARD_GRACE_SECONDS
    + runHomeSeconds

print(
    string.format(
        "Zone 1 Common power %.0f; tutorial hatchling power %.0f; tutorial egg HP %.0f; break %.1fs",
        ZONE_ONE_COMMON_POWER,
        tutorialHatchlingPower,
        tutorialBreakHealth,
        tutorialBreakHealth / tutorialBreakDamagePerSecond
    )
)
print(
    string.format(
        "Tutorial run: %.2fs walk to egg + %.1fs break + %.2fs fight + %.1fs guard grace + %.2fs run home = %.2fs from spawn",
        walkToEggSeconds,
        TUTORIAL_BREAK_SECONDS,
        tutorialFight.meanSeconds,
        GUARD_GRACE_SECONDS,
        runHomeSeconds,
        tutorialFromSpawnSeconds
    )
)
print(string.format("Tutorial Guard: %.1f studs/s; first drop forgiven: true", TUTORIAL_GUARD_SPEED))
