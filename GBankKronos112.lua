-- GBankKronos112
-- Lightweight fake guild bank for Vanilla 1.12 private servers.
-- Bank alt scans bags/bank/mail, then syncs a cached snapshot to guild members.

GBankKronos112DB = GBankKronos112DB or {}

local ADDON = "GBankKronos112"
local PREFIX = "GBK112"
local VERSION = "0.2.1"
local DELIM = "~"
local ROWS = 15

local GBK = {}
GBK.frame = nil
GBK.rows = {}
GBK.offset = 0
GBK.search = ""
GBK.tab = "ALL"
GBK.view = {}
GBK.incoming = {}
GBK.lastAnnounce = 0

local function Now()
    return time and time() or 0
end

local function PlayerName()
    return UnitName("player") or "Unknown"
end

local function Lower(s)
    if not s then return "" end
    return string.lower(s)
end

local function Trim(s)
    if not s then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGBank|r: " .. tostring(msg))
end

local function EnsureDB()
    if not GBankKronos112DB then GBankKronos112DB = {} end
    if not GBankKronos112DB.banks then GBankKronos112DB.banks = {} end
    if not GBankKronos112DB.limits then GBankKronos112DB.limits = {} end
    if not GBankKronos112DB.options then GBankKronos112DB.options = {} end
end

local function LinkName(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.-)%]")
    return name
end

local function LinkItemId(link)
    if not link then return "0" end
    local _, _, id = string.find(link, "item:(%d+):")
    return id or "0"
end

local function AddItem(items, name, itemId, count, source, slot)
    if not name or name == "" then return end
    if not count or count < 1 then count = 1 end
    local key = Lower(name)
    if not items[key] then
        items[key] = { name = name, id = itemId or "0", count = 0, source = source or "", slots = {} }
    end
    items[key].count = items[key].count + count
    if source and slot then
        table.insert(items[key].slots, source .. " " .. slot)
    end
end

local function ScanContainer(items, bag, source)
    local slots = GetContainerNumSlots(bag)
    if not slots then return end
    local i
    for i = 1, slots do
        local link = GetContainerItemLink(bag, i)
        if link then
            local texture, count = GetContainerItemInfo(bag, i)
            local name = LinkName(link)
            local itemId = LinkItemId(link)
            AddItem(items, name, itemId, count or 1, source, tostring(bag) .. ":" .. tostring(i))
        end
    end
end

local function ScanMail(items)
    if not GetInboxNumItems then return 0 end
    if MailFrame and not MailFrame:IsVisible() then return 0 end
    local total = GetInboxNumItems()
    if not total then return 0 end
    local scanned = 0
    local mailIndex
    for mailIndex = 1, total do
        local attachmentIndex
        for attachmentIndex = 1, 16 do
            local name = nil
            local itemId = "0"
            local count = 1
            if GetInboxItemLink then
                local ok, link = pcall(GetInboxItemLink, mailIndex, attachmentIndex)
                if ok and link then
                    name = LinkName(link)
                    itemId = LinkItemId(link)
                end
            end
            if GetInboxItem then
                local ok, itemName, texture, itemCount = pcall(GetInboxItem, mailIndex, attachmentIndex)
                if ok and itemName then
                    if not name then name = itemName end
                    if itemCount then count = itemCount end
                end
            end
            if name then
                AddItem(items, name, itemId, count, "Mail", tostring(mailIndex) .. ":" .. tostring(attachmentIndex))
                scanned = scanned + 1
            end
        end
    end
    return scanned
end

local function IsBankOpen()
    if BankFrame and BankFrame:IsVisible() then return true end
    return false
end

local function SnapshotName(arg)
    arg = Trim(arg or "")
    if arg ~= "" then return arg end
    return PlayerName()
end

local function ScanBankAlt(tabName)
    EnsureDB()
    local name = SnapshotName(tabName)
    local items = {}
    local b

    for b = 0, 4 do
        ScanContainer(items, b, "Bags")
    end

    if IsBankOpen() then
        ScanContainer(items, -1, "Bank")
        for b = 5, 10 do
            ScanContainer(items, b, "BankBag")
        end
    end

    local mailCount = ScanMail(items)

    GBankKronos112DB.banks[name] = {
        name = name,
        owner = PlayerName(),
        updated = Now(),
        guild = GetGuildInfo and GetGuildInfo("player") or "",
        items = items
    }

    local count = 0
    local k, v
    for k, v in pairs(items) do count = count + 1 end

    if IsBankOpen() then
        Print("scanned " .. count .. " unique items for " .. name .. ".")
    else
        Print("scanned bags only for " .. name .. ". Open the bank before /gbank scan to include bank slots.")
    end
    if mailCount > 0 then Print("included " .. mailCount .. " mail attachments.") end
end

local function BuildFlatItems()
    EnsureDB()
    local flat = {}
    local totals = {}
    local bankName, bank
    for bankName, bank in pairs(GBankKronos112DB.banks) do
        if GBK.tab == "ALL" or GBK.tab == bankName then
            local key, item
            for key, item in pairs(bank.items or {}) do
                local search = Lower(GBK.search)
                if search == "" or string.find(Lower(item.name), search, 1, true) then
                    local tkey = Lower(item.name)
                    if not totals[tkey] then
                        totals[tkey] = { name = item.name, id = item.id or "0", count = 0, tabs = {}, sources = {} }
                    end
                    totals[tkey].count = totals[tkey].count + (item.count or 0)
                    totals[tkey].tabs[bankName] = true
                    table.insert(totals[tkey].sources, bankName .. " x" .. tostring(item.count or 0))
                end
            end
        end
    end
    local k, v
    for k, v in pairs(totals) do table.insert(flat, v) end
    table.sort(flat, function(a, b) return Lower(a.name) < Lower(b.name) end)
    return flat
end

local function LimitFor(name)
    EnsureDB()
    return GBankKronos112DB.limits[Lower(name)] or 0
end

local function SetLimit(name, n)
    EnsureDB()
    name = Trim(name)
    n = tonumber(n) or 0
    if name == "" then return end
    if n <= 0 then
        GBankKronos112DB.limits[Lower(name)] = nil
        Print("removed minimum for " .. name .. ".")
    else
        GBankKronos112DB.limits[Lower(name)] = n
        Print("minimum for " .. name .. " set to " .. n .. ".")
    end
end

local function AnnounceLowStock()
    EnsureDB()
    local totals = {}
    local bankName, bank
    for bankName, bank in pairs(GBankKronos112DB.banks) do
        local key, item
        for key, item in pairs(bank.items or {}) do
            local lk = Lower(item.name)
            totals[lk] = (totals[lk] or 0) + (item.count or 0)
        end
    end
    local low = {}
    local key, min
    for key, min in pairs(GBankKronos112DB.limits) do
        local have = totals[key] or 0
        if have < min then
            table.insert(low, { name = key, have = have, min = min, need = min - have })
        end
    end
    table.sort(low, function(a, b) return a.name < b.name end)
    if table.getn(low) == 0 then
        Print("stock check OK. No tracked items are below minimum.")
        return
    end
    Print("low stock:")
    local i
    for i = 1, table.getn(low) do
        Print("  " .. low[i].name .. ": " .. low[i].have .. "/" .. low[i].min .. " need " .. low[i].need)
    end
end

local function Send(msg)
    if not IsInGuild or IsInGuild() then
        SendAddonMessage(PREFIX, msg, "GUILD")
    else
        Print("not in a guild, cannot sync.")
    end
end

local function SerializeSafe(s)
    s = tostring(s or "")
    s = string.gsub(s, "~", "-")
    s = string.gsub(s, "|", "/")
    s = string.gsub(s, "\n", " ")
    return s
end

local function SyncBank(bankName)
    EnsureDB()
    local bank = GBankKronos112DB.banks[bankName]
    if not bank then return end
    local session = tostring(Now()) .. tostring(math.random(100, 999))
    Send("START" .. DELIM .. session .. DELIM .. SerializeSafe(bankName) .. DELIM .. tostring(bank.updated or Now()) .. DELIM .. VERSION)
    local key, item
    for key, item in pairs(bank.items or {}) do
        Send("ITEM" .. DELIM .. session .. DELIM .. SerializeSafe(bankName) .. DELIM .. SerializeSafe(item.name) .. DELIM .. tostring(item.id or "0") .. DELIM .. tostring(item.count or 0))
    end
    Send("END" .. DELIM .. session .. DELIM .. SerializeSafe(bankName))
end

local function SyncAll()
    EnsureDB()
    local sent = 0
    local bankName, bank
    for bankName, bank in pairs(GBankKronos112DB.banks) do
        SyncBank(bankName)
        sent = sent + 1
    end
    Print("synced " .. sent .. " bank snapshot(s) to guild.")
end

local function SplitBar(msg)
    local t = {}
    local part
    for part in string.gfind(msg or "", "([^" .. DELIM .. "]+)") do
        table.insert(t, part)
    end
    return t
end

local function OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX then return end
    if sender == PlayerName() then return end
    local p = SplitBar(msg)
    local cmd = p[1]
    if cmd == "REQ" then
        if GBankKronos112DB and GBankKronos112DB.banks then
            SyncAll()
        end
        return
    end
    if cmd == "START" then
        local session = p[2]
        local bankName = p[3]
        local updated = tonumber(p[4]) or Now()
        if not session or not bankName then return end
        GBK.incoming[session] = { bankName = bankName, updated = updated, owner = sender, items = {} }
        return
    end
    if cmd == "ITEM" then
        local session = p[2]
        local bankName = p[3]
        local itemName = p[4]
        local itemId = p[5]
        local count = tonumber(p[6]) or 0
        if not session or not GBK.incoming[session] then return end
        local key = Lower(itemName)
        GBK.incoming[session].items[key] = { name = itemName, id = itemId or "0", count = count, source = bankName }
        return
    end
    if cmd == "END" then
        EnsureDB()
        local session = p[2]
        local inc = GBK.incoming[session]
        if not inc then return end
        local existing = GBankKronos112DB.banks[inc.bankName]
        if not existing or not existing.updated or inc.updated >= existing.updated then
            GBankKronos112DB.banks[inc.bankName] = {
                name = inc.bankName,
                owner = inc.owner,
                updated = inc.updated,
                guild = GetGuildInfo and GetGuildInfo("player") or "",
                items = inc.items
            }
            Print("received bank snapshot: " .. inc.bankName .. " from " .. inc.owner .. ".")
            if GBK.frame and GBK.frame:IsVisible() then GBK.Refresh() end
            AnnounceLowStock()
        end
        GBK.incoming[session] = nil
        return
    end
end

local function FormatTime(ts)
    if not ts or ts == 0 or not date then return "never" end
    return date("%m/%d %H:%M", ts)
end

local function SourcesText(item)
    local s = ""
    local first = true
    local k
    for k in pairs(item.tabs or {}) do
        if first then s = k; first = false else s = s .. ", " .. k end
    end
    return s
end

function GBK.Refresh()
    if not GBK.frame then return end
    EnsureDB()
    GBK.view = BuildFlatItems()
    local total = table.getn(GBK.view)
    if GBK.offset < 0 then GBK.offset = 0 end
    if GBK.offset > total - ROWS then GBK.offset = total - ROWS end
    if GBK.offset < 0 then GBK.offset = 0 end

    GBK.countText:SetText(tostring(total) .. " item(s)")

    local newest = 0
    local bname, bank
    for bname, bank in pairs(GBankKronos112DB.banks) do
        if bank.updated and bank.updated > newest then newest = bank.updated end
    end
    GBK.updatedText:SetText("Updated: " .. FormatTime(newest))

    local i
    for i = 1, ROWS do
        local row = GBK.rows[i]
        local item = GBK.view[GBK.offset + i]
        if item then
            local min = LimitFor(item.name)
            local low = min > 0 and item.count < min
            row:Show()
            row.name:SetText(item.name)
            row.count:SetText(tostring(item.count))
            row.where:SetText(SourcesText(item))
            if min > 0 then
                row.min:SetText(tostring(item.count) .. "/" .. tostring(min))
            else
                row.min:SetText("")
            end
            if low then
                row.name:SetTextColor(1, 0.25, 0.25)
                row.min:SetTextColor(1, 0.25, 0.25)
            else
                row.name:SetTextColor(1, 0.82, 0)
                row.min:SetTextColor(0.3, 1, 0.3)
            end
        else
            row:Hide()
        end
    end
end

local function SelectTab(tab)
    GBK.tab = tab or "ALL"
    GBK.offset = 0
    GBK.Refresh()
end

local function MakeTabButton(parent, text, x, tab)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(72)
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -54)
    b:SetText(text)
    b:SetScript("OnClick", function() SelectTab(tab) end)
    return b
end

local function RebuildTabButtons()
    if not GBK.frame then return end
    if GBK.tabButtons then
        local i
        for i = 1, table.getn(GBK.tabButtons) do GBK.tabButtons[i]:Hide() end
    end
    GBK.tabButtons = {}
    table.insert(GBK.tabButtons, MakeTabButton(GBK.frame, "All", 12, "ALL"))
    local names = {}
    local bankName
    for bankName in pairs(GBankKronos112DB.banks or {}) do table.insert(names, bankName) end
    table.sort(names)
    local i
    for i = 1, table.getn(names) do
        if i <= 5 then
            table.insert(GBK.tabButtons, MakeTabButton(GBK.frame, names[i], 12 + (i * 76), names[i]))
        end
    end
end

local function CreateUI()
    if GBK.frame then return end
    EnsureDB()

    local f = CreateFrame("Frame", "GBankKronos112Frame", UIParent)
    f:SetWidth(620)
    f:SetHeight(430)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 }})
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetScript("OnMouseWheel", function() if arg1 and arg1 < 0 then GBK.offset = GBK.offset + 3 else GBK.offset = GBK.offset - 3 end GBK.Refresh() end)
    f:Hide()
    table.insert(UISpecialFrames, "GBankKronos112Frame")
    GBK.frame = f

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -18)
    title:SetText("Guild Bank")

    GBK.updatedText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    GBK.updatedText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -22)
    GBK.updatedText:SetText("Updated: never")

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -82)
    label:SetText("Search:")

    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetWidth(220)
    search:SetHeight(20)
    search:SetPoint("LEFT", label, "RIGHT", 8, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function()
        GBK.search = this:GetText() or ""
        GBK.offset = 0
        GBK.Refresh()
    end)
    GBK.searchBox = search

    GBK.countText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    GBK.countText:SetPoint("LEFT", search, "RIGHT", 20, 0)
    GBK.countText:SetText("0 item(s)")

    local sync = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sync:SetWidth(70)
    sync:SetHeight(22)
    sync:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -50)
    sync:SetText("Request")
    sync:SetScript("OnClick", function() Send("REQ") Print("requested latest bank snapshot from online officers.") end)

    local stock = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    stock:SetWidth(70)
    stock:SetHeight(22)
    stock:SetPoint("RIGHT", sync, "LEFT", -6, 0)
    stock:SetText("Stock")
    stock:SetScript("OnClick", function() AnnounceLowStock() end)

    local headerY = -112
    local h1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h1:SetPoint("TOPLEFT", f, "TOPLEFT", 24, headerY)
    h1:SetText("Item")
    local h2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h2:SetPoint("TOPLEFT", f, "TOPLEFT", 330, headerY)
    h2:SetText("Qty")
    local h3 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h3:SetPoint("TOPLEFT", f, "TOPLEFT", 390, headerY)
    h3:SetText("Bank alt")
    local h4 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h4:SetPoint("TOPLEFT", f, "TOPLEFT", 520, headerY)
    h4:SetText("Min")

    local i
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetWidth(570)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 24, headerY - 18 - ((i - 1) * 18))
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name:SetWidth(290)
        row.name:SetJustifyH("LEFT")
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.count:SetPoint("LEFT", row, "LEFT", 310, 0)
        row.count:SetWidth(45)
        row.count:SetJustifyH("LEFT")
        row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.where:SetPoint("LEFT", row, "LEFT", 370, 0)
        row.where:SetWidth(120)
        row.where:SetJustifyH("LEFT")
        row.min = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.min:SetPoint("LEFT", row, "LEFT", 500, 0)
        row.min:SetWidth(70)
        row.min:SetJustifyH("LEFT")
        GBK.rows[i] = row
    end

    local up = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    up:SetWidth(60)
    up:SetHeight(22)
    up:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -88, 22)
    up:SetText("Up")
    up:SetScript("OnClick", function() GBK.offset = GBK.offset - ROWS GBK.Refresh() end)

    local down = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    down:SetWidth(60)
    down:SetHeight(22)
    down:SetPoint("LEFT", up, "RIGHT", 6, 0)
    down:SetText("Down")
    down:SetScript("OnClick", function() GBK.offset = GBK.offset + ROWS GBK.Refresh() end)

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetWidth(70)
    close:SetHeight(22)
    close:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 22)
    close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    RebuildTabButtons()
end

local function ToggleUI()
    CreateUI()
    RebuildTabButtons()
    if GBK.frame:IsVisible() then
        GBK.frame:Hide()
    else
        GBK.Refresh()
        GBK.frame:Show()
    end
end

local function Help()
    Print("commands:")
    Print("/gbank - open viewer")
    Print("/gbank scan [name] - scan bags, open bank, and open mailbox")
    Print("/gbank sync - send cached bank snapshot to guild")
    Print("/gbank request - ask online officers for latest snapshot")
    Print("/gbank limit Item Name = 80 - set minimum stock")
    Print("/gbank clear - clear local cached bank data")
end

local function Slash(msg)
    EnsureDB()
    msg = Trim(msg or "")
    local cmd, rest = nil, nil
    _, _, cmd, rest = string.find(msg, "^(%S+)%s*(.*)$")
    if not cmd then ToggleUI() return end
    cmd = Lower(cmd)
    rest = rest or ""
    if cmd == "scan" then
        ScanBankAlt(rest)
        RebuildTabButtons()
        GBK.Refresh()
    elseif cmd == "sync" then
        SyncAll()
    elseif cmd == "request" or cmd == "req" then
        Send("REQ")
        Print("requested latest bank snapshot from online officers.")
    elseif cmd == "clear" then
        GBankKronos112DB.banks = {}
        Print("cleared local bank cache.")
        RebuildTabButtons()
        GBK.Refresh()
    elseif cmd == "stock" or cmd == "limits" then
        AnnounceLowStock()
    elseif cmd == "limit" then
        local item, num
        _, _, item, num = string.find(rest, "^(.+)%s*=%s*(%d+)%s*$")
        if not item then _, _, item, num = string.find(rest, "^(.+)%s+(%d+)%s*$") end
        if item and num then SetLimit(item, num) else Print("use: /gbank limit Item Name = 80") end
        GBK.Refresh()
    elseif cmd == "help" then
        Help()
    else
        ToggleUI()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        SLASH_GBANKKRONOS1121 = "/gbank"
        SLASH_GBANKKRONOS1122 = "/gbk"
        SLASH_GBANKKRONOS1123 = "/ubb"
        SlashCmdList["GBANKKRONOS112"] = Slash
        Print("loaded. Type /gbank, or /gbank help.")
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(arg1, arg2, arg3, arg4)
    end
end)
