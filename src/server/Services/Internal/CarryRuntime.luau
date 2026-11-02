--!strict

export type CarryState = "Carried" | "Dropped" | "PickupPending" | "Banking" | "Banked" | "Returned"
export type CarryRecord = {
    CreatureUid: string,
    EggUid: string,
    DefId: string,
    ConditionId: string,
    State: CarryState,
    CarrierUserId: number?,
    PreviousCarrierUserId: number?,
    PickupLockoutUntil: number,
    DropExpiresAt: number?,
    DropPosition: Vector3?,
    PickupReservationUserId: number?,
    GrantCommitted: boolean?,
}

export type CarryRuntime = {
    Register: (self: CarryRuntime, record: CarryRecord) -> (boolean, string?),
    Get: (self: CarryRuntime, eggUid: string) -> CarryRecord?,
    GetForUser: (self: CarryRuntime, userId: number) -> CarryRecord?,
    GetDropped: (self: CarryRuntime) -> { CarryRecord },
    Forget: (self: CarryRuntime, eggUid: string) -> boolean,
    Drop: (
        self: CarryRuntime,
        eggUid: string,
        userId: number,
        position: Vector3,
        now: number,
        lifetime: number,
        lockout: number
    ) -> (boolean, string?),
    ReservePickup: (self: CarryRuntime, eggUid: string, userId: number, now: number) -> (boolean, string?),
    CancelPickup: (self: CarryRuntime, eggUid: string, userId: number) -> boolean,
    CompletePickup: (self: CarryRuntime, eggUid: string, userId: number, now: number) -> (boolean, string?),
    BeginBank: (self: CarryRuntime, eggUid: string, userId: number) -> (boolean, string?),
    MarkGrantCommitted: (self: CarryRuntime, eggUid: string, userId: number) -> boolean,
    CancelBank: (self: CarryRuntime, eggUid: string, userId: number) -> boolean,
    CompleteBank: (self: CarryRuntime, eggUid: string, userId: number) -> boolean,
    Return: (self: CarryRuntime, eggUid: string) -> (boolean, string?),
}

local function clone(record: CarryRecord): CarryRecord
    return table.clone(record)
end

local function new(): CarryRuntime
    local recordsByEggUid: { [string]: CarryRecord } = {}
    local eggUidByCreatureUid: { [string]: string } = {}
    local eggUidByCarrierUserId: { [number]: string } = {}
    local eggUidByPickupUserId: { [number]: string } = {}
    local runtime: any = {}

    function runtime:Register(record: CarryRecord): (boolean, string?)
        if record.EggUid == "" or record.CreatureUid == "" or record.DefId == "" or record.ConditionId == "" then
            return false, "InvalidCarryRecord"
        end
        if record.CarrierUserId == nil or record.CarrierUserId <= 0 then
            return false, "InvalidCarrierUserId"
        end
        local existing = recordsByEggUid[record.EggUid]
        if existing ~= nil then
            if existing.CreatureUid == record.CreatureUid then
                return true, nil
            end
            return false, "CreatureAlreadyRegistered"
        end
        if eggUidByCreatureUid[record.CreatureUid] ~= nil then
            return false, "CreatureAlreadyRegistered"
        end
        if eggUidByCarrierUserId[record.CarrierUserId] ~= nil then
            return false, "PlayerAlreadyCarrying"
        end
        recordsByEggUid[record.EggUid] = clone(record)
        eggUidByCreatureUid[record.CreatureUid] = record.EggUid
        eggUidByCarrierUserId[record.CarrierUserId] = record.EggUid
        return true, nil
    end

    function runtime:Get(eggUid: string): CarryRecord?
        local record = recordsByEggUid[eggUid]
        return if record == nil then nil else clone(record)
    end

    function runtime:GetForUser(userId: number): CarryRecord?
        local eggUid = eggUidByCarrierUserId[userId]
        local record = if eggUid == nil then nil else recordsByEggUid[eggUid]
        return if record == nil then nil else clone(record)
    end

    function runtime:GetDropped(): { CarryRecord }
        local dropped = {}
        for _, record in recordsByEggUid do
            if record.State == "Dropped" then
                table.insert(dropped, clone(record))
            end
        end
        return dropped
    end

    function runtime:Forget(eggUid: string): boolean
        local record = recordsByEggUid[eggUid]
        if record == nil or (record.State ~= "Banked" and record.State ~= "Returned") then
            return false
        end
        recordsByEggUid[eggUid] = nil
        if eggUidByCreatureUid[record.CreatureUid] == eggUid then
            eggUidByCreatureUid[record.CreatureUid] = nil
        end
        return true
    end

    function runtime:Drop(
        eggUid: string,
        userId: number,
        position: Vector3,
        now: number,
        lifetime: number,
        lockout: number
    ): (boolean, string?)
        local record = recordsByEggUid[eggUid]
        if record == nil then
            return false, "CreatureNotFound"
        end
        if record.State == "Dropped" and record.PreviousCarrierUserId == userId then
            return true, nil
        end
        if record.State ~= "Carried" or record.CarrierUserId ~= userId or eggUidByCarrierUserId[userId] ~= eggUid then
            return false, "CreatureNotCarriedByPlayer"
        end
        if lifetime <= 0 or lockout < 0 then
            return false, "InvalidDropTiming"
        end
        eggUidByCarrierUserId[userId] = nil
        record.State = "Dropped"
        record.PreviousCarrierUserId = userId
        record.CarrierUserId = nil
        record.PickupReservationUserId = nil
        record.PickupLockoutUntil = now + lockout
        record.DropExpiresAt = now + lifetime
        record.DropPosition = position
        return true, nil
    end

    function runtime:ReservePickup(eggUid: string, userId: number, now: number): (boolean, string?)
        local record = recordsByEggUid[eggUid]
        if record == nil then
            return false, "CreatureNotFound"
        end
        if record.State ~= "Dropped" then
            return false, "CreatureUnavailable"
        end
        if record.DropExpiresAt == nil or now >= record.DropExpiresAt then
            return false, "DropExpired"
        end
        if userId == record.PreviousCarrierUserId and now < record.PickupLockoutUntil then
            return false, "PickupLockedOut"
        end
        if eggUidByCarrierUserId[userId] ~= nil or eggUidByPickupUserId[userId] ~= nil then
            return false, "PlayerAlreadyCarrying"
        end
        record.State = "PickupPending"
        record.PickupReservationUserId = userId
        eggUidByPickupUserId[userId] = eggUid
        return true, nil
    end

    function runtime:CancelPickup(eggUid: string, userId: number): boolean
        local record = recordsByEggUid[eggUid]
        if record == nil or record.State ~= "PickupPending" or record.PickupReservationUserId ~= userId then
            return false
        end
        record.State = "Dropped"
        record.PickupReservationUserId = nil
        eggUidByPickupUserId[userId] = nil
        return true
    end

    function runtime:CompletePickup(eggUid: string, userId: number, now: number): (boolean, string?)
        local record = recordsByEggUid[eggUid]
        if record == nil or record.State ~= "PickupPending" or record.PickupReservationUserId ~= userId then
            return false, "PickupNotReserved"
        end
        if record.DropExpiresAt == nil or now >= record.DropExpiresAt then
            record.State = "Dropped"
            record.PickupReservationUserId = nil
            eggUidByPickupUserId[userId] = nil
            return false, "DropExpired"
        end
        if eggUidByCarrierUserId[userId] ~= nil or eggUidByPickupUserId[userId] ~= eggUid then
            return false, "PlayerAlreadyCarrying"
        end
        record.State = "Carried"
        record.CarrierUserId = userId
        record.PreviousCarrierUserId = nil
        record.PickupReservationUserId = nil
        eggUidByPickupUserId[userId] = nil
        record.PickupLockoutUntil = 0
        record.DropExpiresAt = nil
        record.DropPosition = nil
        eggUidByCarrierUserId[userId] = eggUid
        return true, nil
    end

    function runtime:BeginBank(eggUid: string, userId: number): (boolean, string?)
        local record = recordsByEggUid[eggUid]
        if record == nil then
            return false, "CreatureNotFound"
        end
        if record.State == "Banking" and record.CarrierUserId == userId then
            return true, nil
        end
        if record.State ~= "Carried" or record.CarrierUserId ~= userId then
            return false, "CreatureNotCarriedByPlayer"
        end
        record.State = "Banking"
        return true, nil
    end

    function runtime:CompleteBank(eggUid: string, userId: number): boolean
        local record = recordsByEggUid[eggUid]
        if record == nil or record.State == "Banked" then
            return record ~= nil
        end
        if record.State ~= "Banking" or record.CarrierUserId ~= userId then
            return false
        end
        record.State = "Banked"
        eggUidByCarrierUserId[userId] = nil
        return true
    end

    function runtime:CancelBank(eggUid: string, userId: number): boolean
        local record = recordsByEggUid[eggUid]
        if
            record == nil
            or record.State ~= "Banking"
            or record.CarrierUserId ~= userId
            or record.GrantCommitted == true
        then
            return false
        end
        record.State = "Carried"
        return true
    end

    function runtime:MarkGrantCommitted(eggUid: string, userId: number): boolean
        local record = recordsByEggUid[eggUid]
        if record == nil or record.State ~= "Banking" or record.CarrierUserId ~= userId then
            return false
        end
        record.GrantCommitted = true
        return true
    end

    function runtime:Return(eggUid: string): (boolean, string?)
        local record = recordsByEggUid[eggUid]
        if record == nil then
            return false, "CreatureNotFound"
        end
        if record.State == "Returned" then
            return true, nil
        end
        if record.State ~= "Carried" and record.State ~= "Dropped" and record.State ~= "PickupPending" then
            return false, "CreatureCannotBeReturned"
        end
        if record.CarrierUserId ~= nil and eggUidByCarrierUserId[record.CarrierUserId] == eggUid then
            eggUidByCarrierUserId[record.CarrierUserId] = nil
        end
        if record.PickupReservationUserId ~= nil and eggUidByPickupUserId[record.PickupReservationUserId] == eggUid then
            eggUidByPickupUserId[record.PickupReservationUserId] = nil
        end
        record.State = "Returned"
        record.CarrierUserId = nil
        record.PickupReservationUserId = nil
        record.DropExpiresAt = nil
        record.DropPosition = nil
        return true, nil
    end

    return runtime :: CarryRuntime
end

return { new = new }
