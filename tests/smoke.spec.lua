--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DevPackages = ReplicatedStorage:WaitForChild("DevPackages")
local JestGlobalsModule = DevPackages:WaitForChild("JestGlobals") :: ModuleScript
local JestGlobals = require(JestGlobalsModule)

JestGlobals.it("runs a basic test", function()
	JestGlobals.expect(1 + 2).toBe(3)
end)