--!strict

local Shared = script.Parent.Parent
local ConfigFolder = Shared:WaitForChild("Config")
local RulesFolder = Shared:WaitForChild("Rules")
local PetDefs = require(ConfigFolder:WaitForChild("PetDefs") :: ModuleScript)
local ConditionDefs = require(ConfigFolder:WaitForChild("ConditionDefs") :: ModuleScript)
local PetPower = require(RulesFolder:WaitForChild("PetPower") :: ModuleScript)

local CURRENT_VERSION = 3
local STARTER_PET_DEF_ID = "pet_jackal_pup"
local STARTER_CONDITION_ID = "Sturdy"

export type PetData = {
    DefId: string,
    Condition: string,
    Power: number,
    Gps: number,
    KnockedOutUntil: number,
    Source: string,
}

export type ProfileData = {
    Version: number,
    Pets: { [string]: PetData },
    ChampionPetUid: string,
    SpeedPoints: number,
    PendingHatchRolls: { [string]: { ConditionId: string, Seed: number } },
    TutorialCompleted: boolean,
    TutorialFirstDropForgiven: boolean,
}

local function isFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

local function createStarterPet(): PetData
    local definition = PetDefs[STARTER_PET_DEF_ID]
    local condition = ConditionDefs[STARTER_CONDITION_ID]
    return {
        DefId = STARTER_PET_DEF_ID,
        Condition = STARTER_CONDITION_ID,
        Power = PetPower.Calculate(definition.BasePower, condition.PowerMultiplier),
        Gps = definition.Gps,
        KnockedOutUntil = 0,
        Source = "Starter",
    }
end

local function validatePets(pets: any): (boolean, string?)
    if type(pets) ~= "table" then
        return false, "Pets must be a table."
    end
    for uid, pet in pairs(pets) do
        if type(uid) ~= "string" or uid == "" then
            return false, "Pet UIDs must be non-empty strings."
        end
        if type(pet) ~= "table" then
            return false, "Pets." .. uid .. " must be a table."
        end
        if type(pet.DefId) ~= "string" or type(PetDefs[pet.DefId]) ~= "table" then
            return false, "Pets." .. uid .. ".DefId must reference a known pet definition."
        end
        if type(pet.Condition) ~= "string" or type(ConditionDefs[pet.Condition]) ~= "table" then
            return false, "Pets." .. uid .. ".Condition must reference a known condition."
        end
        if type(pet.Power) ~= "number" or not isFinite(pet.Power) or pet.Power <= 0 then
            return false, "Pets." .. uid .. ".Power must be a finite positive number."
        end
        if type(pet.Gps) ~= "number" or not isFinite(pet.Gps) or pet.Gps < 0 then
            return false, "Pets." .. uid .. ".Gps must be a finite non-negative number."
        end
        if type(pet.KnockedOutUntil) ~= "number" or not isFinite(pet.KnockedOutUntil) or pet.KnockedOutUntil < 0 then
            return false, "Pets." .. uid .. ".KnockedOutUntil must be a finite non-negative number."
        end
        if type(pet.Source) ~= "string" or pet.Source == "" then
            return false, "Pets." .. uid .. ".Source must be a non-empty string."
        end
    end
    return true, nil
end

local function getFirstPetUid(pets: { [string]: PetData }): string?
    local uids = {}
    for uid in pairs(pets) do
        table.insert(uids, uid)
    end
    table.sort(uids)
    return uids[1]
end

local function createTemplate(): ProfileData
    return {
        Version = CURRENT_VERSION,
        Pets = {},
        ChampionPetUid = "",
        SpeedPoints = 0,
        PendingHatchRolls = {},
        TutorialCompleted = false,
        TutorialFirstDropForgiven = false,
    }
end

local function migrate(source: any, userId: number): (boolean, ProfileData | string)
    if type(source) ~= "table" then
        return false, "Profile data must be a table."
    end
    if not isFinite(userId) or userId <= 0 or userId % 1 ~= 0 then
        return false, "UserId must be a positive integer."
    end

    local version = source.Version
    if version == nil then
        version = 0
    elseif type(version) ~= "number" or not isFinite(version) or version < 0 or version % 1 ~= 0 then
        return false, "Profile Version must be a non-negative integer."
    end
    if version > CURRENT_VERSION then
        return false, "Profile Version is newer than this server supports."
    end

    local sourcePets = source.Pets
    if sourcePets == nil then
        sourcePets = {}
    end
    local petsValid, petsError = validatePets(sourcePets)
    if not petsValid then
        return false, petsError or "Profile Pets are invalid."
    end

    local sourceChampionUid = source.ChampionPetUid
    if sourceChampionUid ~= nil and type(sourceChampionUid) ~= "string" then
        return false, "ChampionPetUid must be a string."
    end
    if sourceChampionUid ~= nil and sourceChampionUid ~= "" and sourcePets[sourceChampionUid] == nil then
        return false, "ChampionPetUid must reference an owned pet."
    end

    local sourceSpeedPoints = source.SpeedPoints
    if sourceSpeedPoints == nil then
        sourceSpeedPoints = 0
    end
    if type(sourceSpeedPoints) ~= "number" or not isFinite(sourceSpeedPoints) or sourceSpeedPoints < 0 then
        return false, "SpeedPoints must be a finite non-negative number."
    end
    local pendingHatchRolls = source.PendingHatchRolls
    if pendingHatchRolls == nil then
        pendingHatchRolls = {}
    end
    if type(pendingHatchRolls) ~= "table" then
        return false, "PendingHatchRolls must be a table."
    end
    local tutorialCompleted = source.TutorialCompleted
    if tutorialCompleted == nil then
        tutorialCompleted = false
    elseif type(tutorialCompleted) ~= "boolean" then
        return false, "TutorialCompleted must be a boolean."
    end
    local tutorialFirstDropForgiven = source.TutorialFirstDropForgiven
    if tutorialFirstDropForgiven == nil then
        tutorialFirstDropForgiven = false
    elseif type(tutorialFirstDropForgiven) ~= "boolean" then
        return false, "TutorialFirstDropForgiven must be a boolean."
    end
    for eggUid, roll in pairs(pendingHatchRolls) do
        if
            type(eggUid) ~= "string"
            or eggUid == ""
            or type(roll) ~= "table"
            or type(roll.ConditionId) ~= "string"
            or type(ConditionDefs[roll.ConditionId]) ~= "table"
            or type(roll.Seed) ~= "number"
            or not isFinite(roll.Seed)
            or roll.Seed < 0
            or roll.Seed > 0xFFFFFFFF
            or roll.Seed % 1 ~= 0
        then
            return false, "PendingHatchRolls contains an invalid roll."
        end
    end

    -- Version 0 represents pre-versioned prototype data. Preserve all existing fields.
    local migrated = table.clone(source)
    migrated.Version = CURRENT_VERSION
    migrated.Pets = table.clone(sourcePets)
    migrated.SpeedPoints = sourceSpeedPoints
    migrated.PendingHatchRolls = table.clone(pendingHatchRolls)
    migrated.ChampionPetUid = sourceChampionUid or ""
    migrated.TutorialCompleted = tutorialCompleted
    migrated.TutorialFirstDropForgiven = tutorialFirstDropForgiven

    if next(migrated.Pets) == nil then
        local starterUid = "starter-" .. tostring(userId)
        migrated.Pets[starterUid] = createStarterPet()
        migrated.ChampionPetUid = starterUid
    elseif migrated.ChampionPetUid == "" then
        local firstPetUid = getFirstPetUid(migrated.Pets)
        if firstPetUid == nil then
            return false, "Profile has no pet available to equip as Champion."
        end
        migrated.ChampionPetUid = firstPetUid
    end

    return true, migrated :: ProfileData
end

return {
    CurrentVersion = CURRENT_VERSION,
    CreateTemplate = createTemplate,
    Migrate = migrate,
}
