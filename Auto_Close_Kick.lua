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
            userId = tostring(lp.UserId),
            in_trade = IS_IN_TRADE_ACTIVE
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

-- Helper mencari elemen tombol yang dapat diklik dari GuiObject apa pun
local function resolve_gui_button(obj)
    if not obj then return nil end
    if obj:IsA("GuiButton") then return obj end
    local p = obj:FindFirstAncestorWhichIsA("GuiButton")
    if p then return p end
    local c = obj:FindFirstChildWhichIsA("GuiButton", true)
    if c then return c end
    return obj
end

local function force_click_button(btn)
    if not btn then return false end
    local target = resolve_gui_button(btn)
    if not target then return false end

    local clicked = false

    -- A. Firesignal jika didukung executor (instan 0 ms)
    pcall(function()
        if firesignal then
            if target:IsA("GuiButton") then
                firesignal(target.Activated)
                firesignal(target.MouseButton1Click)
                firesignal(target.MouseButton1Down)
                firesignal(target.MouseButton1Up)
            end
            if btn ~= target and btn:IsA("GuiObject") then
                pcall(function() firesignal(btn.Activated) end)
                pcall(function() firesignal(btn.MouseButton1Click) end)
            end
            clicked = true
        end
    end)

    -- B. getconnections (sangat andal di berbagai executor)
    pcall(function()
        if getconnections then
            local function fire_conns(sig)
                for _, conn in ipairs(getconnections(sig)) do
                    pcall(function() conn:Fire() end)
                    pcall(function()
                        if conn.Function and type(conn.Function) == "function" then
                            conn.Function()
                        end
                    end)
                    clicked = true
                end
            end
            if target:IsA("GuiButton") then
                fire_conns(target.MouseButton1Click)
                fire_conns(target.Activated)
                fire_conns(target.MouseButton1Down)
                fire_conns(target.MouseButton1Up)
            end
            if btn ~= target and btn:IsA("GuiObject") then
                pcall(function() fire_conns(btn.MouseButton1Click) end)
                pcall(function() fire_conns(btn.Activated) end)
            end
        end
    end)

    -- C. Virtual Input Asli Roblox Engine (Sintetik Mouse Click)
    pcall(function()
        local obj_for_pos = (target:IsA("GuiObject") and target) or (btn:IsA("GuiObject") and btn)
        if obj_for_pos and obj_for_pos.AbsolutePosition and obj_for_pos.AbsoluteSize then
            local cx = obj_for_pos.AbsolutePosition.X + (obj_for_pos.AbsoluteSize.X / 2)
            local cy = obj_for_pos.AbsolutePosition.Y + (obj_for_pos.AbsoluteSize.Y / 2)
            if VirtualInputManager then
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                task.wait(0.02)
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
                clicked = true
            elseif VirtualUser then
                VirtualUser:Button1Down(Vector2.new(cx, cy))
                task.wait(0.02)
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

-- Helper memanggil remote internal Adopt Me via RouterClient (Engine Resmi)
local function call_router_client(name, ...)
    local ok, res = false, nil
    pcall(function(...)
        local Fsys = require(ReplicatedStorage.Fsys).load
        local RouterClient = Fsys("RouterClient")
        if RouterClient then
            local r = RouterClient.get(name)
            if r then
                ok, res = safe_call_remote(r, ...)
            end
        end
    end, ...)
    return ok, res
end

-- Helper Deteksi Objek GUI Ter-Render Fisik di Layar (Bukan Hidden Parent / Off-Screen)
local function is_gui_physically_rendered(obj)
    if not obj or not obj:IsA("GuiObject") then return false end
    if not obj.Visible then return false end
    if obj.AbsoluteSize.X < 10 or obj.AbsoluteSize.Y < 10 then return false end
    local pos = obj.AbsolutePosition
    if pos.X < -150 or pos.Y < -150 or pos.X > 4000 or pos.Y > 4000 then return false end
    local p = obj.Parent
    while p and p:IsA("GuiObject") do
        if not p.Visible then return false end
        p = p.Parent
    end
    if p and p:IsA("LayerCollector") and not p.Enabled then
        return false
    end
    return true
end

-- Helper Cek State Trade Resmi dari ClientData Adopt Me Engine (Fsys)
local function check_clientdata_trade_active()
    local active = false
    pcall(function()
        local Fsys = require(ReplicatedStorage.Fsys).load
        local ClientData = Fsys("ClientData")
        if ClientData then
            local trd = ClientData.get("trade") or ClientData.get("active_trade")
            if trd and type(trd) == "table" and (trd.sender or trd.recipient or trd.partner or trd.state or trd.items) then
                active = true
            end
        end
    end)
    return active
end

-- Deteksi Presisi Jendela Trade: HANYA dianggap open jika ClientData aktif atau GUI Modal benar-benar TERENDER FISIK di layar!
local function check_is_trade_actually_open(pGui)
    -- 1. Cek State Internal Adopt Me Engine (Paling Akurat)
    if check_clientdata_trade_active() then
        return true
    end

    -- 2. Cek GUI Layer: Harus ada modal transaksi yang benar-benar aktif di layar
    local target_pGui = pGui
    if not target_pGui then
        local lp = Players.LocalPlayer
        target_pGui = lp and lp:FindFirstChild("PlayerGui")
    end
    if not target_pGui then return false end

    local tradeApp = target_pGui:FindFirstChild("TradeApp")
    if not tradeApp or not tradeApp.Enabled then return false end

    -- Cek tombol transaksi fisik di dalam TradeApp yang benar-benar ter-render di layar
    for _, desc in ipairs(tradeApp:GetDescendants()) do
        if desc:IsA("GuiButton") and is_gui_physically_rendered(desc) then
            local n = string.lower(desc.Name or "")
            local txt = string.lower(desc:IsA("TextButton") and desc.Text or "")
            if string.find(n, "accept") or string.find(n, "confirm") or string.find(n, "decline")
                or string.find(txt, "accept") or string.find(txt, "confirm") or string.find(txt, "terima") or string.find(txt, "konfirmasi") then
                return true
            end
        end
    end

    -- Cek label status transaksi spesifik yang ter-render di layar
    for _, desc in ipairs(tradeApp:GetDescendants()) do
        if desc:IsA("TextLabel") and is_gui_physically_rendered(desc) then
            local txt = string.lower(desc.Text or "")
            if string.find(txt, "your offer") or string.find(txt, "their offer")
                or string.find(txt, "tawaran anda") or string.find(txt, "tawaran mereka")
                or string.find(txt, "safe trade") or string.find(txt, "unbalanced") then
                return true
            end
        end
    end

    return false
end

-- Helper resmi eksekusi Accept Trade Request Adopt Me (Remote + GUI Click)
local LAST_ACCEPTED_TRADE_T = 0
local function accept_incoming_trade_request(sender, accept_btn)
    local now_t = tick()
    if (now_t - LAST_ACCEPTED_TRADE_T) < 0.3 then return end
    LAST_ACCEPTED_TRADE_T = now_t

    local sName = sender and (sender.Name .. " (" .. sender.DisplayName .. ")") or "Pengirim Terdeteksi (Tombol GUI)"
    print(string.format("[DIKA REJOIN] 🤝 TERDETEKSI PERMINTAAN TRADE DARI: %s! Menjalankan Accept...", sName))

    task.spawn(function()
        for attempt = 1, 3 do
            if check_is_trade_actually_open() or TRADE_COMPLETED_SUCCESS then break end

            -- 1. Direct API Layer (Adopt Me ReplicatedStorage.API["TradeAPI/AcceptOrDeclineTradeRequest"]:InvokeServer)
            -- Tepat sesuai packet Remote Spy: args = { [1] = Player, [2] = true }
            if sender and typeof(sender) == "Instance" and sender:IsA("Player") then
                pcall(function()
                    local api = ReplicatedStorage:FindFirstChild("API")
                    if not api then api = ReplicatedStorage:WaitForChild("API", 1) end
                    if api then
                        local reqRemote = api:FindFirstChild("TradeAPI/AcceptOrDeclineTradeRequest")
                        if not reqRemote then reqRemote = api:WaitForChild("TradeAPI/AcceptOrDeclineTradeRequest", 1) end
                        if reqRemote and reqRemote:IsA("RemoteFunction") then
                            reqRemote:InvokeServer(sender, true)
                        end
                    end
                end)
            else
                -- Fallback: jika sender belum teridentifikasi dari teks kartu tapi tombol Accept ada di layar
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Players.LocalPlayer then
                        pcall(function()
                            local api = ReplicatedStorage:FindFirstChild("API")
                            if api and api:FindFirstChild("TradeAPI/AcceptOrDeclineTradeRequest") then
                                api["TradeAPI/AcceptOrDeclineTradeRequest"]:InvokeServer(p, true)
                            end
                        end)
                    end
                end
            end

            -- 2. Klik Fisik Tombol Accept di GUI jika ditemukan
            if accept_btn then
                force_click_button(accept_btn)
            end

            if attempt < 3 then
                task.wait(0.15)
            end
        end
    end)
end

-- Helper mengenali teks permintaan trade (bahasa Inggris & Indonesia)
local function is_trade_request_text(txt)
    if not txt or type(txt) ~= "string" then return false end
    local l = string.lower(txt)
    if string.find(l, "trade request")
        or string.find(l, "sent you a trade")
        or string.find(l, "wants to trade")
        or string.find(l, "trade invitation")
        or string.find(l, "trade with")
        or string.find(l, "sent a trade")
        or string.find(l, "pertukaran")
        or string.find(l, "ingin bertukar")
        or string.find(l, "permintaan")
        or (string.find(l, "trade") and (string.find(l, "with") or string.find(l, "req") or string.find(l, "?") or string.find(l, "invit"))) then
        return true
    end
    return false
end

-- Helper mengenali tombol Decline / Cancel / Tolak
local function is_decline_button(b)
    if not b then return false end
    local n = string.lower(b.Name or "")
    local all_texts = {}
    if b:IsA("TextButton") and b.Text then table.insert(all_texts, string.lower(b.Text)) end
    if b:IsA("TextLabel") and b.Text then table.insert(all_texts, string.lower(b.Text)) end
    for _, d in ipairs(b:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text then
            table.insert(all_texts, string.lower(d.Text))
        end
    end
    local combined = table.concat(all_texts, " ")

    if string.find(n, "decline") or string.find(n, "cancel") or string.find(n, "reject") or string.find(n, "batal") or string.find(n, "tolak")
        or string.find(combined, "decline") or string.find(combined, "cancel") or string.find(combined, "reject") or string.find(combined, "batal") or string.find(combined, "tolak")
        or (combined == "x") or (n == "x") or (n == "closebutton") or (n == "nobutton") then
        return true
    end

    -- Cek warna merah pada tombol atau anaknya
    local function is_color_red(c)
        return c and (c.R > 0.55 and c.R > (c.G * 1.4) and c.R > (c.B * 1.4))
    end
    if b:IsA("GuiObject") and is_color_red(b.BackgroundColor3) then return true end
    if b:IsA("ImageButton") and is_color_red(b.ImageColor3) then return true end
    for _, d in ipairs(b:GetDescendants()) do
        if d:IsA("GuiObject") and is_color_red(d.BackgroundColor3) then return true end
        if d:IsA("ImageButton") and is_color_red(d.ImageColor3) then return true end
    end

    return false
end

-- Helper mengenali tombol Accept / Terima / Ya
local function is_accept_button(b)
    if not b then return false end
    if is_decline_button(b) then return false end

    local n = string.lower(b.Name or "")
    local all_texts = {}
    if b:IsA("TextButton") and b.Text then table.insert(all_texts, string.lower(b.Text)) end
    if b:IsA("TextLabel") and b.Text then table.insert(all_texts, string.lower(b.Text)) end
    for _, d in ipairs(b:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text then
            table.insert(all_texts, string.lower(d.Text))
        end
    end
    local combined = table.concat(all_texts, " ")

    -- 1. Cek kecocokan teks
    if string.find(combined, "accept")
        or string.find(combined, "terima")
        or string.find(combined, "yes")
        or string.find(combined, "ya")
        or string.find(combined, "trade")
        or string.find(combined, "ok")
        or string.find(combined, "setuju")
        or string.find(combined, "✓")
        or string.find(combined, "✔") then
        return true
    end

    -- 2. Cek nama
    if string.find(n, "accept")
        or string.find(n, "green")
        or string.find(n, "yes")
        or string.find(n, "trade")
        or string.find(n, "agree")
        or string.find(n, "confirm")
        or string.find(n, "action")
        or string.find(n, "right") then
        return true
    end

    -- 3. Cek warna hijau pada tombol atau anak-anaknya
    local function is_color_green(c)
        return c and (c.G > 0.4 and c.G > (c.R * 1.1) and c.G > (c.B * 1.1))
    end
    if b:IsA("GuiObject") and is_color_green(b.BackgroundColor3) then return true end
    if b:IsA("ImageButton") and is_color_green(b.ImageColor3) then return true end
    for _, d in ipairs(b:GetDescendants()) do
        if d:IsA("GuiObject") and is_color_green(d.BackgroundColor3) then return true end
        if d:IsA("ImageButton") and is_color_green(d.ImageColor3) then return true end
    end

    return false
end

-- Helper deteksi dialog kartu permintaan trade masuk (Sticky Note / Dialog / Notification)
local function find_active_trade_request(pGui)
    if not pGui then return nil, nil end
    if check_is_trade_actually_open() then return nil, nil end

    local function inspect_dialog_container(container)
        if not container or not container:IsA("GuiObject") then return nil, nil end
        if not container.Visible then return nil, nil end

        local texts = {}
        local accept_btn = nil
        local has_decline = false

        for _, d in ipairs(container:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text and #d.Text > 0 then
                table.insert(texts, string.lower(d.Text))
            end
            if (d:IsA("GuiButton") or d:IsA("TextLabel")) and d.Visible then
                if is_decline_button(d) then
                    has_decline = true
                elseif is_accept_button(d) and not accept_btn then
                    accept_btn = resolve_gui_button(d)
                end
            end
        end

        local combined = table.concat(texts, " ")
        local is_trade = string.find(combined, "trade") or string.find(combined, "pertukaran") or string.find(combined, "tukar")

        -- Kartu permintaan trade valid jika: ada tombol Accept DAN (ada teks trade ATAU ada tombol Decline)
        if accept_btn and (is_trade or (has_decline and (string.find(combined, "sent") or string.find(combined, "request")))) then
            local matched_player = nil

            -- Cara 1: Ekstrak username langsung dari teks kartu (misal: 'robert90 sent you a trade request')
            local captured = string.match(combined, "([%w_]+)%s+sent") or string.match(combined, "([%w_]+)%s+wants")
            if captured then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Players.LocalPlayer and string.lower(p.Name) == string.lower(captured) then
                        matched_player = p
                        break
                    end
                end
            end

            -- Cara 2: Cocokkan username atau display name seluruh pemain lain di server
            if not matched_player then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Players.LocalPlayer then
                        local pName = string.lower(p.Name)
                        local dName = string.lower(p.DisplayName)
                        if string.find(combined, pName, 1, true) or string.find(combined, dName, 1, true) then
                            matched_player = p
                            break
                        end
                    end
                end
            end

            -- Cara 3: Jika di server hanya ada 1 pemain lain (1v1 trade / private server)
            if not matched_player then
                local others = {}
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Players.LocalPlayer then
                        table.insert(others, p)
                    end
                end
                if #others == 1 then
                    matched_player = others[1]
                end
            end

            return matched_player, accept_btn
        end

        return nil, nil
    end

    -- 1. Prioritas Utama: Periksa DialogApp (lokasi resmi Sticky Note Adopt Me)
    local dialogApp = pGui:FindFirstChild("DialogApp")
    if dialogApp and dialogApp.Enabled then
        for _, child in ipairs(dialogApp:GetChildren()) do
            if child:IsA("GuiObject") then
                local p, b = inspect_dialog_container(child)
                if p or b then return p, b end
            end
        end
        local p, b = inspect_dialog_container(dialogApp)
        if p or b then return p, b end
    end

    -- 2. Periksa ScreenGui lainnya di PlayerGui (di luar TradeApp)
    for _, sg in ipairs(pGui:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled and sg.Name ~= "TradeApp" and sg.Name ~= "DialogApp" then
            for _, child in ipairs(sg:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible then
                    local p, b = inspect_dialog_container(child)
                    if p or b then return p, b end
                end
            end
        end
    end

    -- 3. Fallback: Telusuri dari semua tombol Accept yang terlihat
    for _, desc in ipairs(pGui:GetDescendants()) do
        if desc:IsA("GuiButton") and desc.Visible and is_accept_button(desc) then
            local inTradeApp = desc:FindFirstAncestor("TradeApp")
            if not inTradeApp then
                local anc = desc.Parent
                while anc and anc ~= pGui and not anc:IsA("ScreenGui") do
                    local p, b = inspect_dialog_container(anc)
                    if p or b then return p, b end
                    anc = anc.Parent
                end
            end
        end
    end

    return nil, nil
end

local function check_and_accept_incoming_trade(pGui)
    if not pGui then return false end
    if check_is_trade_actually_open() then return false end

    local sender, btn = find_active_trade_request(pGui)
    if sender or btn then
        accept_incoming_trade_request(sender, btn)
        return true
    end
    return false
end

-- Helper otomatis menutup welcome screen (NewsApp / Play!) & RoleChooserApp (Babies)
local function auto_dismiss_welcome_screens(pGui)
    if not pGui then return end

    -- 1. NewsApp (Play! Button)
    local newsApp = pGui:FindFirstChild("NewsApp")
    if newsApp and newsApp.Enabled then
        for _, desc in ipairs(newsApp:GetDescendants()) do
            if (desc:IsA("GuiButton") or desc:IsA("TextLabel")) and desc.Visible then
                local txt = string.lower((desc:IsA("TextButton") and desc.Text) or (desc:IsA("TextLabel") and desc.Text) or desc.Name or "")
                for _, lbl in ipairs(desc:GetDescendants()) do
                    if lbl:IsA("TextLabel") and lbl.Text then
                        txt = txt .. " " .. string.lower(lbl.Text)
                    end
                end
                if string.find(txt, "play") then
                    local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                    if btn and btn.Visible then
                        force_click_button(btn)
                    end
                end
            end
        end
        pcall(function() newsApp.Enabled = false end)
    end

    -- 2. RoleChooserApp (Parent / Baby)
    local roleChooser = pGui:FindFirstChild("RoleChooserApp")
    if roleChooser and roleChooser.Enabled then
        call_router_client("TeamAPI/ChooseTeam", "Babies")
        pcall(function()
            if API and API:FindFirstChild("TeamAPI/ChooseTeam") then
                safe_call_remote(API["TeamAPI/ChooseTeam"], "Babies")
            end
        end)
        for _, desc in ipairs(roleChooser:GetDescendants()) do
            if (desc:IsA("GuiButton") or desc:IsA("TextLabel")) and desc.Visible then
                local txt = string.lower((desc:IsA("TextButton") and desc.Text) or (desc:IsA("TextLabel") and desc.Text) or desc.Name or "")
                for _, lbl in ipairs(desc:GetDescendants()) do
                    if lbl:IsA("TextLabel") and lbl.Text then
                        txt = txt .. " " .. string.lower(lbl.Text)
                    end
                end
                if string.find(txt, "baby") or string.find(txt, "parent") then
                    local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                    if btn and btn.Visible then
                        force_click_button(btn)
                    end
                end
            end
        end
        pcall(function() roleChooser.Enabled = false end)
    end

    -- 3. DailyLoginApp (Klaim Login Harian jika menghalangi)
    local dailyApp = pGui:FindFirstChild("DailyLoginApp")
    if dailyApp and dailyApp.Enabled then
        for _, desc in ipairs(dailyApp:GetDescendants()) do
            if (desc:IsA("GuiButton") or desc:IsA("TextLabel")) and desc.Visible then
                local txt = string.lower((desc:IsA("TextButton") and desc.Text) or (desc:IsA("TextLabel") and desc.Text) or desc.Name or "")
                if string.find(txt, "claim") or string.find(txt, "klaim") or string.find(txt, "ok") then
                    local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                    if btn and btn.Visible then
                        force_click_button(btn)
                    end
                end
            end
        end
        pcall(function() dailyApp.Enabled = false end)
    end
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

    -- LANGSUNG PASANG EVENT LISTENER 0ms TANPA MENUNGGU JEDA!
    pcall(function()
        pGui.DescendantAdded:Connect(function(desc)
            if TRADE_COMPLETED_SUCCESS then return end

            -- Deteksi instan trade request masuk (0ms trigger)
            if not IS_IN_TRADE_ACTIVE then
                local should_check = false
                if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("GuiButton") then
                    local t = string.lower(desc:IsA("TextLabel") and desc.Text or (desc:IsA("TextButton") and desc.Text or desc.Name or ""))
                    if is_trade_request_text(t) or is_accept_button(desc) or is_decline_button(desc) then
                        should_check = true
                    end
                elseif desc:IsA("GuiObject") and (desc.Name == "Dialog" or desc.Name == "Notification" or string.find(string.lower(desc.Name), "trade")) then
                    should_check = true
                end

                if should_check then
                    task.spawn(function()
                        check_and_accept_incoming_trade(pGui)
                    end)
                end
            end

            -- Deteksi instan notifikasi trade sukses
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

    -- EKSEKUSI ULTRA CEPAT SAAT MULAI (STARTUP ACCELERATOR 0ms - 5s):
    -- Menangani jika saat bot baru spawn, sudah ada welcome screen (NewsApp) & trade request masuk!
    task.spawn(function()
        for i = 1, 25 do
            if TRADE_COMPLETED_SUCCESS or IS_IN_TRADE_ACTIVE then break end
            auto_dismiss_welcome_screens(pGui)
            check_and_accept_incoming_trade(pGui)
            task.wait(0.2)
        end
    end)

    print("[DIKA REJOIN] 🤝 Auto-Accept & Auto-Confirm Trade Engine Siap & Aktif!")

    local is_in_trade = false
    local trade_has_confirmed = false
    local last_confirm_time = 0
    local initial_trade_history_count = nil

    pcall(function()
        local Fsys = require(ReplicatedStorage.Fsys).load
        local ClientData = Fsys("ClientData")
        if ClientData then
            local h = ClientData.get("trade_history") or ClientData.get("trades") or ClientData.get("trade_records")
            if h and type(h) == "table" then
                initial_trade_history_count = #h
                print("[DIKA REJOIN] 📜 Trade History awal tercatat: " .. tostring(initial_trade_history_count) .. " transaksi.")
            end
        end
    end)

    -- Loop Auto-Trade Ultra-Responsif (0.25 detik)
    while task.wait(0.25) do
        pcall(function()

            -- 1. Auto-Dismiss Welcome Screens (NewsApp & RoleChooserApp)
            auto_dismiss_welcome_screens(pGui)

            local is_trade_open = check_is_trade_actually_open(pGui)

            -- ==========================================================
            -- A. TAHAP 0: AUTO-ACCEPT PERMINTAAN TRADE MASUK (REQUEST)
            -- Bekerja sepanjang sesi game (termasuk detik awal startup)
            -- Hanya menerima jika terdeteksi ada permintaan trade nyata di layar!
            -- ==========================================================
            if not is_trade_open then
                check_and_accept_incoming_trade(pGui)
            end

            -- ==========================================================
            -- B. TAHAP 1 & 2: AUTO-ACCEPT NEGOTIATION & AUTO-CONFIRM TRADE
            -- HANYA jika TradeApp aktif
            -- ==========================================================
            if is_trade_open then
                if not is_in_trade then
                    is_in_trade = true
                    IS_IN_TRADE_ACTIVE = true
                    print("[DIKA REJOIN] 🤝 Jendela Trade Terbuka! Mengirim sinyal Trade Active (Shield) ke tools...")
                    send_webhook("trade_active", {
                        username = lp.Name,
                        userId = tostring(lp.UserId),
                        in_trade = true
                    })
                end
                IS_IN_TRADE_ACTIVE = true

                -- 1. Direct API Layer (Adopt Me ReplicatedStorage.API: FireServer)
                task.spawn(function()
                    pcall(function()
                        local api = ReplicatedStorage:FindFirstChild("API")
                        if not api then
                            pcall(function() api = ReplicatedStorage:WaitForChild("API", 2) end)
                        end
                        if api then
                            local acceptNeg = api:FindFirstChild("TradeAPI/AcceptNegotiation")
                            if not acceptNeg then
                                pcall(function() acceptNeg = api:WaitForChild("TradeAPI/AcceptNegotiation", 1) end)
                            end
                            if acceptNeg and acceptNeg:IsA("RemoteEvent") then
                                acceptNeg:FireServer()
                            end

                            local confirmTrd = api:FindFirstChild("TradeAPI/ConfirmTrade")
                            if not confirmTrd then
                                pcall(function() confirmTrd = api:WaitForChild("TradeAPI/ConfirmTrade", 1) end)
                            end
                            if confirmTrd and confirmTrd:IsA("RemoteEvent") then
                                confirmTrd:FireServer()
                                trade_has_confirmed = true
                                last_confirm_time = tick()
                            end
                        end
                    end)
                end)

                -- 2. RouterClient resmi Adopt Me Engine (Fsys)
                task.spawn(function()
                    pcall(function()
                        local Fsys = require(ReplicatedStorage:WaitForChild("Fsys")).load
                        local RouterClient = Fsys("RouterClient")
                        if RouterClient then
                            local accNeg = RouterClient.get("TradeAPI/AcceptNegotiation")
                            if accNeg then accNeg:FireServer() end

                            local confTrd = RouterClient.get("TradeAPI/ConfirmTrade")
                            if confTrd then
                                confTrd:FireServer()
                                trade_has_confirmed = true
                                last_confirm_time = tick()
                            end
                        end
                    end)
                end)

                -- 2. GUI Layer: Traversal tombol di dalam TradeApp
                local currentTradeApp = pGui:FindFirstChild("TradeApp")
                if currentTradeApp and currentTradeApp.Enabled then
                    for _, desc in ipairs(currentTradeApp:GetDescendants()) do
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
                end
            else
                -- Jika jendela TradeApp baru saja tertutup (Trade telah usai / selesai)
                if is_in_trade then
                    is_in_trade = false
                    IS_IN_TRADE_ACTIVE = false
                    print("[DIKA REJOIN] 🛡️ Sesi Trade Selesai / Jendela Tertutup. Mengirim status normal ke tools...")
                    send_webhook("trade_active", {
                        username = lp.Name,
                        userId = tostring(lp.UserId),
                        in_trade = false
                    })
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

            -- D. TAHAP 4: DETEKSI RESMI TRADE HISTORY (TRADING LICENSE / CLIENTDATA)
            -- Memantau pertambahan riwayat transaksi di Adopt Me Engine (100% Bukti Transaksi Selesai)
            if not TRADE_COMPLETED_SUCCESS then
                pcall(function()
                    local Fsys = require(ReplicatedStorage.Fsys).load
                    local ClientData = Fsys("ClientData")
                    if ClientData then
                        local h = ClientData.get("trade_history") or ClientData.get("trades") or ClientData.get("trade_records")
                        if h and type(h) == "table" then
                            local cur_count = #h
                            if initial_trade_history_count == nil then
                                initial_trade_history_count = cur_count
                            elseif cur_count > initial_trade_history_count then
                                print(string.format("[DIKA REJOIN] 📜 Deteksi Transaksi Baru di Trade History (%d -> %d)! Sukses Terkonfirmasi.", initial_trade_history_count, cur_count))
                                task.spawn(function()
                                    handle_trade_completed_exit(string.format("Tercatat di Trade History (#%d)", cur_count))
                                end)
                            end
                        end
                    end
                end)
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

    if string.find(lower, "different device", 1, true)
        or string.find(lower, "same account", 1, true)
        or string.find(lower, "264", 1, true)
        or string.find(lower, "273", 1, true)
        or string.find(lower, "267", 1, true)
        or string.find(lower, "268", 1, true)
        or string.find(lower, "277", 1, true)
        or string.find(lower, "279", 1, true)
        or string.find(lower, "524", 1, true)
        or string.find(lower, "529", 1, true)
        or string.find(lower, "kicked", 1, true)
        or string.find(lower, "disconnected", 1, true)
        or string.find(lower, "reconnect", 1, true)
        or string.find(lower, "lost connection", 1, true)
        or string.find(lower, "all trades completed", 1, true) then
        return true
    end
    return false
end

GuiService.ErrorMessageChanged:Connect(function(msg)
    if is_real_kick_or_disconnect(msg) then
        notify_tool_and_exit("ErrorMessageChanged: " .. tostring(msg))
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
            if promptGui then
                local overlay = promptGui:FindFirstChild("promptOverlay") or promptGui
                for _, desc in ipairs(overlay:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local txt = desc.Text
                        if txt and #txt > 0 and is_real_kick_or_disconnect(txt) then
                            notify_tool_and_exit("Prompt Detected: " .. tostring(txt))
                            return
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