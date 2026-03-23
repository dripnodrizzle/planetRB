-- Server-authoritative spherical gravity + camera-relative movement (multi-planet)
-- Requires:
--   Workspace/Planets/<PlanetModel>/Core (BasePart)
--   Character attribute "ActivePlanetId" set (by nearest-core binder or zones)
-- Client must FireServer({
--   moveAxis = Vector3 (x,z in [-1,1]),
--   jumpRequested = boolean,
--   camForward = Vector3,
--   camRight = Vector3,
-- })

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PLANETS_FOLDER = Workspace:WaitForChild("Planets")
local REMOTE_NAME = "PlanetGravityInput"

-- Tunables
local GRAVITY_ACCELERATION = 260
local WALK_SPEED = 30
local AIR_CONTROL_SPEED = 12
local JUMP_SPEED = 62
local JUMP_COOLDOWN = 0.28
local JUMP_AIR_LOCK = 0.20
local GROUND_CHECK_DISTANCE = 10
local IDLE_DAMPING = 0.82
local TARGET_HIP_HEIGHT = 5.0
local SURFACE_CLEARANCE = 0.9

local ALIGN_RESPONSIVENESS = 12
local ALIGN_MAX_TORQUE = 40000
local GROUND_MOVE_BLEND = 0.18
local AIR_MOVE_BLEND = 0.08
local SURFACE_PUSH_SCALE = 18
local SURFACE_PUSH_MAX = 16

-- Remote
local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

type State = {
	Player: Player,
	Humanoid: Humanoid,
	RootPart: BasePart,

	GravityForce: VectorForce,
	Align: AlignOrientation,

	MoveAxis: Vector3, -- (x,0,z)
	JumpRequested: boolean,
	CamForward: Vector3,
	CamRight: Vector3,

	LastForward: Vector3,
	LastJumpTime: number,
	AirUntil: number,
}

local states: {[Model]: State} = {}

local function safeUnit(v: Vector3, fallback: Vector3): Vector3
	if v.Magnitude > 1e-5 then
		return v.Unit
	end
	return fallback
end

local function projectOntoPlane(v: Vector3, normal: Vector3): Vector3
	return v - normal * v:Dot(normal)
end

local function getPlanetId(planetModel: Instance): string
	local id = planetModel:GetAttribute("PlanetId")
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return planetModel.Name
end

local function findPlanetById(planetId: string): Model?
	if planetId == "" then
		return nil
	end
	for _, p in ipairs(PLANETS_FOLDER:GetChildren()) do
		if p:IsA("Model") then
			if getPlanetId(p) == planetId then
				return p
			end
		end
	end
	return nil
end

local function getCoreForCharacter(character: Model): BasePart?
	local planetId = character:GetAttribute("ActivePlanetId")
	if typeof(planetId) ~= "string" or planetId == "" then
		return nil
	end

	local planet = findPlanetById(planetId)
	if not planet then
		return nil
	end

	local core = planet:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		return core
	end
	return nil
end

local function makeRayParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = false
	return params
end

local function getPlanetUp(rootPos: Vector3, corePos: Vector3): Vector3
	return safeUnit(rootPos - corePos, Vector3.new(0, 1, 0))
end

local function getGroundHit(character: Model, rootPart: BasePart, corePos: Vector3)
	local upDir = getPlanetUp(rootPart.Position, corePos)
	return Workspace:Raycast(
		rootPart.Position,
		(-upDir) * GROUND_CHECK_DISTANCE,
		makeRayParams(character)
	)
end

local function cleanupOld(rootPart: BasePart)
	for _, name in ipairs({
		"PlanetGravityAttachment",
		"PlanetGravityForce",
		"PlanetAlignOrientation",
	}) do
		local obj = rootPart:FindFirstChild(name)
		if obj then
			obj:Destroy()
		end
	end
end

local function setupCharacter(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	cleanupOld(rootPart)

	-- Server-authoritative physics ownership
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	-- Keep default Animate script working, but we bypass default movement
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.UseJumpPower = true
	humanoid.MaxSlopeAngle = 89
	humanoid.HipHeight = math.max(humanoid.HipHeight, TARGET_HIP_HEIGHT)

	-- Forces / align
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

	states[character] = {
		Player = player,
		Humanoid = humanoid,
		RootPart = rootPart,

		GravityForce = gravityForce,
		Align = align,

		MoveAxis = Vector3.zero,
		JumpRequested = false,
		CamForward = Vector3.new(0, 0, -1),
		CamRight = Vector3.new(1, 0, 0),

		LastForward = Vector3.new(0, 0, -1),
		LastJumpTime = 0,
		AirUntil = 0,
	}

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			states[character] = nil
		end
	end)
end

-- Receive intent from client
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

	-- moveAxis: clamp & flatten
	if typeof(payload.moveAxis) == "Vector3" then
		local v = Vector3.new(payload.moveAxis.X, 0, payload.moveAxis.Z)
		if v.Magnitude > 1 then
			v = v.Unit
		end
		state.MoveAxis = v
	end

	if typeof(payload.jumpRequested) == "boolean" then
		state.JumpRequested = payload.jumpRequested
	end

	-- camera basis (client can lie; server still clamps speed/accel)
	if typeof(payload.camForward) == "Vector3" then
		state.CamForward = payload.camForward
	end
	if typeof(payload.camRight) == "Vector3" then
		state.CamRight = payload.camRight
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end
end

RunService.Heartbeat:Connect(function()
	for character, state in pairs(states) do
		local humanoid = state.Humanoid
		local rootPart = state.RootPart

		if not character.Parent or humanoid.Health <= 0 or not rootPart.Parent then
			states[character] = nil
			continue
		end

		local core = getCoreForCharacter(character)
		if not core then
			state.GravityForce.Force = Vector3.zero
			state.JumpRequested = false
			continue
		end

		local upDir = getPlanetUp(rootPart.Position, core.Position)
		local gravityDir = -upDir

		-- Gravity force toward core
		state.GravityForce.Force = gravityDir * rootPart.AssemblyMass * GRAVITY_ACCELERATION

		-- Server projects camera onto tangent plane (camera-relative movement)
		local camF = safeUnit(projectOntoPlane(state.CamForward, upDir), state.LastForward)
		local camR = safeUnit(camF:Cross(upDir), rootPart.CFrame.RightVector)

		local axis = state.MoveAxis
		local desiredMove = (camR * axis.X) + (camF * -axis.Z)
		desiredMove = projectOntoPlane(desiredMove, upDir)

		local moveDir = Vector3.zero
		if desiredMove.Magnitude > 0.001 then
			moveDir = desiredMove.Unit
		end

		local facingDir = (moveDir.Magnitude > 0) and moveDir or camF
		facingDir = safeUnit(facingDir, state.LastForward)
		state.LastForward = facingDir

		-- Align body to the surface
		state.Align.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + facingDir, upDir)

		-- Grounding
		local groundHit = getGroundHit(character, rootPart, core.Position)
		local grounded = (groundHit ~= nil) and (time() >= state.AirUntil)

		-- Tangent velocity control
		local velocity = rootPart.AssemblyLinearVelocity
		local radialVelocity = upDir * velocity:Dot(upDir)
		local tangentVelocity = velocity - radialVelocity

		if moveDir.Magnitude > 0 then
			local speed = grounded and WALK_SPEED or AIR_CONTROL_SPEED
			local targetTangent = moveDir * speed
			local blend = grounded and GROUND_MOVE_BLEND or AIR_MOVE_BLEND
			local blendedTangent = tangentVelocity:Lerp(targetTangent, blend)
			rootPart.AssemblyLinearVelocity = radialVelocity + blendedTangent
		else
			rootPart.AssemblyLinearVelocity = radialVelocity + (tangentVelocity * IDLE_DAMPING)
		end

		-- Surface clearance push
		if groundHit then
			local desiredDistance = humanoid.HipHeight + (rootPart.Size.Y * 0.5) + SURFACE_CLEARANCE
			local actualDistance = (rootPart.Position - groundHit.Position).Magnitude
			if actualDistance < desiredDistance then
				local pushAmount = desiredDistance - actualDistance
				rootPart.AssemblyLinearVelocity += upDir * math.min(pushAmount * SURFACE_PUSH_SCALE, SURFACE_PUSH_MAX)
			end
		end

		-- Jump
		if state.JumpRequested and grounded and (time() - state.LastJumpTime) > JUMP_COOLDOWN then
			local v = rootPart.AssemblyLinearVelocity
			local radial = upDir * v:Dot(upDir)
			local tangentOnly = v - radial

			rootPart.AssemblyLinearVelocity = tangentOnly + (upDir * JUMP_SPEED)
			state.LastJumpTime = time()
			state.AirUntil = time() + JUMP_AIR_LOCK
		end

		state.JumpRequested = false
	end
end)
