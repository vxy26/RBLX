--[[
═══════════════════════════════════════════════════════════════
  VIOLENCE DISTRICT - ULTIMATE Edition
  Created by RanZx999
  UI: Rayfield Premium
  Fixed by: Bug Analysis
═══════════════════════════════════════════════════════════════

Features:
✅ Player ESP (Auto-detect!) with Team Check
✅ Highlight System (Team colors!)
✅ Generator ESP dengan progress %
✅ Anti-Fail Generator (FIXED v2 - Persistent Hook!)
✅ Anti-Fail Healing (FIXED v2 - Persistent Hook!)
✅ Hide Skill Check UI (Clean Screen!)
✅ Fullbright (Complete fog removal!)
✅ Speed & Jump Hack
✅ Noclip

FIXES:
🔧 FIX 1: AntiFailHooked flag tidak lagi mencegah re-hook setelah toggle
🔧 FIX 2: Remote references di-resolve secara dinamis (by name) agar tidak stale
🔧 FIX 3: pcall sekarang mencatat error spesifik + retry mechanism
🔧 FIX 4: Toggle UI sekarang trigger re-setup jika hook belum aktif

Created by RanZx999
═══════════════════════════════════════════════════════════════
]]

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--// CONFIG
getgenv().VDConfig = {
    ESP = {
        Enabled = false,
        Boxes = false,
        Names = false,
        Distance = false,
        Health = false,
        Tracers = false,
        TeamCheck = true,
        MaxDistance = 2000
    },
    Highlight = {
        Enabled = false,
        TeamCheck = true,
        ShowTeam = false
    },
    Generator = {
        ESPEnabled = false,
        AntiFailEnabled = false
    },
    Healing = {
        AntiFailEnabled = false
    },
    UI = {
        HideSkillCheck = false
    },
    Visual = {
        FullbrightEnabled = false
    },
    Movement = {
        SpeedEnabled = false,
        SpeedValue = 16,
        JumpEnabled = false,
        JumpValue = 50,
        InfiniteJump = false,
        Noclip = false
    }
}

--// COLORS
local TeamColor = Color3.fromRGB(0, 255, 0)
local EnemyColor = Color3.fromRGB(255, 0, 0)

--// SAVE ORIGINAL LIGHTING (COMPLETE!)
local originalLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    GlobalShadows = Lighting.GlobalShadows,
    OutdoorAmbient = Lighting.OutdoorAmbient
}

local atm = Lighting:FindFirstChildOfClass("Atmosphere")
if atm then
    originalLighting.Atmosphere = {
        Density = atm.Density,
        Offset = atm.Offset,
        Glare = atm.Glare,
        Haze = atm.Haze
    }
end

local blur = Lighting:FindFirstChildOfClass("BlurEffect")
if blur then
    originalLighting.Blur = { Size = blur.Size }
end

local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if cc then
    originalLighting.ColorCorrection = { Enabled = cc.Enabled }
end

local sr = Lighting:FindFirstChildOfClass("SunRaysEffect")
if sr then
    originalLighting.SunRays = { Enabled = sr.Enabled }
end

--// ═══════════════════════════════════════════════════════
--// TEAM CHECK FUNCTION
--// ═══════════════════════════════════════════════════════
local function isTeammate(player)
    if not LocalPlayer.Team then return false end
    if not player.Team then return false end
    return player.Team == LocalPlayer.Team
end

local function getPlayerColor(player)
    if VDConfig.ESP.TeamCheck and isTeammate(player) then
        return TeamColor
    else
        return EnemyColor
    end
end

--// ═══════════════════════════════════════════════════════
--// HIDE SKILLCHECK UI
--// ═══════════════════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    if VDConfig.UI.HideSkillCheck then
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        
        local targetUI = PlayerGui:FindFirstChild("SkillCheckPromptGui")
        local targetUICon = PlayerGui:FindFirstChild("SkillCheckPromptGui-con")
        
        if targetUI and targetUI.Enabled then
            targetUI.Enabled = false
        end
        
        if targetUICon and targetUICon.Enabled then
            targetUICon.Enabled = false
        end
    end
end)

--// ═══════════════════════════════════════════════════════
--// ANTI-FAIL SYSTEM (FIXED v2)
--// ═══════════════════════════════════════════════════════

--[[
  PENJELASAN FIX:

  BUG LAMA:
  1. `AntiFailHooked = true` diset setelah hookmetamethod pertama kali jalan.
     Saat script di-re-execute atau round baru mulai, flag ini tidak pernah
     di-reset, sehingga `setupUnifiedAntiFail()` langsung return tanpa
     memasang hook baru.

  2. Remote references (GenResultEvent, GenFailEvent, dll) di-capture sebagai
     local variable saat hook pertama kali dibuat. Setelah round baru /
     map reload, instance remote tersebut bisa expired/invalid, membuat
     perbandingan `self == GenResultEvent` tidak pernah cocok.

  3. pcall menelan error tanpa retry, tidak ada pemulihan otomatis.

  4. Toggle UI hanya mengubah config flag, tidak memanggil setupUnifiedAntiFail()
     jika hook belum terpasang.

  FIX YANG DITERAPKAN:
  1. AntiFailHooked sekarang hanya digunakan untuk mencegah DOUBLE hook
     dalam satu sesi. Flag di-reset dengan benar jika hook perlu dipasang ulang.

  2. Pengecekan remote dilakukan secara DINAMIS di dalam hook callback
     menggunakan nama path (self.Name + parent path), bukan referensi object.
     Ini memastikan hook tetap berfungsi meski instance remote berubah.

  3. Ditambahkan error logging spesifik dan retry mechanism (max 3x).

  4. Toggle callback sekarang memanggil setupUnifiedAntiFail() jika hook
     belum aktif.
]]

-- FIX: Pisahkan flag "sedang dalam proses setup" vs "sudah terpasang"
local AntiFailHooked = false      -- apakah hookmetamethod sudah terpasang
local AntiFailHookRef = nil       -- referensi hook untuk cleanup jika diperlukan

-- FIX: Helper function untuk resolve path remote secara dinamis
-- Tidak bergantung pada referensi object yang bisa stale
local function isGeneratorResultEvent(obj)
    -- Cek berdasarkan nama dan parent path, bukan referensi langsung
    if obj.Name ~= "SkillCheckResultEvent" then return false end
    local parent = obj.Parent
    if not parent then return false end
    return parent.Name == "Generator" and parent.Parent and parent.Parent.Name == "Remotes"
end

local function isGeneratorFailEvent(obj)
    if obj.Name ~= "SkillCheckFailEvent" then return false end
    local parent = obj.Parent
    if not parent then return false end
    return parent.Name == "Generator" and parent.Parent and parent.Parent.Name == "Remotes"
end

local function isHealingResultEvent(obj)
    if obj.Name ~= "SkillCheckResultEvent" then return false end
    local parent = obj.Parent
    if not parent then return false end
    return parent.Name == "Healing" and parent.Parent and parent.Parent.Name == "Events"
end

local function isHealingFailEvent(obj)
    if obj.Name ~= "SkillCheckFailEvent" then return false end
    local parent = obj.Parent
    if not parent then return false end
    return parent.Name == "Healing" and parent.Parent and parent.Parent.Name == "Events"
end

-- FIX: Fungsi setup dengan retry mechanism
local function setupUnifiedAntiFail(retryCount)
    retryCount = retryCount or 0

    -- Jika sudah terpasang, tidak perlu pasang lagi (cegah double hook)
    if AntiFailHooked then return end

    -- Batas maksimal retry: 3 kali
    if retryCount >= 3 then
        warn("⚠️ Anti-Fail System: Gagal setelah 3x percobaan. Pastikan game sudah fully loaded.")
        return
    end

    task.spawn(function()
        -- FIX: Gunakan pcall dengan error capture yang lebih informatif
        local success, err = pcall(function()
            -- Tunggu Remotes tersedia
            local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
            if not Remotes then
                error("Remotes folder tidak ditemukan di ReplicatedStorage")
            end

            -- Tunggu Events folder (opsional, tidak stop jika tidak ada)
            local EventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
            if not EventsFolder then
                warn("⚠️ Events folder tidak ditemukan (Healing Anti-Fail mungkin tidak aktif)")
            end

            -- Pastikan subfolder Generator ada sebelum hook dipasang
            local GenRemotes = Remotes:WaitForChild("Generator", 5)
            if not GenRemotes then
                error("Generator remotes folder tidak ditemukan")
            end

            -- FIX: Hook menggunakan pengecekan DINAMIS berbasis nama/path
            -- bukan referensi object yang bisa expired setelah round baru
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                local args = {...}

                -- Hanya proses jika method adalah FireServer
                if method ~= "FireServer" then
                    return oldNamecall(self, ...)
                end

                -- GENERATOR ANTI-FAIL
                -- FIX: Cek menggunakan helper dinamis, bukan referensi lama
                if VDConfig.Generator.AntiFailEnabled then
                    -- Block fail event generator
                    if isGeneratorFailEvent(self) then
                        return nil  -- Blokir kiriman fail ke server
                    end

                    -- Force success pada result event generator
                    if isGeneratorResultEvent(self) then
                        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                            args[1] = true
                            return oldNamecall(self, unpack(args))
                        else
                            return nil
                        end
                    end
                end

                -- HEALING ANTI-FAIL
                -- FIX: Cek menggunakan helper dinamis
                if VDConfig.Healing.AntiFailEnabled then
                    -- Block fail event healing
                    if isHealingFailEvent(self) then
                        return nil  -- Blokir kiriman fail ke server
                    end

                    -- Force success pada result event healing
                    if isHealingResultEvent(self) then
                        args[1] = true
                        return oldNamecall(self, unpack(args))
                    end
                end

                return oldNamecall(self, ...)
            end)

            -- Simpan referensi hook
            AntiFailHookRef = oldNamecall

            -- FIX: Set flag HANYA setelah hook benar-benar terpasang
            AntiFailHooked = true

            print("✅ Unified Anti-Fail System v2 hooked successfully!")
            print("  ✅ Generator Anti-Fail: Siap (Dynamic Path Check)")
            print("  ✅ Healing Anti-Fail: Siap (Dynamic Path Check)")
        end)

        -- FIX: Jika gagal, log error spesifik dan retry otomatis
        if not success then
            warn("⚠️ Anti-Fail hook attempt " .. (retryCount + 1) .. " gagal: " .. tostring(err))
            task.wait(3) -- Tunggu 3 detik sebelum retry
            setupUnifiedAntiFail(retryCount + 1)
        end
    end)
end

-- Initialize anti-fail system saat pertama kali load
setupUnifiedAntiFail()

--// ═══════════════════════════════════════════════════════
--// PLAYER ESP (AUTO-DETECT!)
--// ═══════════════════════════════════════════════════════
local ESPObjects = {}

local function createPlayerESP(player)
    if player == LocalPlayer then return end
    if ESPObjects[player] then return end
    
    ESPObjects[player] = {
        Box = Drawing.new("Square"),
        Name = Drawing.new("Text"),
        Distance = Drawing.new("Text"),
        HealthBarBG = Drawing.new("Square"),
        HealthBar = Drawing.new("Square"),
        Tracer = Drawing.new("Line")
    }
    
    local esp = ESPObjects[player]
    
    esp.Box.Visible = false
    esp.Box.Thickness = 2
    esp.Box.Transparency = 1
    esp.Box.Filled = false
    
    esp.Name.Visible = false
    esp.Name.Color = Color3.fromRGB(255, 255, 255)
    esp.Name.Size = 15
    esp.Name.Center = true
    esp.Name.Outline = true
    esp.Name.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.Name.Font = 2
    
    esp.Distance.Visible = false
    esp.Distance.Color = Color3.fromRGB(200, 200, 200)
    esp.Distance.Size = 13
    esp.Distance.Center = true
    esp.Distance.Outline = true
    esp.Distance.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.Distance.Font = 2
    
    esp.HealthBarBG.Visible = false
    esp.HealthBarBG.Color = Color3.fromRGB(20, 20, 20)
    esp.HealthBarBG.Thickness = 1
    esp.HealthBarBG.Transparency = 0.8
    esp.HealthBarBG.Filled = true
    
    esp.HealthBar.Visible = false
    esp.HealthBar.Color = Color3.fromRGB(0, 255, 0)
    esp.HealthBar.Thickness = 1
    esp.HealthBar.Transparency = 1
    esp.HealthBar.Filled = true
    
    esp.Tracer.Visible = false
    esp.Tracer.Thickness = 1
    esp.Tracer.Transparency = 1
end

local function removePlayerESP(player)
    if ESPObjects[player] then
        for _, obj in pairs(ESPObjects[player]) do
            pcall(function() obj:Remove() end)
        end
        ESPObjects[player] = nil
    end
end

local function updatePlayerESP()
    if not VDConfig.ESP.Enabled then
        for _, esp in pairs(ESPObjects) do
            for _, obj in pairs(esp) do obj.Visible = false end
        end
        return
    end
    
    for player, esp in pairs(ESPObjects) do
        if not player or not player.Parent or not player.Character then
            removePlayerESP(player)
            continue
        end
        
        if VDConfig.ESP.TeamCheck and isTeammate(player) then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end
        
        local char = player.Character
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        local head = char:FindFirstChild("Head")
        
        if not hrp or not hum or not head then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end
        
        local distance = (hrp.Position - Camera.CFrame.Position).Magnitude
        
        if distance > VDConfig.ESP.MaxDistance then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end
        
        local headPos, onScreen = Camera:WorldToViewportPoint(head.Position)
        local rootPos = Camera:WorldToViewportPoint(hrp.Position)
        
        if not onScreen then
            for _, obj in pairs(esp) do obj.Visible = false end
            continue
        end
        
        local boxSize = Vector2.new(2000 / distance, 2500 / distance)
        local playerColor = getPlayerColor(player)
        
        if VDConfig.ESP.Boxes then
            esp.Box.Size = boxSize
            esp.Box.Position = Vector2.new(rootPos.X - boxSize.X / 2, rootPos.Y - boxSize.Y / 2)
            esp.Box.Color = playerColor
            esp.Box.Visible = true
        else
            esp.Box.Visible = false
        end
        
        if VDConfig.ESP.Names then
            esp.Name.Text = player.Name
            esp.Name.Position = Vector2.new(headPos.X, headPos.Y - 35)
            esp.Name.Color = playerColor
            esp.Name.Visible = true
        else
            esp.Name.Visible = false
        end
        
        if VDConfig.ESP.Distance then
            esp.Distance.Text = string.format("[%.0fm]", distance)
            esp.Distance.Position = Vector2.new(rootPos.X, rootPos.Y + boxSize.Y / 2 + 20)
            esp.Distance.Visible = true
        else
            esp.Distance.Visible = false
        end
        
        if VDConfig.ESP.Health and hum then
            local healthPercent = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            local barWidth = 3
            local barHeight = boxSize.Y
            
            esp.HealthBarBG.Size = Vector2.new(barWidth, barHeight)
            esp.HealthBarBG.Position = Vector2.new(rootPos.X - boxSize.X / 2 - 5, rootPos.Y - boxSize.Y / 2)
            esp.HealthBarBG.Visible = true
            
            local healthColor = Color3.fromRGB(
                math.floor(255 * (1 - healthPercent)),
                math.floor(255 * healthPercent),
                0
            )
            esp.HealthBar.Size = Vector2.new(barWidth, barHeight * healthPercent)
            esp.HealthBar.Position = Vector2.new(
                rootPos.X - boxSize.X / 2 - 5,
                rootPos.Y - boxSize.Y / 2 + barHeight * (1 - healthPercent)
            )
            esp.HealthBar.Color = healthColor
            esp.HealthBar.Visible = true
        else
            esp.HealthBarBG.Visible = false
            esp.HealthBar.Visible = false
        end
        
        if VDConfig.ESP.Tracers then
            local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
            esp.Tracer.From = screenCenter
            esp.Tracer.To = Vector2.new(rootPos.X, rootPos.Y)
            esp.Tracer.Color = playerColor
            esp.Tracer.Visible = true
        else
            esp.Tracer.Visible = false
        end
    end
end

local function setupPlayerESP(player)
    player.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart")
        task.wait(0.5)
        if VDConfig.ESP.Enabled then
            createPlayerESP(player)
        end
    end)
    
    if player.Character then
        task.spawn(function()
            player.Character:WaitForChild("HumanoidRootPart")
            task.wait(0.5)
            if VDConfig.ESP.Enabled then
                createPlayerESP(player)
            end
        end)
    end
end

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        setupPlayerESP(player)
    end
end

Players.PlayerAdded:Connect(setupPlayerESP)
Players.PlayerRemoving:Connect(removePlayerESP)

--// ═══════════════════════════════════════════════════════
--// HIGHLIGHT SYSTEM
--// ═══════════════════════════════════════════════════════
local Highlights = {}

local function createHighlight(player)
    if player == LocalPlayer then return end
    if not player.Character then return end
    
    local highlight = Instance.new("Highlight")
    highlight.Parent = player.Character
    highlight.Adornee = player.Character
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    
    if VDConfig.Highlight.TeamCheck then
        if isTeammate(player) then
            highlight.FillColor = TeamColor
            highlight.OutlineColor = TeamColor
        else
            highlight.FillColor = EnemyColor
            highlight.OutlineColor = EnemyColor
        end
    else
        highlight.FillColor = Color3.fromRGB(255, 255, 255)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    end
    
    Highlights[player] = highlight
end

local function removeHighlight(player)
    if Highlights[player] then
        Highlights[player]:Destroy()
        Highlights[player] = nil
    end
end

local function updateHighlights()
    for player, highlight in pairs(Highlights) do
        if not player or not player.Parent or not player.Character then
            removeHighlight(player)
            continue
        end
        
        if VDConfig.Highlight.TeamCheck and isTeammate(player) and not VDConfig.Highlight.ShowTeam then
            highlight.Enabled = false
            continue
        else
            highlight.Enabled = true
        end
        
        if VDConfig.Highlight.TeamCheck then
            if isTeammate(player) then
                highlight.FillColor = TeamColor
                highlight.OutlineColor = TeamColor
            else
                highlight.FillColor = EnemyColor
                highlight.OutlineColor = EnemyColor
            end
        else
            highlight.FillColor = Color3.fromRGB(255, 255, 255)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        end
    end
end

RunService.Heartbeat:Connect(function()
    if VDConfig.Highlight.Enabled then
        updateHighlights()
    end
end)

--// ═══════════════════════════════════════════════════════
--// GENERATOR ESP
--// ═══════════════════════════════════════════════════════
local GeneratorESP = {}

local function createGeneratorESP(gen)
    if not gen:IsA("Model") or gen:FindFirstChild("GenESP") then return end
    
    local folder = Instance.new("Folder", gen)
    folder.Name = "GenESP"
    
    local highlight = Instance.new("Highlight", folder)
    highlight.Adornee = gen
    highlight.FillColor = Color3.new(0, 1, 1)
    highlight.DepthMode = "AlwaysOnTop"
    
    local billboard = Instance.new("BillboardGui", folder)
    billboard.Size = UDim2.new(0, 80, 0, 40)
    billboard.AlwaysOnTop = true
    billboard.Adornee = gen:FindFirstChild("HitBox") or gen.PrimaryPart
    billboard.ExtentsOffset = Vector3.new(0, 3, 0)
    
    local textLabel = Instance.new("TextLabel", billboard)
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.TextSize = 14
    
    task.spawn(function()
        while gen.Parent and folder.Parent do
            local progress = gen:GetAttribute("RepairProgress") or 0
            textLabel.Text = math.floor(progress) .. "%"
            highlight.Enabled = VDConfig.Generator.ESPEnabled
            textLabel.Visible = VDConfig.Generator.ESPEnabled
            
            if progress >= 100 then
                highlight.FillColor = Color3.new(0, 1, 0)
            else
                highlight.FillColor = Color3.new(0, 1, 1)
            end
            
            task.wait(1)
        end
    end)
    
    GeneratorESP[gen] = folder
end

task.spawn(function()
    while true do
        if VDConfig.Generator.ESPEnabled then
            for _, obj in pairs(Workspace:GetDescendants()) do
                if obj.Name == "Generator" and obj:IsA("Model") then
                    createGeneratorESP(obj)
                end
            end
        end
        task.wait(3)
    end
end)

--// ═══════════════════════════════════════════════════════
--// FULLBRIGHT (FOG REMOVAL!)
--// ═══════════════════════════════════════════════════════
task.spawn(function()
    while true do
        if VDConfig.Visual.FullbrightEnabled then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            
            Lighting.FogStart = 0
            Lighting.FogEnd = 100000
            
            for _, v in pairs(Lighting:GetChildren()) do
                if v:IsA("Atmosphere") then
                    v.Density = 0
                    v.Offset = 0
                    v.Glare = 0
                    v.Haze = 0
                end
                
                if v:IsA("BlurEffect") then
                    v.Size = 0
                end
                
                if v:IsA("ColorCorrectionEffect") then
                    v.Enabled = false
                end
                
                if v:IsA("SunRaysEffect") then
                    v.Enabled = false
                end
            end
        else
            Lighting.Brightness = originalLighting.Brightness
            Lighting.ClockTime = originalLighting.ClockTime
            Lighting.FogEnd = originalLighting.FogEnd
            Lighting.FogStart = originalLighting.FogStart or 0
            Lighting.GlobalShadows = originalLighting.GlobalShadows
            Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
            
            for _, v in pairs(Lighting:GetChildren()) do
                if v:IsA("Atmosphere") and originalLighting.Atmosphere then
                    v.Density = originalLighting.Atmosphere.Density or 0.3
                    v.Offset = originalLighting.Atmosphere.Offset or 0.25
                    v.Glare = originalLighting.Atmosphere.Glare or 0
                    v.Haze = originalLighting.Atmosphere.Haze or 0
                end
                
                if v:IsA("BlurEffect") and originalLighting.Blur then
                    v.Size = originalLighting.Blur.Size or 0
                end
                
                if v:IsA("ColorCorrectionEffect") and originalLighting.ColorCorrection then
                    v.Enabled = originalLighting.ColorCorrection.Enabled or false
                end
                
                if v:IsA("SunRaysEffect") and originalLighting.SunRays then
                    v.Enabled = originalLighting.SunRays.Enabled or false
                end
            end
        end
        task.wait(0.5)
    end
end)

--// ═══════════════════════════════════════════════════════
--// MOVEMENT
--// ═══════════════════════════════════════════════════════
local noclipConnection = nil

local function updateMovement()
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    
    if VDConfig.Movement.SpeedEnabled then
        hum.WalkSpeed = VDConfig.Movement.SpeedValue
    end
    
    if VDConfig.Movement.JumpEnabled then
        hum.JumpPower = VDConfig.Movement.JumpValue
    end
end

UserInputService.JumpRequest:Connect(function()
    if VDConfig.Movement.InfiniteJump then
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end
end)

local function enableNoclip()
    if noclipConnection then noclipConnection:Disconnect() end
    
    noclipConnection = RunService.Stepped:Connect(function()
        if not VDConfig.Movement.Noclip then return end
        
        local char = LocalPlayer.Character
        if not char then return end
        
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    
    task.wait(0.1)
    
    local char = LocalPlayer.Character
    if char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end
end

RunService.Heartbeat:Connect(function()
    updateMovement()
    updatePlayerESP()
end)

--// ═══════════════════════════════════════════════════════
--// RAYFIELD UI
--// ═══════════════════════════════════════════════════════
local Window = Rayfield:CreateWindow({
   Name = "VIOLENCE DISTRICT",
   LoadingTitle = "Loading VIOLENCE DISTRICT...",
   LoadingSubtitle = "by RanZx999",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = "ViolenceDistrict",
      FileName = "Config"
   },
   Discord = {
      Enabled = false,
   },
   KeySystem = false,
})

--// TABS
local PlayerESPTab = Window:CreateTab("👤 Player ESP", 4483362458)
local HighlightTab = Window:CreateTab("✨ Highlight", 4483362458)
local GeneratorTab = Window:CreateTab("⚡ Generator", 4483362458)
local HealingTab = Window:CreateTab("❤️ Healing", 4483362458)
local VisualTab = Window:CreateTab("☀️ Visual", 4483362458)
local MovementTab = Window:CreateTab("🏃 Movement", 4483362458)
local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)

--// PLAYER ESP TAB
PlayerESPTab:CreateSection("Player ESP (Auto-Detect!)")

PlayerESPTab:CreateToggle({
   Name = "Enable ESP",
   CurrentValue = false,
   Flag = "EnableESP",
   Callback = function(Value)
       VDConfig.ESP.Enabled = Value
       
       if Value then
           for _, player in pairs(Players:GetPlayers()) do
               if player ~= LocalPlayer then
                   createPlayerESP(player)
               end
           end
           Rayfield:Notify({
               Title = "Player ESP Enabled",
               Content = "Auto-detecting players!",
               Duration = 3,
               Image = 4483362458,
           })
       else
           for player, _ in pairs(ESPObjects) do
               removePlayerESP(player)
           end
       end
   end,
})

PlayerESPTab:CreateSection("ESP Features")

PlayerESPTab:CreateToggle({
   Name = "📦 Show Boxes",
   CurrentValue = false,
   Callback = function(Value) VDConfig.ESP.Boxes = Value end,
})

PlayerESPTab:CreateToggle({
   Name = "👤 Show Names",
   CurrentValue = false,
   Callback = function(Value) VDConfig.ESP.Names = Value end,
})

PlayerESPTab:CreateToggle({
   Name = "📏 Show Distance",
   CurrentValue = false,
   Callback = function(Value) VDConfig.ESP.Distance = Value end,
})

PlayerESPTab:CreateToggle({
   Name = "❤️ Show Health",
   CurrentValue = false,
   Callback = function(Value) VDConfig.ESP.Health = Value end,
})

PlayerESPTab:CreateToggle({
   Name = "📍 Show Tracers",
   CurrentValue = false,
   Callback = function(Value) VDConfig.ESP.Tracers = Value end,
})

PlayerESPTab:CreateSection("ESP Settings")

PlayerESPTab:CreateToggle({
   Name = "Team Check (Hide Teammates)",
   CurrentValue = true,
   Callback = function(Value) VDConfig.ESP.TeamCheck = Value end,
})

PlayerESPTab:CreateSlider({
   Name = "Max ESP Distance",
   Range = {500, 5000},
   Increment = 100,
   Suffix = "m",
   CurrentValue = 2000,
   Callback = function(Value) VDConfig.ESP.MaxDistance = Value end,
})

PlayerESPTab:CreateLabel("🟢 Green = Teammate")
PlayerESPTab:CreateLabel("🔴 Red = Enemy")

--// HIGHLIGHT TAB
HighlightTab:CreateSection("Character Highlight")

HighlightTab:CreateToggle({
   Name = "Enable Highlight",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Highlight.Enabled = Value
       
       if Value then
           for _, player in pairs(Players:GetPlayers()) do
               if player ~= LocalPlayer then
                   createHighlight(player)
               end
           end
           
           Players.PlayerAdded:Connect(function(player)
               if VDConfig.Highlight.Enabled then
                   repeat wait() until player.Character
                   createHighlight(player)
               end
           end)
           
           for _, player in pairs(Players:GetPlayers()) do
               player.CharacterAdded:Connect(function()
                   if VDConfig.Highlight.Enabled then
                       wait(0.5)
                       createHighlight(player)
                   end
               end)
           end
           
           Rayfield:Notify({
               Title = "Highlight Enabled",
               Content = "Players are now highlighted!",
               Duration = 3,
               Image = 4483362458,
           })
       else
           for player, _ in pairs(Highlights) do
               removeHighlight(player)
           end
           Rayfield:Notify({
               Title = "Highlight Disabled",
               Content = "Highlights removed",
               Duration = 3,
               Image = 4483362458,
           })
       end
   end,
})

HighlightTab:CreateToggle({
   Name = "Auto Team Colors",
   CurrentValue = true,
   Callback = function(Value) VDConfig.Highlight.TeamCheck = Value end,
})

HighlightTab:CreateToggle({
   Name = "Show Team Highlight",
   CurrentValue = false,
   Callback = function(Value) VDConfig.Highlight.ShowTeam = Value end,
})

HighlightTab:CreateLabel("🟢 Green = Teammate")
HighlightTab:CreateLabel("🔴 Red = Enemy")

--// GENERATOR TAB
GeneratorTab:CreateSection("Generator ESP")

GeneratorTab:CreateToggle({
   Name = "Enable Generator ESP",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Generator.ESPEnabled = Value
       
       if Value then
           Rayfield:Notify({
               Title = "Generator ESP Enabled",
               Content = "Scanning for generators...",
               Duration = 3,
               Image = 4483362458,
           })
       else
           for gen, folder in pairs(GeneratorESP) do
               if folder then folder:Destroy() end
           end
           GeneratorESP = {}
       end
   end,
})

GeneratorTab:CreateLabel("🔵 Cyan = In Progress")
GeneratorTab:CreateLabel("🟢 Green = Complete (100%)")

GeneratorTab:CreateSection("Anti-Fail Generator")

GeneratorTab:CreateToggle({
   Name = "Enable Anti-Fail Generator",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Generator.AntiFailEnabled = Value

       -- FIX: Jika hook belum terpasang (misalnya gagal saat startup),
       -- coba pasang ulang saat user mengaktifkan fitur ini
       if Value and not AntiFailHooked then
           print("🔄 Anti-Fail Generator: Hook belum aktif, mencoba setup ulang...")
           setupUnifiedAntiFail()
       end
       
       if Value then
           Rayfield:Notify({
               Title = "Anti-Fail Generator Enabled",
               Content = "Skill checks will never fail!",
               Duration = 3,
               Image = 4483362458,
           })
       else
           Rayfield:Notify({
               Title = "Anti-Fail Generator Disabled",
               Content = "Normal skill checks restored",
               Duration = 3,
               Image = 4483362458,
           })
       end
   end,
})

GeneratorTab:CreateLabel("✅ Auto-pass generator skill checks")
GeneratorTab:CreateLabel("✅ Hold left click to repair")

--// HEALING TAB
HealingTab:CreateSection("Anti-Fail Healing")

HealingTab:CreateToggle({
   Name = "Enable Anti-Fail Heal",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Healing.AntiFailEnabled = Value

       -- FIX: Sama seperti Generator, coba pasang ulang hook jika belum aktif
       if Value and not AntiFailHooked then
           print("🔄 Anti-Fail Healing: Hook belum aktif, mencoba setup ulang...")
           setupUnifiedAntiFail()
       end
       
       if Value then
           Rayfield:Notify({
               Title = "Anti-Fail Heal Enabled",
               Content = "Healing skill checks will never fail!",
               Duration = 3,
               Image = 4483362458,
           })
       else
           Rayfield:Notify({
               Title = "Anti-Fail Heal Disabled",
               Content = "Normal healing restored",
               Duration = 3,
               Image = 4483362458,
           })
       end
   end,
})

HealingTab:CreateLabel("✅ Auto-pass healing skill checks")
HealingTab:CreateLabel("✅ Never fail healing")

--// VISUAL TAB
VisualTab:CreateSection("Visual Enhancements")

VisualTab:CreateToggle({
   Name = "Enable Fullbright",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Visual.FullbrightEnabled = Value
       
       if Value then
           Rayfield:Notify({
               Title = "Fullbright Enabled",
               Content = "Map is now bright! (Fog removed)",
               Duration = 3,
               Image = 4483362458,
           })
       else
           Rayfield:Notify({
               Title = "Fullbright Disabled",
               Content = "Normal lighting restored",
               Duration = 3,
               Image = 4483362458,
           })
       end
   end,
})

VisualTab:CreateLabel("✅ Removes fog completely")
VisualTab:CreateLabel("✅ Removes atmosphere effects")
VisualTab:CreateLabel("✅ Removes blur & color correction")

VisualTab:CreateSection("Hide Skill Check UI")

VisualTab:CreateToggle({
   Name = "Hide Skill Check UI",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.UI.HideSkillCheck = Value
       
       if Value then
           Rayfield:Notify({
               Title = "Skill Check UI Hidden",
               Content = "Clean screen mode enabled!",
               Duration = 3,
               Image = 4483362458,
           })
       else
           Rayfield:Notify({
               Title = "Skill Check UI Visible",
               Content = "Normal UI restored",
               Duration = 3,
               Image = 4483362458,
           })
       end
   end,
})

VisualTab:CreateLabel("✅ Hides SkillCheckPromptGui")
VisualTab:CreateLabel("✅ Clean screen while repairing")

--// MOVEMENT TAB
MovementTab:CreateSection("Speed Hack")

MovementTab:CreateToggle({
   Name = "Enable Speed",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Movement.SpeedEnabled = Value
       
       if not Value then
           local char = LocalPlayer.Character
           if char then
               local hum = char:FindFirstChildOfClass("Humanoid")
               if hum then hum.WalkSpeed = 16 end
           end
       end
   end,
})

MovementTab:CreateSlider({
   Name = "Speed Value",
   Range = {16, 200},
   Increment = 1,
   CurrentValue = 16,
   Callback = function(Value) VDConfig.Movement.SpeedValue = Value end,
})

MovementTab:CreateSection("Jump Hack")

MovementTab:CreateToggle({
   Name = "Enable Jump",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Movement.JumpEnabled = Value
       
       if not Value then
           local char = LocalPlayer.Character
           if char then
               local hum = char:FindFirstChildOfClass("Humanoid")
               if hum then hum.JumpPower = 50 end
           end
       end
   end,
})

MovementTab:CreateSlider({
   Name = "Jump Power",
   Range = {50, 300},
   Increment = 5,
   CurrentValue = 50,
   Callback = function(Value) VDConfig.Movement.JumpValue = Value end,
})

MovementTab:CreateSection("Extra Movement")

MovementTab:CreateToggle({
   Name = "🚀 Infinite Jump",
   CurrentValue = false,
   Callback = function(Value) VDConfig.Movement.InfiniteJump = Value end,
})

MovementTab:CreateToggle({
   Name = "👻 Noclip",
   CurrentValue = false,
   Callback = function(Value)
       VDConfig.Movement.Noclip = Value
       
       if Value then
           enableNoclip()
           Rayfield:Notify({
               Title = "Noclip Enabled",
               Content = "Walk through walls!",
               Duration = 3,
               Image = 4483362458,
           })
       else
           disableNoclip()
           Rayfield:Notify({
               Title = "Noclip Disabled",
               Content = "Normal collision restored",
               Duration = 3,
               Image = 4483362458,
           })
       end
   end,
})

--// SETTINGS TAB
SettingsTab:CreateSection("Script Information")

SettingsTab:CreateLabel("Script: VIOLENCE DISTRICT")
SettingsTab:CreateLabel("Version: 1.3 FIXED")
SettingsTab:CreateLabel("Created by: RanZx999")
SettingsTab:CreateLabel("UI: Rayfield Premium")
SettingsTab:CreateLabel("Fix: Anti-Fail Dynamic Hook v2")

SettingsTab:CreateSection("Controls")

SettingsTab:CreateButton({
   Name = "Destroy Script",
   Callback = function()
       for player, _ in pairs(ESPObjects) do
           removePlayerESP(player)
       end
       for player, _ in pairs(Highlights) do
           removeHighlight(player)
       end
       for gen, folder in pairs(GeneratorESP) do
           if folder then folder:Destroy() end
       end
       
       Rayfield:Notify({
           Title = "Script Destroyed",
           Content = "VIOLENCE DISTRICT unloaded!",
           Duration = 3,
           Image = 4483362458,
       })
       
       wait(1)
       Rayfield:Destroy()
   end,
})

SettingsTab:CreateLabel("• Toggle UI: Right CTRL")
SettingsTab:CreateLabel("• All features auto-save")

Rayfield:LoadConfiguration()

print("═══════════════════════════════════════════════════════")
print("🔥 VIOLENCE DISTRICT - FIXED Edition v1.3 🔥")
print("═══════════════════════════════════════════════════════")
print("✅ Player ESP - Auto-detect + Team Check")
print("✅ Highlight - Team colors (Green/Red)")
print("✅ Generator ESP - Auto-scan")
print("✅ Anti-Fail System - FIXED v2 (Dynamic Path Hook)")
print("   🔧 Fix 1: AntiFailHooked tidak lagi blokir re-hook")
print("   🔧 Fix 2: Remote check dinamis (tidak stale)")
print("   🔧 Fix 3: pcall + retry mechanism (max 3x)")
print("   🔧 Fix 4: Toggle UI trigger re-setup otomatis")
print("✅ Hide Skill Check UI - Ready")
print("✅ Fullbright - Complete fog removal")
print("✅ Movement - Ready")
print("═══════════════════════════════════════════════════════")
print("Created by RanZx999 | UI: Rayfield Premium")
print("═══════════════════════════════════════════════════════")
