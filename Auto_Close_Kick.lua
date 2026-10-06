-- ==============================================================================
--    DIKA AUTO-DETECT KICK, LIVE TAB SYNC, AUTO-ACCEPT & AUTO-CONFIRM TRADE PRO
-- ==============================================================================
-- 1. 100% NON-BLOCKING & ULTRA-RINGAN: 60 FPS stabil, zero freeze, loading secepat kilat
-- 2. ASYNC TIMEOUT WEBHOOK: Tidak pernah hang di emulator Android / PC
-- 3. EVENT-DRIVEN AUTO-TRADE (MULTI-HIT 2-3x RETRY):
--    - Menerima permintaan trade (Trade Request) di DialogApp, NotificationsApp & PlayerGui
--    - Multi-Hit Retry 2-3x jika terdeteksi permintaan belum ke-accept
--    - Bekerja aktif sepanjang seluruh durasi sesi in-game (bukan cuma di awal)
--    - Menerima tawaran trade (Accept Negotiation)
--    - Konfirmasi trade (Confirm Trade) setelah countdown selesai
--    - Deteksi otomatis saat trade sukses selesai & lapor ke tools untuk rotasi instan!
-- 4. AUTO-DETECT KICK: Menutup tab saat disconnect / kick resmi
-- 5. ⚡ AUTO-KICK DINAMIS (MULTI-BOT DETECT):
--    - 1 bot: Durasi normal (1x)
--    - 2 bot: Otomatis bertambah 2x lipat
--    - n bot: Otomatis diskalakan (n x durasi) agar semua bot sempat trade!

local AUTO_KICK_SECONDS = 80  -- Durasi dasar in-game sebelum auto-kick (detik)
local CURRENT_TARGET_DURATION = AUTO_KICK_SECONDS
local CURRENT_BOTS_DETECTED = 1
local IS_IN_TRADE_ACTIVE = false
local TRADE_COMPLETED_SUCCESS = false

local my_pid = nil
pcall(function()
    if type(getpid) == "function" then
        my_pid = getpid()
    elseif type(get_pid) == "function" then
        my_pid = get_pid()
    elseif type(getgenv) == "function" then
        local genv = getgenv()
        if type(genv.getpid) == "function" then
            my_pid = genv.getpid()
        elseif type(genv.get_pid) == "function" then
            my_pid = genv.get_pid()
        end
    end
end)

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = nil
local VirtualInputManager = nil

pcall(function() VirtualUser = game:GetService("VirtualUser") end)
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

-- Helper Menghitung Jumlah Bot / Pemain Lain di Server Selain Kita (LocalPlayer)
local function get_other_players_count()
    local count = 0
    local lp = Players.LocalPlayer
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            count = count + 1
        end
    end
    return count
end

-- Helper Webhook Non-Blocking (100% Async & Timeout 1 detik)
local function send_webhook(endpoint, payload)
    task.spawn(function()
        pcall(function()
            if type(payload) == "table" and my_pid and not payload.pid then
                payload.pid = my_pid
            end
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

-- Helper Sinkronisasi Otomatis Durasi dari Dika Rejoin Suite (100% Async, Bebas Freeze)
local function sync_config_from_suite()
    task.spawn(function()
        pcall(function()
            local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
            if req then
                local res = req({
                    Url = "http://127.0.0.1:19999/get_config",
                    Method = "GET",
                    Headers = {["Content-Type"] = "application/json"},
                    Timeout = 1,
                    timeout = 1
                })
                if res and (res.StatusCode == 200 or res.Status == 200) and res.Body then
                    local data = HttpService:JSONDecode(res.Body)
                    if data and data.auto_kick_seconds then
                        local val = tonumber(data.auto_kick_seconds)
                        if val and val > 0 then
                            AUTO_KICK_SECONDS = val
                            CURRENT_TARGET_DURATION = AUTO_KICK_SECONDS * math.max(1, CURRENT_BOTS_DETECTED)
                            print("[DIKA REJOIN] 🔄 Config tersinkron: AUTO_KICK_SECONDS = " .. tostring(AUTO_KICK_SECONDS) .. "s")
                        end
                    end
                end
            end
        end)
    end)
end

-- Ambil config saat startup secara murni async di background
sync_config_from_suite()

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
    task.wait(0.5)
    pcall(function()
        if lp and lp.Kick then
            lp:Kick(string.format("[DIKA REJOIN] %s (Auto-DC)", tostring(reason)))
        end
    end)
end

-- Helper Fungsi Khusus: Trade Selesai Terkonfirmasi -> Jeda Aman 1.8s -> Auto-DC Instan
local function handle_trade_completed_exit(source)
    if TRADE_COMPLETED_SUCCESS then return end
    TRADE_COMPLETED_SUCCESS = true
    IS_IN_TRADE_ACTIVE = false

    print(string.format("[DIKA REJOIN] 🎉 TRADE SELESAI TERKONFIRMASI (%s)!", tostring(source or "Success")))
    print("[DIKA REJOIN] ⏳ Menunggu jeda aman 1.8 detik (memastikan inventori tersimpan di server Adopt Me)...")
    task.wait(1.8)

    print("[DIKA REJOIN] 🚪 Mengirim sinyal rotasi ke Dika Tools & Keluar Game...")
    notify_tool_and_exit(string.format("Trade Selesai Terkonfirmasi (%s)", tostring(source or "Success")))
end

-- ------------------------------------------------------------------------------
-- 1. ENGINE AUTO-TRADE PRO: INSTAN & ZERO CPU LAG
-- ------------------------------------------------------------------------------
local function force_click_button(btn)
    if not btn then return false end
    local clicked = false

    -- A. Firesignal jika didukung executor (instan 0 ms)
    pcall(function()
        if firesignal then
            firesignal(btn.Activated)
            firesignal(btn.MouseButton1Click)
            clicked = true
        end
    end)

    -- B. Virtual Input Asli Roblox Engine (Sintetik Mouse Click)
    pcall(function()
        if btn.AbsolutePosition and btn.AbsoluteSize then
            local cx = btn.AbsolutePosition.X + (btn.AbsoluteSize.X / 2)
            local cy = btn.AbsolutePosition.Y + (btn.AbsoluteSize.Y / 2)
            if VirtualInputManager then
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
                clicked = true
            elseif VirtualUser then
                VirtualUser:Button1Down(Vector2.new(cx, cy))
                VirtualUser:Button1Up(Vector2.new(cx, cy))
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

-- Helper deteksi tombol Accept pada pop-up notifikasi atau dialog permintaan trade masuk
local function find_trade_request_accept_buttons(pGui)
    local buttons = {}
    local seen = {}
    if not pGui then return buttons end

    local function add_btn(b)
        if b and b:IsA("GuiButton") and b.Visible and not seen[b] then
            seen[b] = true
            table.insert(buttons, b)
        end
    end

    -- Kumpulkan container dialog & notifikasi yang sedang aktif di PlayerGui
    local candidate_containers = {}
    for _, name in ipairs({"NotificationsApp", "NotificationApp", "DialogApp", "HintsApp"}) do
        local app = pGui:FindFirstChild(name)
        if app and app.Enabled then
            table.insert(candidate_containers, app)
        end
    end

    for _, container in ipairs(candidate_containers) do
        -- Cek jika ada kartu khusus bertuliskan "trade request" atau "sent you a trade" (sticky note Adopt Me)
        for _, desc in ipairs(container:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible then
                local txt = string.lower(desc.Text or "")
                if string.find(txt, "trade request") or string.find(txt, "sent you a trade") then
                    local card = desc:FindFirstAncestorWhichIsA("GuiObject")
                    if card then
                        local topCard = card:FindFirstAncestorWhichIsA("GuiObject") or card
                        for _, sub in ipairs(topCard:GetDescendants()) do
                            if sub:IsA("GuiButton") and sub.Visible then
                                local subname = string.lower(sub.Name or "")
                                local subtext = sub:IsA("TextButton") and string.lower(sub.Text or "") or ""
                                local is_decline = string.find(subname, "decline") or string.find(subname, "cancel") or string.find(subname, "no") or string.find(subname, "red") or string.find(subtext, "decline") or string.find(subtext, "cancel")
                                if not is_decline then
                                    add_btn(sub)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Cari tombol accept berdasarkan nama atau teks di dalam container
        for _, desc in ipairs(container:GetDescendants()) do
            if desc:IsA("GuiButton") and desc.Visible then
                local name = string.lower(desc.Name or "")
                if name == "acceptbutton" or name == "greenbutton" or name == "yesbutton" or name == "accept" then
                    add_btn(desc)
                elseif desc:IsA("TextButton") then
                    local txt = string.lower(desc.Text or "")
                    if string.find(txt, "accept") or string.find(txt, "terima") or string.find(txt, "yes") then
                        add_btn(desc)
                    end
                else
                    local label = desc:FindFirstChildWhichIsA("TextLabel", true)
                    if label and label.Visible then
                        local ltxt = string.lower(label.Text or "")
                        if string.find(ltxt, "accept") or string.find(ltxt, "terima") or string.find(ltxt, "yes") then
                            add_btn(desc)
                        end
                    end
                end
            elseif (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Visible then
                local txt = string.lower(desc.Text or "")
                if string.find(txt, "accept") or string.find(txt, "terima") or string.find(txt, "yes") then
                    local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                    if btn and btn.Visible then
                        add_btn(btn)
                    end
                end
            end
        end
    end

    return buttons
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

    -- Beri jeda 3 detik agar game stabil
    task.wait(3)

    print("[DIKA REJOIN] 🤝 Auto-Accept & Auto-Confirm Trade Engine Siap & Aktif (Multi-Hit 2-3x Retry & Continuous)!")

    -- Event listener instan (0ms) untuk banner notifikasi baru di PlayerGui
    pcall(function()
        pGui.DescendantAdded:Connect(function(desc)
            if TRADE_COMPLETED_SUCCESS then return end
            if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Visible then
                local txt = string.lower(desc.Text or "")
                if string.find(txt, "trade was successful") 
                    or string.find(txt, "trade successful") 
                    or string.find(txt, "the trade was successful")
                    or string.find(txt, "trade completed") 
                    or string.find(txt, "trade complete") 
                    or string.find(txt, "you traded with")
                    or string.find(txt, "pertukaran berhasil")
                    or string.find(txt, "trade berhasil") then
                    task.spawn(function()
                        handle_trade_completed_exit("Notifikasi Instan GUI: " .. tostring(desc.Text))
                    end)
                end
            end
        end)
    end)

    local is_in_trade = false
    local trade_has_confirmed = false
    local last_confirm_time = 0

    -- Loop Auto-Trade Ultra-Responsif (0.25 detik)
    while task.wait(0.25) do
        pcall(function()
            local API = ReplicatedStorage:FindFirstChild("API")
            local tradeApp = pGui:FindFirstChild("TradeApp")
            local is_trade_open = (tradeApp and tradeApp.Enabled)

            -- ==========================================================
            -- A. TAHAP 0: AUTO-ACCEPT PERMINTAAN TRADE MASUK (REQUEST)
            -- Bekerja sepanjang sesi game (bukan hanya di awal)
            -- Multi-hit retry 2-3x jika terdeteksi request belum ter-accept
            -- ==========================================================
            if not is_trade_open then
                local accept_buttons = find_trade_request_accept_buttons(pGui)
                local has_request = (#accept_buttons > 0)

                -- Cek juga apakah ada indikasi notifikasi teks trade request di ScreenGui aktif
                if not has_request then
                    for _, name in ipairs({"NotificationsApp", "NotificationApp", "DialogApp", "HintsApp"}) do
                        local app = pGui:FindFirstChild(name)
                        if app and app.Enabled then
                            for _, desc in ipairs(app:GetDescendants()) do
                                if desc:IsA("TextLabel") and desc.Visible then
                                    local txt = string.lower(desc.Text or "")
                                    if string.find(txt, "trade request") or string.find(txt, "sent you a trade") then
                                        has_request = true
                                        break
                                    end
                                end
                            end
                            if has_request then break end
                        end
                    end
                end

                if has_request then
                    -- Jalankan 2-3x multi-hit accept secara berurutan sampai ter-accept
                    for attempt = 1, 3 do
                        -- Cek apakah sudah berhasil masuk ke TradeApp (artinya accept sukses)
                        local curTradeApp = pGui:FindFirstChild("TradeApp")
                        if curTradeApp and curTradeApp.Enabled then
                            break
                        end

                        -- 1. Panggil Remote Resmi Adopt Me ke semua pemain lain
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

                        -- 2. Klik semua tombol Accept yang terdeteksi
                        local btns_to_click = find_trade_request_accept_buttons(pGui)
                        for _, btn in ipairs(btns_to_click) do
                            force_click_button(btn)
                        end

                        -- 3. Jeda singkat 120ms sebelum retry berikutnya (jika belum ke-accept)
                        if attempt < 3 then
                            task.wait(0.12)
                        end
                    end
                end
            end

            -- ==========================================================
            -- B. TAHAP 1 & 2: AUTO-ACCEPT NEGOTIATION & AUTO-CONFIRM TRADE
            -- HANYA jika TradeApp aktif
            -- ==========================================================
            if is_trade_open then
                is_in_trade = true
                IS_IN_TRADE_ACTIVE = true

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
                        trade_has_confirmed = true
                        last_confirm_time = tick()
                    end
                end

                -- 2. GUI Layer: Traversal tombol di dalam TradeApp
                for _, desc in ipairs(tradeApp:GetDescendants()) do
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
                    elseif desc:IsA("TextLabel") or desc:IsA("TextButton") then
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

                        -- Tahap 2 Indikator: Masuk ke tahap konfirmasi (teks countdown/waiting/peringatan)
                        if string.find(txt, "waiting for") or string.find(txt, "menunggu") or string.find(txt, "safe trade") or string.find(txt, "unbalanced") then
                            trade_has_confirmed = true
                            last_confirm_time = tick()
                        end

                        -- Pop-up Peringatan Unbalanced Trade
                        if string.find(txt, "understand") or string.find(txt, "trade anyway") or string.find(txt, "proceed") or string.find(txt, "paham") then
                            local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                            if btn and btn.Visible then
                                force_click_button(btn)
                            end
                        end
                    end
                end
            else
                -- Jika jendela TradeApp baru saja tertutup (Trade telah usai / selesai)
                if is_in_trade then
                    is_in_trade = false
                    IS_IN_TRADE_ACTIVE = false
                    -- Jika trade tadi telah terkonfirmasi sukses, langsung jalankan auto-exit & rotasi!
                    if trade_has_confirmed and (tick() - last_confirm_time < 20) then
                        task.spawn(function()
                            handle_trade_completed_exit("TradeApp Ditutup Pasca-Konfirmasi")
                        end)
                    end
                    trade_has_confirmed = false
                end
            end

            -- C. TAHAP 3: DETEKSI BANNER NOTIFIKASI SUKSES TRADE (Adopt Me System Banner)
            if not TRADE_COMPLETED_SUCCESS then
                for _, name in ipairs({"NotificationsApp", "NotificationApp", "DialogApp", "HintsApp"}) do
                    local app = pGui:FindFirstChild(name)
                    if app and app.Enabled then
                        for _, desc in ipairs(app:GetDescendants()) do
                            if desc:IsA("TextLabel") and desc.Visible then
                                local txt = string.lower(desc.Text or "")
                                if string.find(txt, "trade was successful") 
                                    or string.find(txt, "trade successful") 
                                    or string.find(txt, "the trade was successful")
                                    or string.find(txt, "trade completed") 
                                    or string.find(txt, "trade complete") 
                                    or string.find(txt, "you traded with")
                                    or string.find(txt, "pertukaran berhasil")
                                    or string.find(txt, "trade berhasil") then
                                    task.spawn(function()
                                        handle_trade_completed_exit("Notifikasi: " .. tostring(desc.Text))
                                    end)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end)

-- Deteksi log pesan Trade Selesai dari Console / LogService (Zeke Hub / Adopt Me Engine)
local LogService = game:GetService("LogService")
pcall(function()
    LogService.MessageOut:Connect(function(msg, msgType)
        if TRADE_COMPLETED_SUCCESS then return end
        if not msg or type(msg) ~= "string" then return end
        local lower = string.lower(msg)
        if string.find(lower, "trade was successful")
            or string.find(lower, "trade successful")
            or string.find(lower, "the trade was successful")
            or string.find(lower, "trade completed") 
            or string.find(lower, "trade complete") 
            or string.find(lower, "all trades completed")
            or string.find(lower, "successfully traded")
            or string.find(lower, "pertukaran berhasil")
            or string.find(lower, "trade berhasil") then
            task.spawn(function()
                handle_trade_completed_exit("Console Log: " .. tostring(msg))
            end)
        end
    end)
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
-- 3. ENGINE AUTO-KICK SETELAH SELESAI LOADING SAVE & MASUK IN-GAME (ZERO FREEZE)
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

    print("[DIKA REJOIN] ⏳ Mendeteksi Status In-Game Adopt Me...")

    -- Fungsi cek in-game yang super cepat (0.002ms, tanpa traversal 30.000 objek)
    local function check_if_ingame()
        -- 1. Tutup pop-up age check / verify prompt jika muncul di layar
        pcall(function()
            local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
            if promptGui then
                local overlay = promptGui:FindFirstChild("promptOverlay")
                if overlay and overlay.Visible then
                    for _, child in ipairs(overlay:GetChildren()) do
                        if child.Visible then
                            for _, b in ipairs(child:GetDescendants()) do
                                if b:IsA("GuiButton") and b.Visible then
                                    local bname = string.lower(b.Name or "")
                                    if string.find(bname, "cancel") or string.find(bname, "close") or string.find(bname, "later") then
                                        force_click_button(b)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)

        -- 2. Cek apakah GUI utama in-game Adopt Me sudah aktif
        local bottomBar = pGui:FindFirstChild("BottomBarApp")
        local roleChooser = pGui:FindFirstChild("RoleChooserApp")
        local houseApp = pGui:FindFirstChild("HouseApp")
        local newsApp = pGui:FindFirstChild("NewsApp")

        if (bottomBar and bottomBar.Enabled) or (roleChooser and roleChooser.Enabled) or (houseApp and houseApp.Enabled) or (newsApp and newsApp.Enabled) then
            return true
        end

        -- 3. Karakter sudah spawn di Workspace
        local char = lp.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
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

    -- Sinkronisasi ulang config async di background
    sync_config_from_suite()

    -- ==============================================================================
    -- AUTO-DETECT MULTI-BOT DYNAMIC TIMER (AUTO-SCALING 2x / nx)
    -- ==============================================================================
    local base_duration = AUTO_KICK_SECONDS
    local initial_bots = get_other_players_count()
    CURRENT_BOTS_DETECTED = math.max(1, initial_bots)
    CURRENT_TARGET_DURATION = base_duration * CURRENT_BOTS_DETECTED

    if CURRENT_BOTS_DETECTED >= 2 then
        print(string.format("[DIKA REJOIN] 👥 Terdeteksi %d Bot di server selain kita! Waktu in-game otomatis bertambah menjadi %dx lipat (%d detik).", CURRENT_BOTS_DETECTED, CURRENT_BOTS_DETECTED, CURRENT_TARGET_DURATION))
    else
        print(string.format("[DIKA REJOIN] ⏱️ Terdeteksi %d Bot di server. Waktu in-game normal: %d detik.", CURRENT_BOTS_DETECTED, CURRENT_TARGET_DURATION))
    end

    send_webhook("player_ingame_ready", {
        username = lp.Name,
        userId = tostring(lp.UserId),
        bot_count = CURRENT_BOTS_DETECTED,
        kick_duration = CURRENT_TARGET_DURATION
    })

    -- Deteksi dinamis real-time jika ada bot baru yang masuk ke server di tengah countdown
    local conn_player_added = Players.PlayerAdded:Connect(function(new_p)
        if new_p ~= lp then
            task.wait(0.5)
            local cur_bots = get_other_players_count()
            if cur_bots > CURRENT_BOTS_DETECTED then
                local old_dur = CURRENT_TARGET_DURATION
                CURRENT_BOTS_DETECTED = cur_bots
                CURRENT_TARGET_DURATION = base_duration * CURRENT_BOTS_DETECTED
                print(string.format("[DIKA REJOIN] ➕ Bot baru bergabung ('%s')! Total terdeteksi %d Bot. Durasi otomatis diperpanjang dari %ds -> %ds (%dx lipat)!", new_p.Name, CURRENT_BOTS_DETECTED, old_dur, CURRENT_TARGET_DURATION, CURRENT_BOTS_DETECTED))
            end
        end
    end)

    local start_tick = tick()
    local paused_time = 0
    local is_currently_paused = false

    while true do
        -- 1. Jika trade telah selesai terkonfirmasi, hentikan countdown seketika!
        if TRADE_COMPLETED_SUCCESS then
            print("[DIKA REJOIN] 🛑 Countdown dihentikan: Trade telah berhasil diselesaikan!")
            break
        end

        -- 2. Jika sedang berada dalam sesi Trade aktif, jeda (pause) countdown timer!
        if IS_IN_TRADE_ACTIVE then
            if not is_currently_paused then
                print("[DIKA REJOIN] ⏸️ Sedang dalam sesi Trade aktif! Timer Auto-Kick dijeda (paused) agar tidak kick di tengah trade...")
                is_currently_paused = true
            end
            task.wait(0.5)
            paused_time = paused_time + 0.5
        else
            if is_currently_paused then
                print("[DIKA REJOIN] ▶️ Sesi Trade selesai / jendela tertutup. Melanjutkan sisa waktu Auto-Kick...")
                is_currently_paused = false
            end

            local elapsed = math.floor((tick() - start_tick) - paused_time)
            local remaining = CURRENT_TARGET_DURATION - elapsed

            if remaining <= 0 then
                break
            end

            -- Cetak countdown berkala (setiap 5 detik atau saat mendekati akhir)
            if remaining % 5 == 0 or remaining <= 3 then
                local live_bots = get_other_players_count()
                local bot_info = live_bots >= 2 and string.format(" [%d Bot - %dx Durasi]", live_bots, CURRENT_BOTS_DETECTED) or ""
                print(string.format("[DIKA REJOIN] ⏱️ Auto-Kick dalam: %d detik...%s", remaining, bot_info))
            end

            task.wait(1)
        end
    end

    pcall(function()
        if conn_player_added then
            conn_player_added:Disconnect()
        end
    end)

    -- HANYA jalankan timeout kick jika trade belum pernah selesai sebelumnya (Safety Fallback)
    if not TRADE_COMPLETED_SUCCESS then
        print(string.format("[DIKA REJOIN] 🚪 Waktu %d detik in-game (%d Bot) tercapai (Safety Timeout)! Menjalankan Auto-Kick...", CURRENT_TARGET_DURATION, CURRENT_BOTS_DETECTED))
        notify_tool_and_exit(string.format("Auto-Kick %ds (%d Bot) In-Game Selesai", CURRENT_TARGET_DURATION, CURRENT_BOTS_DETECTED))

        -- Beri jeda 0.5s agar Python menyelesaikan penutupan proses secara mulus tanpa menampilkan pop-up Disconnected
        task.wait(0.5)
        pcall(function()
            lp:Kick(string.format("[DIKA REJOIN] Selesai Sesi Trade (Auto-Kick %ds - %d Bot)", CURRENT_TARGET_DURATION, CURRENT_BOTS_DETECTED))
        end)
    end
end)

print("[DIKA REJOIN] Auto-Detect Kick, Live Tab Sync, Auto-Accept & Auto-Confirm Trade Pro Aktif (Ultra-Fast 60FPS)!")