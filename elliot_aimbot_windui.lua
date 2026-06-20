-- Elliot Aimbot (standalone) | WindUI
print("Elliot Aimbot loaded")

------------------------------------------------------------------------
-- SERVICES
------------------------------------------------------------------------
local svc = {
    Players      = game:GetService("Players"),
    Run          = game:GetService("RunService"),
    Input        = game:GetService("UserInputService"),
    RS           = game:GetService("ReplicatedStorage"),
    WS           = game:GetService("Workspace"),
    TweenService = game:GetService("TweenService"),
}

local lp  = svc.Players.LocalPlayer
local gui = lp:WaitForChild("PlayerGui", 10)

------------------------------------------------------------------------
-- WINDUI LOADER
------------------------------------------------------------------------
local ui = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

------------------------------------------------------------------------
-- THEME
------------------------------------------------------------------------
ui:AddTheme({
    Name            = "ElliotTheme",
    Accent          = Color3.fromHex("#FFD700"),
    Background      = Color3.fromHex("#1A1410"),
    Outline         = Color3.fromHex("#FFD700"),
    Text            = Color3.fromHex("#FFF8DC"),
    Toggle          = Color3.fromHex("#FFD700"),
    ToggleBar       = Color3.fromHex("#8B6914"),
    Checkbox        = Color3.fromHex("#FFD700"),
    CheckboxIcon    = Color3.fromHex("#FFF8DC"),
    Slider          = Color3.fromHex("#FFD700"),
    SliderThumb     = Color3.fromHex("#FFF8DC"),
    WindowBackground= Color3.fromHex("#0F0D0A"),
})
ui:SetTheme("ElliotTheme")

------------------------------------------------------------------------
-- WINDOW
------------------------------------------------------------------------
local win = ui:CreateWindow({
    Title          = "Elliot Aimbot",
    Icon           = "pizza",
    Author         = "Elliot Module",
    Folder         = "elliot-aimbot",
    Size           = UDim2.fromOffset(480, 420),
    MinSize        = Vector2.new(400, 300),
    MaxSize        = Vector2.new(800, 600),
    Transparent    = true,
    Theme          = "ElliotTheme",
    Resizable      = true,
    SideBarWidth   = 150,
    HideSearchBar  = false,
    ScrollBarEnabled = true,
    BackgroundImageTransparency = 0.4,
})

win:SetToggleKey(Enum.KeyCode.L)

------------------------------------------------------------------------
-- ELLIOT AIMBOT TAB
------------------------------------------------------------------------
local tabElliot = win:Tab({ Title = "Elliot", Icon = "pizza", IconColor = Color3.fromHex("#FFD700"), ShowTabTitle = false })
local secAimbot = tabElliot:Section({ Title = "Pizza Throw Aimbot", Opened = true })

-- Elliot Aimbot Variables
local elliotEnabled     = false
local elliotConnection  = nil
local elliotAutoRotBak  = nil
local elliotPredDist    = 5
local elliotVelThresh   = 16
local elliotAimType     = "Camera + Character"
local elliotThrowDur    = 0.5
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
local elliotCamera      = svc.WS.CurrentCamera
local elliotTargetMode  = "Low HP"
local elliotLastAimTime = 0

-- FIX: Keep buffer but don't block other calls
local function elliotSetupChar(char)
    elliotHum = char:WaitForChild("Humanoid")
    elliotHRP = char:WaitForChild("HumanoidRootPart")
end

if lp.Character then elliotSetupChar(lp.Character) end
lp.CharacterAdded:Connect(function(c) elliotSetupChar(c) end)

-- FIXED HOOK: Less intrusive, passes through all calls quickly
task.spawn(function()
    local ok, re = pcall(function()
        return svc.RS:WaitForChild("Modules",5):WaitForChild("Network",5):WaitForChild("Network",5):WaitForChild("RemoteEvent",5)
    end)
    
    if ok and re then
        -- Use a faster, more specific check
        local oldFire = re.FireServer
        
        re.FireServer = function(self, ...)
            local args = {...}
            
            -- Quick early return if not the right call type (avoids processing overhead)
            if args[1] == "UseActorAbility" and args[2] and type(args[2]) == "table" then
                local abilityData = args[2][1]
                -- Use buffer if available, but fallback to string if not
                local success, result = pcall(function()
                    if type(abilityData) == "string" then
                        return abilityData
                    else
                        return buffer.tostring(abilityData)
                    end
                end)
                
                if success and result and string.find(result, "ThrowPizza") then
                    elliotIsThrowing = true
                    elliotThrowTS = tick()
                    -- Auto-reset after duration (safety net)
                    task.delay(elliotThrowDur + 0.5, function()
                        elliotIsThrowing = false
                    end)
                end
            end
            
            -- Always pass through to original
            return oldFire(self, ...)
        end
    end
end)

local function elliotClearArc()
    for _, p in ipairs(elliotArcParts) do if p and p.Parent then p:Destroy() end end
    elliotArcParts = {}
end

local function elliotCreateArcFolder()
    if elliotArcFolder then elliotArcFolder:Destroy() end
    elliotArcFolder = Instance.new("Folder"); elliotArcFolder.Name="ElliotArc"; elliotArcFolder.Parent=svc.WS
end

local function elliotFindTarget()
    local sf = svc.WS:FindFirstChild("Players") and svc.WS.Players:FindFirstChild("Survivors")
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
                    or  h.Health
                if val < bestVal then best = r; bestVal = val end
            end
        end
    end
    return best
end

local function elliotAimAt(tgt)
    if not tgt or not tgt.Parent then return end
    
    -- Rate limit to prevent lag
    local now = tick()
    if now - elliotLastAimTime < 0.05 then return end
    elliotLastAimTime = now
    
    local vel = tgt.AssemblyLinearVelocity
    local pos = tgt.Position
    local predPos = pos + (tgt.CFrame.LookVector * 2)
    if vel.Magnitude > elliotVelThresh then predPos = predPos + (vel.Unit * elliotPredDist) end
    
    if elliotAimType == "HRP Aimbot" or elliotAimType == "Camera + Character" then
        if elliotHRP then
            -- Only modify AutoRotate temporarily
            if elliotAutoRotBak == nil then 
                elliotAutoRotBak = elliotHum.AutoRotate
                elliotHum.AutoRotate = false
            end
            elliotHRP.AssemblyAngularVelocity = Vector3.new(0,0,0)
            local dir = (predPos - elliotHRP.Position)
            local flat = Vector3.new(dir.X,0,dir.Z).Unit
            local tCF = CFrame.new(elliotHRP.Position, elliotHRP.Position + flat)
            local cur = elliotHRP.CFrame
            local nCF = cur:Lerp(tCF, 0.35)
            elliotHRP.CFrame = CFrame.new(cur.Position) * nCF.Rotation
        end
    end
    
    if elliotAimType == "Camera Aimbot" or elliotAimType == "Camera + Character" then
        local cam = svc.WS.CurrentCamera
        if cam then 
            -- Smooth camera transition
            local targetCF = CFrame.lookAt(cam.CFrame.Position, predPos)
            cam.CFrame = cam.CFrame:Lerp(targetCF, 0.3)
        end
    end
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
        local pos = startPos + iv*t + Vector3.new(0,-0.5*elliotGravity*t*t,0)
        if i > 0 then
            local d = pos - last
            local dm = d.Magnitude
            if dm > 0 then
                local res = svc.WS:Raycast(last, d.Unit*dm, rp)
                if res then table.insert(pts, res.Position); break end
            end
        end
        if pos.Y < -100 then break end
        table.insert(pts, pos); last = pos
    end
    return pts
end

local _elliotLastArcUpdate = 0
local function elliotUpdateArc()
    if not elliotShowArc or not elliotHRP then elliotClearArc(); return end
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
        local part = Instance.new("Part"); part.Name="ArcSeg"..i; part.Size=Vector3.new(0.25,0.25,0.25)
        part.Position=p; part.Anchored=true; part.CanCollide=false; part.Material=Enum.Material.Neon
        part.Shape=Enum.PartType.Ball
        if i == #pts and #pts > 1 then part.Size=Vector3.new(0.5,0.5,0.5); part.Color=Color3.fromRGB(255,255,0); part.Transparency=0
        else part.Color=Color3.fromRGB(255,0,0); part.Transparency=0.15 end
        part.Parent=elliotArcFolder; table.insert(elliotArcParts, part)
    end
end

-- UI Controls
secAimbot:Toggle({ 
    Title = "Enable Aimbot", 
    Type = "Checkbox", 
    Flag = "elliotEnabled", 
    Default = false, 
    Callback = function(v)
        elliotEnabled = v
        if v then
            elliotConnection = svc.Run.RenderStepped:Connect(function()
                if not elliotEnabled or not elliotHum or not elliotHRP then 
                    -- Restore AutoRotate if disabled
                    if elliotAutoRotBak ~= nil then 
                        elliotHum.AutoRotate = elliotAutoRotBak
                        elliotAutoRotBak = nil
                    end
                    return 
                end
                
                if elliotShowArc then elliotUpdateArc() end
                
                -- Check if we should aim
                local shouldAim = elliotRequireAnim and elliotIsThrowing or (not elliotRequireAnim)
                
                if not shouldAim then
                    -- Restore AutoRotate when not aiming
                    if elliotAutoRotBak ~= nil then 
                        elliotHum.AutoRotate = elliotAutoRotBak
                        elliotAutoRotBak = nil
                    end
                    return
                end
                
                -- Reset throw state after duration
                if elliotIsThrowing and (tick() - elliotThrowTS) > elliotThrowDur then
                    elliotIsThrowing = false
                    if elliotAutoRotBak ~= nil then 
                        elliotHum.AutoRotate = elliotAutoRotBak
                        elliotAutoRotBak = nil
                    end
                    return
                end
                
                local tgt = elliotFindTarget()
                if not tgt then
                    if elliotAutoRotBak ~= nil then 
                        elliotHum.AutoRotate = elliotAutoRotBak
                        elliotAutoRotBak = nil
                    end
                    return
                end
                
                elliotAimAt(tgt)
            end)
        else
            if elliotConnection then elliotConnection:Disconnect(); elliotConnection=nil end
            if elliotAutoRotBak ~= nil then 
                if elliotHum then elliotHum.AutoRotate = elliotAutoRotBak end
                elliotAutoRotBak = nil
            end
            elliotClearArc()
            elliotIsThrowing = false
        end
    end 
})

secAimbot:Dropdown({ 
    Title = "Aimbot Type", 
    Flag = "elliotAimType", 
    Values = {"HRP Aimbot","Camera Aimbot","Camera + Character"}, 
    Default = "Camera + Character", 
    Callback = function(v) elliotAimType=v end 
})

secAimbot:Dropdown({ 
    Title = "Target Mode", 
    Flag = "elliotTargetMode", 
    Values = {"Low HP","Closest"}, 
    Default = "Low HP", 
    Callback = function(v) elliotTargetMode=v end 
})

secAimbot:Slider({ 
    Title = "Prediction Studs", 
    Flag = "elliotPredDist", 
    Value = {Min=0,Max=50,Default=5}, 
    Step = 1, 
    Callback = function(v) elliotPredDist=v end 
})

secAimbot:Slider({ 
    Title = "Aim Duration (s)", 
    Flag = "elliotThrowDur", 
    Value = {Min=0.1,Max=2,Default=0.5}, 
    Step = 0.1, 
    Callback = function(v) elliotThrowDur=v end 
})

secAimbot:Slider({ 
    Title = "Pizza Throw Force", 
    Flag = "elliotThrowForce", 
    Value = {Min=50,Max=150,Default=80}, 
    Step = 5, 
    Callback = function(v) elliotThrowForce=v end 
})

secAimbot:Slider({ 
    Title = "Arc Segments", 
    Flag = "elliotArcSegs", 
    Value = {Min=20,Max=100,Default=50}, 
    Step = 5, 
    Callback = function(v) elliotArcSegs=v end 
})

secAimbot:Toggle({ 
    Title = "Show Pizza Arc", 
    Flag = "elliotShowArc", 
    Default = false, 
    Callback = function(v)
        elliotShowArc=v
        if v then elliotCreateArcFolder()
        else elliotClearArc(); if elliotArcFolder then elliotArcFolder:Destroy(); elliotArcFolder=nil end end
    end, 
    Type = "Checkbox"
})

secAimbot:Toggle({ 
    Title = "Require Throw Animation", 
    Flag = "elliotReqAnim", 
    Default = true, 
    Callback = function(v) elliotRequireAnim=v end, 
    Type = "Checkbox"
})

print("Elliot Aimbot ready!")
