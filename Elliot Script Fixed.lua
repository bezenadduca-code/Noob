-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Client references
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)

-- Load WindUI library
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Create main window
local Window = WindUI:CreateWindow({
    Title = "Elliot Script",
    Icon = "pizza",
    Author = "Enhanced Edition",
    Folder = "ElliotScript",
    Size = UDim2.fromOffset(400, 350),
    Transparent = false,
    Theme = "Dark",
    Resizable = false,
    SideBarWidth = 150,
})

-- Window toggle key
Window:SetToggleKey(Enum.KeyCode.K)

-- Mobile open button
Window:EditOpenButton({
    Title = "Elliot",
    Icon = "pizza",
    CornerRadius = UDim.new(0, 16),
    StrokeThickness = 0,
    Color = ColorSequence.new(
        Color3.fromHex("000000"), 
        Color3.fromHex("000000")
    ),
    OnlyMobile = true,
    Enabled = true,
    Draggable = true,
})

-- Create tabs
local ElliotTab = Window:Tab({
    Title = "Elliot",
    Icon = "pizza",
})

-- Sections
local ElliotSection = ElliotTab:Section({ 
    Title = "Elliot Aimbot",
    Opened = true,
})

local AnimationId = "114155003741146"
local AimbotEnabled = false
local RenderConnection
local AutoRotateBackup = nil
local PredictionDistance = 5
local VelocityThreshold = 16
local AimbotType = "Camera + Character"
local Humanoid, HumanoidRootPart = nil, nil
local Camera = workspace.CurrentCamera

-- Pizza throw detection
local IsThrowing = false
local ThrowTimestamp = 0
local ThrowDuration = 0.5 -- How long to aim after throw is detected

-- Arc Visualization Settings
local ShowArc = false
local ArcFolder = nil
local ArcParts = {}
local ArcSegments = 50 -- Increased from 20 for smoother arc
local PizzaSpeed = 80 -- Base speed - will be adjusted based on actual throw force
local PizzaGravity = 196.2 -- Roblox default gravity
local ArcUpdateRate = 0.05 -- Update every 0.05 seconds

-- Actual pizza throw physics from game code
local PizzaThrowForce = 80 -- p_u_33.Config.PizzaThrowForce from the code
local PizzaUpwardComponent = 0.5 -- The Vector3.new(0, 0.5, 0) component

-- Player Movement Tracking
local LastPosition = nil
local LastRotation = nil
local LastUpdateTime = 0
local CurrentVelocity = Vector3.new(0, 0, 0)
local CurrentTurnRate = 0 -- Radians per second

local function SetupCharacter(character)
    Humanoid = character:WaitForChild("Humanoid")
    HumanoidRootPart = character:WaitForChild("HumanoidRootPart")
    LastPosition = HumanoidRootPart.Position
    LastRotation = HumanoidRootPart.CFrame.LookVector
    LastUpdateTime = tick()
end

if LocalPlayer.Character then
    SetupCharacter(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(function(char)
    SetupCharacter(char)
end)

-- Hook into RemoteEvent to detect pizza throws
task.spawn(function()
    local success, remoteEvent = pcall(function()
        return ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("Network", 5):WaitForChild("RemoteEvent", 5)
    end)
    
    if success and remoteEvent then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            
            if method == "FireServer" and self == remoteEvent then
                -- Check if this is a ThrowPizza call
                if args[1] == "UseActorAbility" and args[2] and args[2][1] then
                    local bufferData = args[2][1]
                    -- Check if buffer contains "ThrowPizza"
                    local success, bufferString = pcall(function()
                        return buffer.tostring(bufferData)
                    end)
                    
                    if success and bufferString and string.find(bufferString, "ThrowPizza") then
                        -- Pizza throw detected!
                        IsThrowing = true
                        ThrowTimestamp = tick()
                    end
                end
            end
            
            return oldNamecall(self, ...)
        end)
    end
end)

local function CreateArcFolder()
    if ArcFolder then
        ArcFolder:Destroy()
    end
    ArcFolder = Instance.new("Folder")
    ArcFolder.Name = "PizzaArcVisualizer"
    ArcFolder.Parent = workspace
end

local function ClearArc()
    for _, part in ipairs(ArcParts) do
        if part and part.Parent then
            part:Destroy()
        end
    end
    ArcParts = {}
end

local function CreateArcSegment(position, index)
    local part = Instance.new("Part")
    part.Name = "ArcSegment_" .. index
    part.Size = Vector3.new(0.25, 0.25, 0.25) -- Smaller segments
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Shape = Enum.PartType.Ball
    
    -- Red color for all segments
    part.Color = Color3.fromRGB(255, 0, 0)
    part.Transparency = 0.15 -- Less transparent for better visibility
    
    part.Parent = ArcFolder
    return part
end

local function CalculatePlayerMovement()
    if not HumanoidRootPart then return end
    
    local currentTime = tick()
    local deltaTime = currentTime - LastUpdateTime
    
    if deltaTime > 0 then
        -- Calculate velocity
        local currentPos = HumanoidRootPart.Position
        local displacement = currentPos - LastPosition
        CurrentVelocity = displacement / deltaTime
        
        -- Calculate turn rate
        local currentLookVector = HumanoidRootPart.CFrame.LookVector
        local dotProduct = LastRotation:Dot(currentLookVector)
        dotProduct = math.clamp(dotProduct, -1, 1)
        local angleChange = math.acos(dotProduct)
        CurrentTurnRate = angleChange / deltaTime
        
        -- Update tracking variables
        LastPosition = currentPos
        LastRotation = currentLookVector
        LastUpdateTime = currentTime
    end
end

local function PredictTargetPosition(target, timeAhead)
    if not target or not target.Parent then return target.Position end
    
    local velocity = target.AssemblyLinearVelocity
    local position = target.Position
    
    -- Simple velocity-based prediction
    local predictedPos = position + (velocity * timeAhead)
    
    return predictedPos
end

local function CalculateTrajectoryArc(startPos, targetPos, lookVector)
    -- Use actual game physics: velocity = (LookVector + Vector3.new(0, 0.5, 0)) * PizzaThrowForce
    local throwDirection = (lookVector + Vector3.new(0, PizzaUpwardComponent, 0)).Unit
    local initialVelocity = throwDirection * PizzaThrowForce
    
    -- Calculate more realistic flight time
    local maxTime = 3 -- Maximum flight time in seconds
    local points = {}
    local timeStep = maxTime / ArcSegments
    local lastPos = startPos
    
    -- Raycast parameters to detect ground
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, ArcFolder}
    rayParams.IgnoreWater = false
    
    for i = 0, ArcSegments do
        local t = i * timeStep
        -- Physics: position = start + velocity*t + 0.5*gravity*t^2
        local pos = startPos + initialVelocity * t + Vector3.new(0, -0.5 * PizzaGravity * t * t, 0)
        
        -- Check if this segment would go through the ground
        if i > 0 then
            local direction = pos - lastPos
            local distance = direction.Magnitude
            
            if distance > 0 then
                local rayResult = workspace:Raycast(lastPos, direction.Unit * distance, rayParams)
                
                if rayResult then
                    -- Hit something (ground, wall, etc.)
                    -- Add the hit point as the final point
                    table.insert(points, rayResult.Position)
                    break
                end
            end
        end
        
        table.insert(points, pos)
        lastPos = pos
    end
    
    return points
end

local function FindTarget()
    if not HumanoidRootPart then return nil end
    
    local closestTarget = nil
    local closestDistance = math.huge
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer or not player.Character then continue end
        
        local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
        local targetHum = player.Character:FindFirstChild("Humanoid")
        
        if not targetRoot or not targetHum or targetHum.Health <= 0 then continue end
        
        local distance = (targetRoot.Position - HumanoidRootPart.Position).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            closestTarget = targetRoot
        end
    end
    
    return closestTarget
end

local function UpdateArcVisualization(target)
    if not target or not HumanoidRootPart then
        ClearArc()
        return
    end
    
    ClearArc()
    
    local targetPos = PredictTargetPosition(target, 0.1)
    local points = CalculateTrajectoryArc(HumanoidRootPart.Position + Vector3.new(0, 2, 0), targetPos, HumanoidRootPart.CFrame.LookVector)
    
    for i, pos in ipairs(points) do
        CreateArcSegment(pos, i)
        table.insert(ArcParts, ArcParts[#ArcParts + 1])
    end
end

------------------------------------------------------------------------
-- FIXED: Aimbot with Fallbacks for Camera + Character
------------------------------------------------------------------------

local function AimAt(target)
    if not target or not target.Parent then return end
    
    local success, err = pcall(function()
        -- Calculate predicted position
        local predictedPos = PredictTargetPosition(target, 0.1)
        if not predictedPos then return end
        
        -- Apply prediction distance adjustment
        local velocityUnit = target.AssemblyLinearVelocity.Unit
        if target.AssemblyLinearVelocity.Magnitude > VelocityThreshold then
            predictedPos = predictedPos + (velocityUnit * PredictionDistance)
        end
        
        -- HRP Aimbot (Humanoid + HumanoidRootPart rotation)
        local hrpAimSuccess = false
        if HumanoidRootPart and Humanoid then
            local hrpSuccess, hrpErr = pcall(function()
                if not AutoRotateBackup then
                    AutoRotateBackup = Humanoid.AutoRotate
                end
                Humanoid.AutoRotate = false
                
                -- Zero out angular velocity for stable aiming
                HumanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                
                -- Calculate direction to target
                local direction = (predictedPos - HumanoidRootPart.Position)
                local directionFlat = Vector3.new(direction.X, 0, direction.Z).Unit
                
                -- Create target CFrame looking at the predicted position (Y-axis only rotation)
                local targetCFrame = CFrame.new(HumanoidRootPart.Position, HumanoidRootPart.Position + directionFlat)
                
                -- Smoothly interpolate between current and target rotation
                local currentCFrame = HumanoidRootPart.CFrame
                local newCFrame = currentCFrame:Lerp(targetCFrame, 0.35)
                
                -- Preserve the current position, only update rotation
                HumanoidRootPart.CFrame = CFrame.new(currentCFrame.Position) * (newCFrame - newCFrame.Position)
            end)
            
            hrpAimSuccess = hrpSuccess
            if not hrpSuccess then
                warn("[Aimbot] HRP aiming failed:", hrpErr, "- Attempting fallback to Camera Aimbot")
            end
        end
        
        -- Camera Aimbot (fallback or combined with HRP)
        if AimbotType == "Camera Aimbot" or AimbotType == "Camera + Character" then
            local camSuccess, camErr = pcall(function()
                if Camera then
                    local cameraCFrame = CFrame.lookAt(Camera.CFrame.Position, predictedPos)
                    Camera.CFrame = cameraCFrame
                end
            end)
            
            if not camSuccess then
                warn("[Aimbot] Camera aiming failed:", camErr)
            end
        end
        
        -- If both failed, try emergency fallback: direct prediction aim
        if not hrpAimSuccess and AimbotType == "Camera + Character" then
            local emergencySuccess, emergencyErr = pcall(function()
                if HumanoidRootPart and Humanoid then
                    -- Emergency fallback: simple direct aim at predicted position
                    local direction = (predictedPos - HumanoidRootPart.Position).Unit
                    HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.Position, HumanoidRootPart.Position + direction)
                end
            end)
            
            if not emergencySuccess then
                warn("[Aimbot] Emergency fallback failed:", emergencyErr)
            end
        end
    end)
    
    if not success then
        warn("[Aimbot] Critical error in AimAt function:", err)
    end
end

-- UI Controls
ElliotSection:Slider({
    Title = "Prediction Studs",
    Step = 1,
    Value = { Min = 0, Max = 50, Default = 5 },
    Callback = function(value)
        PredictionDistance = value
    end
})

ElliotSection:Slider({
    Title = "Aim Duration (seconds)",
    Step = 0.1,
    Value = { Min = 0.1, Max = 2, Default = 0.5 },
    Callback = function(value)
        ThrowDuration = value
    end
})

ElliotSection:Slider({
    Title = "Pizza Throw Force",
    Step = 5,
    Value = { Min = 50, Max = 150, Default = 80 },
    Callback = function(value)
        PizzaThrowForce = value
    end
})

-- Add ping display
local PingDisplay = ElliotSection:Paragraph({
    Title = "Network Ping",
    Description = "Calculating..."
})

-- Update ping display every second
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local pingMs = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
            PingDisplay:Set({
                Title = "Network Ping",
                Description = string.format("%.0f ms", pingMs)
            })
        end)
    end
end)

ElliotSection:Slider({
    Title = "Arc Segments",
    Step = 5,
    Value = { Min = 20, Max = 100, Default = 50 },
    Callback = function(value)
        ArcSegments = value
    end
})

ElliotSection:Dropdown({
    Title = "Aimbot Type",
    Values = {"HRP Aimbot", "Camera Aimbot", "Camera + Character"},
    Default = "Camera + Character",
    Multi = false,
    Callback = function(option)
        AimbotType = option
        Window:Notify({
            Title = "Aimbot Type",
            Description = "Changed to: " .. tostring(option),
            Duration = 2
        })
    end
})

-- Add setting for animation requirement
local RequireAnimation = true

ElliotSection:Divider()

-- Arc Toggle
ElliotSection:Toggle({
    Title = "Show Pizza Arc",
    Type = "Checkbox",
    Default = false,
    Callback = function(value)
        ShowArc = value
        
        if value then
            CreateArcFolder()
            Window:Notify({
                Title = "Pizza Arc",
                Description = "Arc visualization enabled!",
                Duration = 2
            })
        else
            ClearArc()
            if ArcFolder then
                ArcFolder:Destroy()
                ArcFolder = nil
            end
            Window:Notify({
                Title = "Pizza Arc",
                Description = "Arc visualization disabled!",
                Duration = 2
            })
        end
    end
})

ElliotSection:Toggle({
    Title = "Require Throw Animation",
    Type = "Checkbox",
    Default = true,
    Callback = function(value)
        RequireAnimation = value
        Window:Notify({
            Title = "Throw Detection",
            Description = RequireAnimation and "Aims only when throwing pizza" or "Aims always (no throw check)",
            Duration = 2
        })
    end
})

ElliotSection:Divider()

ElliotSection:Toggle({
    Title = "Elliot Aimbot",
    Type = "Checkbox",
    Default = false,
    Callback = function(value)
        AimbotEnabled = value
        
        if value then
            RenderConnection = RunService.RenderStepped:Connect(function()
                if not AimbotEnabled then
                    return
                end
                
                -- Check if character references are valid
                if not Humanoid or not HumanoidRootPart or not Humanoid.Parent then
                    if AutoRotateBackup ~= nil then
                        pcall(function()
                            Humanoid.AutoRotate = AutoRotateBackup
                        end)
                        AutoRotateBackup = nil
                    end
                    return
                end
                
                -- Update player movement calculations
                CalculatePlayerMovement()
                
                -- Check if throw duration has expired
                if IsThrowing and (tick() - ThrowTimestamp) > ThrowDuration then
                    IsThrowing = false
                end
                
                -- Always update arc if enabled
                if ShowArc then
                    local target = FindTarget()
                    UpdateArcVisualization(target)
                end
                
                -- Check if we should aim
                local shouldAim = false
                
                if RequireAnimation then
                    -- Check for throw detection
                    shouldAim = IsThrowing
                else
                    -- Always aim when aimbot is on
                    shouldAim = true
                end
                
                if not shouldAim then
                    if AutoRotateBackup ~= nil then
                        pcall(function()
                            Humanoid.AutoRotate = AutoRotateBackup
                        end)
                        AutoRotateBackup = nil
                    end
                    return
                end
                
                local target = FindTarget()
                if not target then
                    if AutoRotateBackup ~= nil then
                        pcall(function()
                            Humanoid.AutoRotate = AutoRotateBackup
                        end)
                        AutoRotateBackup = nil
                    end
                    return
                end
                
                AimAt(target)
            end)
            
            Window:Notify({
                Title = "Aimbot",
                Description = "Aimbot enabled! " .. (RequireAnimation and "(Throw Detection)" or "(Always On)"),
                Duration = 2
            })
        else
            if RenderConnection then
                RenderConnection:Disconnect()
                RenderConnection = nil
            end
            if AutoRotateBackup ~= nil then
                pcall(function()
                    Humanoid.AutoRotate = AutoRotateBackup
                end)
                AutoRotateBackup = nil
            end
            ClearArc()
            
            Window:Notify({
                Title = "Aimbot",
                Description = "Aimbot disabled!",
                Duration = 2
            })
        end
    end
})

-- Notification on script load
Window:Notify({
    Title = "Elliot Script",
    Description = "Script loaded successfully! Press K to toggle UI.",
    Duration = 3
})
