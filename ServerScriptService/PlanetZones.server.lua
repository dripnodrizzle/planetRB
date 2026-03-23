-- Binds ActivePlanetId when touching Workspace.Planets/*/Zone
local function onTouch(part)
    if part:IsA("Zone") then
        -- Logic to bind ActivePlanetId
    end
end

Workspace.Planets.ChildAdded:Connect(function(planets)
    planets.Zone.Touched:Connect(onTouch)
end);