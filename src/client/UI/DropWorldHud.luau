--!strict

local HudTheme = require(script.Parent:WaitForChild("HudTheme") :: ModuleScript)

export type DropWorldView = {
    EggUid: string,
    Adornee: BasePart,
    RemainingSeconds: number,
}

export type DropWorldHud = {
    Sync: (self: DropWorldHud, views: { DropWorldView }) -> (),
    Destroy: (self: DropWorldHud) -> (),
}

type Marker = {
    Gui: BillboardGui,
    Label: TextLabel,
}

local function createMarker(adornee: BasePart): Marker
    local gui = Instance.new("BillboardGui")
    gui.Name = "DropTimerBillboard"
    gui.AlwaysOnTop = true
    gui.MaxDistance = HudTheme.BillboardMaxDistance
    gui.Size = UDim2.fromOffset(160, 36)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
    gui.Adornee = adornee
    gui.Parent = adornee

    local label = Instance.new("TextLabel")
    label.BackgroundColor3 = HudTheme.PanelColor
    label.BackgroundTransparency = 0.2
    label.Font = Enum.Font.GothamBold
    label.Size = UDim2.fromScale(1, 1)
    label.Text = ""
    label.TextColor3 = HudTheme.PromptColor
    label.TextScaled = true
    label.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = label

    return {
        Gui = gui,
        Label = label,
    }
end

local function create(): DropWorldHud
    local markers: { [string]: Marker } = {}
    local hud = {} :: DropWorldHud

    function hud:Sync(views: { DropWorldView })
        local seen: { [string]: boolean } = {}
        for _, view in views do
            seen[view.EggUid] = true
            local marker = markers[view.EggUid]
            if marker == nil or marker.Gui.Adornee ~= view.Adornee then
                if marker ~= nil then
                    marker.Gui:Destroy()
                end
                marker = createMarker(view.Adornee)
                markers[view.EggUid] = marker
            end
            marker.Label.Text = string.format("%.1fs", math.max(0, view.RemainingSeconds))
        end

        for eggUid, marker in markers do
            if seen[eggUid] ~= true then
                marker.Gui:Destroy()
                markers[eggUid] = nil
            end
        end
    end

    function hud:Destroy()
        for _, marker in markers do
            marker.Gui:Destroy()
        end
        table.clear(markers)
    end

    return hud
end

return {
    Create = create,
}
