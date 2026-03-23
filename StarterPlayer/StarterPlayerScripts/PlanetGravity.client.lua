-- Sends camera-relative movement intent to server every frame.
-- Reads shared shift lock state from ReplicatedStorage.ShiftLockEnabled
-- Server must have ServerScriptService/PlanetGravity.server.lua listening on RemoteEvent "PlanetGravityInput"

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remote = ReplicatedStorage:WaitForChild("PlanetGravityInput")

-- Shared shift lock state (camera script toggles this)
local shiftValue = ReplicatedStorage:FindFirstChild("ShiftLockEnabled")
if not shiftValue then
	shiftValue = Instance.new("BoolValue")
	shiftValue.Name = "ShiftLockEnabled"
	shiftValue.Value = false
	shiftValue.Parent = ReplicatedStorage
end

local jumpQueued = false
UserInputService.JumpRequest:Connect(function()
	jumpQueued = true
end)

local function getMoveAxis(): Vector3
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then z += 1 end

	local v = Vector3.new(x, 0, z)
	if v.Magnitude > 1 then v = v.Unit end
	return v
end

RunService.RenderStepped:Connect(function()
	local cam = Workspace.CurrentCamera
	if not cam then return end

	remote:FireServer({
		moveAxis = getMoveAxis(),
		jumpRequested = jumpQueued,
		camForward = cam.CFrame.LookVector,
		camRight = cam.CFrame.RightVector,
		shiftLock = shiftValue.Value,
	})

	jumpQueued = false
end)
