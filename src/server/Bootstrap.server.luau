--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ConfigValidatorModule = ConfigFolder:WaitForChild("ConfigValidator") :: ModuleScript
local ConfigValidator = require(ConfigValidatorModule)

local isConfigValid, configError = ConfigValidator.Validate()
if not isConfigValid then
    error(configError or "Shared config validation failed.", 0)
end

local FrameworkModule = Shared:WaitForChild("Framework") :: ModuleScript
local Framework = require(FrameworkModule)

Framework.Start():catch(warn)
