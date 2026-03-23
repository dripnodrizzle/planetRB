local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

local PLANETS_FOLDER = Workspace:WaitForChild("Planets")

local yaw = 0
local pitch = math.rad(-15)
local distance = 20
local height = 6

local dragging = false
local lastMousePos: Vector2? = nil
local SENSITIVITY = 0.008
local MIN_PITCH = math.rad(-80)
local MAX_PITCH = math.rad(20)

local function safeUnit(v: Vector3, fallback: Vector3): Vector3
if v.Magnitude > 1e-5 then return v.Unit end
return fallback
end

local function projectOntoPlane(v: Vector3, normal: Vector3): Vector3
return v - normal * v:Dot(normal)
end

local function getPlanetCoreFromCharacter(character: Model): BasePart?
local planetId = character:GetAttribute("ActivePlanetId")
if typeof(planetId) ~= "string" or planetId == "" then
return nil
end

for _, planet in ipairs(PLANETS_FOLDER:GetChildren()) do
if planet:IsA("Model") then
local id = planet:GetAttribute("PlanetId")
if (typeof(id) == "string" and id == planetId) or planet.Name == planetId then
local core = planet:FindFirstChild("Core")
if core and core:IsA("BasePart") then
return core
end
end
end
end
return nil
end

UserInputService.InputBegan:Connect(function(input, gp)
if gp then return end
if input.UserInputType == Enum.UserInputType.MouseButton2 then
dragging = true
lastMousePos = UserInputService:GetMouseLocation()
UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
end
end)

UserInputService.InputEnded:Connect(function(input, gp)
if input.UserInputType == Enum.UserInputType.MouseButton2 then
dragging = false
lastMousePos = nil
UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end
end)

RunService.RenderStepped:Connect(function()
local character = player.Character
if not character then return end

local hrp = character:FindFirstChild("HumanoidRootPart")
if not (hrp and hrp:IsA("BasePart")) then return end

local core = getPlanetCoreFromCharacter(character)
if not core then
camera.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, distance), hrp.Position)
return
end

if dragging then
local cur = UserInputService:GetMouseLocation()
if lastMousePos then
local delta = cur - lastMousePos
yaw -= delta.X * SENSITIVITY
pitch = math.clamp(pitch - delta.Y * SENSITIVITY, MIN_PITCH, MAX_PITCH)
end
lastMousePos = cur
end

local planetUp = safeUnit(hrp.Position - core.Position, Vector3.new(0, 1, 0))

local refForward = projectOntoPlane(Vector3.new(0, 0, -1), planetUp)
refForward = safeUnit(refForward, Vector3.new(0, 0, -1))
local refRight = safeUnit(refForward:Cross(planetUp), Vector3.new(1, 0, 0))

local forward = (refForward * math.cos(yaw) + refRight * math.sin(yaw))
forward = safeUnit(projectOntoPlane(forward, planetUp), refForward)

local camRight = safeUnit(forward:Cross(planetUp), refRight)
local pitchCF = CFrame.fromAxisAngle(camRight, pitch)
local lookDir = pitchCF:VectorToWorldSpace(forward)
lookDir = safeUnit(projectOntoPlane(lookDir, planetUp), forward)

local camPos = hrp.Position - lookDir * distance + planetUp * height
camera.CFrame = CFrame.lookAt(camPos, hrp.Position, planetUp)
end)
