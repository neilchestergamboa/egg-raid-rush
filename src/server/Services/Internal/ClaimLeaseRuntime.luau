--!strict

export type ClaimLeaseRuntime = {
    Start: (self: ClaimLeaseRuntime, eggUid: string, userId: number, expiresAt: number) -> (boolean, string?),
    Refresh: (self: ClaimLeaseRuntime, eggUid: string, userId: number, expiresAt: number) -> (boolean, string?),
    Cancel: (self: ClaimLeaseRuntime, eggUid: string, userId: number?) -> boolean,
}

type Lease = {
    UserId: number,
    ExpiresAt: number,
    Generation: number,
}

type Options = {
    Now: () -> number,
    Schedule: (seconds: number, callback: () -> ()) -> (),
    OnExpired: (eggUid: string, userId: number) -> (),
}

local function isFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

local function new(options: Options): ClaimLeaseRuntime
    local leaseByEggUid: { [string]: Lease } = {}
    local generationByEggUid: { [string]: number } = {}
    local runtime: any = {}

    local function scheduleCheck(eggUid: string, generation: number)
        local lease = leaseByEggUid[eggUid]
        if lease == nil or lease.Generation ~= generation then
            return
        end
        options.Schedule(math.max(0, lease.ExpiresAt - options.Now()), function()
            local current = leaseByEggUid[eggUid]
            if current == nil or current.Generation ~= generation then
                return
            end
            local remaining = current.ExpiresAt - options.Now()
            if remaining > 0 then
                scheduleCheck(eggUid, generation)
                return
            end
            leaseByEggUid[eggUid] = nil
            options.OnExpired(eggUid, current.UserId)
        end)
    end

    function runtime:Start(eggUid: string, userId: number, expiresAt: number): (boolean, string?)
        local current = leaseByEggUid[eggUid]
        if current ~= nil then
            if current.UserId == userId then
                return true, nil
            end
            return false, "ClaimLeaseAlreadyOwned"
        end
        if eggUid == "" or userId <= 0 or userId % 1 ~= 0 then
            return false, "InvalidClaimLease"
        end
        if not isFinite(expiresAt) or expiresAt <= options.Now() then
            return false, "InvalidClaimExpiry"
        end

        local generation = (generationByEggUid[eggUid] or 0) + 1
        generationByEggUid[eggUid] = generation
        leaseByEggUid[eggUid] = { UserId = userId, ExpiresAt = expiresAt, Generation = generation }
        scheduleCheck(eggUid, generation)
        return true, nil
    end

    function runtime:Refresh(eggUid: string, userId: number, expiresAt: number): (boolean, string?)
        local lease = leaseByEggUid[eggUid]
        if lease == nil or lease.UserId ~= userId then
            return false, "ClaimLeaseNotFound"
        end
        if not isFinite(expiresAt) or expiresAt <= options.Now() then
            return false, "InvalidClaimExpiry"
        end
        if expiresAt <= lease.ExpiresAt then
            return true, nil
        end
        lease.ExpiresAt = expiresAt
        return true, nil
    end

    function runtime:Cancel(eggUid: string, userId: number?): boolean
        local lease = leaseByEggUid[eggUid]
        if lease == nil or (userId ~= nil and lease.UserId ~= userId) then
            return false
        end
        leaseByEggUid[eggUid] = nil
        generationByEggUid[eggUid] = (generationByEggUid[eggUid] or 0) + 1
        return true
    end

    return runtime :: ClaimLeaseRuntime
end

return { new = new }
