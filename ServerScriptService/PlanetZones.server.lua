-- PlanetZones.server.lua

-- Binds character attribute ActivePlanetId to the nearest planet in Workspace/Planets/*/Core

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local PLANETS_FOLDER = Workspace:WaitForChild("Planets")

local UPDATE_INTERVAL = 0.25

local function getPlanetId(planetModel: Model): string
	local id = planetModel:GetAttribute("PlanetId")
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return planetModel.Name
end

local function getCores()
	local cores = {}
	for _, planet in ipairs(PLANETS_FOLDER:GetChildren()) do
		if planet:IsA("Model") then
			local core = planet:FindFirstChild("Core")
			if core and core:IsA("BasePart") then
				table.insert(cores, {
					planetId = getPlanetId(planet),
					core = core,
				})
			end
		end
	end
	return cores
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < UPDATE_INTERVAL then return end
	acc = 0

	local cores = getCores()
	if #cores == 0 then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then continue end

		local bestPlanetId: string? = nil
		local bestDist = math.huge

		for _, entry in ipairs(cores) do
			local d = (hrp.Position - entry.core.Position).Magnitude
			if d < bestDist then
				bestDist = d
				bestPlanetId = entry.planetId
			end
		end

		if bestPlanetId then
			character:SetAttribute("ActivePlanetId", bestPlanetId)
		end
	end
end)
