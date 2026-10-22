if not game:IsLoaded() then game.Loaded:Wait() end
if not syn or not protectgui then getgenv().protectgui = function() end end

local SilentAimSettings = {
    Enabled = false,
    ClassName = "Spent Hub Silent Aim",
    ToggleKey = "RightAlt",
    TeamCheck = false,
    VisibleCheck = false,
    TargetPart = "HumanoidRootPart",
    SilentAimMethod = "Raycast",
    FOVRadius = 130,
    FOVVisible = false,
    ShowSilentAimTarget = false,
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    HitChance = 100
}
getgenv().SilentAimSettings = SilentAimSettings

-- ESP settings
local ESPSettings = {
    Enabled = false,
    Box = true,
    Name = true,
    Health = true,
    Distance = true,
    Tracer = false,
    Skeleton = false,
    MaxDistance = 1000,
    Color = Color3.fromRGB(120, 90, 255),
    TeamCheck = true,
    RenderFPS = 60
}
getgenv().ESPSettings = ESPSettings

local MainFileName = "SpentHub"
local FileToSave = ""
local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local GetPlayers = Players.GetPlayers
local WorldToScreen = Camera.WorldToScreenPoint
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.RenderStepped
local Heartbeat = RunService.Heartbeat
local GetMouseLocation = UserInputService.GetMouseLocation
local ValidTargetParts = {"Head", "HumanoidRootPart"}
local PredictionAmount = 0.165

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local isLandscape = Camera.ViewportSize.X > Camera.ViewportSize.Y

-- drawings
local mouse_box = Drawing.new("Square")
mouse_box.Visible = false
mouse_box.ZIndex = 999
mouse_box.Color = Color3.fromRGB(120, 90, 255)
mouse_box.Thickness = 2
mouse_box.Size = Vector2.new(24, 24)
mouse_box.Filled = false

local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1.5
fov_circle.NumSides = 100
fov_circle.Radius = 130
fov_circle.Filled = false
fov_circle.Visible = false
fov_circle.ZIndex = 999
fov_circle.Transparency = 0.85
fov_circle.Color = Color3.fromRGB(120, 90, 255)

-- ESP drawings cache
local ESPDrawings = {}

local ExpectedArguments = {
    FindPartOnRayWithIgnoreList = { ArgCountRequired = 3, Args = { "Instance", "Ray", "table", "boolean", "boolean" } },
    FindPartOnRayWithWhitelist = { ArgCountRequired = 3, Args = { "Instance", "Ray", "table", "boolean" } },
    FindPartOnRay = { ArgCountRequired = 2, Args = { "Instance", "Ray", "Instance", "boolean", "boolean" } },
    Raycast = { ArgCountRequired = 3, Args = { "Instance", "Vector3", "Vector3", "RaycastParams" } }
}

local function CalculateChance(Percentage)
    Percentage = math.floor(Percentage)
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100
    return chance <= Percentage / 100
end

-- file handling
if not isfolder(MainFileName) then makefolder(MainFileName) end
if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then
    makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
end
local Files = listfiles(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))

local function GetFiles()
    local out = {}
    for i = 1, #Files do
        local file = Files[i]
        if file:sub(-4) == '.lua' then
            local pos = file:find('.lua', 1, true)
            local start = pos
            local char = file:sub(pos, pos)
            while char ~= '/' and char ~= '\\' and char ~= '' do
                pos = pos - 1
                char = file:sub(pos, pos)
            end
            if char == '/' or char == '\\' then table.insert(out, file:sub(pos + 1, start - 1)) end
        end
    end
    return out
end

local function UpdateFile(FileName)
    writefile(string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName), HttpService:JSONEncode(SilentAimSettings))
end

local function LoadFile(FileName)
    local File = string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName)
    local ConfigData = HttpService:JSONDecode(readfile(File))
    for Index, Value in next, ConfigData do SilentAimSettings[Index] = Value end
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function ValidateArguments(Args, RayMethod)
    local Matches = 0
    if #Args < RayMethod.ArgCountRequired then return false end
    for Pos, Argument in next, Args do
        if typeof(Argument) == RayMethod.Args[Pos] then Matches = Matches + 1 end
    end
    return Matches >= RayMethod.ArgCountRequired
end

local function getDirection(Origin, Position) return (Position - Origin).Unit * 1000 end
local function getMousePosition() return GetMouseLocation(UserInputService) end

local function IsPlayerVisible(Player)
    local PC = Player.Character
    local LPC = LocalPlayer.Character
    if not (PC and LPC) then return false end
    local PRoot = FindFirstChild(PC, SilentAimSettings.TargetPart) or FindFirstChild(PC, "HumanoidRootPart")
    if not PRoot then return false end
    local Obscuring = #GetPartsObscuringTarget(Camera, {PRoot.Position, LPC, PC}, {LPC, PC})
    return Obscuring == 0
end

local function getClosestPlayer()
    if not SilentAimSettings.TargetPart then return end
    local Closest
    local DistanceToMouse
    for _, Player in next, GetPlayers(Players) do
        if Player == LocalPlayer then continue end
        if SilentAimSettings.TeamCheck and Player.Team == LocalPlayer.Team then continue end
        local Character = Player.Character
        if not Character then continue end
        if SilentAimSettings.VisibleCheck and not IsPlayerVisible(Player) then continue end
        local HRP = FindFirstChild(Character, "HumanoidRootPart")
        local Hum = FindFirstChild(Character, "Humanoid")
        if not HRP or not Hum or Hum.Health <= 0 then continue end
        local ScreenPos, OnScreen = getPositionOnScreen(HRP.Position)
        if not OnScreen then continue end
        local Dist = (getMousePosition() - ScreenPos).Magnitude
        if Dist <= (DistanceToMouse or SilentAimSettings.FOVRadius or 2000) then
            Closest = (SilentAimSettings.TargetPart == "Random" and Character[ValidTargetParts[math.random(1, #ValidTargetParts)]]) or Character[SilentAimSettings.TargetPart]
            DistanceToMouse = Dist
        end
    end
    return Closest
end

-- ================= OPTIMIZED ESP SYSTEM =================
local function createESPDrawings()
    return {
        box = Drawing.new("Square"),
        name = Drawing.new("Text"),
        healthBar = Drawing.new("Square"),
        healthBg = Drawing.new("Square"),
        distance = Drawing.new("Text"),
        tracer = Drawing.new("Line"),
        skeletonLines = {}
    }
end

local function cleanupESPDrawings(d)
    for _, obj in pairs(d) do
        if type(obj) == "table" then
            for _, sub in pairs(obj) do
                if sub and sub.Remove then sub:Remove() end
            end
        elseif obj and obj.Remove then
            obj:Remove()
        end
    end
end

local function resetESPDrawings(d, visible)
    d.box.Visible = visible
    d.name.Visible = visible
    d.healthBar.Visible = visible
    d.healthBg.Visible = visible
    d.distance.Visible = visible
    d.tracer.Visible = visible
    for _, line in pairs(d.skeletonLines) do
        line.Visible = visible
    end
end

local function updateESPPlayer(player)
    local d = ESPDrawings[player]
    if not d then
        d = createESPDrawings()
        ESPDrawings[player] = d
    end

    local char = player.Character
    if not char then
        resetESPDrawings(d, false)
        return
    end

    if ESPSettings.TeamCheck and player.Team == LocalPlayer.Team then
        resetESPDrawings(d, false)
        return
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local head = char:FindFirstChild("Head")
    if not hrp or not hum or hum.Health <= 0 or not head then
        resetESPDrawings(d, false)
        return
    end

    local camPos = Camera.CFrame.Position
    local dist = (hrp.Position - camPos).Magnitude
    if dist > ESPSettings.MaxDistance then
        resetESPDrawings(d, false)
        return
    end

    -- Compute box
    local topPos = head.Position + Vector3.new(0, 0.5, 0)
    local bottomPos = hrp.Position - Vector3.new(0, 3, 0)
    local topScreen, topOn = WorldToViewportPoint(Camera, topPos)
    local bottomScreen, bottomOn = WorldToViewportPoint(Camera, bottomPos)

    if not topOn or not bottomOn then
        resetESPDrawings(d, false)
        return
    end

    local height = math.abs(topScreen.Y - bottomScreen.Y)
    local width = height * 0.6
    local x = topScreen.X - width / 2
    local y = topScreen.Y

    if height <= 0 or height > 5000 then
        resetESPDrawings(d, false)
        return
    end

    -- Box
    d.box.Visible = ESPSettings.Box
    d.box.Color = ESPSettings.Color
    d.box.Thickness = 1
    d.box.Filled = false
    d.box.Size = Vector2.new(width, height)
    d.box.Position = Vector2.new(x, y)

    -- Name
    d.name.Visible = ESPSettings.Name
    d.name.Color = ESPSettings.Color
    d.name.Size = 13
    d.name.Center = true
    d.name.Outline = true
    d.name.OutlineColor = Color3.fromRGB(0, 0, 0)
    d.name.Text = player.Name
    d.name.Position = Vector2.new(topScreen.X, y - 18)

    -- Health bar
    local healthPct = hum.Health / hum.MaxHealth
    local barH = height
    local barW = 3
    d.healthBg.Visible = ESPSettings.Health
    d.healthBg.Color = Color3.fromRGB(0, 0, 0)
    d.healthBg.Thickness = 1
    d.healthBg.Filled = true
    d.healthBg.Size = Vector2.new(barW + 2, barH + 2)
    d.healthBg.Position = Vector2.new(x - 8, y - 1)

    d.healthBar.Visible = ESPSettings.Health
    d.healthBar.Color = Color3.fromRGB(70, 210, 130)
    d.healthBar.Thickness = 1
    d.healthBar.Filled = true
    d.healthBar.Size = Vector2.new(barW, barH * healthPct)
    d.healthBar.Position = Vector2.new(x - 7, y + barH * (1 - healthPct))

    -- Distance
    d.distance.Visible = ESPSettings.Distance
    d.distance.Color = Color3.fromRGB(180, 180, 200)
    d.distance.Size = 11
    d.distance.Center = true
    d.distance.Outline = true
    d.distance.OutlineColor = Color3.fromRGB(0, 0, 0)
    d.distance.Text = math.floor(dist) .. "m"
    d.distance.Position = Vector2.new(topScreen.X, y + height + 2)

    -- Tracer
    if ESPSettings.Tracer then
        d.tracer.Visible = true
        d.tracer.Color = ESPSettings.Color
        d.tracer.Thickness = 1
        d.tracer.Transparency = 0.5
        d.tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        d.tracer.To = Vector2.new(topScreen.X, topScreen.Y)
    else
        d.tracer.Visible = false
    end

    -- Skeleton
    if ESPSettings.Skeleton then
        local bones = {
            {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
            {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"},
            {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"},
            {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"},
            {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}
        }
        for i, pair in ipairs(bones) do
            if not d.skeletonLines[i] then d.skeletonLines[i] = Drawing.new("Line") end
            local line = d.skeletonLines[i]
            local a = char:FindFirstChild(pair[1])
            local b = char:FindFirstChild(pair[2])
            if a and b then
                local aPos, aOn = WorldToViewportPoint(Camera, a.Position)
                local bPos, bOn = WorldToViewportPoint(Camera, b.Position)
                if aOn and bOn then
                    line.Visible = true
                    line.Color = ESPSettings.Color
                    line.Thickness = 1
                    line.Transparency = 0.3
                    line.From = Vector2.new(aPos.X, aPos.Y)
                    line.To = Vector2.new(bPos.X, bPos.Y)
                else
                    line.Visible = false
                end
            else
                line.Visible = false
            end
        end
    else
        for _, line in pairs(d.skeletonLines) do line.Visible = false end
    end
end

local function cleanupAllESP()
    for player, d in pairs(ESPdrawings or {}) do
        cleanupESPDrawings(d)
    end
    ESPDrawings = {}
end

local lastESPRender = 0
local espFrameInterval = 1 / ESPSettings.RenderFPS

-- ================= PREMIUM UI =================
local SG = Instance.new("ScreenGui")
SG.Name = "SpentHub"
SG.ResetOnSpawn = false
SG.IgnoreGuiInset = true
SG.DisplayOrder = 999
SG.Parent = game:GetService("CoreGui")

local T = {
    Bg = Color3.fromRGB(8, 8, 12),
    Panel = Color3.fromRGB(16, 16, 22),
    PanelLight = Color3.fromRGB(24, 24, 32),
    Accent = Color3.fromRGB(120, 90, 255),
    Accent2 = Color3.fromRGB(200, 80, 255),
    Text = Color3.fromRGB(240, 240, 248),
    TextDim = Color3.fromRGB(130, 130, 150),
    Green = Color3.fromRGB(70, 210, 130),
    Stroke = Color3.fromRGB(45, 45, 60)
}

local uiW = isLandscape and 660 or 420
local uiH = isLandscape and 420 or 620
if isMobile and isLandscape then uiW, uiH = 700, 400 end

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, uiW, 0, uiH)
Main.Position = UDim2.new(0.5, -uiW/2, 0.5, -uiH/2)
Main.BackgroundColor3 = T.Bg
Main.BackgroundTransparency = 0.02
Main.BorderSizePixel = 0
Main.Parent = SG
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 16)

local glow = Instance.new("Frame")
glow.Size = UDim2.new(1, 24, 1, 24)
glow.Position = UDim2.new(0, -12, 0, -12)
glow.BackgroundColor3 = T.Accent
glow.BackgroundTransparency = 0.82
glow.BorderSizePixel = 0
glow.ZIndex = 0
glow.Parent = Main
Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 22)
TweenService:Create(glow, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    {BackgroundTransparency = 0.65, Size = UDim2.new(1, 32, 1, 32), Position = UDim2.new(0, -16, 0, -16)}):Play()

local stroke = Instance.new("UIStroke", Main)
stroke.Color = T.Stroke
stroke.Thickness = 1

local aurora = Instance.new("Frame")
aurora.Size = UDim2.new(1, 0, 1, 0)
aurora.BackgroundColor3 = T.Bg
aurora.BorderSizePixel = 0
aurora.ClipsDescendants = true
aurora.ZIndex = 1
aurora.Parent = Main
Instance.new("UICorner", aurora).CornerRadius = UDim.new(0, 16)

local auroraGrad = Instance.new("UIGradient")
auroraGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 20, 50)),
    ColorSequenceKeypoint.new(0.35, Color3.fromRGB(10, 10, 20)),
    ColorSequenceKeypoint.new(0.7, Color3.fromRGB(40, 20, 60)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 30))
})
auroraGrad.Rotation = 45
auroraGrad.Parent = aurora

task.spawn(function()
    while aurora.Parent do
        auroraGrad.Rotation = auroraGrad.Rotation + 0.5
        if auroraGrad.Rotation >= 360 then auroraGrad.Rotation = 0 end
        task.wait(0.03)
    end
end)

local scan = Instance.new("Frame")
scan.Size = UDim2.new(1, 0, 1, 0)
scan.BackgroundTransparency = 1
scan.ZIndex = 2
scan.ClipsDescendants = true
scan.Parent = Main
Instance.new("UICorner", scan).CornerRadius = UDim.new(0, 16)
for i = 0, 60 do
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, i/60, 0)
    line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    line.BackgroundTransparency = 0.965
    line.BorderSizePixel = 0
    line.ZIndex = 2
    line.Parent = scan
end

local noise = Instance.new("Frame")
noise.Size = UDim2.new(1, 0, 1, 0)
noise.BackgroundTransparency = 1
noise.ZIndex = 2
noise.ClipsDescendants = true
noise.Parent = Main
Instance.new("UICorner", noise).CornerRadius = UDim.new(0, 16)
for i = 1, 140 do
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 1, 0, 1)
    dot.Position = UDim2.new(math.random(), 0, math.random(), 0)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BackgroundTransparency = math.random(80, 95) / 100
    dot.BorderSizePixel = 0
    dot.ZIndex = 2
    dot.Parent = noise
end

local sweep = Instance.new("Frame")
sweep.Size = UDim2.new(0.18, 0, 1.6, 0)
sweep.Position = UDim2.new(-0.4, 0, -0.3, 0)
sweep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sweep.BackgroundTransparency = 0.93
sweep.BorderSizePixel = 0
sweep.Rotation = 22
sweep.ZIndex = 3
sweep.Parent = Main
Instance.new("UICorner", sweep).CornerRadius = UDim.new(0, 16)

task.spawn(function()
    while sweep.Parent do
        sweep.Position = UDim2.new(-0.4, 0, -0.3, 0)
        TweenService:Create(sweep, TweenInfo.new(2.6, Enum.EasingStyle.Sine), {Position = UDim2.new(1.6, 0, -0.3, 0)}):Play()
        task.wait(3.5)
    end
end)

local Title = Instance.new("Frame")
Title.Size = UDim2.new(1, 0, 0, 48)
Title.BackgroundColor3 = T.Panel
Title.BackgroundTransparency = 0.1
Title.ZIndex = 4
Title.Parent = Main
Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 16)
local titleStroke = Instance.new("UIStroke", Title)
titleStroke.Color = T.Stroke
titleStroke.Thickness = 1
titleStroke.Transparency = 0.5

local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(0, 4, 0, 24)
accentBar.Position = UDim2.new(0, 18, 0.5, -12)
accentBar.BackgroundColor3 = T.Accent
accentBar.BorderSizePixel = 0
accentBar.ZIndex = 5
accentBar.Parent = Title
Instance.new("UICorner", accentBar).CornerRadius = UDim.new(1, 0)
local accentGrad = Instance.new("UIGradient")
accentGrad.Color = ColorSequence.new(T.Accent, T.Accent2)
accentGrad.Parent = accentBar

task.spawn(function()
    TweenService:Create(accentBar, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Size = UDim2.new(0, 4, 0, 32), Position = UDim2.new(0, 18, 0.5, -16)}):Play()
end)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -160, 1, 0)
TitleLabel.Position = UDim2.new(0, 32, 0, 0)
TitleLabel.Text = ""
TitleLabel.TextColor3 = T.Text
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.TextSize = 15
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 5
TitleLabel.Parent = Title

task.spawn(function()
    local txt = "SPENT HUB"
    while TitleLabel.Parent do
        for i = 1, #txt do
            TitleLabel.Text = txt:sub(1, i)
            task.wait(0.055)
        end
        task.wait(5)
        TitleLabel.Text = ""
        task.wait(0.2)
    end
end)

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 32, 0, 32)
MinBtn.Position = UDim2.new(1, -76, 0.5, -16)
MinBtn.Text = "—"
MinBtn.TextColor3 = T.TextDim
MinBtn.BackgroundColor3 = T.PanelLight
MinBtn.Font = Enum.Font.GothamBold
MinBtn.BorderSizePixel = 0
MinBtn.ZIndex = 5
MinBtn.Parent = Title
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 8)

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 32, 0, 32)
Close.Position = UDim2.new(1, -40, 0.5, -16)
Close.Text = "X"
Close.TextColor3 = T.Text
Close.BackgroundColor3 = T.PanelLight
Close.Font = Enum.Font.GothamBold
Close.BorderSizePixel = 0
Close.ZIndex = 5
Close.Parent = Title
Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 8)
Close.MouseButton1Click:Connect(function()
    cleanupAllESP()
    TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
    task.wait(0.3)
    SG:Destroy()
end)

local dragging, dragStart, frameStart
Title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = i.Position; frameStart = Main.Position
    end
end)
Title.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        Main.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + d.X, frameStart.Y.Scale, frameStart.Y.Offset + d.Y)
    end
end)
Title.InputEnded:Connect(function() dragging = false end)

UserInputService.InputChanged:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local relX = (i.Position.X - Main.AbsolutePosition.X) / math.max(Main.AbsoluteSize.X, 1)
    local relY = (i.Position.Y - Main.AbsolutePosition.Y) / math.max(Main.AbsoluteSize.Y, 1)
    if relX > -0.15 and relX < 1.15 and relY > -0.15 and relY < 1.15 then
        auroraGrad.Rotation = 45 + relX * 80
        glow.Position = UDim2.new(0, -12 + relX * 4, 0, -12 + relY * 4)
    end
end)

local minimized = false
local fullSize = UDim2.new(0, uiW, 0, uiH)
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    MinBtn.Text = minimized and "+" or "—"
    TweenService:Create(Main, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Size = minimized and UDim2.new(0, uiW, 0, 48) or fullSize}):Play()
end)

local Body = Instance.new("Frame")
Body.Size = isLandscape and UDim2.new(1, 0, 1, -48) or UDim2.new(1, 0, 1, -108)
Body.Position = UDim2.new(0, 0, 0, 48)
Body.BackgroundTransparency = 1
Body.ZIndex = 4
Body.Parent = Main

local Sidebar = Instance.new("Frame")
if isLandscape then
    Sidebar.Size = UDim2.new(0, 160, 1, -20)
    Sidebar.Position = UDim2.new(0, 10, 0, 10)
else
    Sidebar.Size = UDim2.new(1, -20, 0, 52)
    Sidebar.Position = UDim2.new(0, 10, 0, 10)
end
Sidebar.BackgroundColor3 = T.Panel
Sidebar.BackgroundTransparency = 0.15
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 5
Sidebar.Parent = Body
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 12)
local sideStroke = Instance.new("UIStroke", Sidebar)
sideStroke.Color = T.Stroke
sideStroke.Thickness = 1
sideStroke.Transparency = 0.5

local sidebarLayout = Instance.new("UIListLayout", Sidebar)
sidebarLayout.FillDirection = isLandscape and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
sidebarLayout.Padding = UDim.new(0, 5)
sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sidebarLayout.VerticalAlignment = isLandscape and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center
if isLandscape then Instance.new("UIPadding", Sidebar).PaddingTop = UDim.new(0, 8) end

local Pages = Instance.new("Frame")
if isLandscape then
    Pages.Size = UDim2.new(1, -190, 1, -20)
    Pages.Position = UDim2.new(0, 180, 0, 10)
else
    Pages.Size = UDim2.new(1, -20, 1, -140)
    Pages.Position = UDim2.new(0, 10, 0, 72)
end
Pages.BackgroundColor3 = T.Panel
Pages.BackgroundTransparency = 0.15
Pages.BorderSizePixel = 0
Pages.ZIndex = 5
Pages.Parent = Body
Instance.new("UICorner", Pages).CornerRadius = UDim.new(0, 12)
local pageStroke = Instance.new("UIStroke", Pages)
pageStroke.Color = T.Stroke
pageStroke.Thickness = 1
pageStroke.Transparency = 0.5

local function makePage()
    local s = Instance.new("ScrollingFrame")
    s.Size = UDim2.new(1, -16, 1, -16)
    s.Position = UDim2.new(0, 8, 0, 8)
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 4
    s.ScrollBarImageColor3 = T.TextDim
    s.CanvasSize = UDim2.new(0, 0, 0, 0)
    s.Visible = false
    s.ZIndex = 6
    s.Parent = Pages
    local l = Instance.new("UIListLayout", s)
    l.Padding = UDim.new(0, 8)
    return s
end

local CombatPage = makePage()
local VisualPage = makePage()
local ESPPage = makePage()
local ConfigPage = makePage()
CombatPage.Visible = true

local tabs = {}
local function makeTab(name, page, order)
    local b = Instance.new("TextButton")
    if isLandscape then
        b.Size = UDim2.new(1, -16, 0, 44)
    else
        b.Size = UDim2.new(0, 100, 1, -8)
    end
    b.BackgroundColor3 = T.Bg
    b.Text = name
    b.TextColor3 = T.TextDim
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.BorderSizePixel = 0
    b.LayoutOrder = order
    b.ZIndex = 6
    b.Parent = Sidebar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

    local indicator = Instance.new("Frame")
    if isLandscape then
        indicator.Size = UDim2.new(0, 3, 0, 20)
        indicator.Position = UDim2.new(0, 0, 0.5, -10)
    else
        indicator.Size = UDim2.new(0, 20, 0, 3)
        indicator.Position = UDim2.new(0.5, -10, 1, -4)
    end
    indicator.BackgroundColor3 = T.Accent
    indicator.BorderSizePixel = 0
    indicator.Visible = false
    indicator.ZIndex = 7
    indicator.Parent = b
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

    tabs[name] = {button = b, indicator = indicator, page = page}

    b.MouseEnter:Connect(function()
        if not tabs[name].indicator.Visible then
            TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = T.PanelLight}):Play()
        end
    end)
    b.MouseLeave:Connect(function()
        if not tabs[name].indicator.Visible then
            TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = T.Bg}):Play()
        end
    end)

    b.MouseButton1Click:Connect(function()
        for n, t in pairs(tabs) do
            t.button.BackgroundColor3 = T.Bg
            t.button.TextColor3 = T.TextDim
            t.indicator.Visible = false
            t.page.Visible = false
        end
        b.BackgroundColor3 = T.PanelLight
        b.TextColor3 = T.Text
        indicator.Visible = true
        page.Visible = true
        page.Position = UDim2.new(0, 20, 0, 8)
        TweenService:Create(page, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 8, 0, 8)
        }):Play()
    end)
    return b
end

makeTab("COMBAT", CombatPage, 1)
makeTab("VISUAL", VisualPage, 2)
makeTab("ESP", ESPPage, 3)
makeTab("CONFIG", ConfigPage, 4)
tabs["COMBAT"].button.BackgroundColor3 = T.PanelLight
tabs["COMBAT"].button.TextColor3 = T.Text
tabs["COMBAT"].indicator.Visible = true

local function newLabel(parent, text, order, dim)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 0, 24)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = dim and T.TextDim or T.Text
    l.Font = Enum.Font.GothamBold
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = order or 0
    l.ZIndex = 7
    l.Parent = parent
    return l
end

local function newToggle(parent, label, order, initial, cb)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -16, 0, 44)
    f.BackgroundColor3 = T.PanelLight
    f.BackgroundTransparency = 0.1
    f.BorderSizePixel = 0
    f.LayoutOrder = order or 0
    f.ZIndex = 7
    f.Parent = parent
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
    local fStroke = Instance.new("UIStroke", f)
    fStroke.Color = T.Stroke
    fStroke.Thickness = 1
    fStroke.Transparency = 0.5

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -70, 1, 0)
    l.Position = UDim2.new(0, 14, 0, 0)
    l.Text = label
    l.TextColor3 = T.Text
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamSemibold
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = 8
    l.Parent = f

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 44, 0, 22)
    track.Position = UDim2.new(1, -56, 0.5, -11)
    track.BackgroundColor3 = initial and T.Green or T.Panel
    track.BorderSizePixel = 0
    track.ZIndex = 8
    track.Parent = f
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = initial and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
    knob.BackgroundColor3 = T.Text
    knob.BorderSizePixel = 0
    knob.ZIndex = 9
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local state = initial
    local function setState(v, anim)
        state = v
        if cb then cb(v) end
        local targetPos = v and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
        local targetColor = v and T.Green or T.Panel
        if anim then
            TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = targetPos}):Play()
            TweenService:Create(track, TweenInfo.new(0.15), {BackgroundColor3 = targetColor}):Play()
        else
            knob.Position = targetPos
            track.BackgroundColor3 = targetColor
        end
    end

    f.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            setState(not state, true)
        end
    end)
    f.MouseEnter:Connect(function()
        TweenService:Create(fStroke, TweenInfo.new(0.15), {Color = T.Accent, Transparency = 0.3}):Play()
    end)
    f.MouseLeave:Connect(function()
        TweenService:Create(fStroke, TweenInfo.new(0.15), {Color = T.Stroke, Transparency = 0.5}):Play()
    end)
    return {frame = f, set = function(v) setState(v, false) end, get = function() return state end}
end

local function newSlider(parent, label, min, max, def, order, cb)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -16, 0, 56)
    f.BackgroundColor3 = T.PanelLight
    f.BackgroundTransparency = 0.1
    f.BorderSizePixel = 0
    f.LayoutOrder = order or 0
    f.ZIndex = 7
    f.Parent = parent
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
    local fStroke = Instance.new("UIStroke", f)
    fStroke.Color = T.Stroke
    fStroke.Thickness = 1
    fStroke.Transparency = 0.5

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -20, 0, 18)
    l.Position = UDim2.new(0, 14, 0, 6)
    l.Text = label
    l.TextColor3 = T.Text
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamSemibold
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = 8
    l.Parent = f

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0, 60, 0, 18)
    valLabel.Position = UDim2.new(1, -74, 0, 6)
    valLabel.Text = tostring(def)
    valLabel.TextColor3 = T.Accent
    valLabel.BackgroundTransparency = 1
    valLabel.Font = Enum.Font.GothamBold
    valLabel.TextSize = 12
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.ZIndex = 8
    valLabel.Parent = f

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -28, 0, 6)
    bar.Position = UDim2.new(0, 14, 0, 34)
    bar.BackgroundColor3 = T.Panel
    bar.BorderSizePixel = 0
    bar.ZIndex = 8
    bar.Parent = f
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((def-min)/(max-min), 0, 1, 0)
    fill.BackgroundColor3 = T.Accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 9
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new((def-min)/(max-min), -7, 0.5, -7)
    knob.Text = ""
    knob.BackgroundColor3 = T.Text
    knob.BorderSizePixel = 0
    knob.ZIndex = 10
    knob.Parent = bar
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local drag = false
    local function upd(x)
        local p = math.clamp((x - bar.AbsolutePosition.X)/bar.AbsoluteSize.X, 0, 1)
        local v = math.floor(min + (max-min)*p)
        fill.Size = UDim2.new(p, 0, 1, 0)
        knob.Position = UDim2.new(p, -7, 0.5, -7)
        valLabel.Text = tostring(v)
        if cb then cb(v) end
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true; upd(i.Position.X) end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then upd(i.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
    end)
    return f
end

local function newCycle(parent, label, options, def, order, cb)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -16, 0, 44)
    f.BackgroundColor3 = T.PanelLight
    f.BackgroundTransparency = 0.1
    f.BorderSizePixel = 0
    f.LayoutOrder = order or 0
    f.ZIndex = 7
    f.Parent = parent
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -100, 1, 0)
    l.Position = UDim2.new(0, 14, 0, 0)
    l.Text = label
    l.TextColor3 = T.Text
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamSemibold
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = 8
    l.Parent = f

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 78, 0, 26)
    btn.Position = UDim2.new(1, -90, 0.5, -13)
    btn.Text = def
    btn.TextColor3 = T.Accent
    btn.BackgroundColor3 = T.Bg
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    btn.ZIndex = 8
    btn.Parent = f
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local idx = 1
    for i, o in ipairs(options) do if o == def then idx = i end end
    btn.MouseButton1Click:Connect(function()
        idx = (idx % #options) + 1
        btn.Text = options[idx]
        if cb then cb(options[idx]) end
    end)
    return f
end

newLabel(CombatPage, "SILENT AIM", 1, true)
local enabledToggle = newToggle(CombatPage, "Enable Silent Aim", 2, false, function(v)
    SilentAimSettings.Enabled = v
    mouse_box.Visible = v and SilentAimSettings.ShowSilentAimTarget
end)
newToggle(CombatPage, "Team Check", 3, false, function(v) SilentAimSettings.TeamCheck = v end)
newToggle(CombatPage, "Visible Check", 4, false, function(v) SilentAimSettings.VisibleCheck = v end)
newCycle(CombatPage, "Target Part", {"Head","HumanoidRootPart","Random"}, "HumanoidRootPart", 5, function(v) SilentAimSettings.TargetPart = v end)
newCycle(CombatPage, "Method", {"Raycast","FindPartOnRay","FindPartOnRayWithWhitelist","FindPartOnRayWithIgnoreList","Mouse.Hit/Target"}, "Raycast", 6, function(v) SilentAimSettings.SilentAimMethod = v end)
newSlider(CombatPage, "Hit Chance", 0, 100, 100, 7, function(v) SilentAimSettings.HitChance = v end)

newLabel(VisualPage, "FIELD OF VIEW", 1, true)
newToggle(VisualPage, "Show FOV Circle", 2, false, function(v)
    SilentAimSettings.FOVVisible = v
    fov_circle.Visible = v
end)
newSlider(VisualPage, "FOV Radius", 0, 360, 130, 3, function(v)
    SilentAimSettings.FOVRadius = v
    fov_circle.Radius = v
end)
newToggle(VisualPage, "Show Silent Aim Target", 4, false, function(v)
    SilentAimSettings.ShowSilentAimTarget = v
    mouse_box.Visible = v and SilentAimSettings.Enabled
end)
newLabel(VisualPage, "PREDICTION", 5, true)
newToggle(VisualPage, "Mouse.Hit Prediction", 6, false, function(v) SilentAimSettings.MouseHitPrediction = v end)
newSlider(VisualPage, "Prediction Amount", 16, 100, 16, 7, function(v)
    PredictionAmount = v / 100
    SilentAimSettings.MouseHitPredictionAmount = PredictionAmount
end)

-- ESP page
newLabel(ESPPage, "ESP SYSTEM", 1, true)
local espToggle = newToggle(ESPPage, "Enable ESP", 2, false, function(v)
    ESPSettings.Enabled = v
    if not v then
        for player, d in pairs(ESPdrawings or {}) do
            resetESPDrawings(d, false)
        end
    end
end)
newToggle(ESPPage, "Box ESP", 3, true, function(v) ESPSettings.Box = v end)
newToggle(ESPPage, "Name ESP", 4, true, function(v) ESPSettings.Name = v end)
newToggle(ESPPage, "Health ESP", 5, true, function(v) ESPSettings.Health = v end)
newToggle(ESPPage, "Distance ESP", 6, true, function(v) ESPSettings.Distance = v end)
newToggle(ESPPage, "Tracer ESP", 7, false, function(v) ESPSettings.Tracer = v end)
newToggle(ESPPage, "Skeleton ESP", 8, false, function(v) ESPSettings.Skeleton = v end)
newToggle(ESPPage, "ESP Team Check", 9, true, function(v) ESPSettings.TeamCheck = v end)
newSlider(ESPPage, "ESP Max Distance", 100, 5000, 1000, 10, function(v) ESPSettings.MaxDistance = v end)

-- Config page
newLabel(ConfigPage, "CONFIGURATION", 1, true)
local configName = "config1"
local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -16, 0, 40)
nameBox.BackgroundColor3 = T.PanelLight
nameBox.TextColor3 = T.Text
nameBox.PlaceholderText = "Config name"
nameBox.PlaceholderColor3 = T.TextDim
nameBox.Text = ""
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 12
nameBox.BorderSizePixel = 0
nameBox.LayoutOrder = 2
nameBox.ZIndex = 7
nameBox.Parent = ConfigPage
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 8)
nameBox:GetPropertyChangedSignal("Text"):Connect(function()
    if nameBox.Text and #nameBox.Text > 0 then configName = nameBox.Text end
end)

local saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(1, -16, 0, 40)
saveBtn.BackgroundColor3 = T.PanelLight
saveBtn.Text = "Save Config"
saveBtn.TextColor3 = T.Text
saveBtn.Font = Enum.Font.GothamSemibold
saveBtn.TextSize = 12
saveBtn.BorderSizePixel = 0
saveBtn.LayoutOrder = 3
saveBtn.ZIndex = 7
saveBtn.Parent = ConfigPage
Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 8)
saveBtn.MouseButton1Click:Connect(function()
    if configName and configName ~= "" then UpdateFile(configName) end
end)

local loadBtn = Instance.new("TextButton")
loadBtn.Size = UDim2.new(1, -16, 0, 40)
loadBtn.BackgroundColor3 = T.PanelLight
loadBtn.Text = "Load Config"
loadBtn.TextColor3 = T.Text
loadBtn.Font = Enum.Font.GothamSemibold
loadBtn.TextSize = 12
loadBtn.BorderSizePixel = 0
loadBtn.LayoutOrder = 4
loadBtn.ZIndex = 7
loadBtn.Parent = ConfigPage
Instance.new("UICorner", loadBtn).CornerRadius = UDim.new(0, 8)
loadBtn.MouseButton1Click:Connect(function()
    if configName and configName ~= "" then
        local ok = pcall(function() LoadFile(configName) end)
        if ok then
            enabledToggle.set(SilentAimSettings.Enabled)
            fov_circle.Visible = SilentAimSettings.FOVVisible
            fov_circle.Radius = SilentAimSettings.FOVRadius
            mouse_box.Visible = SilentAimSettings.ShowSilentAimTarget and SilentAimSettings.Enabled
            PredictionAmount = SilentAimSettings.MouseHitPredictionAmount
        end
    end
end)

-- loading ring
local loadingRing = Instance.new("Frame")
loadingRing.Size = UDim2.new(0, 60, 0, 60)
loadingRing.Position = UDim2.new(0.5, -30, 0.5, -30)
loadingRing.BackgroundTransparency = 1
loadingRing.ZIndex = 20
loadingRing.Parent = Main

local ring = Instance.new("Frame")
ring.Size = UDim2.new(1, 0, 1, 0)
ring.BackgroundTransparency = 1
ring.ZIndex = 20
ring.Parent = loadingRing
local ringStroke = Instance.new("UIStroke", ring)
ringStroke.Color = T.Accent
ringStroke.Thickness = 3
ringStroke.Transparency = 0.3
Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)

task.spawn(function()
    local start = tick()
    local rot = 0
    while tick() - start < 0.9 do
        rot = (rot + 12) % 360
        if loadingRing.Parent then ring.Rotation = rot end
        task.wait(0.02)
    end
    if loadingRing.Parent then
        TweenService:Create(loadingRing, TweenInfo.new(0.3), {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
        task.wait(0.3)
        loadingRing:Destroy()
    end
end)

-- silent aim loop
RenderStepped:Connect(function()
    if SilentAimSettings.Enabled and SilentAimSettings.ShowSilentAimTarget then
        local target = getClosestPlayer()
        if target then
            local Root = target.Parent and target.Parent.PrimaryPart or target
            local pos, onScreen = WorldToViewportPoint(Camera, Root.Position)
            mouse_box.Visible = onScreen
            if onScreen then mouse_box.Position = Vector2.new(pos.X, pos.Y) end
        else
            mouse_box.Visible = false
        end
    elseif not SilentAimSettings.Enabled then
        mouse_box.Visible = false
    end

    if SilentAimSettings.FOVVisible then
        fov_circle.Visible = true
        fov_circle.Position = getMousePosition()
    else
        fov_circle.Visible = false
    end
end)

-- optimized ESP loop (60fps capped, no lag)
Heartbeat:Connect(function()
    if not ESPSettings.Enabled then
        for _, d in pairs(ESPdrawings or {}) do
            resetESPDrawings(d, false)
        end
        return
    end

    local now = tick()
    if now - lastESPRender < espFrameInterval then return end
    lastESPRender = now

    -- update existing + create new
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            updateESPPlayer(player)
        end
    end

    -- cleanup removed players
    for player, d in pairs(ESPdrawings or {}) do
        if not player.Parent or not player.Character then
            cleanupESPDrawings(d)
            ESPdrawings[player] = nil
        end
    end
end)

-- hooks
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    local chance = CalculateChance(SilentAimSettings.HitChance)

    if SilentAimSettings.Enabled and self == workspace and not checkcaller() and chance == true then
        if Method == "FindPartOnRayWithIgnoreList" and SilentAimSettings.SilentAimMethod == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithIgnoreList) then
                local A_Ray = Arguments[2]
                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    Arguments[2] = Ray.new(Origin, getDirection(Origin, HitPart.Position))
                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif Method == "FindPartOnRayWithWhitelist" and SilentAimSettings.SilentAimMethod == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithWhitelist) then
                local A_Ray = Arguments[2]
                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    Arguments[2] = Ray.new(Origin, getDirection(Origin, HitPart.Position))
                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and SilentAimSettings.SilentAimMethod:lower() == Method:lower() then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRay) then
                local A_Ray = Arguments[2]
                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    Arguments[2] = Ray.new(Origin, getDirection(Origin, HitPart.Position))
                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif Method == "Raycast" and SilentAimSettings.SilentAimMethod == Method then
            if ValidateArguments(Arguments, ExpectedArguments.Raycast) then
                local A_Origin = Arguments[2]
                local HitPart = getClosestPlayer()
                if HitPart then
                    Arguments[3] = getDirection(A_Origin, HitPart.Position)
                    return oldNamecall(unpack(Arguments))
                end
            end
        end
    end
    return oldNamecall(...)
end))

local oldIndex
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    if self == Mouse and not checkcaller() and SilentAimSettings.Enabled and SilentAimSettings.SilentAimMethod == "Mouse.Hit/Target" then
        local HitPart = getClosestPlayer()
        if HitPart then
            if Index == "Target" or Index == "target" then
                return HitPart
            elseif Index == "Hit" or Index == "hit" then
                return (SilentAimSettings.MouseHitPrediction and (HitPart.CFrame + (HitPart.Velocity * PredictionAmount))) or HitPart.CFrame
            elseif Index == "X" or Index == "x" then
                return self.X
            elseif Index == "Y" or Index == "y" then
                return self.Y
            elseif Index == "UnitRay" then
                return Ray.new(self.Origin, (self.Hit - self.Origin).Unit)
            end
        end
    end
    return oldIndex(self, Index)
end))

Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    local land = Camera.ViewportSize.X > Camera.ViewportSize.Y
    if land then
        Main.Size = UDim2.new(0, 660, 0, 420)
        Main.Position = UDim2.new(0.5, -330, 0.5, -210)
    else
        Main.Size = UDim2.new(0, 420, 0, 620)
        Main.Position = UDim2.new(0.5, -210, 0.5, -310)
    end
end)

print("Spent Hub v1.1 loaded | Silent Aim + Optimized ESP | PC + Mobile")
