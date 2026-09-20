-- ==============================================================================
--    DIKA AUTO-DETECT KICK, LIVE TAB SYNC, AUTO-ACCEPT & AUTO-KICK 25S (LUA)
-- ==============================================================================
-- 1. 100% NON-BLOCKING: Startup instan & tidak pernah menahan loading save
-- 2. ASYNC TIMEOUT WEBHOOK: Tidak pernah hang di emulator Android / PC
-- 3. AUTO-ACCEPT TRADE REQUEST ONLY: Otomatis menerima permintaan trade masuk dari Main
-- 4. AUTO-DETECT KICK: Menutup tab saat disconnect / kick resmi
-- 5. ⚡ AUTO-KICK 25 DETIK IN-GAME: Otomatis kick & lapor selesai setelah 25 detik in-game

local AUTO_KICK_SECONDS = 30  -- Durasi in-game sebelum auto-kick (detik)

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = nil
local VirtualInputManager = nil

pcall(function() VirtualUser = game:GetService("VirtualUser") end)
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

-- Helper Webhook Non-Blocking (Async & Timeout 1 detik)
local function send_webhook(endpoint, payload)
    task.spawn(function()
        pcall(function()
            local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
            if req then
                req({
                    Url = "http://127.0.0.1:19999/" .. endpoint,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = HttpService:JSONEncode(payload),
                    Timeout = 1,
                    timeout = 1
                })
            end
        end)
    end)
end

-- Helper Sinkronisasi Otomatis Durasi dari Dika Rejoin Suite
local function sync_config_from_suite()
    local synced = false
    pcall(function()
        local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
        if req then
            local res = req({
                Url = "http://127.0.0.1:19999/get_config",
                Method = "GET",
                Headers = {["Content-Type"] = "application/json"},
                Timeout = 2,
                timeout = 2
            })
            if res and (res.StatusCode == 200 or res.Status == 200) and res.Body then
                local data = HttpService:JSONDecode(res.Body)
                if data and data.auto_kick_seconds then
                    local val = tonumber(data.auto_kick_seconds)
                    if val and val > 0 then
                        AUTO_KICK_SECONDS = val
                        synced = true
                        print("[DIKA REJOIN] 🔄 Config tersinkron dari Tools: AUTO_KICK_SECONDS = " .. tostring(AUTO_KICK_SECONDS) .. " detik")
                    end
                end
            end
        end
    end)

    if not synced then
        pcall(function()
            local body = game:HttpGet("http://127.0.0.1:19999/get_config", true)
            if body and #body > 0 then
                local data = HttpService:JSONDecode(body)
                if data and data.auto_kick_seconds then
                    local val = tonumber(data.auto_kick_seconds)
                    if val and val > 0 then
                        AUTO_KICK_SECONDS = val
                        synced = true
                        print("[DIKA REJOIN] 🔄 Config tersinkron dari Tools (HttpGet): AUTO_KICK_SECONDS = " .. tostring(AUTO_KICK_SECONDS) .. " detik")
                    end
                end
            end
        end)
    end
    return synced
end

-- Ambil config saat startup secara async
task.spawn(function()
    sync_config_from_suite()
end)

-- ------------------------------------------------------------------------------
-- 0. SINKRONISASI TAB AKTIF KE DIKA REJOIN (DETACHED THREAD)
-- ------------------------------------------------------------------------------
task.spawn(function()
    local timeout = 0
    while not game:IsLoaded() and timeout < 15 do
        task.wait(0.5)
        timeout = timeout + 0.5
    end

    local lp = Players.LocalPlayer
    while not lp do
        task.wait(0.5)
        lp = Players.LocalPlayer
    end

    send_webhook("tab_online", {
        username = lp.Name,
        userId = tostring(lp.UserId)
    })

    while task.wait(3) do
        send_webhook("tab_heartbeat", {
            username = lp.Name,
            userId = tostring(lp.UserId)
        })
    end
end)

-- ------------------------------------------------------------------------------
-- 1. ENGINE AUTO-ACCEPT TRADE REQUEST MASUK (HANYA TERIMA PERMINTAAN TRADE)
-- ------------------------------------------------------------------------------
local function force_click_button(btn)
    if not btn then return false end
    local clicked = false

    -- A. Firesignal pada event klik
    pcall(function()
        if firesignal then
            firesignal(btn.Activated)
            firesignal(btn.MouseButton1Click)
            firesignal(btn.MouseButton1Down)
            firesignal(btn.MouseButton1Up)
            clicked = true
        end
    end)

    -- B. Direct Signal Fire
    pcall(function()
        if btn.Activated then btn.Activated:Fire() clicked = true end
        if btn.MouseButton1Click then btn.MouseButton1Click:Fire() clicked = true end
    end)

    -- C. Virtual User / Input Click (Simulasi Sentuhan Layar Asli)
    pcall(function()
        if btn.AbsolutePosition and btn.AbsoluteSize then
            local cx = btn.AbsolutePosition.X + (btn.AbsoluteSize.X / 2)
            local cy = btn.AbsolutePosition.Y + (btn.AbsoluteSize.Y / 2)

            if VirtualUser then
                VirtualUser:Button1Down(Vector2.new(cx, cy))
                task.wait(0.01)
                VirtualUser:Button1Up(Vector2.new(cx, cy))
                clicked = true
            elseif VirtualInputManager then
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                task.wait(0.01)
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
                clicked = true
            end
        end
    end)

    return clicked
end

task.spawn(function()
    local lp = Players.LocalPlayer
    while not lp do
        task.wait(0.5)
        lp = Players.LocalPlayer
    end

    -- Tunggu PlayerGui siap
    local pGui = lp:WaitForChild("PlayerGui", 25)
    if not pGui then return end

    -- Beri jeda 4 detik agar game stabil
    task.wait(4)

    print("[DIKA REJOIN] 🤝 Auto-Accept Trade Request Engine Siap & Aktif!")

    -- Loop Khusus Auto-Accept Permintaan Trade Masuk (0.25 detik)
    while task.wait(0.25) do
        pcall(function()
            local API = ReplicatedStorage:FindFirstChild("API")

            -- A. PANGGIL REMOTE ACCEPT TRADE REQUEST SECARA ASYNC
            if API then
                local reqRemote = API:FindFirstChild("TradeAPI/AcceptOrDeclineTradeRequest")
                if reqRemote then
                    for _, player in ipairs(Players:GetPlayers()) do
                        if player ~= lp then
                            task.spawn(function()
                                pcall(function()
                                    reqRemote:InvokeServer(player, true)
                                end)
                            end)
                        end
                    end
                end
            end

            -- B. AUTO-CLICK TOMBOL ACCEPT DI POP-UP DIALOG TRADE (DialogApp)
            local dialogApp = pGui:FindFirstChild("DialogApp")
            if dialogApp and dialogApp.Enabled then
                for _, desc in ipairs(dialogApp:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local txt = string.lower(desc.Text or "")
                        if string.find(txt, "accept") or string.find(txt, "yes") or string.find(txt, "terima") then
                            local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                            if btn and btn.Visible then
                                force_click_button(btn)
                            end
                        end
                    end

                    if desc:IsA("GuiButton") and desc.Visible then
                        local name = string.lower(desc.Name or "")
                        if name == "acceptbutton" or name == "greenbutton" then
                            force_click_button(desc)
                        end
                    end
                end
            end
        end)
    end
end)

-- ------------------------------------------------------------------------------
-- 2. ENGINE AUTO-DETECT KICK & CLOSE TAB
-- ------------------------------------------------------------------------------
local function notify_tool_and_exit(reason)
    print("[DIKA REJOIN] Disconnect / Kick / Trade Selesai (" .. tostring(reason) .. "). Mengirim sinyal...")
    local lp = Players.LocalPlayer
    local uName = lp and lp.Name or "Unknown"
    local uId = lp and tostring(lp.UserId) or ""
    send_webhook("trade_completed", {
        username = uName,
        userId = uId,
        reason = tostring(reason)
    })
    task.wait(1.5)
    pcall(function()
        if getgenv().killprocess or killprocess then
            (getgenv().killprocess or killprocess)()
        elseif game.Shutdown then
            game:Shutdown()
        end
    end)
end

local function is_real_kick_or_disconnect(txt)
    if not txt or type(txt) ~= "string" or #txt == 0 then return false end
    local lower = txt:lower()

    local exact_phrases = {
        "all trades completed",
        "error code: 267",
        "error code: 273",
        "error code: 264",
        "error code: 268",
        "error code: 277",
        "error code: 279",
        "error code: 524",
        "error code: 529",
        "same account launched experience from different device",
        "you have been kicked by this experience",
        "you have been kicked due to unexpected client behavior",
        "lost connection to the game server",
        "disconnected: you have been kicked"
    }

    for _, phrase in ipairs(exact_phrases) do
        if string.find(lower, phrase, 1, true) then
            return true
        end
    end
    return false
end

GuiService.ErrorMessageChanged:Connect(function(msg)
    if is_real_kick_or_disconnect(msg) then
        notify_tool_and_exit("ErrorMessageChanged: " .. tostring(msg))
    end
end)

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
            if promptGui then
                local overlay = promptGui:FindFirstChild("promptOverlay")
                if overlay and overlay.Visible then
                    local errPrompt = overlay:FindFirstChild("ErrorPrompt")
                    if errPrompt and errPrompt.Visible then
                        local errMsg = errPrompt:FindFirstChild("ErrorMessage", true)
                        if errMsg and errMsg.Text and is_real_kick_or_disconnect(errMsg.Text) then
                            notify_tool_and_exit("ErrorPrompt: " .. tostring(errMsg.Text))
                        end
                    end
                end
            end
        end)
    end
end)

-- ------------------------------------------------------------------------------
-- 3. ENGINE AUTO-KICK SETELAH SELESAI LOADING SAVE & MASUK IN-GAME
-- ------------------------------------------------------------------------------
task.spawn(function()
    while not game:IsLoaded() do
        task.wait(0.5)
    end

    local lp = Players.LocalPlayer
    while not lp do
        task.wait(0.5)
        lp = Players.LocalPlayer
    end

    local pGui = lp:WaitForChild("PlayerGui", 45)
    if not pGui then return end

    -- Deteksi Khusus Adopt Me: Tunggu sampai "LOADING SAVE..." benar-benar selesai!
    print("[DIKA REJOIN] ⏳ Mendeteksi Loading Save Adopt Me... Menunggu hingga selesai loading...")
    local load_timeout = 0
    while load_timeout < 120 do
        local still_loading = false

        -- Cek apakah ada GUI loading atau teks "loading save" / "loading house"
        for _, gui in ipairs(pGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled then
                local gname = string.lower(gui.Name)
                if string.find(gname, "loading") or string.find(gname, "loadingsave") then
                    still_loading = true
                    break
                end
                for _, desc in ipairs(gui:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local txt = string.lower(desc.Text or "")
                        if string.find(txt, "loading save") or string.find(txt, "loading house") or string.find(txt, "loading...") then
                            still_loading = true
                            break
                        end
                    end
                end
                if still_loading then break end
            end
        end

        -- Jika MASIH LOADING, dilarang keras selesai! Tetap tunggu sampai teks loading hilang
        if not still_loading then
            -- Pastikan GUI in-game nyata (bukan DialogApp pop-up) sudah ada
            local has_ingame_gui = pGui:FindFirstChild("BottomBarApp") or pGui:FindFirstChild("RoleChooserApp") or pGui:FindFirstChild("NewsApp")
            if has_ingame_gui or load_timeout >= 30 then
                break
            end
        end

        task.wait(1)
        load_timeout = load_timeout + 1
    end

    task.wait(2)
    print("[DIKA REJOIN] 🎮 Loading Save Selesai! Pemain Aktif In-Game!")
    send_webhook("player_ingame_ready", {
        username = lp.Name,
        userId = tostring(lp.UserId)
    })

    -- Sinkronisasi ulang config tepat sebelum timer countdown dimulai agar selalu up-to-date dengan GUI
    sync_config_from_suite()

    print("[DIKA REJOIN] ⏱️ Timer Auto-Kick " .. tostring(AUTO_KICK_SECONDS) .. " Detik In-Game Dimulai!")

    for i = AUTO_KICK_SECONDS, 1, -1 do
        task.wait(1)
        if i % 5 == 0 or i <= 3 then
            print("[DIKA REJOIN] ⏱️ Auto-Kick dalam: " .. tostring(i) .. " detik...")
        end
    end

    print("[DIKA REJOIN] 🚪 Waktu " .. tostring(AUTO_KICK_SECONDS) .. " detik in-game tercapai! Menjalankan Auto-Kick...")
    notify_tool_and_exit("Auto-Kick " .. tostring(AUTO_KICK_SECONDS) .. "s In-Game Selesai")

    pcall(function()
        lp:Kick("[DIKA REJOIN] Selesai Sesi Trade (Auto-Kick " .. tostring(AUTO_KICK_SECONDS) .. "s)")
    end)
end)

print("[DIKA REJOIN] Auto-Detect Kick, Live Tab Sync, Auto-Accept & Auto-Kick " .. tostring(AUTO_KICK_SECONDS) .. "s Aktif!")