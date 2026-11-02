--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
local Config = Shared:WaitForChild("Config")
local GuardDefs = require(Config:WaitForChild("GuardDefs") :: ModuleScript)
local CarryDefs = require(Config:WaitForChild("CarryDefs") :: ModuleScript)
local CarryRules = require(Shared:WaitForChild("Rules"):WaitForChild("CarryRules") :: ModuleScript)

type GuardRecord = {
    EggUid: string,
    UserId: number,
    SpawnPosition: Vector3,
    Speed: number,
    Part: Part,
    Returning: boolean,
}

local GuardService = Framework.CreateService({ Name = "GuardService", Client = {} })
local carryService: any = nil
local guardsByEggUid: { [string]: GuardRecord } = {}

local function findEggPosition(eggUid: string): Vector3?
    for _, instance in Workspace:GetDescendants() do
        if instance:GetAttribute("EggUid") == eggUid then
            if instance:IsA("BasePart") then
                return instance.Position
            elseif instance:IsA("Model") then
                return instance:GetPivot().Position
            end
        end
    end
    return nil
end

local function findSafeGate(): BasePart?
    for _, instance in Workspace:GetDescendants() do
        if instance:IsA("BasePart") and (instance.Name == "SafeGate" or instance:GetAttribute("SafeGate") == true) then
            return instance
        end
    end
    return nil
end

local function getRoot(player: Player): BasePart?
    local character = player.Character
    if character == nil then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil
    end
    return root
end

local function destroyGuard(eggUid: string)
    local record = guardsByEggUid[eggUid]
    if record == nil then
        return
    end
    guardsByEggUid[eggUid] = nil
    record.Part:Destroy()
end

local function runChase(record: GuardRecord)
    local accumulated = 0
    while guardsByEggUid[record.EggUid] == record do
        local delta = RunService.Heartbeat:Wait()
        accumulated += delta
        if accumulated < CarryDefs.RuntimeUpdateIntervalSeconds then
            continue
        end
        local elapsed = accumulated
        accumulated = 0

        local destination: Vector3
        if record.Returning then
            destination = record.SpawnPosition
        else
            local player = Players:GetPlayerByUserId(record.UserId)
            local root = if player == nil then nil else getRoot(player)
            if root == nil then
                destroyGuard(record.EggUid)
                return
            end
            destination = root.Position
            if CarryRules.IsWithinDistance(record.Part.Position, destination, CarryDefs.GuardTagDistanceStuds) then
                local dropped = carryService:OnGuardTagged(record.EggUid, record.UserId, root.Position)
                if dropped then
                    record.Returning = true
                    continue
                end
            end
        end

        local nextPosition = CarryRules.StepToward(record.Part.Position, destination, record.Speed, elapsed)
        local gate = findSafeGate()
        if gate ~= nil and CarryRules.IsInsideGate(nextPosition, gate.CFrame, gate.Size) then
            if record.Returning then
                destroyGuard(record.EggUid)
                return
            end
            continue
        end
        record.Part.Position = nextPosition

        if
            record.Returning
            and CarryRules.IsWithinDistance(nextPosition, record.SpawnPosition, CarryDefs.GuardTagDistanceStuds)
        then
            destroyGuard(record.EggUid)
            return
        end
    end
end

function GuardService:KnitStart()
    carryService = Framework.GetService("CarryService")
end

function GuardService:StartChase(eggUid: string, guardDefId: string, carrier: Player): (boolean, string?)
    if guardsByEggUid[eggUid] ~= nil then
        return true, nil
    end
    local definition = GuardDefs[guardDefId]
    local spawnPosition = findEggPosition(eggUid)
    local safeGate = findSafeGate()
    if type(definition) ~= "table" or type(definition.Speed) ~= "number" or spawnPosition == nil then
        return false, "GuardConfigOrEggObjectMissing"
    end
    if safeGate == nil then
        return false, "SafeGateObjectMissing"
    end
    local part = Instance.new("Part")
    part.Name = "RaidGuard_" .. guardDefId
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.one * CarryDefs.GuardVisualSize
    part.Material = Enum.Material.SmoothPlastic
    part.Color = Color3.fromRGB(233, 175, 73)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = true
    part.Position = spawnPosition + Vector3.new(0, CarryDefs.GuardVisualSize * 0.5, 0)
    part:SetAttribute("EggUid", eggUid)
    part:SetAttribute("GuardDefId", guardDefId)
    part:SetAttribute("TargetUserId", carrier.UserId)
    part.Parent = Workspace

    local record: GuardRecord = {
        EggUid = eggUid,
        UserId = carrier.UserId,
        SpawnPosition = part.Position,
        Speed = definition.Speed,
        Part = part,
        Returning = false,
    }
    guardsByEggUid[eggUid] = record
    task.spawn(runChase, record)
    return true, nil
end

function GuardService:StopChase(eggUid: string)
    destroyGuard(eggUid)
end

return GuardService
