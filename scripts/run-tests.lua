--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local testRoot = ReplicatedStorage:WaitForChild("Tests")

local DevPackages = ReplicatedStorage:WaitForChild("DevPackages")
local JestModule = DevPackages:WaitForChild("Jest") :: ModuleScript
local runCLI = require(JestModule).runCLI

local processServiceExists, ProcessService = pcall(function()
	return game:GetService("ProcessService")
end)

local status, result = runCLI(testRoot, {
	verbose = false,
	ci = true,
}, { testRoot }):awaitStatus()

if status == "Rejected" then
	warn(result)
	if processServiceExists then
		ProcessService:ExitAsync(1)
	end
	error("Jest could not start")
end

if status == "Resolved" and result.results.success then
	if processServiceExists then
		ProcessService:ExitAsync(0)
	end
	return
end

if processServiceExists then
	ProcessService:ExitAsync(1)
end

error("Jest tests failed")