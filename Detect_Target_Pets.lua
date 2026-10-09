-- ==============================================================================
-- DIKA REJOIN MANAGER PRO + ACCOUNTOPS IPC + ZEKE DUAL-ENGINE SCANNER (LUA)
-- Auto-Detects Target Pets, Summarizes Quantities & Sends IPC to Desktop + AccountOps Web
-- ==============================================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DESKTOP_TOOL_URL = "http://127.0.0.1:19999/inventory_sync"

    local TARGET_PET_KEYWORDS = {
        ["skelicorn"] = "🍓 Skelicorn",
        ["frostbite bear"] = "🍓 Frostbite Bear",
        ["frostbite_bear"] = "🍓 Frostbite Bear",
        ["frostbite"] = "🍓 Frostbite Bear",
        ["strawberry tortle"] = "🍓 Strawberry Tortle",
        ["strawberry_tortle"] = "🍓 Strawberry Tortle",
        ["dragonfruit fox"] = "🦊 Dragonfruit Fox",
        ["dragonfruit_fox"] = "🦊 Dragonfruit Fox",
        ["dragonfruit"] = "🦊 Dragonfruit Fox",
        ["dango penguins"] = "🍡 Dango Penguins",
        ["dango_penguins"] = "🍡 Dango Penguins",
        ["dango penguin"] = "🍡 Dango Penguins",
        ["dango_penguin"] = "🍡 Dango Penguins",
        ["dango"] = "🍡 Dango Penguins",
        ["gemstone egg"] = "Gemstone Egg",
        ["gemstone_egg"] = "Gemstone Egg",
        ["crystal egg"] = "Crystal Egg",
        ["crystal_egg"] = "Crystal Egg",
        ["jumpscare"] = "Jumpscare",
        ["mummy spider"] = "Mummy Spider",
        ["mummy_spider"] = "Mummy Spider",
        ["velocirooster"] = "🍓 Velocirooster",
        ["sushi penguin"] = "🐧 Sushi Penguin",
        ["sushi_penguin"] = "🐧 Sushi Penguin",
        ["kiwi kiwi"] = "🥝 Kiwi Kiwi",
        ["kiwi_kiwi"] = "🥝 Kiwi Kiwi",
        ["kiwi"] = "🥝 Kiwi Kiwi",
        ["little lamb"] = "🐑 Little Lamb",
        ["little_lamb"] = "🐑 Little Lamb",
        ["lamb"] = "🐑 Little Lamb",
        ["crimson cape"] = "🐑 Crimson Cape",
        ["crimson_cape"] = "🐑 Crimson Cape",
        ["pain au chat"] = "🐑 Pain Au Chat",
        ["pain_au_chat"] = "🐑 Pain Au Chat",
        ["three blind mice"] = "🐭 Three Blind Mice",
        ["three_blind_mice"] = "🐭 Three Blind Mice",
        ["blind mice"] = "🐭 Three Blind Mice",
        ["huntsman robin"] = "🏹 Huntsman Robin",
        ["huntsman_robin"] = "🏹 Huntsman Robin",
        ["chihuahua"] = "🐕 Chihuahua",
        ["purrowl"] = "🐱 Purrowl",
        ["2d box"] = "📦 2D Box",
        ["2d_box"] = "📦 2D Box",
        ["admin abuse egg"] = "Admin Abuse Egg",
        ["admin_abuse_egg"] = "Admin Abuse Egg",
        ["admin abuse"] = "Admin Abuse Egg",
        ["emberlight"] = "🔥 Emberlight",
        ["silverback gorilla"] = "🦍 Silverback Gorilla",
        ["silverback_gorilla"] = "🦍 Silverback Gorilla",
        ["gorilla"] = "🦍 Silverback Gorilla"
    }

local function get_local_player_inventory()
    local clientData = ReplicatedStorage:FindFirstChild("ClientModules") and ReplicatedStorage.ClientModules:FindFirstChild("Core") and require(ReplicatedStorage.ClientModules.Core.ClientData)
    if not clientData then return nil end
    local inv = clientData.get_data()[Players.LocalPlayer.Name] and clientData.get_data()[Players.LocalPlayer.Name].inventory
    return inv and inv.pets or nil
end

local function scan_and_report_pets()
    local pets = get_local_player_inventory()
    if not pets then return end

    local target_found = {}
    local summary = {}
    local total_targets = 0
    local total_pets = 0
    local accops_items = {}

    for id, p_data in pairs(pets) do
        total_pets = total_pets + 1
        local kind = string.lower(p_data.id or p_data.kind or "")
        local is_target = false
        local matched_name = kind

        for kw, display_name in pairs(TARGET_PET_KEYWORDS) do
            if string.find(kind, kw, 1, true) then
                total_targets = total_targets + 1
                summary[display_name] = (summary[display_name] or 0) + 1
                is_target = true
                matched_name = display_name
                table.insert(target_found, {
                    name = display_name,
                    raw_kind = kind,
                    age = p_data.properties and p_data.properties.age or 1
                })
                break
            end
        end

        if is_target then
            table.insert(accops_items, {
                name = kind,
                amount = 1,
                display_name = matched_name,
                rarity = "Legendary"
            } )
        end
    end

    -- 1. KIRIM KE DESKTOP SUITE DIKA REJOIN (Lokal IPC / Webhook)
    local payload = {
        username = Players.LocalPlayer.Name,
        total_all_pets = total_pets,
        total_target_pets = total_targets,
        summary = summary,
        pet_items = target_found
    }

    local body = HttpService:JSONEncode(payload)
    pcall(function()
        if syn and syn.request then
            syn.request({Url = DESKTOP_TOOL_URL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
        elseif request then
            request({Url = DESKTOP_TOOL_URL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
        elseif http and http.request then
            http.request({Url = DESKTOP_TOOL_URL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
        elseif http_request then
            http_request({Url = DESKTOP_TOOL_URL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
        end
    end)

    -- 2. KIRIM KE ACCOUNTOPS IPC (Dashboard Web AccountOps)
    pcall(function()
        if getgenv().AccopsIPC and getgenv().AccopsIPC.send then
            getgenv().AccopsIPC.send({
                player = Players.LocalPlayer.Name,
                game = "adoptmecostum",
                total_pets = total_pets,
                target_pets = total_targets,
                items = accops_items
            })
        end
    end)
end

task.spawn(function()
    while task.wait(5) do
        pcall(scan_and_report_pets)
    end
end)

print("[DIKA REJOIN + ACCOPS] Dual-Engine Scanner Aktif! Memindai target pets...")
