--!strict

export type FightRecord = any

export type FightRuntime = {
    Get: (self: FightRuntime, eggUid: string) -> FightRecord?,
    GetForUser: (self: FightRuntime, userId: number) -> string?,
    Start: (self: FightRuntime, eggUid: string, fight: FightRecord) -> (boolean, string?),
    Retreat: (self: FightRuntime, eggUid: string, userId: number) -> (FightRecord?, string?),
    Finish: (self: FightRuntime, eggUid: string, fight: FightRecord) -> boolean,
}

local function new(): FightRuntime
    local byEggUid: { [string]: FightRecord } = {}
    local byUserId: { [number]: string } = {}
    local runtime: any = {}

    function runtime:Get(eggUid: string): FightRecord?
        return byEggUid[eggUid]
    end

    function runtime:GetForUser(userId: number): string?
        return byUserId[userId]
    end

    function runtime:Start(eggUid: string, fight: FightRecord): (boolean, string?)
        if
            type(eggUid) ~= "string"
            or eggUid == ""
            or type(fight.UserId) ~= "number"
            or fight.UserId <= 0
            or fight.UserId % 1 ~= 0
        then
            return false, "InvalidFight"
        end
        if byEggUid[eggUid] ~= nil then
            return false, "FightAlreadyRunning"
        end
        if byUserId[fight.UserId] ~= nil then
            return false, "PlayerAlreadyFighting"
        end
        byEggUid[eggUid] = fight
        byUserId[fight.UserId] = eggUid
        return true, nil
    end

    function runtime:Retreat(eggUid: string, userId: number): (FightRecord?, string?)
        local fight = byEggUid[eggUid]
        if fight == nil or fight.UserId ~= userId or fight.Retreated then
            return nil, "FightNotActive"
        end
        fight.Retreated = true
        byEggUid[eggUid] = nil
        byUserId[userId] = nil
        return fight, nil
    end

    function runtime:Finish(eggUid: string, fight: FightRecord): boolean
        if byEggUid[eggUid] ~= fight then
            return false
        end
        byEggUid[eggUid] = nil
        if byUserId[fight.UserId] == eggUid then
            byUserId[fight.UserId] = nil
        end
        return true
    end

    return runtime :: FightRuntime
end

return { new = new }
