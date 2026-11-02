--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("JestGlobals") :: ModuleScript)
local ProfileSchema = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("ProfileSchema") :: ModuleScript
)
local ProfileSessionManager = require(
    ServerScriptService:WaitForChild("ServerServices"):WaitForChild("Internal"):WaitForChild("ProfileSessionManager") :: ModuleScript
)

JestGlobals.describe("ProfileSchema", function()
    JestGlobals.it("creates the Phase A profile template", function()
        local template = ProfileSchema.CreateTemplate()
        JestGlobals.expect(template.Version).toBe(ProfileSchema.CurrentVersion)
        JestGlobals.expect(template.Pets).toEqual({})
        JestGlobals.expect(template.ChampionPetUid).toBe("")
        JestGlobals.expect(template.SpeedPoints).toBe(0)
    end)

    JestGlobals.it("grants a stable Sturdy Jackal Pup starter and equips it", function()
        local ok, migratedOrError = ProfileSchema.Migrate(ProfileSchema.CreateTemplate(), 2468)
        JestGlobals.expect(ok).toBe(true)
        local migrated = migratedOrError :: any
        JestGlobals.expect(migrated.ChampionPetUid).toBe("starter-2468")
        JestGlobals.expect(migrated.Pets["starter-2468"]).toEqual({
            DefId = "pet_jackal_pup",
            Condition = "Sturdy",
            Power = 120,
            Gps = 1,
            KnockedOutUntil = 0,
            Source = "Starter",
        })
    end)

    JestGlobals.it("migrates unversioned data without discarding existing fields", function()
        local legacy = { SpeedPoints = 400, PreviousField = "keep" }
        local ok, migratedOrError = ProfileSchema.Migrate(legacy, 2468)
        JestGlobals.expect(ok).toBe(true)
        local migrated = migratedOrError :: any
        JestGlobals.expect(migrated.Version).toBe(1)
        JestGlobals.expect(migrated.SpeedPoints).toBe(400)
        JestGlobals.expect(migrated.PreviousField).toBe("keep")
        JestGlobals.expect(migrated.Pets["starter-2468"] ~= nil).toBe(true)
    end)

    JestGlobals.it("preserves existing pets and fills a missing Champion deterministically", function()
        local existingPet = {
            DefId = "pet_hyena_pup",
            Condition = "Sturdy",
            Power = 120,
            Gps = 1,
            KnockedOutUntil = 0,
            Source = "Starter",
        }
        local legacy = { Pets = { hyena_uid = existingPet }, SpeedPoints = 15 }
        local ok, migratedOrError = ProfileSchema.Migrate(legacy, 2468)
        JestGlobals.expect(ok).toBe(true)
        local migrated = migratedOrError :: any
        JestGlobals.expect(migrated.Pets.hyena_uid).toEqual(existingPet)
        JestGlobals.expect(migrated.ChampionPetUid).toBe("hyena_uid")
        JestGlobals.expect(migrated.SpeedPoints).toBe(15)
    end)

    JestGlobals.it("is idempotent when the same profile is migrated twice", function()
        local firstOk, firstOrError = ProfileSchema.Migrate(ProfileSchema.CreateTemplate(), 2468)
        JestGlobals.expect(firstOk).toBe(true)
        local secondOk, secondOrError = ProfileSchema.Migrate(firstOrError, 2468)
        JestGlobals.expect(secondOk).toBe(true)
        JestGlobals.expect(secondOrError).toEqual(firstOrError)
    end)

    JestGlobals.it("rejects future versions and malformed profiles without mutating them", function()
        local future = { Version = 99, Pets = {}, ChampionPetUid = "", SpeedPoints = 0 }
        local originalFuture = table.clone(future)
        local futureOk = ProfileSchema.Migrate(future, 2468)
        JestGlobals.expect(futureOk).toBe(false)
        JestGlobals.expect(future).toEqual(originalFuture)

        local malformed = { Version = 0, Pets = "not a table", SpeedPoints = 0 }
        local originalMalformed = table.clone(malformed)
        local malformedOk = ProfileSchema.Migrate(malformed, 2468)
        JestGlobals.expect(malformedOk).toBe(false)
        JestGlobals.expect(malformed).toEqual(originalMalformed)
    end)
end)

local function makeSignal()
    local callbacks = {}
    return {
        Connect = function(_, callback)
            table.insert(callbacks, callback)
            return { Disconnect = function() end }
        end,
        Fire = function()
            for _, callback in callbacks do
                callback()
            end
        end,
    }
end

local function makeProfile(data: any)
    local sessionEndSignal = makeSignal()
    local profile = {
        Data = data,
        Active = true,
        EndCalls = 0,
        AddedUserIds = {},
        OnSessionEnd = sessionEndSignal,
        IsActive = function(self)
            return self.Active
        end,
        AddUserId = function(self, userId)
            table.insert(self.AddedUserIds, userId)
        end,
        EndSession = function(self)
            if self.Active then
                self.EndCalls += 1
                self.Active = false
                self.OnSessionEnd:Fire()
            end
        end,
        TriggerExternalEnd = function(self)
            self.Active = false
            self.OnSessionEnd:Fire()
        end,
    }
    return profile
end

local function makeStore(profile: any)
    local store = { Calls = 0, Profile = profile, OnStart = nil }
    function store:StartSessionAsync(_key, options)
        self.Calls += 1
        if self.OnStart ~= nil then
            self.OnStart(options)
        end
        return self.Profile
    end
    return store
end

local function makePlayer(userId: number)
    return { UserId = userId, Connected = true, KickCount = 0 }
end

JestGlobals.describe("ProfileSessionManager", function()
    JestGlobals.it("loads one session and treats duplicate loads idempotently", function()
        local player = makePlayer(51)
        local profile = makeProfile(ProfileSchema.CreateTemplate())
        local store = makeStore(profile)
        local nestedLoadOk: boolean? = nil
        local manager = ProfileSessionManager.new(store, ProfileSchema, function(user)
            return user.Connected
        end, function() end)
        store.OnStart = function()
            nestedLoadOk = manager:Load(player)
        end

        local loaded = manager:Load(player)
        local duplicateLoaded = manager:Load(player)
        JestGlobals.expect(loaded).toBe(true)
        JestGlobals.expect(nestedLoadOk).toBe(false)
        JestGlobals.expect(duplicateLoaded).toBe(true)
        JestGlobals.expect(store.Calls).toBe(1)
        JestGlobals.expect(profile.AddedUserIds).toEqual({ 51 })
        JestGlobals.expect(manager:GetProfile(51)).toBe(profile)
    end)

    JestGlobals.it("returns a typed failure when ProfileStore cannot acquire a session", function()
        local player = makePlayer(52)
        local store = makeStore(nil)
        local manager = ProfileSessionManager.new(store, ProfileSchema, function(user)
            return user.Connected
        end, function() end)

        local loaded, reason = manager:Load(player)
        JestGlobals.expect(loaded).toBe(false)
        JestGlobals.expect(reason).toBe("ProfileSessionUnavailable")
        JestGlobals.expect(manager:GetProfile(52)).toBe(nil)
    end)

    JestGlobals.it("ends a session when the player leaves during loading", function()
        local player = makePlayer(53)
        local profile = makeProfile(ProfileSchema.CreateTemplate())
        local store = makeStore(profile)
        local manager = ProfileSessionManager.new(store, ProfileSchema, function(user)
            return user.Connected
        end, function() end)
        store.OnStart = function(options)
            player.Connected = false
            JestGlobals.expect(options.Cancel()).toBe(true)
        end

        local loaded, reason = manager:Load(player)
        JestGlobals.expect(loaded).toBe(false)
        JestGlobals.expect(reason).toBe("PlayerLeftDuringProfileLoad")
        JestGlobals.expect(profile.EndCalls).toBe(1)
        JestGlobals.expect(manager:GetProfile(53)).toBe(nil)
    end)

    JestGlobals.it("releases a profile once and tolerates duplicate release", function()
        local player = makePlayer(54)
        local profile = makeProfile(ProfileSchema.CreateTemplate())
        local manager = ProfileSessionManager.new(makeStore(profile), ProfileSchema, function(user)
            return user.Connected
        end, function() end)
        JestGlobals.expect(manager:Load(player)).toBe(true)

        local released = manager:Release(player)
        local duplicateReleased = manager:Release(player)
        JestGlobals.expect(released).toBe(true)
        JestGlobals.expect(duplicateReleased).toBe(false)
        JestGlobals.expect(profile.EndCalls).toBe(1)
        JestGlobals.expect(manager:GetProfile(54)).toBe(nil)
    end)

    JestGlobals.it("releases a session and returns a failure when profile migration is rejected", function()
        local player = makePlayer(55)
        local profile = makeProfile(ProfileSchema.CreateTemplate())
        local manager = ProfileSessionManager.new(makeStore(profile), {
            Migrate = function()
                return false, "UnsupportedProfileVersion"
            end,
        }, function(user)
            return user.Connected
        end, function() end)

        local loaded, reason = manager:Load(player)
        JestGlobals.expect(loaded).toBe(false)
        JestGlobals.expect(reason).toBe("UnsupportedProfileVersion")
        JestGlobals.expect(profile.EndCalls).toBe(1)
        JestGlobals.expect(manager:GetProfile(55)).toBe(nil)
    end)

    JestGlobals.it("removes and reports an unexpectedly ended session", function()
        local player = makePlayer(56)
        local profile = makeProfile(ProfileSchema.CreateTemplate())
        local kickCount = 0
        local manager = ProfileSessionManager.new(makeStore(profile), ProfileSchema, function(user)
            return user.Connected
        end, function(user)
            user.KickCount += 1
            kickCount += 1
        end)
        JestGlobals.expect(manager:Load(player)).toBe(true)

        profile:TriggerExternalEnd()
        JestGlobals.expect(manager:GetProfile(56)).toBe(nil)
        JestGlobals.expect(kickCount).toBe(1)
    end)
end)
