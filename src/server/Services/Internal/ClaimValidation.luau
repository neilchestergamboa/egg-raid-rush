--!strict

export type ResultCode =
    "Claimed"
    | "EggNotFound"
    | "EggUnavailable"
    | "EggObjectUnavailable"
    | "NoCharacter"
    | "TooFar"
    | "CarryingCreature"
    | "ProfileNotReady"
    | "NoPetEquipped"
    | "PetRecovering"
    | "FightInProgress"
    | "InvalidPet"

export type Context = {
    EggExists: boolean,
    EggState: string?,
    EggObjectExists: boolean,
    HasCharacter: boolean,
    IsWithinRange: boolean,
    IsCarryingCreature: boolean,
    IsFighting: boolean,
    HasProfile: boolean,
    ChampionPet: any?,
    Now: number,
}

local function isFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

local function validate(context: Context): (ResultCode, number?)
    if not context.EggExists then
        return "EggNotFound", nil
    end
    if context.EggState ~= "Sealed" then
        return "EggUnavailable", nil
    end
    if not context.EggObjectExists then
        return "EggObjectUnavailable", nil
    end
    if not context.HasCharacter then
        return "NoCharacter", nil
    end
    if not context.IsWithinRange then
        return "TooFar", nil
    end
    if context.IsCarryingCreature then
        return "CarryingCreature", nil
    end
    if context.IsFighting then
        return "FightInProgress", nil
    end
    if not context.HasProfile then
        return "ProfileNotReady", nil
    end

    local pet = context.ChampionPet
    if pet == nil then
        return "NoPetEquipped", nil
    end
    if type(pet.KnockedOutUntil) ~= "number" or not isFinite(pet.KnockedOutUntil) then
        return "InvalidPet", nil
    end
    if pet.KnockedOutUntil > context.Now then
        return "PetRecovering", nil
    end
    if type(pet.Power) ~= "number" or not isFinite(pet.Power) or pet.Power <= 0 then
        return "InvalidPet", nil
    end
    return "Claimed", pet.Power
end

return { Validate = validate }
