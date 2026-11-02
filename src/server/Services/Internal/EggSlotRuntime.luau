--!strict

export type EggState =
    "Sealed"
    | "Claimed"
    | "Breaking"
    | "Released"
    | "Fighting"
    | "Won"
    | "Lost"
    | "Carried"
    | "Banked"
    | "Respawning"

export type EggSlotDefinition = {
    Uid: string,
    DefId: string,
    ZoneId: number,
    Slot: number?,
    RarityId: string,
    RespawnSeconds: number,
    IsTutorial: boolean,
}

export type EggSlotRecord = EggSlotDefinition & {
    State: EggState,
    ClaimantUserId: number?,
    ExpiresAt: number?,
    RespawnSourceState: "Lost" | "Banked"?,
    ConditionRoll: string?,
    ConditionSeed: number?,
    ConditionRollOwnerUserId: number?,
    ClaimedPetUid: string?,
    ClaimedPetPower: number?,
}

export type EggSlotRuntime = {
    TryClaim: (self: EggSlotRuntime, uid: string, claimantUserId: number) -> (boolean, string?),
    SetExpiresAt: (self: EggSlotRuntime, uid: string, expiresAt: number) -> (boolean, string?),
    ClearExpiresAt: (self: EggSlotRuntime, uid: string) -> (boolean, string?),
    ReleaseClaim: (self: EggSlotRuntime, uid: string, reason: string) -> (boolean, string?),
    Transition: (self: EggSlotRuntime, uid: string, targetState: EggState) -> (boolean, string?),
    GetSlot: (self: EggSlotRuntime, uid: string) -> EggSlotRecord?,
    GetAllSlots: (self: EggSlotRuntime) -> { EggSlotRecord },
    CommitHatch: (
        self: EggSlotRuntime,
        uid: string,
        claimantUserId: number,
        petUid: string,
        petPower: number,
        conditionId: string,
        seed: number
    ) -> (boolean, string?),
}

type RuntimeOptions = {
    Now: () -> number,
    Schedule: (seconds: number, callback: () -> ()) -> (),
    OnChanged: (record: EggSlotRecord, previousState: EggState?, reason: string) -> (),
}

local VALID_NEXT_STATES: { [EggState]: { [EggState]: boolean } } = {
    Sealed = { Claimed = true },
    Claimed = { Breaking = true, Released = true },
    Breaking = { Fighting = true, Released = true },
    Released = { Sealed = true },
    Fighting = { Won = true, Lost = true },
    Won = { Carried = true },
    Carried = { Banked = true },
    Lost = {},
    Banked = {},
    Respawning = {},
}

local function cloneRecord(record: EggSlotRecord): EggSlotRecord
    return table.clone(record)
end

local function isFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

local function new(definitions: { EggSlotDefinition }, options: RuntimeOptions): EggSlotRuntime
    local recordsByUid: { [string]: EggSlotRecord } = {}
    local orderedUids = {}
    local respawnGenerationByUid: { [string]: number } = {}
    local runtime: any = {}

    for _, definition in definitions do
        assert(definition.Uid ~= "", "Egg slot Uid must be non-empty.")
        assert(recordsByUid[definition.Uid] == nil, "Egg slot Uids must be unique.")
        assert(definition.RespawnSeconds > 0, "Egg slot respawn time must be positive.")
        local record: EggSlotRecord = {
            Uid = definition.Uid,
            DefId = definition.DefId,
            ZoneId = definition.ZoneId,
            Slot = definition.Slot,
            RarityId = definition.RarityId,
            RespawnSeconds = definition.RespawnSeconds,
            IsTutorial = definition.IsTutorial,
            State = "Sealed",
            ClaimantUserId = nil,
            ExpiresAt = nil,
            RespawnSourceState = nil,
            ConditionRoll = nil,
            ConditionSeed = nil,
            ConditionRollOwnerUserId = nil,
            ClaimedPetUid = nil,
            ClaimedPetPower = nil,
        }
        recordsByUid[record.Uid] = record
        table.insert(orderedUids, record.Uid)
        respawnGenerationByUid[record.Uid] = 0
        options.OnChanged(cloneRecord(record), nil, "Initialized")
    end

    table.sort(orderedUids)

    local function getRecord(uid: string): EggSlotRecord?
        return recordsByUid[uid]
    end

    local function commitState(record: EggSlotRecord, nextState: EggState, reason: string)
        local previousState = record.State
        record.State = nextState
        options.OnChanged(cloneRecord(record), previousState, reason)
    end

    local function beginRespawn(record: EggSlotRecord, sourceState: "Lost" | "Banked")
        record.ClaimantUserId = nil
        record.ExpiresAt = nil
        record.ConditionRoll = nil
        record.ConditionSeed = nil
        record.ConditionRollOwnerUserId = nil
        record.ClaimedPetUid = nil
        record.ClaimedPetPower = nil
        commitState(record, sourceState, "EggConsumed")
        record.RespawnSourceState = sourceState
        record.ExpiresAt = options.Now() + record.RespawnSeconds
        commitState(record, "Respawning", "RespawnScheduled")

        local uid = record.Uid
        local generation = (respawnGenerationByUid[uid] or 0) + 1
        respawnGenerationByUid[uid] = generation

        local function finishRespawn()
            local current = recordsByUid[uid]
            if current == nil or current.State ~= "Respawning" or respawnGenerationByUid[uid] ~= generation then
                return
            end

            local remaining = (current.ExpiresAt or 0) - options.Now()
            if remaining > 0 then
                options.Schedule(remaining, finishRespawn)
                return
            end

            current.ClaimantUserId = nil
            current.ExpiresAt = nil
            current.RespawnSourceState = nil
            commitState(current, "Sealed", "RespawnComplete")
        end

        options.Schedule(record.RespawnSeconds, finishRespawn)
    end

    function runtime:CommitHatch(
        uid: string,
        claimantUserId: number,
        petUid: string,
        petPower: number,
        conditionId: string,
        seed: number
    ): (boolean, string?)
        local record = getRecord(uid)
        if record == nil then
            return false, "EggNotFound"
        end
        if record.State ~= "Claimed" or record.ClaimantUserId ~= claimantUserId then
            return false, "EggNotClaimedByPlayer"
        end
        if petUid == "" or not isFinite(petPower) or petPower <= 0 or conditionId == "" then
            return false, "InvalidHatchCommit"
        end
        if not isFinite(seed) or seed < 0 or seed % 1 ~= 0 or seed > 0xFFFFFFFF then
            return false, "InvalidConditionSeed"
        end
        if record.ConditionRoll == nil or record.ConditionRollOwnerUserId ~= claimantUserId then
            record.ConditionRoll = conditionId
            record.ConditionSeed = seed
            record.ConditionRollOwnerUserId = claimantUserId
        end
        record.ClaimedPetUid = petUid
        record.ClaimedPetPower = petPower
        options.OnChanged(cloneRecord(record), record.State, "HatchConditionCommitted")
        return true, nil
    end

    function runtime:SetExpiresAt(uid: string, expiresAt: number): (boolean, string?)
        local record = getRecord(uid)
        if record == nil then
            return false, "EggNotFound"
        end
        if record.State ~= "Claimed" and record.State ~= "Breaking" then
            return false, "EggNotClaimed"
        end
        if not isFinite(expiresAt) or expiresAt <= options.Now() then
            return false, "InvalidExpiry"
        end
        if record.ExpiresAt == expiresAt then
            return true, nil
        end

        record.ExpiresAt = expiresAt
        options.OnChanged(cloneRecord(record), record.State, "ExpiresAtUpdated")
        return true, nil
    end

    function runtime:ClearExpiresAt(uid: string): (boolean, string?)
        local record = getRecord(uid)
        if record == nil then
            return false, "EggNotFound"
        end
        if record.ExpiresAt == nil then
            return true, nil
        end

        record.ExpiresAt = nil
        options.OnChanged(cloneRecord(record), record.State, "ExpiresAtCleared")
        return true, nil
    end

    function runtime:TryClaim(uid: string, claimantUserId: number): (boolean, string?)
        local record = getRecord(uid)
        if record == nil then
            return false, "EggNotFound"
        end
        if claimantUserId <= 0 or claimantUserId % 1 ~= 0 then
            return false, "InvalidClaimant"
        end
        if record.State == "Claimed" and record.ClaimantUserId == claimantUserId then
            return true, nil
        end

        if record.State ~= "Sealed" then
            return false, "EggNotSealed"
        end

        record.ClaimantUserId = claimantUserId
        commitState(record, "Claimed", "Claimed")
        return true, nil
    end

    function runtime:ReleaseClaim(uid: string, reason: string): (boolean, string?)
        local record = getRecord(uid)
        if record == nil then
            return false, "EggNotFound"
        end
        if record.State == "Sealed" then
            return true, nil
        end
        if record.State ~= "Claimed" and record.State ~= "Breaking" then
            return false, "EggCannotBeReleased"
        end

        commitState(record, "Released", reason)
        record.ClaimantUserId = nil
        record.ExpiresAt = nil
        record.ClaimedPetUid = nil
        record.ClaimedPetPower = nil
        commitState(record, "Sealed", "ReleaseComplete")
        return true, nil
    end

    function runtime:Transition(uid: string, targetState: EggState): (boolean, string?)
        local record = getRecord(uid)
        if record == nil then
            return false, "EggNotFound"
        end
        if record.State == targetState then
            return true, nil
        end
        if record.State == "Respawning" and record.RespawnSourceState == targetState then
            return true, nil
        end
        if not VALID_NEXT_STATES[record.State][targetState] then
            return false, "InvalidEggStateTransition"
        end

        if targetState == "Lost" or targetState == "Banked" then
            beginRespawn(record, targetState)
        else
            commitState(record, targetState, "Transition")
        end
        return true, nil
    end

    function runtime:GetSlot(uid: string): EggSlotRecord?
        local record = getRecord(uid)
        if record == nil then
            return nil
        end
        return cloneRecord(record)
    end

    function runtime:GetAllSlots(): { EggSlotRecord }
        local copies = {}
        for _, uid in orderedUids do
            local record = recordsByUid[uid]
            if record ~= nil then
                table.insert(copies, cloneRecord(record))
            end
        end
        return copies
    end

    return runtime :: EggSlotRuntime
end

return { new = new }
