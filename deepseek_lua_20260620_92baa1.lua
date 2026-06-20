-- Fix this -- Noli Dev Panel + Nova Proximity + Collision Blocker (SPAM FIXED)
-- LocalScript / client executor

local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local playerName  = LocalPlayer.Name

------------------------------------------------------------------------
-- FIXED: Network Module handling
------------------------------------------------------------------------

-- Get the Network module correctly
local NetworkModule = ReplicatedStorage:FindFirstChild("Modules") and 
                      ReplicatedStorage.Modules:FindFirstChild("Network") and
                      ReplicatedStorage.Modules.Network:FindFirstChild("Network")

local Network = nil
local RemoteEvent = nil
local FireServerFunc = nil

if NetworkModule and NetworkModule:IsA("ModuleScript") then
    -- It's a ModuleScript, require it
    local success, result = pcall(require, NetworkModule)
    if success and result then
        Network = result
        print("[NoliPanel] Network module loaded successfully!")
        
        -- The module itself IS the network interface
        -- It likely has a FireServer function or is callable itself
        if type(result) == "table" then
            -- Check if the table has a FireServer method
            if result.FireServer then
                FireServerFunc = result.FireServer
                RemoteEvent = result -- Store the table for reference
            elseif result.RemoteEvent and type(result.RemoteEvent) == "table" then
                -- RemoteEvent might be nested
                RemoteEvent = result.RemoteEvent
                if RemoteEvent.FireServer then
                    FireServerFunc = RemoteEvent.FireServer
                end
            end
        elseif type(result) == "function" then
            -- The module returns a function
            FireServerFunc = result
        end
    else
        warn("[NoliPanel] Failed to require Network module:", result)
    end
end

-- If we still don't have a FireServer function, try to find a RemoteEvent
if not FireServerFunc then
    -- Search for any RemoteEvent in ReplicatedStorage
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            RemoteEvent = obj
            FireServerFunc = function(...) 
                return RemoteEvent:FireServer(...) 
            end
            print("[NoliPanel] Found RemoteEvent by searching:", RemoteEvent.Name)
            break
        end
    end
end

if not FireServerFunc then
    warn("[NoliPanel] Could not find network fire function! Nova auto-detonate will not work.")
end

------------------------------------------------------------------------
-- Helper function to fire network events safely
------------------------------------------------------------------------

local function FireNetworkEvent(action, data)
    if not FireServerFunc then
        warn("[NoliPanel] Cannot fire network event - FireServer function not found")
        return false
    end
    
    local success, err = pcall(function()
        FireServerFunc(action, data)
    end)
    
    if not success then
        warn("[NoliPanel] Failed to fire network event:", err)
        return false
    end
    return true
end

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------

local cfg = {
    sharpDuration  = 0.4,
    driftTurnSpeed = 1.0,
}

local DASH_SPEED      = 60
local SHARP_TURNSPEED = 12

local state = {
    voidRushOverride = false,
    noWallCollision  = false,
}

-- Nova
local NoliConfig = nil
pcall(function() 
    NoliConfig = require(ReplicatedStorage.Assets.Killers.Noli.Config) 
end)

local NOVA_RADIUS = 26
local NOVA_WINDUP = 2
local NOVA_LIFETIME = 4
local MIN_DETONATE = 4
local MAX_DETONATE = NOVA_RADIUS
local detonateRadius = NOVA_RADIUS * 0.55
local novaEnabled = true
local novaActiveConns = {}
local novaListener = nil

------------------------------------------------------------------------
-- Cleanup registry
------------------------------------------------------------------------

local cleanupTasks = {}
local function onUnload(fn) table.insert(cleanupTasks, fn) end

------------------------------------------------------------------------
-- Build UI
------------------------------------------------------------------------

local existing = PlayerGui:FindFirstChild("NoliDevPanel")
if existing then existing:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name         = "NoliDevPanel"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999
screenGui.Parent       = PlayerGui
onUnload(function() screenGui:Destroy() end)

local panel = Instance.new("Frame")
panel.Name             = "Panel"
panel.Size             = UDim2.new(0, 224, 0, 306)
panel.Position         = UDim2.new(0, 12, 0, 12)
panel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
panel.BorderSizePixel  = 0
panel.Parent           = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

------------------------------------------------------------------------
-- Panel drag
------------------------------------------------------------------------

local anySliderHeld = false
local panelDragging = false
local dragOffset    = Vector2.new()

local title = Instance.new("TextLabel")
title.Name             = "TitleBar"
title.Size             = UDim2.new(1, 0, 0, 26)
title.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
title.BorderSizePixel  = 0
title.Text             = "Noli Dev Panel"
title.TextColor3       = Color3.fromRGB(200, 200, 200)
title.Font             = Enum.Font.SourceSansBold
title.TextSize         = 13
title.ZIndex           = 2
title.Parent           = panel
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local titleClip = Instance.new("Frame")
titleClip.Size             = UDim2.new(1, 0, 0, 8)
titleClip.Position         = UDim2.new(0, 0, 1, -8)
titleClip.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
titleClip.BorderSizePixel  = 0
titleClip.ZIndex           = 2
titleClip.Parent           = title

local dragBtn = Instance.new("TextButton")
dragBtn.Size                   = UDim2.new(1, -28, 1, 0)
dragBtn.BackgroundTransparency = 1
dragBtn.Text                   = ""
dragBtn.ZIndex                 = 3
dragBtn.Parent                 = title

dragBtn.MouseButton1Down:Connect(function()
    if anySliderHeld then return end
    panelDragging = true
    local mouse = LocalPlayer:GetMouse()
    local pp    = panel.AbsolutePosition
    dragOffset  = Vector2.new(mouse.X - pp.X, mouse.Y - pp.Y)
end)

local panelMoveConn = UserInputService.InputChanged:Connect(function(input)
    if not panelDragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        local vp = workspace.CurrentCamera.ViewportSize
        local mx = math.clamp(input.Position.X - dragOffset.X, 0, vp.X - panel.AbsoluteSize.X)
        local my = math.clamp(input.Position.Y - dragOffset.Y, 0, vp.Y - panel.AbsoluteSize.Y)
        panel.Position = UDim2.new(0, mx, 0, my)
    end
end)

local panelEndConn = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        panelDragging = false
    end
end)

onUnload(function()
    panelMoveConn:Disconnect()
    panelEndConn:Disconnect()
end)

------------------------------------------------------------------------
-- Unload button
------------------------------------------------------------------------

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size             = UDim2.new(0, 22, 0, 18)
unloadBtn.Position         = UDim2.new(1, -24, 0.5, -9)
unloadBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
unloadBtn.BorderSizePixel  = 0
unloadBtn.Text             = "✕"
unloadBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
unloadBtn.Font             = Enum.Font.SourceSansBold
unloadBtn.TextSize         = 12
unloadBtn.ZIndex           = 4
unloadBtn.Parent           = title
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 4)

unloadBtn.MouseButton1Click:Connect(function()
    for _, fn in ipairs(cleanupTasks) do pcall(fn) end
    print("[NoliPanel] Unloaded.")
end)

------------------------------------------------------------------------
-- Toggle factory
------------------------------------------------------------------------

local function makeToggle(labelText, yOffset)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, -16, 0, 30)
    row.Position         = UDim2.new(0, 8, 0, yOffset)
    row.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
    row.BorderSizePixel  = 0
    row.Parent           = panel
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -52, 1, 0)
    lbl.Position               = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = labelText
    lbl.TextColor3             = Color3.fromRGB(210, 210, 210)
    lbl.Font                   = Enum.Font.SourceSans
    lbl.TextSize               = 13
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = row

    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(0, 44, 0, 20)
    btn.Position         = UDim2.new(1, -50, 0.5, -10)
    btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    btn.BorderSizePixel  = 0
    btn.Text             = "OFF"
    btn.TextColor3       = Color3.fromRGB(160, 160, 160)
    btn.Font             = Enum.Font.SourceSansBold
    btn.TextSize         = 11
    btn.Parent           = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    return btn
end

local function setPill(btn, on)
    btn.BackgroundColor3 = on and Color3.fromRGB(60, 180, 80) or Color3.fromRGB(70, 70, 70)
    btn.TextColor3       = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 160, 160)
    btn.Text             = on and "ON" or "OFF"
end

------------------------------------------------------------------------
-- Slider factory
------------------------------------------------------------------------

local function makeSlider(labelText, yOffset, minVal, maxVal, default, decimals, onChange)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, -16, 0, 42)
    row.Position         = UDim2.new(0, 8, 0, yOffset)
    row.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
    row.BorderSizePixel  = 0
    row.Parent           = panel
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local fmt = "%." .. decimals .. "f"

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -8, 0, 16)
    lbl.Position               = UDim2.new(0, 8, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.SourceSans
    lbl.TextSize               = 12
    lbl.TextColor3             = Color3.fromRGB(180, 180, 180)
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = row

    local function setLabel(v)
        lbl.Text = labelText .. ":  " .. string.format(fmt, v)
    end
    setLabel(default)

    local track = Instance.new("Frame")
    track.Size             = UDim2.new(1, -16, 0, 6)
    track.Position         = UDim2.new(0, 8, 0, 28)
    track.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    track.BorderSizePixel  = 0
    track.Parent           = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 3)

    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new((default - minVal) / (maxVal - minVal), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(90, 150, 230)
    fill.BorderSizePixel  = 0
    fill.Parent           = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

    local dragZone = Instance.new("TextButton")
    dragZone.Size                   = UDim2.new(1, 0, 0, 20)
    dragZone.Position               = UDim2.new(0, 0, 0.5, -10)
    dragZone.BackgroundTransparency = 1
    dragZone.Text                   = ""
    dragZone.ZIndex                 = 5
    dragZone.Parent                 = track

    local isDragging = false

    local function applyX(screenX)
        local abs   = track.AbsolutePosition
        local sz    = track.AbsoluteSize
        local t     = math.clamp((screenX - abs.X) / sz.X, 0, 1)
        local mult  = 10 ^ decimals
        local value = math.floor((minVal + t * (maxVal - minVal)) * mult + 0.5) / mult
        fill.Size   = UDim2.new(t, 0, 1, 0)
        setLabel(value)
        onChange(value)
    end

    dragZone.MouseButton1Down:Connect(function()
        isDragging    = true
        anySliderHeld = true
        panelDragging = false
        applyX(LocalPlayer:GetMouse().X)
    end)

    local moveConn = UserInputService.InputChanged:Connect(function(input)
        if not isDragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            applyX(input.Position.X)
        end
    end)

    local endConn = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and isDragging then
            isDragging    = false
            anySliderHeld = false
        end
    end)

    onUnload(function()
        moveConn:Disconnect()
        endConn:Disconnect()
    end)
end

------------------------------------------------------------------------
-- Section divider
------------------------------------------------------------------------

local function makeDivider(yOffset, labelText)
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -16, 0, 16)
    lbl.Position               = UDim2.new(0, 8, 0, yOffset)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = labelText
    lbl.TextColor3             = Color3.fromRGB(120, 120, 120)
    lbl.Font                   = Enum.Font.SourceSansBold
    lbl.TextSize               = 11
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = panel
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------

-- Dev tools
local btnVR = makeToggle("Void Rush Override", 30)
local btnWC = makeToggle("No Wall Collision",  64)
makeSlider("Sharp turn (s)", 98,  0.1, 2.0, cfg.sharpDuration,  1, function(v) cfg.sharpDuration  = v end)
makeSlider("Drift speed",   144,  0.1, 8.0, cfg.driftTurnSpeed, 1, function(v) cfg.driftTurnSpeed = v end)

-- Nova section
makeDivider(192, "── Nova Proximity ──")
local btnNova = makeToggle("Auto Detonate", 212)
makeSlider("Detonate radius", 246, MIN_DETONATE, MAX_DETONATE, detonateRadius, 1, function(v)
    detonateRadius = v
end)

-- Nova starts ON so sync the pill immediately
setPill(btnNova, true)

------------------------------------------------------------------------
-- Character references
------------------------------------------------------------------------

local function setupCharacter(character)
    _G.NHP  = character:WaitForChild("HumanoidRootPart")
    _G.NHum = character:WaitForChild("Humanoid")
end

if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end
local charConn = LocalPlayer.CharacterAdded:Connect(setupCharacter)
onUnload(function() charConn:Disconnect() end)

------------------------------------------------------------------------
-- Void Rush Override
------------------------------------------------------------------------

local overrideConn  = nil
local dashStartTime = nil
local currentDir    = nil
local prevVRS       = nil

local function resetDash()
    dashStartTime = tick()
    currentDir    = nil
end

local function stopOverride()
    dashStartTime = nil
    currentDir    = nil

    local hum = _G.NHum
    if hum then
        hum.WalkSpeed  = 16
        hum.AutoRotate = true
        hum:Move(Vector3.new(0, 0, 0))
    end

    if overrideConn then
        overrideConn:Disconnect()
        overrideConn = nil
    end
end

local function startOverride()
    if overrideConn then return end

    overrideConn = RunService.RenderStepped:Connect(function(dt)
        local hum  = _G.NHum
        local root = _G.NHP
        if not hum or not root or not dashStartTime then return end

        hum.WalkSpeed  = DASH_SPEED
        hum.AutoRotate = false

        local camLook = workspace.CurrentCamera.CFrame.LookVector
        local target  = Vector3.new(camLook.X, 0, camLook.Z)
        if target.Magnitude < 0.01 then return end
        target = target.Unit

        if not currentDir then
            local lv   = root.CFrame.LookVector
            currentDir = Vector3.new(lv.X, 0, lv.Z).Unit
        end

        local elapsed   = tick() - dashStartTime
        local turnSpeed = elapsed < cfg.sharpDuration
            and SHARP_TURNSPEED
            or  cfg.driftTurnSpeed

        local diff = target - currentDir
        if diff.Magnitude > 0.001 then
            currentDir = (currentDir + diff.Unit * math.min(diff.Magnitude, turnSpeed * dt)).Unit
        end

        hum:Move(currentDir)
    end)
end

local vrWatchConn = RunService.RenderStepped:Connect(function()
    if not state.voidRushOverride then
        if overrideConn then stopOverride() end
        prevVRS = nil
        return
    end

    local char = _G.NHum and _G.NHum.Parent
    local vrs  = char and char:GetAttribute("VoidRushState")

    if vrs == "Dashing" and prevVRS ~= "Dashing" then
        resetDash()
        startOverride()
    elseif vrs ~= "Dashing" and overrideConn then
        stopOverride()
    end

    prevVRS = vrs
end)

onUnload(function()
    vrWatchConn:Disconnect()
    stopOverride()
    prevVRS = nil
end)

------------------------------------------------------------------------
-- [FIXED] Collision Blocker - Works with Network Module
------------------------------------------------------------------------

local collisionKey = playerName .. "VoidRushCollision"
local lastBlockTime = 0
local originalFireServer = nil

-- Store the original FireServer function if it exists
if FireServerFunc then
    originalFireServer = FireServerFunc
    
    -- Override the FireServer function to intercept collision calls
    FireServerFunc = function(...)
        local args = { ... }
        local name = args[1]
        
        -- If blocker is ON and it's the collision key
        if name == collisionKey and state.noWallCollision then
            -- ANTI-SPAM: Only block it once every 1 second
            local currentTime = tick()
            if currentTime - lastBlockTime > 1 then
                lastBlockTime = currentTime
                print("[NoliPanel] Blocked collision call:", collisionKey)
                return false -- Block the call
            end
        end
        
        -- Otherwise pass through to original
        if originalFireServer then
            return originalFireServer(...)
        end
    end
    
    print("[NoliPanel] Collision blocker hooked successfully!")
end

------------------------------------------------------------------------
-- Nova Proximity tracking
------------------------------------------------------------------------

local function disconnectNovaConns()
    for _, conn in ipairs(novaActiveConns) do
        conn:Disconnect()
    end
    novaActiveConns = {}
end

local function trackVoidstar(voidstar)
    if not novaEnabled then return end

    local fired = false
    local trackConn

    trackConn = RunService.Heartbeat:Connect(function()
        if not voidstar or not voidstar.Parent then
            trackConn:Disconnect()
            return
        end
        if not novaEnabled then return end

        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end

            local char = player.Character
            if not char or not char.PrimaryPart then continue end

            local dist = (voidstar.Position - char.PrimaryPart.Position).Magnitude
            if dist <= detonateRadius and not fired then
                fired = true
                trackConn:Disconnect()
                
                -- Use the network function to fire Nova
                local success = FireNetworkEvent("UseActorAbility", {
                    buffer.fromstring("\x03\x04\x00\x00\x00Nova")
                })
                
                if not success then
                    warn("[NoliPanel] Failed to fire Nova ability")
                end
                return
            end
        end
    end)

    table.insert(novaActiveConns, trackConn)

    task.delay(NOVA_WINDUP + NOVA_LIFETIME + 0.5, function()
        trackConn:Disconnect()
    end)
end

local function startNovaListener()
    if novaListener then return end
    
    novaListener = workspace.DescendantAdded:Connect(function(inst)
        if inst:IsA("BasePart") and inst.Name == "Voidstar" then
            trackVoidstar(inst)
        end
    end)
end

local function stopNovaListener()
    if novaListener then
        novaListener:Disconnect()
        novaListener = nil
    end
    disconnectNovaConns()
end

onUnload(stopNovaListener)

-- Start listening immediately (Nova toggle starts ON)
startNovaListener()

------------------------------------------------------------------------
-- Toggle callbacks
------------------------------------------------------------------------

btnVR.MouseButton1Click:Connect(function()
    state.voidRushOverride = not state.voidRushOverride
    setPill(btnVR, state.voidRushOverride)
    if not state.voidRushOverride then prevVRS = nil end
end)

btnWC.MouseButton1Click:Connect(function()
    state.noWallCollision = not state.noWallCollision
    setPill(btnWC, state.noWallCollision)
    
    if state.noWallCollision then
        print("[NoliPanel] Collision Blocker ENABLED (Anti-Spam Active).")
    else
        print("[NoliPanel] Collision Blocker DISABLED.")
    end
end)

btnNova.MouseButton1Click:Connect(function()
    novaEnabled = not novaEnabled
    setPill(btnNova, novaEnabled)
    if novaEnabled then
        startNovaListener()
    else
        stopNovaListener()
    end
end)

print("[NoliPanel] Loaded. Drag via title bar. ✕ to unload.")
print("[NoliPanel] Network module found:", NetworkModule ~= nil)
print("[NoliPanel] FireServer function found:", FireServerFunc ~= nil)