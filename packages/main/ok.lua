-- == Fish It • RBXGeneral -> Telegram (PHOTO) + Anti-AFK + Mythic/Secret filter ==
-- GUI kanan-bawah + draggable + status FILE/HTTP/CH. Kirim FOTO ke Telegram (sendPhoto).
-- Hanya kirim jika ikan ada di DB dan rarity = Mythic/Secret.

-- ========= CONFIG =========
local CHANNEL_NAME   = "RBXGeneral"
local KEYWORDS       = { "obtained a", "obtained an" } -- minimal filter
local RESCAN_STATUS  = 0.5

-- Telegram
local BOT_TOKEN = "7932832208:AAFXAMhRg1xuUBKtUECmN0r7uwdtjZZJGfY"
local CHAT_ID   = "-1002908443693"

-- ========= EXECUTOR APIS (compat) =========
local G = getgenv and getgenv() or _G
local writefile  = writefile  or (G and G.writefile)
local appendfile = appendfile or (G and G.appendfile)
local readfile   = readfile   or (G and G.readfile)
local isfile     = isfile     or (G and G.isfile)     or function(_) return false end
local makefolder = makefolder or (G and G.makefolder) or function(_) end
local isfolder   = isfolder   or (G and G.isfolder)   or function(_) return false end
local requestFn  = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)

local HttpService     = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local Players         = game:GetService("Players")
local UserInputService= game:GetService("UserInputService")
local VirtualUser     = game:GetService("VirtualUser")
local lp              = Players.LocalPlayer

local function jenc(t) return HttpService:JSONEncode(t) end
local function jdec(s) local ok,res=pcall(function() return HttpService:JSONDecode(s) end) return ok and res or nil end

-- ========= FILE BASE (workspace first) =========
local function ensureFolder(path)
    if isfolder(path) then return true end
    local ok = pcall(makefolder, path)
    return ok and isfolder(path)
end
local BASE = "workspace/fishit_logs"
if not ensureFolder(BASE) then BASE = "fishit_logs"; ensureFolder(BASE) end
local function P(name) return (BASE.."/"..name) end

local LOG_FILE   = P("rbxgeneral_mythic_secret.txt")
local DBG_FILE   = P("debug.txt")
local CACHE_FILE = P("sent_cache.json")

local FILE_OK = (writefile and appendfile and isfile and makefolder) and true or false
if FILE_OK then
    if not isfile(LOG_FILE) then pcall(writefile, LOG_FILE, "# start\n") end
    if not isfile(DBG_FILE) then pcall(writefile, DBG_FILE, "# debug\n") end
end
local HTTP_OK = (requestFn ~= nil)

local function dbg(...)
    local s = table.concat({...}, " ")
    print("[DBG]", s)
    if FILE_OK then pcall(appendfile, DBG_FILE, os.date("[%H:%M:%S] ")..s.."\n") end
end

-- ========= DB Mythic/Secret (dari kamu) =========
local RAW_LIST = {
    {"Lost Isle","Blob Fish","Mythic","https://assets.antibokeh.com/fish/blob-fish.png"},
    {"Lost Isle","Giant Squid","Secret","https://assets.antibokeh.com/fish/giant-squid.png"},
    {"Lost Isle","Robot Kraken","Secret","https://assets.antibokeh.com/fish/robot-kraken.png"},
    {"Lost Isle","Queen Crab","Secret","https://assets.antibokeh.com/fish/queen-crab.png"},
    {"Lost Isle","King Crab","Secret","https://assets.antibokeh.com/fish/king-crab.png"},

    {"Ocean","Manta Ray","Mythic","https://assets.antibokeh.com/fish/manta-ray.png"},
    {"Ocean","Hammerhead Shark","Mythic","https://assets.antibokeh.com/fish/hammerhead-shark.png"},
    {"Ocean","Blob Shark","Secret","https://assets.antibokeh.com/fish/blob-shark.png"},
    {"Ocean","Ghost Shark","Secret","https://assets.antibokeh.com/fish/ghost-shark.png"},
    {"Ocean","Worm Fish","Secret","https://assets.antibokeh.com/fish/worm-fish.png"},

    {"Konoha","Loggerhead Turtle","Mythic","https://assets.antibokeh.com/fish/loggerhead-turtle.png"},
    {"Konoha","Prismy Seahorse","Mythic","https://assets.antibokeh.com/fish/prismy-seahorse.png"},

    {"Kohona Volcano","Blueflame Ray","Mythic","https://assets.antibokeh.com/fish/blueflame-ray.png"},

    {"Coral Reefs","Hawks Turtle","Mythic","https://assets.antibokeh.com/fish/hawks-turtle.png"},
    {"Coral Reefs","Luminous Fish","Mythic","https://assets.antibokeh.com/fish/luminous-fish.png"},
    {"Coral Reefs","Monster Shark","Secret","https://assets.antibokeh.com/fish/monster-shark.png"},
    {"Coral Reefs","Eerie Shark","Secret","https://assets.antibokeh.com/fish/eerie-shark.png"},

    {"Esoteric Depths","Abyss Seahorse","Mythic","https://assets.antibokeh.com/fish/abyss-seahorse.png"},

    {"Tropical Grove","Thresher Shark","Mythic","https://assets.antibokeh.com/fish/thresher-shark.png"},
    {"Tropical Grove","Great Whale","Secret","https://assets.antibokeh.com/fish/great-whale.png"},
    -- Strippled Seahorse tidak diberi rarity -> di-skip sesuai filter Mythic/Secret

    {"Creater Island","Plasma Shark","Mythic","https://assets.antibokeh.com/fish/plasma-shark.png"},
    {"Creater Island","Frostborn Shark","Secret","https://assets.antibokeh.com/fish/frostborn-shark.png"},

    {"Fisherman Island","Orca","Secret","https://assets.antibokeh.com/fish/orca.png"},
}

local REMOVE_PREFIX = { -- kata depan yang sering jadi modifier
    SHINY=true, MIDNIGHT=true, STONE=true, GALAXY=true, ALBINO=true,
    ENCHANT=true, PRISMATIC=true, AURORA=true
}

local DB = {} -- key: lower fish base name -> {island=..., rarity=..., img=...}
for _,row in ipairs(RAW_LIST) do
    local island, name, rarity, img = row[1], row[2], row[3], row[4]
    if rarity and (rarity=="Mythic" or rarity=="Secret") then
        DB[string.lower(name)] = {island=island, rarity=rarity, img=img, name=name}
    end
end

local function stripPrefixes(name)
    local tokens = {}
    for w in string.gmatch(name, "%S+") do table.insert(tokens, w) end
    while #tokens>1 and REMOVE_PREFIX[string.upper(tokens[1])] do
        table.remove(tokens,1)
    end
    return table.concat(tokens," ")
end

-- ========= HELPERS =========
local function normalize(s)
    if typeof(s)~="string" then return "" end
    s = s:gsub("<[^>]->","")
    s = s:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
    return s
end
local function hasKeyword(line)
    local l=line:lower()
    for _,k in ipairs(KEYWORDS) do if l:find(k,1,true) then return true end end
    return false
end
local function esc_html(s)
    return tostring(s):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")
end

local function parseChanceIn(text)
    local part = text:lower():match("1 in%s*([%d%.%s%a]+)%s*chance")
    if not part then return nil end
    part = part:gsub("%s","")
    local num = tonumber(part:match("[%d%.]+"))
    if not num then return nil end
    if part:find("k") then num=num*1e3 end
    if part:find("m") then num=num*1e6 end
    if part:find("b") then num=num*1e9 end
    return math.floor(num+0.5)
end

local function extractName(text)
    return text:match("obtained a%s+(.-)%s*%(")
        or text:match("obtained an%s+(.-)%s*%(")
        or text:match("obtained a%s+(.-)%s+with")
        or text:match("obtained an%s+(.-)%s+with")
end
local function extractWeight(text)
    return text:match("%(([%d%.,%sKMBkmb]+%s*kg)%)")
end
local function matchFish(baseName)
    if not baseName then return nil end
    local key = string.lower(stripPrefixes(baseName))
    return DB[key]
end

-- neat caption + photo
local function buildCaption(info, text, sender)
    local rarity = info.rarity
    local badge  = (rarity=="Mythic") and "🟣 Mythic" or "🖤 Secret"
    local name   = extractName(text) or info.name
    name = stripPrefixes(name)

    local weight = extractWeight(text)
    local chance = parseChanceIn(text)

    local cap = {}
    table.insert(cap, "🐟 <b>"..esc_html(name).."</b>")
    table.insert(cap, "🏝️ "..esc_html(info.island))
    table.insert(cap, "⭐ "..badge)
    if weight then table.insert(cap, "⚖️ "..esc_html(weight)) end
    if chance then table.insert(cap, "🎲 Chance: <b>1 in "..tostring(chance).."</b>") end
    if sender then table.insert(cap, "👤 <code>"..esc_html(sender).."</code>") end
    table.insert(cap, "—")
    table.insert(cap, "<i>"..esc_html(text).."</i>")
    return table.concat(cap, "\n")
end

local function urlencode(s)
    return (tostring(s):gsub("\n","%%0A"):gsub("\r",""):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function sendPhoto(url, captionHTML)
    if not HTTP_OK then return false, "no_http" end
    -- Try POST JSON
    local ok, res = pcall(requestFn, {
        Url = ("https://api.telegram.org/bot%s/sendPhoto"):format(BOT_TOKEN),
        Method = "POST",
        Headers = {["Content-Type"]="application/json"},
        Body = jenc({chat_id=CHAT_ID, photo=url, caption=captionHTML, parse_mode="HTML", disable_web_page_preview=true})
    })
    if ok then return true, res end
    -- Fallback GET
    local u = ("https://api.telegram.org/bot%s/sendPhoto?chat_id=%s&photo=%s&caption=%s&parse_mode=HTML")
        :format(BOT_TOKEN, CHAT_ID, urlencode(url), urlencode(captionHTML))
    return pcall(requestFn, {Url=u, Method="GET"})
end

local function logLine(line)
    if FILE_OK then pcall(appendfile, LOG_FILE, os.date("[%Y-%m-%d %H:%M:%S] ")..line.."\n") end
end

-- ========= DEDUPE =========
local sent = {}
if FILE_OK and isfile(CACHE_FILE) then
    for _,k in ipairs(jdec(readfile(CACHE_FILE)) or {}) do sent[k]=true end
end
local function persistCache()
    if not FILE_OK then return end
    local list = {}; for k in pairs(sent) do table.insert(list,k) end
    pcall(writefile, CACHE_FILE, jenc(list))
end

-- ========= CORE =========
local active = false
local CHANNEL_OK = false
local boundConn = nil

local function processMessage(text, sender)
    local line = normalize(text)
    if line=="" then return end
    if not active then return end
    if not hasKeyword(line) then return end
    if sent[line] then return end

    local got = extractName(line)
    local info = matchFish(got)
    if not info then return end -- not in DB
    -- Only Mythic/Secret already enforced by DB build

    sent[line] = true
    persistCache()
    logLine(line)

    local caption = buildCaption(info, line, sender)
    local ok = sendPhoto(info.img, caption)
    dbg(ok and "SENT TG photo ok" or "SENT TG photo fail")
end

local function bindChannel(chan)
    if boundConn then boundConn:Disconnect(); boundConn=nil end
    CHANNEL_OK = chan ~= nil
    if not chan then return end
    dbg("Bind channel:", chan.Name)
    boundConn = chan.MessageReceived:Connect(function(msg)
        local t = msg.Text or ""
        local who = nil
        pcall(function() if msg.TextSource then who = msg.TextSource.Name end end)
        processMessage(t, who)
    end)
end

local function initChannel()
    local folder = TextChatService:FindFirstChild("TextChannels")
    if not folder then
        TextChatService.ChildAdded:Connect(function(c)
            if c.Name=="TextChannels" then initChannel() end
        end)
        return
    end
    local ch = folder:FindFirstChild(CHANNEL_NAME)
    if ch and ch:IsA("TextChannel") then bindChannel(ch)
    else
        dbg("Channel '"..CHANNEL_NAME.."' not found; waiting…")
        folder.ChildAdded:Connect(function(c)
            if c.Name==CHANNEL_NAME and c:IsA("TextChannel") then bindChannel(c) end
        end)
    end
end
initChannel()

-- ========= ANTI-AFK =========
local antiAfkActive = true
lp.Idled:Connect(function()
    if antiAfkActive then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0,0), workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
        dbg("ANTI-AFK: idled pulse")
    end
end)
task.spawn(function()
    while true do
        task.wait(math.random(240,360)) -- 4–6 menit
        if antiAfkActive then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0,0), workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
            dbg("ANTI-AFK: periodic pulse")
        end
    end
end)

-- ========= GUI (kanan-bawah + draggable + status + toggles) =========
local pgui = lp:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "FishItLoggerGUI"
gui.ResetOnSpawn = false
gui.Parent = pgui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 310, 0, 120)
frame.Position = UDim2.new(1, -320, 1, -130)
frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
frame.BorderSizePixel = 2
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -10, 0, 20)
title.Position = UDim2.new(0, 5, 0, 4)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(230,230,230)
title.BackgroundTransparency = 1
title.Font = Enum.Font.SourceSansBold
title.TextSize = 16
title.Parent = frame

task.spawn(function()
    while task.wait(RESCAN_STATUS) do
        title.Text = ("RBXGeneral | FILE:%s HTTP:%s CH:%s | DB:%d")
            :format(FILE_OK and "OK" or "NO", HTTP_OK and "OK" or "NO",
                    CHANNEL_OK and "OK" or "WAIT",
                    (function() local c=0 for _ in pairs(DB) do c+=1 end return c end)())
    end
end)

local btnLog = Instance.new("TextButton")
btnLog.Size = UDim2.new(1, -10, 0, 34)
btnLog.Position = UDim2.new(0, 5, 0, 30)
btnLog.Text = "Logger: OFF"
btnLog.BackgroundColor3 = Color3.fromRGB(120,0,0)
btnLog.TextColor3 = Color3.fromRGB(255,255,255)
btnLog.Font = Enum.Font.SourceSansBold
btnLog.TextSize = 20
btnLog.Parent = frame

btnLog.MouseButton1Click:Connect(function()
    active = not active
    if active then
        btnLog.Text = "Logger: ON"
        btnLog.BackgroundColor3 = Color3.fromRGB(0,140,0)
        dbg("STATE -> Logger ON")
    else
        btnLog.Text = "Logger: OFF"
        btnLog.BackgroundColor3 = Color3.fromRGB(120,0,0)
        dbg("STATE -> Logger OFF")
    end
end)

local btnAfk = Instance.new("TextButton")
btnAfk.Size = UDim2.new(1, -10, 0, 34)
btnAfk.Position = UDim2.new(0, 5, 0, 70)
btnAfk.Text = "Anti-AFK: ON"
btnAfk.BackgroundColor3 = Color3.fromRGB(0,120,160)
btnAfk.TextColor3 = Color3.fromRGB(255,255,255)
btnAfk.Font = Enum.Font.SourceSansBold
btnAfk.TextSize = 20
btnAfk.Parent = frame

btnAfk.MouseButton1Click:Connect(function()
    antiAfkActive = not antiAfkActive
    if antiAfkActive then
        btnAfk.Text = "Anti-AFK: ON"
        btnAfk.BackgroundColor3 = Color3.fromRGB(0,120,160)
        dbg("STATE -> Anti-AFK ON")
    else
        btnAfk.Text = "Anti-AFK: OFF"
        btnAfk.BackgroundColor3 = Color3.fromRGB(100,100,100)
        dbg("STATE -> Anti-AFK OFF")
    end
end)

-- draggable
do
    local dragging, dragStart, startPos = false
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = input.Position; startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                       startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

dbg("Loaded. Klik Logger ON. Hanya Mythic/Secret sesuai DB + foto dikirim ke Telegram.")
