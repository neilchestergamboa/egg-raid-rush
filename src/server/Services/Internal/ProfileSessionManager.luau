--!strict

export type PlayerRef = { UserId: number }

export type ProfileSessionManager = {
    Load: (self: ProfileSessionManager, player: PlayerRef) -> (boolean, string?),
    Release: (self: ProfileSessionManager, player: PlayerRef) -> (boolean, string?),
    GetProfile: (self: ProfileSessionManager, userId: number) -> any?,
    SetPetKnockedOutUntil: (
        self: ProfileSessionManager,
        userId: number,
        petUid: string,
        untilTime: number
    ) -> (boolean, string?),
    GetOrCreateHatchRoll: (
        self: ProfileSessionManager,
        userId: number,
        eggUid: string,
        conditionId: string,
        seed: number
    ) -> (any?, string?),
    ClearHatchRoll: (self: ProfileSessionManager, userId: number, eggUid: string) -> (boolean, string?),
    GrantPet: (self: ProfileSessionManager, userId: number, petUid: string, petData: any) -> (boolean, string?),
    CompleteTutorial: (self: ProfileSessionManager, userId: number) -> (boolean, string?),
    ConsumeTutorialFirstDropForgiveness: (self: ProfileSessionManager, userId: number) -> (boolean, string?),
}

type SessionRecord = {
    Player: PlayerRef,
    Profile: any,
}

local function new(
    playerStore: any,
    profileSchema: any,
    isPlayerConnected: (PlayerRef) -> boolean,
    onUnexpectedSessionEnd: (PlayerRef) -> ()
): ProfileSessionManager
    local profilesByUserId: { [number]: SessionRecord } = {}
    local loadingPlayersByUserId: { [number]: PlayerRef } = {}
    local manager: any = {}

    function manager:Load(player: PlayerRef): (boolean, string?)
        local userId = player.UserId
        local current = profilesByUserId[userId]
        if current ~= nil and current.Player == player and current.Profile:IsActive() then
            return true, nil
        end
        if current ~= nil then
            profilesByUserId[userId] = nil
        end
        if loadingPlayersByUserId[userId] == player then
            return false, "ProfileLoadAlreadyInProgress"
        end

        loadingPlayersByUserId[userId] = player
        local loadOk, profileOrError = pcall(function()
            return playerStore:StartSessionAsync(tostring(userId), {
                Cancel = function()
                    return not isPlayerConnected(player) or loadingPlayersByUserId[userId] ~= player
                end,
            })
        end)
        if loadingPlayersByUserId[userId] == player then
            loadingPlayersByUserId[userId] = nil
        end
        if not loadOk then
            return false, tostring(profileOrError)
        end

        local profile = profileOrError
        if profile == nil then
            return false, "ProfileSessionUnavailable"
        end
        if not isPlayerConnected(player) then
            profile:EndSession()
            return false, "PlayerLeftDuringProfileLoad"
        end

        local migrationCallOk, didMigrate, migratedDataOrError = pcall(function()
            return profileSchema.Migrate(profile.Data, userId)
        end)
        if not migrationCallOk then
            profile:EndSession()
            return false, tostring(didMigrate)
        end
        if not didMigrate then
            profile:EndSession()
            return false, tostring(migratedDataOrError)
        end
        if not isPlayerConnected(player) then
            profile:EndSession()
            return false, "PlayerLeftDuringProfileLoad"
        end

        profile.Data = migratedDataOrError
        local addUserIdOk, addUserIdError = pcall(function()
            profile:AddUserId(userId)
        end)
        if not addUserIdOk then
            profile:EndSession()
            return false, tostring(addUserIdError)
        end

        profilesByUserId[userId] = { Player = player, Profile = profile }
        profile.OnSessionEnd:Connect(function()
            local activeRecord = profilesByUserId[userId]
            if activeRecord ~= nil and activeRecord.Profile == profile then
                profilesByUserId[userId] = nil
                if isPlayerConnected(player) then
                    onUnexpectedSessionEnd(player)
                end
            end
        end)
        return true, nil
    end

    function manager:Release(player: PlayerRef): (boolean, string?)
        local userId = player.UserId
        local record = profilesByUserId[userId]
        if record == nil or record.Player ~= player then
            return false, "ProfileNotLoaded"
        end

        -- Remove ownership before ending; ProfileStore signals OnSessionEnd for a normal release too.
        profilesByUserId[userId] = nil
        local endOk, endError = pcall(function()
            if record.Profile:IsActive() then
                record.Profile:EndSession()
            end
        end)
        if not endOk then
            return false, tostring(endError)
        end
        return true, nil
    end

    function manager:GetProfile(userId: number): any?
        local record = profilesByUserId[userId]
        if record == nil then
            return nil
        end
        return record.Profile
    end

    function manager:SetPetKnockedOutUntil(userId: number, petUid: string, untilTime: number): (boolean, string?)
        local record = profilesByUserId[userId]
        if record == nil or not record.Profile:IsActive() then
            return false, "ProfileNotLoaded"
        end
        if type(petUid) ~= "string" or petUid == "" then
            return false, "InvalidPetUid"
        end
        if type(untilTime) ~= "number" or untilTime ~= untilTime or untilTime < 0 or untilTime == math.huge then
            return false, "InvalidKnockoutExpiry"
        end
        local pet = record.Profile.Data.Pets[petUid]
        if type(pet) ~= "table" then
            return false, "PetNotFound"
        end
        pet.KnockedOutUntil = untilTime
        return true, nil
    end

    function manager:GetOrCreateHatchRoll(
        userId: number,
        eggUid: string,
        conditionId: string,
        seed: number
    ): (any?, string?)
        local record = profilesByUserId[userId]
        if record == nil or not record.Profile:IsActive() then
            return nil, "ProfileNotLoaded"
        end
        if
            type(eggUid) ~= "string"
            or eggUid == ""
            or type(conditionId) ~= "string"
            or conditionId == ""
            or type(seed) ~= "number"
            or seed ~= seed
            or seed < 0
            or seed > 0xFFFFFFFF
            or seed % 1 ~= 0
        then
            return nil, "InvalidHatchRoll"
        end
        local rolls = record.Profile.Data.PendingHatchRolls
        local existing = rolls[eggUid]
        if existing ~= nil then
            return table.clone(existing), nil
        end
        local committed = { ConditionId = conditionId, Seed = seed }
        rolls[eggUid] = committed
        return table.clone(committed), nil
    end

    function manager:ClearHatchRoll(userId: number, eggUid: string): (boolean, string?)
        local record = profilesByUserId[userId]
        if record == nil or not record.Profile:IsActive() then
            return false, "ProfileNotLoaded"
        end
        if type(eggUid) ~= "string" or eggUid == "" then
            return false, "InvalidEggUid"
        end
        record.Profile.Data.PendingHatchRolls[eggUid] = nil
        return true, nil
    end

    function manager:GrantPet(userId: number, petUid: string, petData: any): (boolean, string?)
        local record = profilesByUserId[userId]
        if record == nil or not record.Profile:IsActive() then
            return false, "ProfileNotLoaded"
        end
        if type(petUid) ~= "string" or petUid == "" or type(petData) ~= "table" then
            return false, "InvalidPetGrant"
        end
        local pets = record.Profile.Data.Pets
        local existing = pets[petUid]
        if existing ~= nil then
            if
                existing.DefId == petData.DefId
                and existing.Condition == petData.Condition
                and existing.Power == petData.Power
                and existing.Gps == petData.Gps
                and existing.Source == petData.Source
            then
                return true, "AlreadyGranted"
            end
            return false, "PetUidConflict"
        end
        pets[petUid] = table.clone(petData)
        return true, nil
    end

    function manager:CompleteTutorial(userId: number): (boolean, string?)
        local record = profilesByUserId[userId]
        if record == nil or not record.Profile:IsActive() then
            return false, "ProfileNotLoaded"
        end
        record.Profile.Data.TutorialCompleted = true
        return true, nil
    end

    function manager:ConsumeTutorialFirstDropForgiveness(userId: number): (boolean, string?)
        local record = profilesByUserId[userId]
        if record == nil or not record.Profile:IsActive() then
            return false, "ProfileNotLoaded"
        end
        local data = record.Profile.Data
        if data.TutorialFirstDropForgiven then
            return false, "AlreadyForgiven"
        end
        data.TutorialFirstDropForgiven = true
        return true, nil
    end

    return manager :: ProfileSessionManager
end

return { new = new }
