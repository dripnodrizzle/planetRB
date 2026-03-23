-- Planet-up scriptable camera with:
-- - RMB drag to rotate (when shift lock is OFF)
-- - Shift toggles shift lock (LockCenter) + over-shoulder offset
-- - Uses character attribute ActivePlanetId to find Workspace/Planets/<planet>/Core

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

local PLANETS_FOLDER = Workspace:WaitForChild("Planets")

-- Shared shift lock state (also read by PlanetGravity.client.lua)
local shiftValue = ReplicatedStorage:FindFirstChild("ShiftLockEnabled")
if not shiftValue then
	shiftValue = Instance.new("BoolValue")
	shiftValue.Name = "ShiftLockEnabled"
	shiftValue.Value = false
	shiftValue.Parent = ReplicatedStorage
end

-- Camera tuning
local distance = 20
local height = 6
local yaw = 0
local pitch = math.rad(-15)

local SENSITIVITY = 0.008
local MIN_PITCH = math.rad(-80)
local MAX_PITCH = math.rad(20)

-- RMB drag state (only when shift lock OFF)
local dragging = false
local lastMousePos: Vector2? = nil

-- Shift lock shoulder offsets
local SHIFTLOCK_OFFSET_RIGHT = 2.25
local SHIFTLOCK_OFFSET_UP = 0.6

local function safeUnit(v: Vector3, fallback: Vector3): Vector3
	if v.Magnitude > 1e-5 then return v.Unit end
	return fallback
end

local function projectOntoPlane(v: Vector3, normal: Vector3): Vector3
	return v - normal * v:Dot(normal)
end

local function getPlanetIdFromCharacter(character: Model): string?
	local planetId = character:GetAttribute("ActivePlanetId")
	if typeof(planetId) == "string" and planetId ~= "" then
		return planetId
	end
	return nil
end

local function getPlanetCoreById(planetId: string): BasePart?
	for _, planet in ipairs(PLANETS_FOLDER:GetChildren()) do
		if planet:IsA("Model") then
			local idAttr = planet:GetAttribute("PlanetId")
			local id = (typeof(idAttr) == "string" and idAttr ~= "") and idAttr or planet.Name
			if id == planetId then
				local core = planet:FindFirstChild("Core")
				if core and core:IsA("BasePart") then
					return core
				end
			end
		end
	end
	return nil
end

local function applyMouseBehavior()
	if shiftValue.Value then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		UserInputService.MouseBehavior = dragging and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Toggle shift lock
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftValue.Value = not shiftValue.Value
		dragging = false
		lastMousePos = nil
		applyMouseBehavior()
		return
	end

	-- RMB drag (only when shift lock OFF)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and not shiftValue.Value then
		dragging = true
		lastMousePos = UserInputService:GetMouseLocation()
		applyMouseBehavior()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and not shiftValue.Value then
		dragging = false
		lastMousePos = nil
		applyMouseBehavior()
	end
end)

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end

	local planetId = getPlanetIdFromCharacter(character)
	if not planetId then
		camera.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, distance), hrp.Position)
		return
	end

	local core = getPlanetCoreById(planetId)
	if not core then
		camera.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, distance), hrp.Position)
		return
	end

	-- Mouse delta -> yaw/pitch
	if shiftValue.Value then
		local delta = UserInputService:GetMouseDelta()
		yaw -= delta.X * SENSITIVITY
		pitch = math.clamp(pitch - delta.Y * SENSITIVITY, MIN_PITCH, MAX_PITCH)
	elseif dragging then
		local cur = UserInputService:GetMouseLocation()
		if lastMousePos then
			local delta = cur - lastMousePos
			yaw -= delta.X * SENSITIVITY
			pitch = math.clamp(pitch - delta.Y * SENSITIVITY, MIN_PITCH, MAX_PITCH)
		end
		lastMousePos = cur
	end

	local planetUp = safeUnit(hrp.Position - core.Position, Vector3.new(0, 1, 0))

	-- Stable reference forward on tangent plane
	local refForward = projectOntoPlane(Vector3.new(0, 0, -1), planetUp)
	refForward = safeUnit(refForward, Vector3.new(0, 0, -1))
	local refRight = safeUnit(refForward:Cross(planetUp), Vector3.new(1, 0, 0))

	-- Yaw around planetUp
	local forward = refForward * math.cos(yaw) + refRight * math.sin(yaw)
	forward = safeUnit(projectOntoPlane(forward, planetUp), refForward)

	-- Pitch around camera right
	local camRight = safeUnit(forward:Cross(planetUp), refRight)
	local pitchCF = CFrame.fromAxisAngle(camRight, pitch)

	local lookDir = pitchCF:VectorToWorldSpace(forward)
	lookDir = safeUnit(projectOntoPlane(lookDir, planetUp), forward)

	local camPos = hrp.Position - lookDir * distance + planetUp * height

	-- Shoulder offset when shift lock ON
	if shiftValue.Value then
		camPos += camRight * SHIFTLOCK_OFFSET_RIGHT
		camPos += planetUp * SHIFTLOCK_OFFSET_UP
	end

	camera.CFrame = CFrame.lookAt(camPos, hrp.Position, planetUp)
end)

applyMouseBehavior()
