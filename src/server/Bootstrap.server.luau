--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ConfigValidator = require(ConfigFolder:WaitForChild("ConfigValidator") :: ModuleScript)

local isConfigValid, configError = ConfigValidator.Validate()
if not isConfigValid then
    error(configError or "Shared config validation failed.", 0)
end

local ServicesFolder = script.Parent:WaitForChild("Services")
for _, serviceModule in ServicesFolder:GetChildren() do
    if serviceModule:IsA("ModuleScript") then
        require(serviceModule)
    end
end

local Framework = require(Shared:WaitForChild("Framework") :: ModuleScript)
Framework.Start():catch(warn)
