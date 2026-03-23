-- Option B: nearest-core auto-binder (no Zone parts needed)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PLANETS_FOLDER = Workspace:WaitForChild("Planets")

-- How often to re-evaluate (seconds). Lower = more responsive, higher = cheaper.
local UPDATE_INTERVAL = 0.25

-- Optional: only bind if within this many studs of the core. Set to nil to always bind nearest.
local MAX_CORE_DISTANCE: number? = nil

local function getPlanetId(planetModel: Instance): string
	local id = planetModel:GetAttribute("PlanetId")
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return planetModel.Name
end

local function getPlanetCore(planetModel: Instance): BasePart?
	local core = planetModel:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		return core
	end
	return nil
end

local function chooseNearestPlanetId(position: Vector3): string?
	local bestId: string? = nil
	local bestDistSq = math.huge

	for _, planet in ipairs(PLANETS_FOLDER:GetChildren()) do
		if planet:IsA("Model") then
			local core = getPlanetCore(planet)
			if core then
				local d = (position - core.Position)
				local distSq = d:Dot(d)
				if distSq < bestDistSq then
					bestDistSq = distSq
					bestId = getPlanetId(planet)
				end
			end
		end
	end

	if not bestId then
		return nil
	end

	if MAX_CORE_DISTANCE then
		if bestDistSq > (MAX_CORE_DISTANCE * MAX_CORE_DISTANCE) then
			return nil
		end
	end

	return bestId
end

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < UPDATE_INTERVAL then
		return
	end
	accum = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then
			continue
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			continue
		end

		local nearestId = chooseNearestPlanetId(hrp.Position)
		if nearestId then
			character:SetAttribute("ActivePlanetId", nearestId)
		else
			-- If no planets exist, clear it
			character:SetAttribute("ActivePlanetId", "")
		end
	end
end)
