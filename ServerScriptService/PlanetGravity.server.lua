local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

Workspace.Gravity = 0

local PLANET_CORE = Workspace:WaitForChild("PlanetCore")
local REMOTE_NAME = "PlanetGravityInput"

local GRAVITY_ACCELERATION = 260
local WALK_SPEED = 30
local AIR_CONTROL_SPEED = 12
local JUMP_SPEED = 62
local JUMP_COOLDOWN = 0.28
local JUMP_AIR_LOCK = 0.20
local GROUND_CHECK_DISTANCE = 9
local IDLE_DAMPING = 0.82
local TARGET_HIP_HEIGHT = 5.0
local SURFACE_CLEARANCE = 0.9

local ALIGN_RESPONSIVENESS = 10
local ALIGN_MAX_TORQUE = 35000
local GROUND_MOVE_BLEND = 0.18
local AIR_MOVE_BLEND = 0.08
local SURFACE_PUSH_SCALE = 18
local SURFACE_PUSH_MAX = 16

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not remote then
remote = Instance.new("RemoteEvent")
remote.Name = REMOTE_NAME
remote.Parent = ReplicatedStorage
end

local states = {}

local function safeUnit(v: Vector3, fallback: Vector3): Vector3
if v.Magnitude > 1e-5 then
return v.Unit
end
return fallback
end

local function projectOntoPlane(v: Vector3, normal: Vector3): Vector3
return v - normal * v:Dot(normal)
end

local function getPlanetUp(worldPosition: Vector3): Vector3
return safeUnit(worldPosition - PLANET_CORE.Position, Vector3.new(0, 1, 0))
end

local function makeRayParams(character: Model): RaycastParams
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { character }
params.IgnoreWater = false
return params
end

local function getGroundHit(character: Model, rootPart: BasePart)
local upDir = getPlanetUp(rootPart.Position)
local gravityDir = -upDir

return Workspace:Raycast(
rootPart.Position,
gravityDir * GROUND_CHECK_DISTANCE,
makeRayParams(character)
)
end

local function cleanupOldObjects(rootPart: BasePart)
for _, name in ipairs({
"PlanetGravityAttachment",
"PlanetGravityForce",
"PlanetAlignOrientation",
"GravityDebug",
}) do
local obj = rootPart:FindFirstChild(name)
if obj then
obj:Destroy()
end
end
end

local function setupCharacter(character: Model)
local player = Players:GetPlayerFromCharacter(character)
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

cleanupOldObjects(rootPart)

pcall(function()
rootPart:SetNetworkOwner(player)
end)

humanoid.AutoRotate = false
humanoid.WalkSpeed = 0
humanoid.JumpPower = 0
humanoid.UseJumpPower = true
humanoid.MaxSlopeAngle = 89
humanoid.HipHeight = math.max(humanoid.HipHeight, TARGET_HIP_HEIGHT)

humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

local attachment = Instance.new("Attachment")
attachment.Name = "PlanetGravityAttachment"
attachment.Parent = rootPart

local gravityForce = Instance.new("VectorForce")
gravityForce.Name = "PlanetGravityForce"
gravityForce.Attachment0 = attachment
gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
gravityForce.ApplyAtCenterOfMass = true
gravityForce.Parent = rootPart

local align = Instance.new("AlignOrientation")
align.Name = "PlanetAlignOrientation"
align.Attachment0 = attachment
align.Mode = Enum.OrientationAlignmentMode.OneAttachment
align.RigidityEnabled = false
align.ReactionTorqueEnabled = false
align.Responsiveness = ALIGN_RESPONSIVENESS
align.MaxTorque = ALIGN_MAX_TORQUE
align.Parent = rootPart

local debugPart = Instance.new("Part")
debugPart.Name = "GravityDebug"
debugPart.Anchored = false
debugPart.CanCollide = false
debugPart.Massless = true
debugPart.Material = Enum.Material.Neon
debugPart.Color = Color3.fromRGB(255, 0, 0)
debugPart.Size = Vector3.new(0.35, 0.35, 10)
debugPart.Parent = rootPart

states[character] = {
Player = player,
Humanoid = humanoid,
RootPart = rootPart,
GravityForce = gravityForce,
Align = align,
MoveInput = Vector3.zero,
JumpRequested = false,
LastForward = Vector3.new(0, 0, -1),
LastJumpTime = 0,
AirUntil = 0,
LastDebugPrint = 0,
}

character.AncestryChanged:Connect(function(_, parent)
if not parent then
states[character] = nil
end
end)
end

local function cleanupCharacter(character: Model)
states[character] = nil
end

remote.OnServerEvent:Connect(function(player, payload)
if typeof(payload) ~= "table" then
return
end

local character = player.Character
if not character then
return
end

local state = states[character]
if not state then
return
end

if typeof(payload.moveInput) == "Vector3" then
state.MoveInput = payload.moveInput
end

if typeof(payload.jumpRequested) == "boolean" then
state.JumpRequested = payload.jumpRequested
end
end)

Players.PlayerAdded:Connect(function(player)
player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(cleanupCharacter)

if player.Character then
setupCharacter(player.Character)
end
end)

for _, player in ipairs(Players:GetPlayers()) do
player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(cleanupCharacter)

if player.Character then
setupCharacter(player.Character)
end
end

RunService.Heartbeat:Connect(function()
for character, state in pairs(states) do
local humanoid = state.Humanoid
local rootPart = state.RootPart

if not character.Parent or not rootPart.Parent or humanoid.Health <= 0 then
states[character] = nil
continue
end

local upDir = getPlanetUp(rootPart.Position)
local gravityDir = -upDir

state.GravityForce.Force = gravityDir * rootPart.AssemblyMass * GRAVITY_ACCELERATION

local debugPart = rootPart:FindFirstChild("GravityDebug")
if debugPart then
debugPart.CFrame = CFrame.lookAt(
rootPart.Position + gravityDir * 5,
rootPart.Position + gravityDir * 10
)
end

local currentLook = projectOntoPlane(rootPart.CFrame.LookVector, upDir)
currentLook = safeUnit(currentLook, state.LastForward)

local currentRight = safeUnit(currentLook:Cross(upDir), rootPart.CFrame.RightVector)

local rawInput = state.MoveInput

local desiredMove =
(currentRight * rawInput.X) +
(currentLook * -rawInput.Z)

desiredMove = projectOntoPlane(desiredMove, upDir)

local moveDir = Vector3.zero
if desiredMove.Magnitude > 0.001 then
moveDir = desiredMove.Unit
end

local facingDir = moveDir
if facingDir.Magnitude <= 0 then
facingDir = currentLook
end
facingDir = safeUnit(facingDir, state.LastForward)
state.LastForward = facingDir

state.Align.CFrame = CFrame.lookAt(
rootPart.Position,
rootPart.Position + facingDir,
upDir
)

local groundHit = getGroundHit(character, rootPart)
local grounded = groundHit ~= nil and time() >= state.AirUntil

local velocity = rootPart.AssemblyLinearVelocity
local radialVelocity = upDir * velocity:Dot(upDir)
local tangentVelocity = velocity - radialVelocity

if moveDir.Magnitude > 0 then
local speed = grounded and WALK_SPEED or AIR_CONTROL_SPEED
local targetTangent = moveDir * speed
local blendedTangent = tangentVelocity:Lerp(targetTangent, grounded and GROUND_MOVE_BLEND or AIR_MOVE_BLEND)
rootPart.AssemblyLinearVelocity = radialVelocity + blendedTangent
else
rootPart.AssemblyLinearVelocity = radialVelocity + (tangentVelocity * IDLE_DAMPING)
end

if groundHit then
local desiredDistance = humanoid.HipHeight + (rootPart.Size.Y * 0.5) + SURFACE_CLEARANCE
local actualDistance = (rootPart.Position - groundHit.Position).Magnitude

if actualDistance < desiredDistance then
local pushAmount = desiredDistance - actualDistance
rootPart.AssemblyLinearVelocity += upDir * math.min(pushAmount * SURFACE_PUSH_SCALE, SURFACE_PUSH_MAX)
end
end

local humState = humanoid:GetState()
if humState == Enum.HumanoidStateType.Physics
or humState == Enum.HumanoidStateType.PlatformStanding
or humState == Enum.HumanoidStateType.Ragdoll then

if grounded then
humanoid:ChangeState(Enum.HumanoidStateType.Running)
end
end

if state.JumpRequested and grounded and (time() - state.LastJumpTime) > JUMP_COOLDOWN then
local currentVelocity = rootPart.AssemblyLinearVelocity
local currentRadial = upDir * currentVelocity:Dot(upDir)
local currentTangentOnly = currentVelocity - currentRadial

rootPart.AssemblyLinearVelocity = currentTangentOnly + (upDir * JUMP_SPEED)
state.LastJumpTime = time()
state.AirUntil = time() + JUMP_AIR_LOCK
end

if time() - state.LastDebugPrint > 1 then
state.LastDebugPrint = time()
print("Input:", rawInput, "MoveDir:", moveDir, "Grounded:", grounded)
end

state.JumpRequested = false
end
end)
