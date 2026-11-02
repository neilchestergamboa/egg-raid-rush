--!strict

local HudTheme = require(script.Parent:WaitForChild("HudTheme") :: ModuleScript)

export type CarryHudState = {
    Visible: boolean,
    Title: string,
    Detail: string,
}

export type GuardHudState = {
    Visible: boolean,
    Text: string,
    IsClose: boolean,
}

export type DropHudState = {
    Visible: boolean,
    Text: string,
}

export type PickupHudState = {
    PromptText: string?,
    ShowKeyPrompt: boolean,
    ShowActionButton: boolean,
    ActionText: string,
    HoldProgress: number?,
}

export type ChaseScreenHud = {
    SetCarry: (self: ChaseScreenHud, state: CarryHudState) -> (),
    SetGuard: (self: ChaseScreenHud, state: GuardHudState) -> (),
    SetDrop: (self: ChaseScreenHud, state: DropHudState) -> (),
    SetPickup: (self: ChaseScreenHud, state: PickupHudState) -> (),
    SetStatus: (self: ChaseScreenHud, text: string?) -> (),
    PlayBankFlash: (self: ChaseScreenHud) -> (),
    Destroy: (self: ChaseScreenHud) -> (),
}

export type ChaseScreenHudCallbacks = {
    OnPickup: () -> (),
}

local function createRounded(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.AnchorPoint = anchor
    frame.BackgroundColor3 = HudTheme.PanelColor
    frame.BackgroundTransparency = 0.12
    frame.Position = position
    frame.Size = size
    frame.Visible = false
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.Parent = frame

    return frame
end

local function create(playerGui: PlayerGui, callbacks: ChaseScreenHudCallbacks): ChaseScreenHud
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ChaseHud"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = HudTheme.ChaseDisplayOrder
    screenGui.Parent = playerGui

    local carryFrame = createRounded(
        screenGui,
        "CarryIndicator",
        UDim2.fromOffset(280, 72),
        UDim2.fromOffset(16, 16),
        Vector2.new(0, 0)
    )
    local carryTitle = Instance.new("TextLabel")
    carryTitle.Name = "Title"
    carryTitle.BackgroundTransparency = 1
    carryTitle.Font = Enum.Font.GothamBold
    carryTitle.Size = UDim2.new(1, 0, 0, 24)
    carryTitle.Text = "Carrying"
    carryTitle.TextColor3 = HudTheme.AccentColor
    carryTitle.TextScaled = true
    carryTitle.TextXAlignment = Enum.TextXAlignment.Left
    carryTitle.Parent = carryFrame

    local carryDetail = Instance.new("TextLabel")
    carryDetail.Name = "Detail"
    carryDetail.BackgroundTransparency = 1
    carryDetail.Font = Enum.Font.GothamMedium
    carryDetail.Position = UDim2.fromOffset(0, 28)
    carryDetail.Size = UDim2.new(1, 0, 0, 24)
    carryDetail.Text = ""
    carryDetail.TextColor3 = HudTheme.PromptColor
    carryDetail.TextScaled = true
    carryDetail.TextXAlignment = Enum.TextXAlignment.Left
    carryDetail.Parent = carryFrame

    local guardFrame = createRounded(
        screenGui,
        "GuardWarning",
        UDim2.new(1, -32, 0, 56),
        UDim2.new(0.5, 0, 0, 96),
        Vector2.new(0.5, 0)
    )
    local guardLabel = Instance.new("TextLabel")
    guardLabel.Name = "Text"
    guardLabel.BackgroundTransparency = 1
    guardLabel.Font = Enum.Font.GothamBold
    guardLabel.Size = UDim2.fromScale(1, 1)
    guardLabel.Text = ""
    guardLabel.TextColor3 = HudTheme.GuardWarningColor
    guardLabel.TextScaled = true
    guardLabel.Parent = guardFrame

    local dropFrame = createRounded(
        screenGui,
        "DropCountdown",
        UDim2.fromOffset(280, 56),
        UDim2.fromOffset(16, 16),
        Vector2.new(0, 0)
    )
    local dropLabel = Instance.new("TextLabel")
    dropLabel.Name = "Text"
    dropLabel.BackgroundTransparency = 1
    dropLabel.Font = Enum.Font.GothamBold
    dropLabel.Size = UDim2.fromScale(1, 1)
    dropLabel.Text = ""
    dropLabel.TextColor3 = HudTheme.PromptColor
    dropLabel.TextScaled = true
    dropLabel.TextXAlignment = Enum.TextXAlignment.Left
    dropLabel.Parent = dropFrame

    local prompt = Instance.new("TextLabel")
    prompt.Name = "PickupPrompt"
    prompt.AnchorPoint = Vector2.new(0.5, 1)
    prompt.BackgroundColor3 = HudTheme.PanelColor
    prompt.BackgroundTransparency = 0.2
    prompt.Font = Enum.Font.GothamBold
    prompt.Position = UDim2.new(0.5, 0, 1, -28)
    prompt.Size = UDim2.fromOffset(300, 48)
    prompt.Text = ""
    prompt.TextColor3 = HudTheme.PromptColor
    prompt.TextScaled = true
    prompt.Visible = false
    prompt.Parent = screenGui

    local promptCorner = Instance.new("UICorner")
    promptCorner.CornerRadius = UDim.new(0, 10)
    promptCorner.Parent = prompt

    local actionButton = Instance.new("TextButton")
    actionButton.Name = "PickupButton"
    actionButton.AnchorPoint = Vector2.new(0.5, 1)
    actionButton.AutoButtonColor = true
    actionButton.BackgroundColor3 = HudTheme.ActionColor
    actionButton.Font = Enum.Font.GothamBold
    actionButton.Position = UDim2.new(0.5, 0, 1, -28)
    actionButton.Size = UDim2.fromOffset(HudTheme.ActionButtonSize, HudTheme.ActionButtonSize)
    actionButton.Text = "Pick up"
    actionButton.TextColor3 = Color3.new(1, 1, 1)
    actionButton.TextScaled = true
    actionButton.Visible = false
    actionButton.Parent = screenGui

    local actionCorner = Instance.new("UICorner")
    actionCorner.CornerRadius = UDim.new(1, 0)
    actionCorner.Parent = actionButton

    local actionStroke = Instance.new("UIStroke")
    actionStroke.Color = HudTheme.StrokeColor
    actionStroke.Thickness = 3
    actionStroke.Parent = actionButton

    local holdTrack = Instance.new("Frame")
    holdTrack.Name = "HoldTrack"
    holdTrack.AnchorPoint = Vector2.new(0.5, 1)
    holdTrack.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
    holdTrack.BorderSizePixel = 0
    holdTrack.Position = UDim2.new(0.5, 0, 1, -120)
    holdTrack.Size = UDim2.fromOffset(220, 10)
    holdTrack.Visible = false
    holdTrack.Parent = screenGui

    local holdCorner = Instance.new("UICorner")
    holdCorner.CornerRadius = UDim.new(1, 0)
    holdCorner.Parent = holdTrack

    local holdFill = Instance.new("Frame")
    holdFill.Name = "Fill"
    holdFill.BackgroundColor3 = HudTheme.AccentColor
    holdFill.BorderSizePixel = 0
    holdFill.Size = UDim2.fromScale(0, 1)
    holdFill.Parent = holdTrack

    local holdFillCorner = Instance.new("UICorner")
    holdFillCorner.CornerRadius = UDim.new(1, 0)
    holdFillCorner.Parent = holdFill

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.AnchorPoint = Vector2.new(0.5, 1)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.GothamMedium
    status.Position = UDim2.new(0.5, 0, 1, -140)
    status.Size = UDim2.fromOffset(360, 28)
    status.Text = ""
    status.TextColor3 = HudTheme.PromptColor
    status.TextScaled = true
    status.Visible = false
    status.Parent = screenGui

    local bankFlash = Instance.new("Frame")
    bankFlash.Name = "BankFlash"
    bankFlash.BackgroundColor3 = HudTheme.BankFlashColor
    bankFlash.BackgroundTransparency = 1
    bankFlash.BorderSizePixel = 0
    bankFlash.Size = UDim2.fromScale(1, 1)
    bankFlash.ZIndex = 20
    bankFlash.Parent = screenGui

    local bankLabel = Instance.new("TextLabel")
    bankLabel.Name = "Banked"
    bankLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    bankLabel.BackgroundTransparency = 1
    bankLabel.Font = Enum.Font.GothamBold
    bankLabel.Position = UDim2.fromScale(0.5, 0.42)
    bankLabel.Size = UDim2.fromOffset(320, 64)
    bankLabel.Text = "Banked!"
    bankLabel.TextColor3 = HudTheme.AccentColor
    bankLabel.TextScaled = true
    bankLabel.Visible = false
    bankLabel.ZIndex = 21
    bankLabel.Parent = screenGui

    actionButton.MouseButton1Down:Connect(function()
        callbacks.OnPickup()
    end)

    local hud = {} :: ChaseScreenHud

    function hud:SetCarry(state: CarryHudState)
        carryFrame.Visible = state.Visible
        carryTitle.Text = state.Title
        carryDetail.Text = state.Detail
        dropFrame.Position = if state.Visible then UDim2.fromOffset(16, 160) else UDim2.fromOffset(16, 16)
    end

    function hud:SetGuard(state: GuardHudState)
        guardFrame.Visible = state.Visible
        guardLabel.Text = state.Text
        guardLabel.TextColor3 = if state.IsClose then HudTheme.GuardCloseColor else HudTheme.GuardWarningColor
        guardFrame.BackgroundColor3 = if state.IsClose then Color3.fromRGB(72, 28, 16) else HudTheme.PanelColor
    end

    function hud:SetDrop(state: DropHudState)
        dropFrame.Visible = state.Visible
        dropLabel.Text = state.Text
    end

    function hud:SetPickup(state: PickupHudState)
        prompt.Visible = state.ShowKeyPrompt and state.PromptText ~= nil
        prompt.Text = state.PromptText or ""
        actionButton.Visible = state.ShowActionButton
        actionButton.Text = state.ActionText
        local holding = state.HoldProgress ~= nil
        holdTrack.Visible = holding
        if holding and state.HoldProgress ~= nil then
            holdFill.Size = UDim2.fromScale(math.clamp(state.HoldProgress, 0, 1), 1)
        end
        if state.ShowActionButton then
            prompt.Position = UDim2.new(0.5, 0, 1, -(HudTheme.ActionButtonSize + 48))
            status.Position = UDim2.new(0.5, 0, 1, -(HudTheme.ActionButtonSize + 100))
            holdTrack.Position = UDim2.new(0.5, 0, 1, -(HudTheme.ActionButtonSize + 16))
        else
            prompt.Position = UDim2.new(0.5, 0, 1, -28)
            status.Position = UDim2.new(0.5, 0, 1, -88)
            holdTrack.Position = UDim2.new(0.5, 0, 1, -84)
        end
    end

    function hud:SetStatus(text: string?)
        status.Visible = text ~= nil and text ~= ""
        status.Text = text or ""
    end

    function hud:PlayBankFlash()
        bankLabel.Visible = true
        bankFlash.BackgroundTransparency = 0.55
        task.delay(0.35, function()
            if bankFlash.Parent == nil then
                return
            end
            bankFlash.BackgroundTransparency = 1
        end)
        task.delay(1.6, function()
            if bankLabel.Parent == nil then
                return
            end
            bankLabel.Visible = false
        end)
    end

    function hud:Destroy()
        screenGui:Destroy()
    end

    return hud
end

return {
    Create = create,
}
