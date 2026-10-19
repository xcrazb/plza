local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- KONFIGURASI WEBHOOK
-- ============================================================
local WEBHOOK_URL = "https://discord.com/api/webhooks/1561760133770645504/cfe4Ry7Zys2AmyB6bguziupMzjj3dwNwCYzBz0pcXKuklYDUGunx2KxILJXVS19Eb2B_" 

-- ============================================================
-- 1. Dependencies
-- ============================================================
local Inv = require(LocalPlayer.PlayerScripts.TS.ui.features.toolbar["inventory.state"])
local MAKE_LISTING = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].remo.src.container["tradePlaza.makeListing"]
local getPlayerDataById = require(ReplicatedStorage.TS.state["player-data"]).getPlayerDataById
local DEFAULT_USER_ID = require(ReplicatedStorage.TS.constants).DEFAULT_USER_ID

local function resolve(x) return typeof(x) == "function" and x() or x end

-- 2. State
local PriceByType, TypeList, isRunning = {}, {}, false
local GUI, scrollContent, startBtn, stateLbl, tokenLbl, afkLbl
local liveLabels, rowFrames = {}, {}

-- Helper: Ambil Token Player
local function getTokens()
    local pd = getPlayerDataById(tostring(DEFAULT_USER_ID))
    if not pd then return 0 end
    return pd.tokens or pd.currency and pd.currency.tokens or pd.tokenBalance or 0
end

-- Helper: Kirim Webhook via request()
local function sendWebhook(petName)
    if WEBHOOK_URL == "" or WEBHOOK_URL:find("XXXXXX") then return end
    
    task.spawn(function()
        local currentTokens = getTokens()
        local data = {
            ["content"] = "💰 **PET TERJUAL!**",
            ["embeds"] = {{
                ["color"] = 65280,
                ["fields"] = {
                    {["name"] = "🐾 Jenis Pet", ["value"] = tostring(petName), ["inline"] = true},
                    {["name"] = "💎 Total Token", ["value"] = tostring(currentTokens), ["inline"] = true}
                },
                ["footer"] = {["text"] = "Auto Re-Listing System"}
            }}
        }
        
        local jsonData = HttpService:JSONEncode(data)
        
        local success, response = pcall(function()
            return request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = jsonData
            })
        end)
        
        if not success then
            warn("[WEBHOOK] ❌ Gagal mengirim ke Discord: " .. tostring(response))
        end
    end)
end

-- 3. Core Logic
local function runRelistLoop()
    local typeQueues = {}
    for _, entry in ipairs(TypeList) do
        local price = PriceByType[entry.petType]
        if price then
            typeQueues[entry.petType] = {}
            for _, uid in ipairs(entry.uids) do
                table.insert(typeQueues[entry.petType], { uid = uid, petType = entry.petType, price = price })
            end
        end
    end

    if not next(typeQueues) then
        if stateLbl then stateLbl.Text = "❌ Isi harga minimal 1 pet." end
        isRunning = false
        return
    end

    local activeListingUIDs = {}
    for pt, queue in pairs(typeQueues) do
        if not isRunning then break end
        local item = table.remove(queue, 1)
        if item then
            MAKE_LISTING:FireServer("pet", item.uid, item.price)
            activeListingUIDs[item.uid] = { petType = item.petType, price = item.price }
            task.wait(1)
        end
    end

    if not isRunning then return end
    if stateLbl then stateLbl.Text = "🟢 Memantau Inventory..." end

    while isRunning do
        task.wait(2)
        if not isRunning then break end

        local petsData = resolve(Inv.petsData)
        if petsData then
            local currentInventoryUIDs, hasSold = {}, false
            for uid in pairs(petsData) do currentInventoryUIDs[uid] = true end

            for uid, info in pairs(activeListingUIDs) do
                if not currentInventoryUIDs[uid] then
                    activeListingUIDs[uid] = nil
                    hasSold = true
                    
                    sendWebhook(info.petType)

                    local queue = typeQueues[info.petType]
                    if queue and #queue > 0 then
                        local nextItem = table.remove(queue, 1)
                        MAKE_LISTING:FireServer("pet", nextItem.uid, nextItem.price)
                        activeListingUIDs[nextItem.uid] = { petType = nextItem.petType, price = nextItem.price }
                        task.wait(1)
                    end
                end
            end

            if hasSold then
                local typeMap = {}
                for uid, data in pairs(petsData) do
                    local eq = resolve(Inv.equippedPetsData) or {}
                    if not table.find(eq, uid) then
                        typeMap[data.petType] = (typeMap[data.petType] or 0) + 1
                    end
                end

                for pt, lbl in pairs(liveLabels) do
                    local count = typeMap[pt] or 0
                    if lbl and lbl.Parent then
                        lbl.Text = "Sisa: " .. count
                        lbl.TextColor3 = count == 0 and Color3.fromRGB(230, 100, 100) or Color3.fromRGB(150, 200, 255)
                        if rowFrames[pt] then rowFrames[pt].BackgroundTransparency = count == 0 and 0.5 or 0 end
                    end
                end
            end
        end
    end

    isRunning = false
    if stateLbl then stateLbl.Text = "⏹️ Berhenti" end
    if startBtn then
        startBtn.Text = "🔥 Mulai Re-Listing"
        startBtn.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
    end
end

-- ============================================================
-- 4. ANTI-AFK SYSTEM (DENGAN INDIKATOR GUI)
-- ============================================================
local function setupAntiAFK()
    -- 1. VirtualUser untuk Idle Roblox
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        
        -- Tampilkan di GUI
        if afkLbl then
            afkLbl.Text = "🛡️ Anti-AFK: Idle terdeteksi, memancing..."
            afkLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
            task.delay(3, function()
                if afkLbl and afkLbl.Parent then
                    afkLbl.Text = "🛡️ Anti-AFK: Aktif (Siap)"
                    afkLbl.TextColor3 = Color3.fromRGB(150, 255, 150)
                end
            end)
        end
    end)

    -- 2. Humanoid Move untuk Game AFK Detection
    task.spawn(function()
        while task.wait(60) do -- Setiap 1 menit
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                -- Tampilkan di GUI
                if afkLbl then
                    afkLbl.Text = "🛡️ Anti-AFK: Memancing aktivitas..."
                    afkLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
                end
                
                -- Lakukan pergerakan
                hum:Move(Vector3.new(1, 0, 0), true)
                task.wait(0.2)
                hum:Move(Vector3.new(0, 0, 0), false)
                
                -- Kembalikan teks setelah selesai
                task.delay(3, function()
                    if afkLbl and afkLbl.Parent then
                        afkLbl.Text = "🛡️ Anti-AFK: Aktif (Siap)"
                        afkLbl.TextColor3 = Color3.fromRGB(150, 255, 150)
                    end
                end)
            end
        end
    end)
end

-- ============================================================
-- 5. GUI Build
-- ============================================================
local function buildGUI()
    if PlayerGui:FindFirstChild("AutoListingGui") then PlayerGui.AutoListingGui:Destroy() end
    GUI = Instance.new("ScreenGui", PlayerGui)
    GUI.Name = "AutoListingGui"
    GUI.ResetOnSpawn = false

    local toggle = Instance.new("TextButton", GUI)
    toggle.Size, toggle.Position = UDim2.new(0, 140, 0, 38), UDim2.new(1, -160, 0, 20)
    toggle.BackgroundColor3, toggle.Text, toggle.TextColor3 = Color3.fromRGB(40, 120, 220), "🐾 Re-Listing", Color3.new(1,1,1)
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

    local main = Instance.new("Frame", GUI)
    main.Size, main.Position, main.BackgroundColor3 = UDim2.new(0, 450, 0, 570), UDim2.new(0.5, -225, 0.5, -285), Color3.fromRGB(28, 28, 34)
    main.Active, main.Draggable = true, true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

    local titleBar = Instance.new("Frame", main)
    titleBar.Size, titleBar.BackgroundColor3 = UDim2.new(1, 0, 0, 40), Color3.fromRGB(40, 40, 50)
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

    local titleText = Instance.new("TextLabel", titleBar)
    titleText.Size, titleText.Position, titleText.BackgroundTransparency = UDim2.new(1, -50, 1, 0), UDim2.new(0, 15, 0, 0), 1
    titleText.Text, titleText.TextColor3, titleText.TextXAlignment = "🐾 Re-Listing + Anti-AFK", Color3.new(1,1,1), Enum.TextXAlignment.Left

    local closeBtn = Instance.new("TextButton", titleBar)
    closeBtn.Size, closeBtn.Position = UDim2.new(0, 30, 0, 30), UDim2.new(1, -38, 0, 5)
    closeBtn.BackgroundColor3, closeBtn.Text, closeBtn.TextColor3 = Color3.fromRGB(200, 60, 60), "✕", Color3.new(1,1,1)
    closeBtn.MouseButton1Click:Connect(function() GUI.Enabled = false end)

    local topBar = Instance.new("Frame", main)
    topBar.Size, topBar.Position, topBar.BackgroundTransparency = UDim2.new(1, -20, 0, 160), UDim2.new(0, 10, 0, 45), 1

    -- Status Re-Listing
    stateLbl = Instance.new("TextLabel", topBar)
    stateLbl.Size, stateLbl.BackgroundTransparency, stateLbl.Text = UDim2.new(1, 0, 0, 22), 1, "⏳ Idle"
    stateLbl.TextColor3, stateLbl.TextXAlignment = Color3.fromRGB(200, 200, 200), Enum.TextXAlignment.Left

    -- Status Anti-AFK
    afkLbl = Instance.new("TextLabel", topBar)
    afkLbl.Size, afkLbl.Position, afkLbl.BackgroundTransparency = UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 24), 1
    afkLbl.Text, afkLbl.TextColor3 = "🛡️ Anti-AFK: Aktif (Siap)", Color3.fromRGB(150, 255, 150)
    afkLbl.TextXAlignment = Enum.TextXAlignment.Left
    afkLbl.Font = Enum.Font.GothamBold

    -- Token Label
    tokenLbl = Instance.new("TextLabel", topBar)
    tokenLbl.Size, tokenLbl.Position, tokenLbl.BackgroundTransparency = UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 48), 1
    tokenLbl.Text, tokenLbl.TextColor3 = "💰 Tokens: 0", Color3.fromRGB(100, 255, 100)
    tokenLbl.TextXAlignment = Enum.TextXAlignment.Left
    tokenLbl.Font = Enum.Font.GothamBold

    task.spawn(function()
        while GUI and GUI.Parent do
            if tokenLbl and tokenLbl.Parent then
                tokenLbl.Text = "💰 Tokens: " .. tostring(getTokens())
            end
            task.wait(2)
        end
    end)

    local setAllBtn = Instance.new("TextButton", topBar)
    setAllBtn.Size, setAllBtn.Position, setAllBtn.BackgroundColor3 = UDim2.new(0, 100, 0, 28), UDim2.new(0, 0, 0, 75), Color3.fromRGB(120, 100, 200)
    setAllBtn.Text, setAllBtn.TextColor3 = "Set Semua", Color3.new(1,1,1)
    Instance.new("UICorner", setAllBtn).CornerRadius = UDim.new(0, 6)

    local bulkBox = Instance.new("TextBox", topBar)
    bulkBox.Size, bulkBox.Position, bulkBox.BackgroundColor3 = UDim2.new(0, 100, 0, 28), UDim2.new(0, 110, 0, 75), Color3.fromRGB(45, 45, 55)
    bulkBox.Text, bulkBox.TextColor3 = "100", Color3.new(1,1,1)
    Instance.new("UICorner", bulkBox).CornerRadius = UDim.new(0, 6)

    startBtn = Instance.new("TextButton", topBar)
    startBtn.Size, startBtn.Position = UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 110)
    startBtn.BackgroundColor3, startBtn.Text, startBtn.TextColor3 = Color3.fromRGB(60, 170, 90), "🔥 Mulai Re-Listing", Color3.new(1,1,1)
    Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 8)

    local scroll = Instance.new("ScrollingFrame", main)
    scroll.Size, scroll.Position = UDim2.new(1, -20, 1, -230), UDim2.new(0, 10, 0, 195)
    scroll.BackgroundColor3, scroll.ScrollBarThickness, scroll.AutomaticCanvasSize = Color3.fromRGB(22, 22, 28), 6, Enum.AutomaticSize.Y
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
    scrollContent = scroll

    Instance.new("UIListLayout", scroll).Padding = UDim.new(0, 2)
    Instance.new("UIPadding", scroll).PaddingTop, Instance.new("UIPadding", scroll).PaddingLeft = UDim.new(0, 4), UDim.new(0, 4)

    toggle.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)
    setAllBtn.MouseButton1Click:Connect(function()
        local n = tonumber(bulkBox.Text) or 100
        for _, entry in ipairs(TypeList) do PriceByType[entry.petType] = n end
        for _, child in ipairs(scrollContent:GetChildren()) do
            if child:IsA("Frame") then
                local box = child:FindFirstChildOfClass("TextBox")
                local lbl = child:FindFirstChild("NameLabel")
                if box and lbl and PriceByType[lbl.Text] then
                    box.Text = tostring(PriceByType[lbl.Text])
                    box.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
                end
            end
        end
    end)

    startBtn.MouseButton1Click:Connect(function()
        if isRunning then
            isRunning = false
        else
            isRunning = true
            startBtn.Text = "⏹️ Stop"
            startBtn.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
            task.spawn(runRelistLoop)
        end
    end)
end

-- ============================================================
-- 6. Init & Auto-Scan
-- ============================================================
buildGUI()
setupAntiAFK() -- Panggil Anti-AFK setelah GUI dibuat agar indikatornya muncul

task.spawn(function()
    while GUI and GUI.Parent do
        local petsData = resolve(Inv.petsData)
        if petsData then
            local eq = resolve(Inv.equippedPetsData) or {}
            TypeList, liveLabels, rowFrames = {}, {}, {}
            for _, child in ipairs(scrollContent:GetChildren()) do
                if child:IsA("Frame") then child:Destroy() end
            end

            local typeMap = {}
            for uid, data in pairs(petsData) do
                if not table.find(eq, uid) then
                    local pt = data.petType or "Unknown"
                    if not typeMap[pt] then typeMap[pt] = { count = 0, uids = {} } end
                    typeMap[pt].count = typeMap[pt].count + 1
                    table.insert(typeMap[pt].uids, uid)
                end
            end

            local i = 0
            for pt, info in pairs(typeMap) do
                i = i + 1
                table.insert(TypeList, { petType = pt, count = info.count, uids = info.uids })

                local row = Instance.new("Frame", scrollContent)
                row.Size, row.BackgroundColor3, row.LayoutOrder = UDim2.new(1, -8, 0, 34), Color3.fromRGB(35, 35, 42), i
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
                rowFrames[pt] = row

                local nameLbl = Instance.new("TextLabel", row)
                nameLbl.Name, nameLbl.Size, nameLbl.Position, nameLbl.BackgroundTransparency = "NameLabel", UDim2.new(0, 150, 1, 0), UDim2.new(0, 10, 0, 0), 1
                nameLbl.Text, nameLbl.TextColor3, nameLbl.TextXAlignment = pt, Color3.fromRGB(220, 220, 230), Enum.TextXAlignment.Left

                local countLbl = Instance.new("TextLabel", row)
                countLbl.Size, countLbl.Position, countLbl.BackgroundTransparency = UDim2.new(0, 80, 1, 0), UDim2.new(0, 160, 0, 0), 1
                countLbl.Text, countLbl.TextColor3 = "Sisa: " .. info.count, Color3.fromRGB(150, 200, 255)
                liveLabels[pt] = countLbl

                local box = Instance.new("TextBox", row)
                box.Size, box.Position, box.BackgroundColor3 = UDim2.new(0, 90, 0, 26), UDim2.new(1, -100, 0, 4), Color3.fromRGB(45, 45, 55)
                box.Text, box.TextColor3, box.PlaceholderText = "", Color3.new(1,1,1), "harga..."
                Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)

                box.FocusLost:Connect(function()
                    local n = tonumber(box.Text)
                    if n and n > 0 then
                        PriceByType[pt] = math.floor(n)
                        box.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
                    else
                        PriceByType[pt] = nil
                        box.Text = ""
                        box.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
                    end
                end)
            end
            break
        end
        task.wait(2)
    end
end)
