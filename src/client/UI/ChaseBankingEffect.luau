--!strict

local HudTheme = require(script.Parent:WaitForChild("HudTheme") :: ModuleScript)

export type ChaseBankingEffect = {
    SetApproaching: (self: ChaseBankingEffect, gate: BasePart?) -> (),
    PlaySuccess: (self: ChaseBankingEffect, gate: BasePart?) -> (),
    Destroy: (self: ChaseBankingEffect) -> (),
}

local function createHighlight(name: string, fill: Color3, outline: Color3): Highlight
    local highlight = Instance.new("Highlight")
    highlight.Name = name
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = fill
    highlight.OutlineColor = outline
    highlight.FillTransparency = 0.65
    highlight.OutlineTransparency = 0.1
    return highlight
end

local function create(): ChaseBankingEffect
    local approachHighlight: Highlight? = nil
    local successInstances: { Instance } = {}
    local effect = {} :: ChaseBankingEffect

    local function clearApproach()
        if approachHighlight ~= nil then
            approachHighlight:Destroy()
            approachHighlight = nil
        end
    end

    function effect:SetApproaching(gate: BasePart?)
        if gate == nil then
            clearApproach()
            return
        end
        local current = approachHighlight
        if current ~= nil and current.Adornee == gate then
            return
        end
        clearApproach()
        local highlight = createHighlight("SafeGateApproach", HudTheme.AccentColor, HudTheme.PromptColor)
        highlight.Adornee = gate
        highlight.Parent = gate
        approachHighlight = highlight
    end

    function effect:PlaySuccess(gate: BasePart?)
        for _, instance in successInstances do
            instance:Destroy()
        end
        table.clear(successInstances)
        if gate == nil then
            return
        end

        local highlight = createHighlight("SafeGateBanked", HudTheme.BankFlashColor, HudTheme.AccentColor)
        highlight.FillTransparency = 0.4
        highlight.Adornee = gate
        highlight.Parent = gate
        table.insert(successInstances, highlight)

        local attachment = Instance.new("Attachment")
        attachment.Name = "BankSparkle"
        attachment.Parent = gate
        table.insert(successInstances, attachment)

        local sparkles = Instance.new("ParticleEmitter")
        sparkles.Name = "BankSparkles"
        sparkles.Color = ColorSequence.new(HudTheme.AccentColor, HudTheme.PromptColor)
        sparkles.LightEmission = 0.6
        sparkles.Lifetime = NumberRange.new(0.4, 0.8)
        sparkles.Rate = 40
        sparkles.Speed = NumberRange.new(4, 8)
        sparkles.SpreadAngle = Vector2.new(180, 180)
        sparkles.Size = NumberSequence.new(0.35, 0)
        sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        sparkles.Parent = attachment
        table.insert(successInstances, sparkles)

        task.delay(1.6, function()
            for _, instance in successInstances do
                instance:Destroy()
            end
            table.clear(successInstances)
        end)
    end

    function effect:Destroy()
        clearApproach()
        for _, instance in successInstances do
            instance:Destroy()
        end
        table.clear(successInstances)
    end

    return effect
end

return {
    Create = create,
}
