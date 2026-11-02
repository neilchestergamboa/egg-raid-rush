--!strict

local HudTheme = require(script.Parent:WaitForChild("HudTheme") :: ModuleScript)

export type FightHudState = {
    Visible: boolean,
    PetName: string,
    HatchlingName: string,
    PetHp: number,
    PetMaxHp: number,
    HatchlingHp: number,
    HatchlingMaxHp: number,
    ShowRetreat: boolean,
}

export type PromptHudState = {
    PromptText: string?,
    ShowKeyPrompt: boolean,
    ShowActionButton: boolean,
    ActionText: string,
}

export type EggScreenHud = {
    SetPrompt: (self: EggScreenHud, state: PromptHudState) -> (),
    SetFight: (self: EggScreenHud, state: FightHudState) -> (),
    SetTutorial: (self: EggScreenHud, text: string?) -> (),
    SetStatus: (self: EggScreenHud, text: string?) -> (),
    Destroy: (self: EggScreenHud) -> (),
}

export type EggScreenHudCallbacks = {
    OnAction: () -> (),
    OnRetreat: () -> (),
}

local function createBar(parent: Instance, name: string, fillColor: Color3): (Frame, TextLabel)
    local row = Instance.new("Frame")
    row.Name = name
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 36)
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Name = "Name"
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = HudTheme.PromptColor
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Size = UDim2.new(1, 0, 0, 16)
    label.Parent = row

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
    track.BorderSizePixel = 0
    track.Position = UDim2.fromOffset(0, 18)
    track.Size = UDim2.new(1, 0, 0, HudTheme.BarHeight)
    track.Parent = row

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 6)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BackgroundColor3 = fillColor
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale(1, 1)
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 6)
    fillCorner.Parent = fill

    return fill, label
end

local function setBar(fill: Frame, label: TextLabel, name: string, hp: number, maxHp: number)
    local ratio = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
    fill.Size = UDim2.fromScale(ratio, 1)
    label.Text = string.format("%s  %d/%d", name, math.floor(hp + 0.5), math.floor(maxHp + 0.5))
end

local function create(playerGui: PlayerGui, callbacks: EggScreenHudCallbacks): EggScreenHud
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggInteractionHud"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = HudTheme.ScreenDisplayOrder
    screenGui.Parent = playerGui

    local fightPanel = Instance.new("Frame")
    fightPanel.Name = "FightPanel"
    fightPanel.AnchorPoint = Vector2.new(0.5, 0)
    fightPanel.BackgroundColor3 = HudTheme.PanelColor
    fightPanel.BackgroundTransparency = 0.18
    fightPanel.Position = UDim2.new(0.5, 0, 0, 16)
    fightPanel.Size = UDim2.fromOffset(360, 102)
    fightPanel.Visible = false
    fightPanel.Parent = screenGui

    local tutorialBanner = Instance.new("TextLabel")
    tutorialBanner.Name = "TutorialGuidance"
    tutorialBanner.AnchorPoint = Vector2.new(0.5, 0)
    tutorialBanner.BackgroundColor3 = HudTheme.PanelColor
    tutorialBanner.BackgroundTransparency = 0.12
    tutorialBanner.Font = Enum.Font.GothamBold
    tutorialBanner.Position = UDim2.new(0.5, 0, 0, 128)
    tutorialBanner.Size = UDim2.new(0.8, 0, 0, 48)
    tutorialBanner.Text = ""
    tutorialBanner.TextColor3 = HudTheme.PromptColor
    tutorialBanner.TextScaled = true
    tutorialBanner.TextWrapped = true
    tutorialBanner.Visible = false
    tutorialBanner.Parent = screenGui

    local tutorialConstraint = Instance.new("UISizeConstraint")
    tutorialConstraint.MinSize = Vector2.new(240, 44)
    tutorialConstraint.MaxSize = Vector2.new(520, 56)
    tutorialConstraint.Parent = tutorialBanner

    local tutorialCorner = Instance.new("UICorner")
    tutorialCorner.CornerRadius = UDim.new(0, 12)
    tutorialCorner.Parent = tutorialBanner

    local tutorialStroke = Instance.new("UIStroke")
    tutorialStroke.Color = HudTheme.AccentColor
    tutorialStroke.Thickness = 2
    tutorialStroke.Parent = tutorialBanner

    local fightCorner = Instance.new("UICorner")
    fightCorner.CornerRadius = UDim.new(0, 12)
    fightCorner.Parent = fightPanel

    local fightPadding = Instance.new("UIPadding")
    fightPadding.PaddingTop = UDim.new(0, 10)
    fightPadding.PaddingBottom = UDim.new(0, 10)
    fightPadding.PaddingLeft = UDim.new(0, 14)
    fightPadding.PaddingRight = UDim.new(0, 14)
    fightPadding.Parent = fightPanel

    local fightLayout = Instance.new("UIListLayout")
    fightLayout.FillDirection = Enum.FillDirection.Vertical
    fightLayout.Padding = UDim.new(0, 8)
    fightLayout.SortOrder = Enum.SortOrder.LayoutOrder
    fightLayout.Parent = fightPanel

    local petFill, petLabel = createBar(fightPanel, "PetBar", HudTheme.PetBarColor)
    local hatchFill, hatchLabel = createBar(fightPanel, "HatchlingBar", HudTheme.HatchlingBarColor)

    local prompt = Instance.new("TextLabel")
    prompt.Name = "KeyPrompt"
    prompt.AnchorPoint = Vector2.new(0.5, 1)
    prompt.BackgroundColor3 = HudTheme.PanelColor
    prompt.BackgroundTransparency = 0.2
    prompt.Font = Enum.Font.GothamBold
    prompt.Position = UDim2.new(0.5, 0, 1, -28)
    prompt.Size = UDim2.fromOffset(280, 44)
    prompt.Text = ""
    prompt.TextColor3 = HudTheme.PromptColor
    prompt.TextScaled = true
    prompt.Visible = false
    prompt.Parent = screenGui

    local promptCorner = Instance.new("UICorner")
    promptCorner.CornerRadius = UDim.new(0, 10)
    promptCorner.Parent = prompt

    local promptPadding = Instance.new("UIPadding")
    promptPadding.PaddingLeft = UDim.new(0, 12)
    promptPadding.PaddingRight = UDim.new(0, 12)
    promptPadding.Parent = prompt

    local actionButton = Instance.new("TextButton")
    actionButton.Name = "ActionButton"
    actionButton.AnchorPoint = Vector2.new(0.5, 1)
    actionButton.AutoButtonColor = true
    actionButton.BackgroundColor3 = HudTheme.ActionColor
    actionButton.Font = Enum.Font.GothamBold
    actionButton.Position = UDim2.new(0.5, 0, 1, -28)
    actionButton.Size = UDim2.fromOffset(HudTheme.ActionButtonSize, HudTheme.ActionButtonSize)
    actionButton.Text = "Break"
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

    local retreatButton = Instance.new("TextButton")
    retreatButton.Name = "RetreatButton"
    retreatButton.AnchorPoint = Vector2.new(1, 1)
    retreatButton.AutoButtonColor = true
    retreatButton.BackgroundColor3 = HudTheme.RetreatColor
    retreatButton.Font = Enum.Font.GothamBold
    retreatButton.Position = UDim2.new(1, -24, 1, -28)
    retreatButton.Size = UDim2.fromOffset(120, 48)
    retreatButton.Text = "Retreat"
    retreatButton.TextColor3 = Color3.new(1, 1, 1)
    retreatButton.TextScaled = true
    retreatButton.Visible = false
    retreatButton.Parent = screenGui

    local retreatCorner = Instance.new("UICorner")
    retreatCorner.CornerRadius = UDim.new(0, 12)
    retreatCorner.Parent = retreatButton

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.AnchorPoint = Vector2.new(0.5, 1)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.GothamMedium
    status.Position = UDim2.new(0.5, 0, 1, -120)
    status.Size = UDim2.fromOffset(360, 28)
    status.Text = ""
    status.TextColor3 = HudTheme.PromptColor
    status.TextScaled = true
    status.Visible = false
    status.Parent = screenGui

    actionButton.Activated:Connect(function()
        callbacks.OnAction()
    end)
    retreatButton.Activated:Connect(function()
        callbacks.OnRetreat()
    end)

    local hud = {} :: EggScreenHud

    function hud:SetPrompt(state: PromptHudState)
        prompt.Visible = state.ShowKeyPrompt and state.PromptText ~= nil
        prompt.Text = state.PromptText or ""
        actionButton.Visible = state.ShowActionButton
        actionButton.Text = state.ActionText
        if state.ShowActionButton then
            prompt.Position = UDim2.new(0.5, 0, 1, -(HudTheme.ActionButtonSize + 48))
            status.Position = UDim2.new(0.5, 0, 1, -(HudTheme.ActionButtonSize + 92))
        else
            prompt.Position = UDim2.new(0.5, 0, 1, -28)
            status.Position = UDim2.new(0.5, 0, 1, -80)
        end
    end

    function hud:SetFight(state: FightHudState)
        fightPanel.Visible = state.Visible
        retreatButton.Visible = state.Visible and state.ShowRetreat
        if not state.Visible then
            return
        end
        setBar(petFill, petLabel, state.PetName, state.PetHp, state.PetMaxHp)
        setBar(hatchFill, hatchLabel, state.HatchlingName, state.HatchlingHp, state.HatchlingMaxHp)
    end

    function hud:SetTutorial(text: string?)
        tutorialBanner.Visible = text ~= nil and text ~= ""
        tutorialBanner.Text = text or ""
    end

    function hud:SetStatus(text: string?)
        status.Visible = text ~= nil and text ~= ""
        status.Text = text or ""
    end

    function hud:Destroy()
        screenGui:Destroy()
    end

    return hud
end

return {
    Create = create,
}
