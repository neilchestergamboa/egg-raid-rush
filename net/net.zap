-- Egg Raid Rush network contracts.

type EggActionResultCode = enum {
    Claimed,
    ClaimLostRace,
    EggNotFound,
    EggUnavailable,
    EggObjectUnavailable,
    NoCharacter,
    TooFar,
    CarryingCreature,
    ProfileNotReady,
    NoPetEquipped,
    PetRecovering,
    InvalidPet,
    RateLimited,
    ServerError,
}

funct RequestEgg = {
    call: Async,
    args: (eggUid: string.utf8(1..64)),
    rets: EggActionResultCode,
}
