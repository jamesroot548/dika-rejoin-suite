-- ==============================================================================
--    DIKA AUTO-DETECT KICK, LIVE TAB SYNC, AUTO-ACCEPT & AUTO-CONFIRM TRADE PRO
-- ==============================================================================
-- 1. 100% NON-BLOCKING: Startup instan & tidak pernah menahan loading save
-- 2. ASYNC TIMEOUT WEBHOOK: Tidak pernah hang di emulator Android / PC
-- 3. AUTO-ACCEPT & AUTO-CONFIRM TRADE SAMPAI SELESAI:
--    - Menerima permintaan trade masuk (Trade Request)
--    - Menerima tawaran trade (Accept Negotiation)
--    - Konfirmasi trade (Confirm Trade) setelah countdown selesai
--    - Deteksi otomatis saat trade sukses selesai & lapor ke tools untuk rotasi instan!
-- 4. AUTO-DETECT KICK: Menutup tab saat disconnect / kick resmi
-- 5. ⚡ AUTO-KICK 30 DETIK IN-GAME: Fallback kick jika tidak ada trade

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

-- Helper Fungsi Exit & Webhook Notifikasi
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
    task.wait(0.3)
    pcall(function()
        if type(killprocess) == "function" then
            killprocess()
        elseif type(getgenv) == "function" and type(getgenv().killprocess) == "function" then
            getgenv().killprocess()
        elseif type(getgenv) == "function" and type(getgenv().kill_process) == "function" then
            getgenv().kill_process()
        elseif game.Shutdown then
            game:Shutdown()
        end
    end)
end

-- ------------------------------------------------------------------------------
-- 1. ENGINE AUTO-TRADE PRO: AUTO-ACCEPT REQUEST, NEGOTIATION & CONFIRM SAMPAI SELESAI
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
        if btn.Activated then
            btn.Activated:Fire()
            clicked = true
        end
        if btn.MouseButton1Click then
            btn.MouseButton1Click:Fire()
            clicked = true
        end
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

-- Helper aman memanggil RemoteFunction / RemoteEvent Adopt Me
local function safe_call_remote(remote, ...)
    if not remote then return false end
    local ok, res = false, nil
    if remote:IsA("RemoteFunction") then
        ok, res = pcall(function(...) return remote:InvokeServer(...) end, ...)
    elseif remote:IsA("RemoteEvent") then
        ok, res = pcall(function(...) return remote:FireServer(...) end, ...)
    end
    return ok, res
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

    print("[DIKA REJOIN] 🤝 Auto-Accept & Auto-Confirm Trade Engine Siap & Aktif!")

    local is_in_trade = false
    local trade_has_confirmed = false
    local last_confirm_time = 0

    -- Loop Khusus Auto-Trade (0.2 detik agar respon instan & gesit)
    while task.wait(0.2) do
        pcall(function()
            local API = ReplicatedStorage:FindFirstChild("API")

            -- ==========================================================
            -- A. TAHAP 0: AUTO-ACCEPT PERMINTAAN TRADE MASUK (REQUEST)
            -- ==========================================================
            if API then
                local reqRemote = API:FindFirstChild("TradeAPI/AcceptOrDeclineTradeRequest")
                if reqRemote then
                    for _, player in ipairs(Players:GetPlayers()) do
                        if player ~= lp then
                            task.spawn(function()
                                safe_call_remote(reqRemote, player, true)
                            end)
                        end
                    end
                end
            end

            -- Pop-up Dialog Masuk (DialogApp)
            local dialogApp = pGui:FindFirstChild("DialogApp")
            if dialogApp and dialogApp.Enabled then
                for _, desc in ipairs(dialogApp:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local txt = string.lower(desc.Text or "")
                        if string.find(txt, "accept") or string.find(txt, "yes") or string.find(txt, "terima") or string.find(txt, "agree") or string.find(txt, "understand") then
                            local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                            if btn and btn.Visible then
                                force_click_button(btn)
                            end
                        end
                    end

                    if desc:IsA("GuiButton") and desc.Visible then
                        local name = string.lower(desc.Name or "")
                        if name == "acceptbutton" or name == "greenbutton" or name == "yesbutton" then
                            force_click_button(desc)
                        end
                    end
                end
            end

            -- ==========================================================
            -- B. TAHAP 1 & 2: AUTO-ACCEPT NEGOTIATION & AUTO-CONFIRM TRADE
            -- ==========================================================
            local tradeApp = pGui:FindFirstChild("TradeApp")
            if tradeApp and tradeApp.Enabled then
                is_in_trade = true

                -- 1. Panggil Remote Resmi Adopt Me (Direct API Layer)
                if API then
                    local acceptNegRemote = API:FindFirstChild("TradeAPI/AcceptNegotiation")
                    if acceptNegRemote then
                        task.spawn(function()
                            safe_call_remote(acceptNegRemote)
                        end)
                    end

                    local confirmTrdRemote = API:FindFirstChild("TradeAPI/ConfirmTrade")
                    if confirmTrdRemote then
                        task.spawn(function()
                            safe_call_remote(confirmTrdRemote)
                        end)
                    end
                end

                -- 2. GUI Layer: Traversal tombol di dalam TradeApp
                for _, desc in ipairs(tradeApp:GetDescendants()) do
                    -- Deteksi tombol berdasarkan Text
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local txt = string.lower(desc.Text or "")

                        -- Tahap 1: Accept Negotiation (Tombol Accept)
                        if string.find(txt, "accept") or string.find(txt, "terima") then
                            local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                            if btn and btn.Visible then
                                force_click_button(btn)
                            end
                        end

                        -- Tahap 2: Confirm Trade (Tombol Confirm - tunggu countdown selesai)
                        if (string.find(txt, "confirm") or string.find(txt, "konfirmasi")) and not string.find(txt, "wait") then
                            local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                            if btn and btn.Visible then
                                force_click_button(btn)
                                trade_has_confirmed = true
                                last_confirm_time = tick()
                            end
                        end

                        -- Pop-up Peringatan Unbalanced Trade (misal: Main menerima pet gratis dari Bot)
                        if string.find(txt, "understand") or string.find(txt, "trade anyway") or string.find(txt, "proceed") or string.find(txt, "paham") then
                            local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                            if btn and btn.Visible then
                                force_click_button(btn)
                            end
                        end
                    end

                    -- Deteksi tombol berdasarkan Nama Objek
                    if desc:IsA("GuiButton") and desc.Visible then
                        local name = string.lower(desc.Name or "")
                        if name == "acceptbutton" or name == "actionbutton" or name == "greenbutton" then
                            force_click_button(desc)
                        elseif name == "confirmbutton" then
                            force_click_button(desc)
                            trade_has_confirmed = true
                            last_confirm_time = tick()
                        elseif string.find(name, "checkbox") or string.find(name, "agree") or string.find(name, "understand") then
                            force_click_button(desc)
                        end
                    end
                end
            else
                -- Jika jendela TradeApp baru saja tertutup (Trade telah usai / selesai)
                if is_in_trade then
                    is_in_trade = false
                    -- Jika sebelumnya sudah ter-Confirm dalam 10 detik terakhir
                    if trade_has_confirmed and (tick() - last_confirm_time < 10) then
                        print("[DIKA REJOIN] 🎉 Trade Selesai Terkonfirmasi! Tetap aktif in-game sampai timer (" .. tostring(AUTO_KICK_SECONDS) .. " detik) selesai.")
                    end
                    trade_has_confirmed = false
                end
            end
        end)
    end
end)

-- ------------------------------------------------------------------------------
-- 2. ENGINE AUTO-DETECT KICK & CLOSE TAB
-- ------------------------------------------------------------------------------

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

    -- Deteksi Khusus Adopt Me: Tunggu sampai "LOADING SAVE..." benar-benar selesai & Pemain Aktif In-Game!
    print("[DIKA REJOIN] ⏳ Mendeteksi Status In-Game Adopt Me...")

    local function check_if_ingame()
        -- 1. Auto-Dismiss Dialog Pop-up Usia ("Unlock chat with an age check") agar loading tidak terhenti!
        pcall(function()
            for _, root_gui in ipairs({pGui, CoreGui}) do
                if root_gui then
                    for _, desc in ipairs(root_gui:GetDescendants()) do
                        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                            local txt = string.lower(desc.Text or "")
                            if string.find(txt, "age check") or string.find(txt, "verify your age") or string.find(txt, "unlock chat") then
                                local parent = desc.Parent
                                if parent then
                                    for _, b in ipairs(parent:GetDescendants()) do
                                        if b:IsA("GuiButton") and b.Visible then
                                            local btxt = string.lower(b.Text or "")
                                            local bname = string.lower(b.Name or "")
                                            if string.find(btxt, "cancel") or string.find(btxt, "batal") or string.find(btxt, "later") or string.find(bname, "cancel") or string.find(bname, "close") then
                                                force_click_button(b)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)

        -- 2. Cek apakah ada teks "loading save" yang BENAR-BENAR SEDANG TAMPIL (Visible) di layar
        local is_actively_loading = false
        pcall(function()
            for _, gui in ipairs(pGui:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    for _, desc in ipairs(gui:GetDescendants()) do
                        if desc:IsA("TextLabel") and desc.Visible and desc.TextTransparency < 0.5 then
                            local txt = string.lower(desc.Text or "")
                            if (string.find(txt, "loading save") or string.find(txt, "loading house")) and desc.AbsoluteSize.X > 20 and desc.AbsolutePosition.Y >= 0 then
                                is_actively_loading = true
                                break
                            end
                        end
                    end
                    if is_actively_loading then break end
                end
            end
        end)

        if is_actively_loading then
            return false
        end

        -- 3. Cek apakah GUI utama in-game Adopt Me sudah aktif (BottomBarApp, RoleChooserApp, NewsApp, HouseApp)
        local bottomBar = pGui:FindFirstChild("BottomBarApp")
        local roleChooser = pGui:FindFirstChild("RoleChooserApp")
        local newsApp = pGui:FindFirstChild("NewsApp")
        local houseApp = pGui:FindFirstChild("HouseApp")

        if (bottomBar and bottomBar.Enabled) or (roleChooser and roleChooser.Enabled) or (newsApp and newsApp.Enabled) or (houseApp and houseApp.Enabled) then
            return true
        end

        -- 4. Fallback: Jika karakter sudah spawn dan berdiri di dalam rumah / Workspace
        if lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") then
            return true
        end

        return false
    end

    local wait_count = 0
    while wait_count < 90 do
        if check_if_ingame() then
            break
        end
        task.wait(1)
        wait_count = wait_count + 1
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

print("[DIKA REJOIN] Auto-Detect Kick, Live Tab Sync, Auto-Accept & Auto-Confirm Trade Pro Aktif!")