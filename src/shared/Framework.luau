--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local KnitModule = Packages:WaitForChild("Knit") :: ModuleScript

return require(KnitModule)
