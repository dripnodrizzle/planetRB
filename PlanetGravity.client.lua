-- Correct client script that fires PlanetGravityInput with moveInput and jumpRequested
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local moveInput = Vector3.new(0, 0, 0)
local jumpRequested = false

UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.W then
            moveInput = Vector3.new(0, 0, 1)
        elseif input.KeyCode == Enum.KeyCode.S then
            moveInput = Vector3.new(0, 0, -1)
        else
            moveInput = Vector3.new(0, 0, 0)
        end
    end
end)

UserInputService.JumpRequest:Connect(function()
    jumpRequested = true
end)

RunService.RenderStepped:Connect(function()
    game.ReplicatedStorage.PlanetGravityInput:Fire(moveInput, jumpRequested)
    jumpRequested = false
end)