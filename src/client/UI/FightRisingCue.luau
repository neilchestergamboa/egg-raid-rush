--!strict

local SoundService = game:GetService("SoundService")

export type FightRisingCue = {
    Update: (self: FightRisingCue, deltaSeconds: number, intensity: number, isAudible: boolean) -> (),
    Destroy: (self: FightRisingCue) -> (),
}

local PING_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"

local function createCue(): FightRisingCue
    local sound = Instance.new("Sound")
    sound.Name = "FightRisingCue"
    sound.SoundId = PING_SOUND_ID
    sound.Volume = 0.28
    sound.RollOffMode = Enum.RollOffMode.Linear
    sound.Parent = SoundService

    local accumulator = 0

    local cue = {} :: FightRisingCue

    function cue:Update(deltaSeconds: number, intensity: number, isAudible: boolean)
        if not isAudible then
            accumulator = 0
            return
        end

        local clamped = math.clamp(intensity, 0, 1)
        local interval = 1.15 - clamped * 0.9
        accumulator += deltaSeconds
        if accumulator < interval then
            return
        end

        accumulator = 0
        sound.PlaybackSpeed = 0.88 + clamped * 0.95
        sound.Volume = 0.18 + clamped * 0.22
        sound:Play()
    end

    function cue:Destroy()
        sound:Destroy()
    end

    return cue
end

return {
    Create = createCue,
}
