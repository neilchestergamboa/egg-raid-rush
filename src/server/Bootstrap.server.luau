--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameworkModule = Shared:WaitForChild("Framework") :: ModuleScript
local Framework = require(FrameworkModule)

Framework.Start():catch(warn)
