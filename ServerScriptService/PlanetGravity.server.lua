-- Server-authoritative multi-planet gravity movement script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvent = ReplicatedStorage:WaitForChild("PlanetGravityInput")

local function onPlanetGravityInput(player, input)
    -- Implement gravity movement here
end

RemoteEvent.OnServerEvent:Connect(onPlanetGravityInput)