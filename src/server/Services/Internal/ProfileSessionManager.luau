--!strict

export type PlayerRef = { UserId: number }

export type ProfileSessionManager = {
    Load: (self: ProfileSessionManager, player: PlayerRef) -> (boolean, string?),
    Release: (self: ProfileSessionManager, player: PlayerRef) -> (boolean, string?),
    GetProfile: (self: ProfileSessionManager, userId: number) -> any?,
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

    return manager :: ProfileSessionManager
end

return { new = new }
