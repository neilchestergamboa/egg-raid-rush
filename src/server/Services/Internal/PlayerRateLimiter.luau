--!strict

export type PlayerRateLimiter = {
    Allow: (self: PlayerRateLimiter, userId: number, now: number) -> boolean,
    Forget: (self: PlayerRateLimiter, userId: number) -> (),
}

local function new(minimumIntervalSeconds: number): PlayerRateLimiter
    assert(minimumIntervalSeconds > 0, "minimumIntervalSeconds must be positive.")
    local lastRequestAtByUserId: { [number]: number } = {}
    local limiter: any = {}

    function limiter:Allow(userId: number, now: number): boolean
        local previous = lastRequestAtByUserId[userId]
        if previous ~= nil and now - previous < minimumIntervalSeconds then
            return false
        end
        lastRequestAtByUserId[userId] = now
        return true
    end

    function limiter:Forget(userId: number)
        lastRequestAtByUserId[userId] = nil
    end

    return limiter :: PlayerRateLimiter
end

return { new = new }
