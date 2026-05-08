-- ================================================
--   🍬 Candy Farm GUI - Delta Executor
--   Game: Candy World / Roblox
--   Compatible: Delta Executor (Lightweight)
-- ================================================

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")
local VirtualUser    = game:GetService("VirtualUser")

local LocalPlayer    = Players.LocalPlayer
local Character      = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HRP            = Character:WaitForChild("HumanoidRootPart")

-- ================================================
-- STATE
-- ================================================
local autoFarmActive = false
local antiAfkActive  = false
local autoFarmThread = nil
local antiAfkThread  = nil

-- ================================================
-- GUI SETUP
-- ================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name             = "CandyFarmGUI"
ScreenGui.ResetOnSpawn     = false
ScreenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent           = game:GetService("CoreGui")   -- pakai CoreGui agar tidak reset

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name              = "MainFrame"
MainFrame.Size              = UDim2.new(0, 240, 0, 200)
MainFrame.Position          = UDim2.new(0, 16, 0.5, -100)
MainFrame.BackgroundColor3  = Color3.fromRGB(30, 20, 45)
MainFrame.BorderSizePixel   = 0
MainFrame.Active            = true
MainFrame.Draggable         = true
MainFrame.Parent            = ScreenGui

-- Rounded corners
local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 14)
UICorner.Parent       = MainFrame

-- Gradient accent border (stroke)
local UIStroke = Instance.new("UIStroke")
UIStroke.Color        = Color3.fromRGB(255, 180, 60)
UIStroke.Thickness    = 2
UIStroke.Parent       = MainFrame

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Name              = "TitleBar"
TitleBar.Size              = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3  = Color3.fromRGB(255, 180, 60)
TitleBar.BorderSizePixel   = 0
TitleBar.Parent            = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 14)
TitleCorner.Parent       = TitleBar

-- Fix bottom corners of title bar
local TitleFix = Instance.new("Frame")
TitleFix.Size             = UDim2.new(1, 0, 0.5, 0)
TitleFix.Position         = UDim2.new(0, 0, 0.5, 0)
TitleFix.BackgroundColor3 = Color3.fromRGB(255, 180, 60)
TitleFix.BorderSizePixel  = 0
TitleFix.Parent           = TitleBar

-- Title Label
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Text                 = "🍬 Candy Farm"
TitleLabel.Size                 = UDim2.new(1, -40, 1, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.TextColor3           = Color3.fromRGB(30, 20, 45)
TitleLabel.TextScaled           = true
TitleLabel.Font                 = Enum.Font.GothamBold
TitleLabel.Parent               = TitleBar

-- Close Button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Text                 = "✕"
CloseBtn.Size                 = UDim2.new(0, 30, 0, 30)
CloseBtn.Position             = UDim2.new(1, -34, 0, 4)
CloseBtn.BackgroundColor3     = Color3.fromRGB(220, 60, 60)
CloseBtn.TextColor3           = Color3.fromRGB(255, 255, 255)
CloseBtn.TextScaled           = true
CloseBtn.Font                 = Enum.Font.GothamBold
CloseBtn.BorderSizePixel      = 0
CloseBtn.Parent               = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent       = CloseBtn

-- ================================================
-- HELPER: Create Toggle Button
-- ================================================
local function createButton(name, labelText, posY)
    local Btn = Instance.new("TextButton")
    Btn.Name                  = name
    Btn.Text                  = labelText
    Btn.Size                  = UDim2.new(1, -24, 0, 44)
    Btn.Position              = UDim2.new(0, 12, 0, posY)
    Btn.BackgroundColor3      = Color3.fromRGB(50, 35, 75)
    Btn.TextColor3            = Color3.fromRGB(255, 220, 100)
    Btn.TextScaled            = true
    Btn.Font                  = Enum.Font.GothamSemibold
    Btn.BorderSizePixel       = 0
    Btn.AutoButtonColor       = false
    Btn.Parent                = MainFrame

    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 10)
    BtnCorner.Parent       = Btn

    local BtnStroke = Instance.new("UIStroke")
    BtnStroke.Color     = Color3.fromRGB(255, 180, 60)
    BtnStroke.Thickness = 1.5
    BtnStroke.Parent    = Btn

    return Btn
end

-- Status label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Text                  = "Status: Idle"
StatusLabel.Size                  = UDim2.new(1, -24, 0, 22)
StatusLabel.Position              = UDim2.new(0, 12, 0, 162)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3            = Color3.fromRGB(180, 180, 180)
StatusLabel.TextScaled            = true
StatusLabel.Font                  = Enum.Font.Gotham
StatusLabel.Parent                = MainFrame

-- Create the two main buttons
local AutoFarmBtn = createButton("AutoFarmBtn", "🍭 Auto Farm Candies  [ OFF ]", 50)
local AntiAfkBtn  = createButton("AntiAfkBtn",  "🛡️ Anti-AFK  [ OFF ]",         108)

-- ================================================
-- UTILITY: Update button appearance
-- ================================================
local function setButtonState(btn, active, label)
    if active then
        btn.Text             = label .. "  [ ON ]"
        btn.BackgroundColor3 = Color3.fromRGB(255, 150, 30)
        btn.TextColor3       = Color3.fromRGB(30, 20, 45)
    else
        btn.Text             = label .. "  [ OFF ]"
        btn.BackgroundColor3 = Color3.fromRGB(50, 35, 75)
        btn.TextColor3       = Color3.fromRGB(255, 220, 100)
    end
end

local function updateStatus(msg)
    StatusLabel.Text = "Status: " .. msg
end

-- ================================================
-- CHARACTER REFRESH (handle respawn)
-- ================================================
local function refreshCharacter()
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    HRP       = Character:WaitForChild("HumanoidRootPart")
end

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HRP       = char:WaitForChild("HumanoidRootPart")
end)

-- ================================================
-- AUTO FARM LOGIC
-- ================================================
local function runAutoFarm()
    while autoFarmActive do
        local candiesFolder = workspace:FindFirstChild("Candies")

        if not candiesFolder then
            updateStatus("Candies folder not found!")
            task.wait(3)
            continue
        end

        local candies = candiesFolder:GetChildren()

        if #candies == 0 then
            updateStatus("No candies. Waiting...")
            task.wait(2)
            continue
        end

        for _, candy in ipairs(candies) do
            if not autoFarmActive then break end

            -- Refresh character reference each iteration (safety)
            refreshCharacter()

            if HRP and candy:IsA("BasePart") then
                -- Teleport ke candy
                HRP.CFrame = candy.CFrame + Vector3.new(0, 3, 0)
                updateStatus("Farming: " .. candy.Name)
                task.wait(0.35)  -- jeda aman agar tidak crash

            elseif HRP and candy:FindFirstChildWhichIsA("BasePart") then
                local part = candy:FindFirstChildWhichIsA("BasePart")
                HRP.CFrame = part.CFrame + Vector3.new(0, 3, 0)
                updateStatus("Farming: " .. candy.Name)
                task.wait(0.35)
            end
        end

        -- Jeda setelah satu putaran selesai
        task.wait(1)
    end
    updateStatus("Idle")
end

-- ================================================
-- ANTI-AFK LOGIC
-- ================================================
local function runAntiAfk()
    while antiAfkActive do
        -- Simulasi aktivitas agar server tidak kick
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(18)  -- ping setiap 18 detik
    end
end

-- ================================================
-- BUTTON EVENTS
-- ================================================
AutoFarmBtn.MouseButton1Click:Connect(function()
    autoFarmActive = not autoFarmActive
    setButtonState(AutoFarmBtn, autoFarmActive, "🍭 Auto Farm Candies")

    if autoFarmActive then
        autoFarmThread = task.spawn(runAutoFarm)
        updateStatus("Auto Farm aktif!")
    else
        updateStatus("Auto Farm dimatikan.")
    end
end)

AntiAfkBtn.MouseButton1Click:Connect(function()
    antiAfkActive = not antiAfkActive
    setButtonState(AntiAfkBtn, antiAfkActive, "🛡️ Anti-AFK")

    if antiAfkActive then
        antiAfkThread = task.spawn(runAntiAfk)
        updateStatus("Anti-AFK aktif!")
    else
        updateStatus("Anti-AFK dimatikan.")
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    -- Matikan semua proses
    autoFarmActive = false
    antiAfkActive  = false
    task.wait(0.1)
    ScreenGui:Destroy()
end)

-- ================================================
-- INIT MESSAGE
-- ================================================
updateStatus("Ready! Pilih fitur di atas.")
-- ================================================
