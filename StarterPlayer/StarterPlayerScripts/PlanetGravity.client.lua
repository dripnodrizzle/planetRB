local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("PlanetGravityInput")

local jumpQueued = false

UserInputService.JumpRequest:Connect(function()
	jumpQueued = true
end)

local function getMoveInput()
	local x = 0
	local z = 0

	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		z += 1
	end

	local v = Vector3.new(x, 0, z)
	if v.Magnitude > 1 then
		v = v.Unit
	end

	return v
end

RunService.RenderStepped:Connect(function()
	remote:FireServer({
		moveInput = getMoveInput(),
		jumpRequested = jumpQueued,
	})

	jumpQueued = false
end)