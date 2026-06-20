print("Elliot Aimbot loaded")

------------------------------------------------------------------------
-- SERVICES
------------------------------------------------------------------------
local svc = {
    Players      = game:GetService("Players"),
    Run          = game:GetService("RunService"),
    Input        = game:GetService("UserInputService"),
    WS           = game:GetService("Workspace"),
}

local lp = svc.Players.LocalPlayer

------------------------------------------------------------------------
-- WINDUI LOADER (OFFICIAL)
------------------------------------------------------------------------
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

------------------------------------------------------------------------
-- WINDUI SETUP
------------------------------------------------------------------------
WindUI:SetTheme("Crimson")

local Window = WindUI:CreateWindow({
    Title = "Elliot Aimbot",
    Icon = "target",
    Folder = "ElliotAimbot",
    Size = UDim2.fromOffset(580, 490),
    Theme = "Crimson",
    Acrylic = true,
})

------------------------------------------------------------------------
-- MANUAL KEYBIND
------------------------------------------------------------------------
local uiVisible = true

svc.Input.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.L and input.UserInputType == Enum.UserInputType.Keyboard then
        uiVisible = not uiVisible
        if uiVisible then
            Window:Show()
        else
            Window:Hide()
        end
    end
end)

------------------------------------------------------------------------
-- ELLIOT AIMBOT VARIABLES
------------------------------------------------------------------------
local elliotEnabled     = false
local elliotConnection  = nil
local elliotAutoRotBak  = nil
local elliotAimType     = "Camera + Character"
local elliotThrowDur    = 0.6
local elliotIsThrowing  = false
local elliotThrowTS     = 0
local elliotRequireAnim = true
local elliotShowArc     = false
local elliotArcFolder   = nil
local elliotArcParts    = {}
local elliotArcSegs     = 50
local elliotThrowForce  = 80
local elliotUpComp      = 0.5
local elliotGravity     = 196.2
local elliotHum, elliotHRP = nil, nil
local elliotTargetMode  = "Low HP"
local elliotLastAimTime = 0
local elliotSmoothness  = 0.15
local elliotPredDist    = 5
local elliotThrowAnimId = "rbxassetid://114155003741146"

------------------------------------------------------------------------
-- CHARACTER SETUP WITH ANIMATION HOOK
------------------------------------------------------------------------
local function hookAnimator(animator)
    if not animator then return end
    
    local connection = animator.AnimationPlayed:Connect(function(animTrack)
        if not animTrack or not animTrack.Animation then return end
        
        local animId = ""
        pcall(function()
            animId = tostring(animTrack.Animation.AnimationId)
        end)
        
        if animId:find("114155003741146") or animId:find(elliotThrowAnimId) then
            elliotIsThrowing = true
            elliotThrowTS = tick()
            print("[Elliot] 🎬 Throw animation detected!")
        end
    end)
    
    return connection
end

local animatorConnection = nil
local function elliotSetupChar(char)
    elliotHum = char:WaitForChild("Humanoid", 3)
    elliotHRP = char:WaitForChild("HumanoidRootPart", 3)
    
    if elliotHum then
        local animator = elliotHum:FindFirstChildOfClass("Animator")
        if animator then
            hookAnimator(animator)
        else
            elliotHum.ChildAdded:Connect(function(child)
                if child:IsA("Animator") then
                    hookAnimator(child)
                end
            end)
        end
    end
end

if lp.Character then elliotSetupChar(lp.Character) end
lp.CharacterAdded:Connect(function(c) elliotSetupChar(c) end)

------------------------------------------------------------------------
-- ARC VISUALIZATION
------------------------------------------------------------------------
local function elliotClearArc()
    for _, p in ipairs(elliotArcParts) do
        if p and p.Parent then p:Destroy() end
    end
    elliotArcParts = {}
end

local function elliotCreateArcFolder()
    if elliotArcFolder then elliotArcFolder:Destroy() end
    elliotArcFolder = Instance.new("Folder")
    elliotArcFolder.Name = "ElliotArc"
    elliotArcFolder.Parent = svc.WS
end

local function elliotArcCalc(startPos, lookVec)
    local dir = (lookVec + Vector3.new(0, elliotUpComp, 0)).Unit
    local iv   = dir * elliotThrowForce
    local maxT = 3
    local pts  = {}
    local step = maxT / elliotArcSegs
    local last = startPos
    local rp   = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { lp.Character, elliotArcFolder }
    
    for i = 0, elliotArcSegs do
        local t   = i * step
        local pos = startPos + iv*t + Vector3.new(0, -0.5*elliotGravity*t*t, 0)
        if i > 0 then
            local d = pos - last
            local dm = d.Magnitude
            if dm > 0 then
                local res = svc.WS:Raycast(last, d.Unit*dm, rp)
                if res then
                    table.insert(pts, res.Position)
                    break
                end
            end
        end
        if pos.Y < -100 then break end
        table.insert(pts, pos)
        last = pos
    end
    return pts
end

local _elliotLastArcUpdate = 0
local function elliotUpdateArc()
    if not elliotShowArc or not elliotHRP then
        elliotClearArc()
        return
    end
    
    local now = tick()
    if now - _elliotLastArcUpdate < 0.1 then return end
    _elliotLastArcUpdate = now
    
    local char = lp.Character
    local lArm = char and (char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand") or char:FindFirstChild("LeftLowerArm"))
    local startPos = lArm and lArm.Position or (elliotHRP.Position + Vector3.new(-1,1,0) + elliotHRP.CFrame.LookVector*2)
    local pts = elliotArcCalc(startPos, elliotHRP.CFrame.LookVector)
    
    elliotClearArc()
    if not elliotArcFolder then elliotCreateArcFolder() end
    
    for i, p in ipairs(pts) do
        local part = Instance.new("Part")
        part.Name = "ArcSeg"..i
        part.Size = Vector3.new(0.25, 0.25, 0.25)
        part.Position = p
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Shape = Enum.PartType.Ball
        
        if i == #pts and #pts > 1 then
            part.Size = Vector3.new(0.5, 0.5, 0.5)
            part.Color = Color3.fromRGB(255, 255, 0)
            part.Transparency = 0
        else
            part.Color = Color3.fromRGB(255, 0, 0)
            part.Transparency = 0.15
        end
        
        part.Parent = elliotArcFolder
        table.insert(elliotArcParts, part)
    end
end

------------------------------------------------------------------------
-- TARGET FINDING
------------------------------------------------------------------------
local function elliotFindTarget()
    local sf = svc.WS:FindFirstChild("Players")
    if sf then sf = sf:FindFirstChild("Survivors") end
    if not sf then sf = svc.WS:FindFirstChild("Survivors") end
    if not sf or not elliotHRP then return nil end
    
    local best, bestVal = nil, math.huge
    for _, s in ipairs(sf:GetChildren()) do
        if s ~= lp.Character then
            local h = s:FindFirstChildOfClass("Humanoid")
            local r = s:FindFirstChild("HumanoidRootPart")
            if h and r and h.Health > 0 then
                local val = elliotTargetMode == "Closest"
                    and (r.Position - elliotHRP.Position).Magnitude
                    or h.Health
                if val < bestVal then
                    best = r
                    bestVal = val
                end
            end
        end
    end
    return best
end

------------------------------------------------------------------------
-- AIMING
------------------------------------------------------------------------
local function elliotAimAt(tgt)
    if not tgt or not tgt.Parent then return end
    
    local now = tick()
    if now - elliotLastAimTime < 0.016 then return end
    elliotLastAimTime = now
    
    local vel = tgt.AssemblyLinearVelocity or Vector3.zero
    local pos = tgt.Position
    local predPos = pos
    
    if vel.Magnitude > 2 then
        local dist = (tgt.Position - elliotHRP.Position).Magnitude
        local predTime = math.min(dist / elliotThrowForce, 1.0)
        predPos = tgt.Position + (vel * predTime * (elliotPredDist / 5))
    end
    
    -- HRP Aimbot
    if elliotAimType == "HRP Aimbot" or elliotAimType == "Camera + Character" then
        if elliotHRP and elliotHum then
            if elliotAutoRotBak == nil then
                elliotAutoRotBak = elliotHum.AutoRotate
                elliotHum.AutoRotate = false
            end
            
            elliotHRP.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            local direction = (predPos - elliotHRP.Position)
            local flatDirection = Vector3.new(direction.X, 0, direction.Z)
            
            if flatDirection.Magnitude > 0.1 then
                local lookAt = CFrame.lookAt(elliotHRP.Position, elliotHRP.Position + flatDirection.Unit)
                local cur = elliotHRP.CFrame
                local nCF = cur:Lerp(CFrame.new(cur.Position) * lookAt.Rotation, elliotSmoothness)
                elliotHRP.CFrame = nCF
            end
        end
    end
    
    -- Camera Aimbot
    if elliotAimType == "Camera Aimbot" or elliotAimType == "Camera + Character" then
        local cam = svc.WS.CurrentCamera
        if cam then
            local targetCF = CFrame.lookAt(cam.CFrame.Position, predPos)
            cam.CFrame = cam.CFrame:Lerp(targetCF, elliotSmoothness * 1.5)
        end
    end
end

------------------------------------------------------------------------
-- MAIN AIMBOT LOOP
------------------------------------------------------------------------
local function startAimbot()
    if elliotConnection then elliotConnection:Disconnect() end
    
    elliotConnection = svc.Run.RenderStepped:Connect(function()
        if not elliotEnabled or not elliotHum or not elliotHRP then
            if elliotAutoRotBak ~= nil and elliotHum then
                elliotHum.AutoRotate = elliotAutoRotBak
                elliotAutoRotBak = nil
            end
            return
        end
        
        if elliotShowArc then elliotUpdateArc() end
        
        local shouldAim = false
        if elliotRequireAnim then
            shouldAim = elliotIsThrowing and (tick() - elliotThrowTS) <= elliotThrowDur
        else
            shouldAim = true
        end
        
        if elliotIsThrowing and (tick() - elliotThrowTS) > elliotThrowDur then
            elliotIsThrowing = false
        end
        
        if not shouldAim then
            if elliotAutoRotBak ~= nil and elliotHum then
                elliotHum.AutoRotate = elliotAutoRotBak
                elliotAutoRotBak = nil
            end
            return
        end
        
        local tgt = elliotFindTarget()
        if tgt then
            elliotAimAt(tgt)
        else
            if elliotAutoRotBak ~= nil and elliotHum then
                elliotHum.AutoRotate = elliotAutoRotBak
                elliotAutoRotBak = nil
            end
        end
    end)
end

------------------------------------------------------------------------
-- WINDUI UI (ONE TAB, CORRECT SYNTAX)
------------------------------------------------------------------------
local MainTab = Window:Tab({
    Title = "Aimbot",
    Icon = "crosshair"
})

-- Main toggle
MainTab:Toggle({
    Title = "Enable Aimbot",
    Description = "Toggle the aimbot on/off",
    Value = false,
    Callback = function(v)
        elliotEnabled = v
        if v then
            startAimbot()
            print("[Elliot] ✅ Aimbot enabled")
        else
            if elliotConnection then
                elliotConnection:Disconnect()
                elliotConnection = nil
            end
            if elliotAutoRotBak ~= nil and elliotHum then
                elliotHum.AutoRotate = elliotAutoRotBak
                elliotAutoRotBak = nil
            end
            elliotClearArc()
            elliotIsThrowing = false
            print("[Elliot] ❌ Aimbot disabled")
        end
    end
})

-- Aimbot Type Dropdown
MainTab:Dropdown({
    Title = "Aimbot Type",
    Description = "Choose how the aimbot targets",
    Values = {"HRP Aimbot", "Camera Aimbot", "Camera + Character"},
    Value = "Camera + Character",
    Callback = function(v)
        elliotAimType = v
        print("[Elliot] Aimbot type: " .. v)
    end
})

-- Target Mode Dropdown
MainTab:Dropdown({
    Title = "Target Mode",
    Description = "How targets are selected",
    Values = {"Low HP", "Closest"},
    Value = "Low HP",
    Callback = function(v)
        elliotTargetMode = v
        print("[Elliot] Target mode: " .. v)
    end
})

-- Sliders (CORRECT WindUI syntax)
MainTab:Slider({
    Title = "Throw Window (s)",
    Description = "Duration of throw animation window",
    Step = 0.1,
    Value = {
        Min = 0.1,
        Max = 2,
        Default = 0.6,
    },
    Callback = function(v)
        elliotThrowDur = v
    end
})

MainTab:Slider({
    Title = "Smoothness",
    Description = "How smooth the aimbot transitions",
    Step = 0.01,
    Value = {
        Min = 0.05,
        Max = 0.5,
        Default = 0.15,
    },
    Callback = function(v)
        elliotSmoothness = v
    end
})

MainTab:Slider({
    Title = "Prediction (studs)",
    Description = "How much to predict target movement",
    Step = 1,
    Value = {
        Min = 0,
        Max = 50,
        Default = 5,
    },
    Callback = function(v)
        elliotPredDist = v
    end
})

MainTab:Slider({
    Title = "Throw Force",
    Description = "Force of the throw",
    Step = 5,
    Value = {
        Min = 50,
        Max = 150,
        Default = 80,
    },
    Callback = function(v)
        elliotThrowForce = v
    end
})

MainTab:Slider({
    Title = "Arc Segments",
    Description = "Number of segments in arc visualization",
    Step = 5,
    Value = {
        Min = 20,
        Max = 100,
        Default = 50,
    },
    Callback = function(v)
        elliotArcSegs = v
    end
})

-- Toggles
MainTab:Toggle({
    Title = "Require Animation",
    Description = "Only aim when throw animation plays",
    Value = true,
    Callback = function(v)
        elliotRequireAnim = v
        print("[Elliot] Animation requirement: " .. (v and "ON" or "OFF"))
    end
})

MainTab:Toggle({
    Title = "Show Arc Visualization",
    Description = "Display the throw arc",
    Value = false,
    Callback = function(v)
        elliotShowArc = v
        if v then
            elliotCreateArcFolder()
            print("[Elliot] Arc visualization enabled")
        else
            elliotClearArc()
            if elliotArcFolder then
                elliotArcFolder:Destroy()
                elliotArcFolder = nil
            end
            print("[Elliot] Arc visualization disabled")
        end
    end
})

-- Keybind button
MainTab:Keybind({
    Title = "Toggle UI",
    Description = "Press L to toggle the window",
    Value = Enum.KeyCode.L,
    Mode = "Toggle",
    Callback = function(Key)
        uiVisible = not uiVisible
        if uiVisible then
            Window:Show()
        else
            Window:Hide()
        end
    end
})

------------------------------------------------------------------------
-- NOTIFICATION
------------------------------------------------------------------------
WindUI:Notify({
    Title = "Elliot Aimbot",
    Content = "Aimbot loaded successfully! Press L to toggle UI",
    Duration = 3
})

print("✅ Elliot Aimbot ready! Press L to toggle UI")
