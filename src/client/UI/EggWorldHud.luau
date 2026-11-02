--!strict

local Players = game:GetService("Players")

local HudTheme = require(script.Parent:WaitForChild("HudTheme") :: ModuleScript)

export type EggWorldView = {
    Uid: string,
    State: string?,
    ClaimantUserId: number?,
    Health: number?,
    MaxHealth: number?,
    CrackStage: number?,
    CrackStageCount: number,
    PetHp: number?,
    PetMaxHp: number?,
    HatchlingHp: number?,
    HatchlingMaxHp: number?,
    PetName: string,
    HatchlingName: string,
    Adornee: BasePart?,
}

export type EggWorldHud = {
    Sync: (self: EggWorldHud, views: { EggWorldView }) -> (),
    Destroy: (self: EggWorldHud) -> (),
}

type Marker = {
    Ring: CylinderHandleAdornment,
    HealthGui: BillboardGui,
    HealthFill: Frame,
    HealthLabel: TextLabel,
    CrackPips: { Frame },
    FightGui: BillboardGui,
    PetFill: Frame,
    HatchFill: Frame,
    PetLabel: TextLabel,
    HatchLabel: TextLabel,
}

local function healthColor(ratio: number): Color3
    if ratio > 0.5 then
        return HudTheme.HealthHighColor
    elseif ratio > 0.25 then
        return HudTheme.HealthMidColor
    end
    return HudTheme.HealthLowColor
end

local function claimantColor(userId: number): Color3
    local player = Players:GetPlayerByUserId(userId)
    if player ~= nil then
        local character = player.Character
        if character ~= nil then
            local bodyColors = character:FindFirstChildOfClass("BodyColors")
            if bodyColors ~= nil then
                return bodyColors.TorsoColor.Color
            end
        end
    end
    return Color3.fromHSV((userId * 0.6180339887) % 1, 0.72, 0.98)
end

local function createBillboard(name: string, size: UDim2, offset: Vector3, adornee: BasePart): BillboardGui
    local gui = Instance.new("BillboardGui")
    gui.Name = name
    gui.AlwaysOnTop = true
    gui.MaxDistance = HudTheme.BillboardMaxDistance
    gui.Size = size
    gui.StudsOffsetWorldSpace = offset
    gui.Adornee = adornee
    gui.Parent = adornee
    return gui
end

local function createFillBar(parent: Instance, name: string, color: Color3, y: number): (Frame, TextLabel)
    local label = Instance.new("TextLabel")
    label.Name = name .. "Name"
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.Position = UDim2.fromOffset(0, y)
    label.Size = UDim2.new(1, 0, 0, 14)
    label.Text = ""
    label.TextColor3 = HudTheme.PromptColor
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent

    local track = Instance.new("Frame")
    track.Name = name .. "Track"
    track.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
    track.BorderSizePixel = 0
    track.Position = UDim2.fromOffset(0, y + 14)
    track.Size = UDim2.new(1, 0, 0, 10)
    track.Parent = parent

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 4)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BackgroundColor3 = color
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale(1, 1)
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fill

    return fill, label
end

local function createMarker(adornee: BasePart, crackStageCount: number): Marker
    local ring = Instance.new("CylinderHandleAdornment")
    ring.Name = "ClaimRing"
    ring.AlwaysOnTop = false
    ring.CFrame = CFrame.Angles(0, 0, math.rad(90))
    ring.Height = 0.28
    ring.Transparency = 0.25
    ring.Adornee = adornee
    ring.Parent = adornee

    local healthGui =
        createBillboard("EggHealthBillboard", UDim2.fromOffset(160, 42), HudTheme.HealthStudsOffset, adornee)

    local healthFill, healthLabel = createFillBar(healthGui, "Health", HudTheme.HealthHighColor, 0)
    healthLabel.Text = "Egg"

    local pipRow = Instance.new("Frame")
    pipRow.Name = "CrackStages"
    pipRow.BackgroundTransparency = 1
    pipRow.Position = UDim2.fromOffset(0, 28)
    pipRow.Size = UDim2.new(1, 0, 0, 10)
    pipRow.Parent = healthGui

    local pipLayout = Instance.new("UIListLayout")
    pipLayout.FillDirection = Enum.FillDirection.Horizontal
    pipLayout.Padding = UDim.new(0, 4)
    pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pipLayout.Parent = pipRow

    local crackPips = {}
    for index = 1, crackStageCount do
        local pip = Instance.new("Frame")
        pip.Name = "Crack" .. tostring(index)
        pip.BackgroundColor3 = HudTheme.CrackOffColor
        pip.BorderSizePixel = 0
        pip.LayoutOrder = index
        pip.Size = UDim2.new(1 / crackStageCount, -4, 1, 0)
        pip.Parent = pipRow

        local pipCorner = Instance.new("UICorner")
        pipCorner.CornerRadius = UDim.new(0, 3)
        pipCorner.Parent = pip

        table.insert(crackPips, pip)
    end

    local fightGui = createBillboard("EggFightBillboard", UDim2.fromOffset(180, 58), HudTheme.FightStudsOffset, adornee)
    local petFill, petLabel = createFillBar(fightGui, "Pet", HudTheme.PetBarColor, 0)
    local hatchFill, hatchLabel = createFillBar(fightGui, "Hatchling", HudTheme.HatchlingBarColor, 28)

    return {
        Ring = ring,
        HealthGui = healthGui,
        HealthFill = healthFill,
        HealthLabel = healthLabel,
        CrackPips = crackPips,
        FightGui = fightGui,
        PetFill = petFill,
        HatchFill = hatchFill,
        PetLabel = petLabel,
        HatchLabel = hatchLabel,
    }
end

local function destroyMarker(marker: Marker)
    marker.Ring:Destroy()
    marker.HealthGui:Destroy()
    marker.FightGui:Destroy()
end

local function updateMarker(marker: Marker, view: EggWorldView)
    local adornee = view.Adornee
    if adornee == nil then
        return
    end

    local radius = math.max(adornee.Size.X, adornee.Size.Z) * 0.55 + 1.6
    marker.Ring.Radius = radius
    local showRing = view.ClaimantUserId ~= nil
        and (view.State == "Claimed" or view.State == "Breaking" or view.State == "Fighting")
    marker.Ring.Visible = showRing
    if showRing and view.ClaimantUserId ~= nil then
        marker.Ring.Color3 = claimantColor(view.ClaimantUserId)
    end

    local showHealth = view.State == "Breaking" and view.Health ~= nil and view.MaxHealth ~= nil and view.MaxHealth > 0
    marker.HealthGui.Enabled = showHealth
    if showHealth and view.Health ~= nil and view.MaxHealth ~= nil then
        local ratio = math.clamp(view.Health / view.MaxHealth, 0, 1)
        marker.HealthFill.Size = UDim2.fromScale(ratio, 1)
        marker.HealthFill.BackgroundColor3 = healthColor(ratio)
        marker.HealthLabel.Text =
            string.format("Egg  %d/%d", math.floor(view.Health + 0.5), math.floor(view.MaxHealth + 0.5))
        local stage = view.CrackStage or 1
        for index, pip in marker.CrackPips do
            pip.BackgroundColor3 = if index <= stage then HudTheme.CrackOnColor else HudTheme.CrackOffColor
        end
    end

    local showFight = view.State == "Fighting"
        and view.PetMaxHp ~= nil
        and view.HatchlingMaxHp ~= nil
        and view.PetHp ~= nil
        and view.HatchlingHp ~= nil
    marker.FightGui.Enabled = showFight
    if
        showFight
        and view.PetHp ~= nil
        and view.PetMaxHp ~= nil
        and view.HatchlingHp ~= nil
        and view.HatchlingMaxHp ~= nil
    then
        local petRatio = if view.PetMaxHp > 0 then math.clamp(view.PetHp / view.PetMaxHp, 0, 1) else 0
        local hatchRatio = if view.HatchlingMaxHp > 0
            then math.clamp(view.HatchlingHp / view.HatchlingMaxHp, 0, 1)
            else 0
        marker.PetFill.Size = UDim2.fromScale(petRatio, 1)
        marker.HatchFill.Size = UDim2.fromScale(hatchRatio, 1)
        marker.PetLabel.Text = view.PetName
        marker.HatchLabel.Text = view.HatchlingName
    end
end

local function create(): EggWorldHud
    local markers: { [string]: Marker } = {}
    local hud = {} :: EggWorldHud

    function hud:Sync(views: { EggWorldView })
        local seen: { [string]: boolean } = {}
        for _, view in views do
            seen[view.Uid] = true
            local adornee = view.Adornee
            if adornee == nil then
                local existing = markers[view.Uid]
                if existing ~= nil then
                    destroyMarker(existing)
                    markers[view.Uid] = nil
                end
                continue
            end

            local marker = markers[view.Uid]
            if marker == nil or marker.Ring.Adornee ~= adornee then
                if marker ~= nil then
                    destroyMarker(marker)
                end
                marker = createMarker(adornee, view.CrackStageCount)
                markers[view.Uid] = marker
            end
            updateMarker(marker, view)
        end

        for uid, marker in markers do
            if seen[uid] ~= true then
                destroyMarker(marker)
                markers[uid] = nil
            end
        end
    end

    function hud:Destroy()
        for _, marker in markers do
            destroyMarker(marker)
        end
        table.clear(markers)
    end

    return hud
end

return {
    Create = create,
}
