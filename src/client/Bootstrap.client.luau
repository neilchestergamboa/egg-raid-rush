--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameworkModule = Shared:WaitForChild("Framework") :: ModuleScript
local Framework = require(FrameworkModule)

local controllers = script.Parent:WaitForChild("Controllers")
Framework.AddControllers(controllers)
Framework.Start():catch(warn)
