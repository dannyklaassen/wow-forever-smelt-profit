local SP = SmeltProfit
local LibAHTab = LibStub("LibAHTab-1-0")
local TAB_ID = "SmeltProfit"
local ROW_HEIGHT, COLUMNS = 22, { 240, 100, 100, 100, 100 }
local DEPOSIT_STACK = 20 -- deposit is asked for a stack and divided, so rounding on 1 unit doesn't skew it

local events = CreateFrame("Frame")
local ahOpen, pending, panel, window

local function name(id)
    return C_Item.GetItemNameByID(id) or SP.items[id]
end

local function money(n)
    if not n then return "|cff808080-|r" end
    local text = C_CurrencyInfo.GetCoinTextureString(math.abs(n))
    return n < 0 and "-" .. text or text
end

local function refresh()
    if not (panel and panel:IsVisible()) then return end
    local db = SmeltProfitDB
    panel.scan:SetEnabled(ahOpen == true and not pending)
    if pending then
        panel.status:SetText("Scanning...")
    elseif not db then
        panel.status:SetText("No scan yet. Open the auction house to scan.")
    else
        panel.status:SetText(("Scanned %s. Mats: cheapest of ore or bar. Profit: after %d%% AH cut and the 2h deposit."):format(
            date("%d-%m %H:%M", db.time), SP.AH_CUT * 100))
    end

    for i, e in ipairs(SP.Rows(db and db.prices or {}, db and db.deposits or {})) do
        local row = panel.rows[i]
        local icon = ("|T%d:16|t "):format(C_Item.GetItemIconByID(e.r.bar) or 134400)
        row[1]:SetText(icon .. name(e.r.bar) .. (e.r.note and (" |cff808080(" .. e.r.note .. ")|r") or ""))
        row[2]:SetText(money(e.buy))
        row[3]:SetText(money(e.sell))
        row[4]:SetText(money(e.deposit))
        local color = not e.profit and "" or e.profit > 0 and "|cff40ff40" or "|cffff4040"
        row[5]:SetText(color .. money(e.profit) .. "|r")
    end
end

-- One panel, shown either in the AH tab or in the standalone /smelt window.
local function showPanelIn(host)
    if not panel then
        panel = CreateFrame("Frame")
        panel:SetSize(660, 70 + ROW_HEIGHT * #SP.recipes)

        panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        panel.status:SetPoint("TOPLEFT", 0, -6)

        panel.scan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        panel.scan:SetSize(90, 22)
        panel.scan:SetPoint("TOPRIGHT")
        panel.scan:SetText("Rescan")
        panel.scan:SetScript("OnClick", function() SP.Scan() end)

        panel.rows = {}
        for i = 0, #SP.recipes do -- row 0 is the header
            local row, x = {}, 0
            for c, width in ipairs(COLUMNS) do
                local fs = panel:CreateFontString(nil, "OVERLAY", i == 0 and "GameFontNormal" or "GameFontHighlight")
                fs:SetPoint("TOPLEFT", x, -40 - i * ROW_HEIGHT)
                fs:SetWidth(width)
                fs:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
                fs:SetWordWrap(false)
                row[c] = fs
                x = x + width
            end
            panel.rows[i] = row
        end
        local header = panel.rows[0]
        header[1]:SetText("Bar")
        header[2]:SetText("Mats / bar")
        header[3]:SetText("Sells / bar")
        header[4]:SetText("Deposit 2h")
        header[5]:SetText("Profit / bar")
    end
    panel:SetParent(host)
    panel:ClearAllPoints()
    panel:SetPoint("TOP", host, "TOP", 0, host == window and -60 or 0)
    panel:Show()
    refresh()
end

local function createTab()
    if LibAHTab:DoesIDExist(TAB_ID) then return end
    local content = CreateFrame("Frame", nil, AuctionHouseFrame)
    content:SetPoint("TOPLEFT", 20, -60)
    content:SetPoint("BOTTOMRIGHT", -20, 30)
    content:SetScript("OnShow", showPanelIn)
    LibAHTab:CreateTab(TAB_ID, content, "Smelt", "Smelt Profit")
end

local function createWindow()
    window = CreateFrame("Frame", "SmeltProfitFrame", UIParent, "PortraitFrameTemplate")
    window:SetSize(700, 110 + ROW_HEIGHT * #SP.recipes)
    window:SetPoint("CENTER")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetTitle("Smelt Profit")
    window:SetPortraitToAsset("Interface\\Icons\\Trade_Mining")
    window:SetScript("OnShow", showPanelIn)
    tinsert(UISpecialFrames, "SmeltProfitFrame") -- Escape closes it
end

function SP.Show()
    if ahOpen then
        LibAHTab:SetSelected(TAB_ID)
    else
        if not window then createWindow() end
        window:Show()
    end
end

function SP.Scan()
    if not ahOpen then
        print("|cffffd200Smelt Profit:|r open the auction house to scan.")
        return
    end
    local keys = {}
    for id in pairs(SP.items) do keys[#keys + 1] = C_AuctionHouse.MakeItemKey(id) end
    local scan = {}
    pending = scan
    C_AuctionHouse.SearchForItemKeys(keys, { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } })
    refresh()
    -- The server can drop a search when throttled; don't leave Rescan disabled forever.
    C_Timer.After(10, function()
        if pending == scan then pending = false; refresh() end
    end)
end

local function readResults()
    local prices = SP.PricesFromResults(C_AuctionHouse.GetBrowseResults())
    if not prices then return end -- another search's results; keep waiting for ours
    -- Results arrive in pages; Blizzard's list only asks for more on scroll, so ask until we have all.
    if not C_AuctionHouse.HasFullBrowseResults() then
        C_AuctionHouse.RequestMoreBrowseResults()
        return
    end
    pending = false

    -- ponytail: minPrice is the single cheapest unit; a per-item commodity search
    -- (SendSearchQuery) would give the real price for a full stack if thin listings mislead.
    local deposits = {}
    for _, r in ipairs(SP.recipes) do
        local stack = C_AuctionHouse.CalculateCommodityDeposit(r.bar, SP.DURATION, DEPOSIT_STACK)
        deposits[r.bar] = stack and math.ceil(stack / DEPOSIT_STACK)
    end
    SmeltProfitDB = { prices = prices, deposits = deposits, time = time() }
    refresh()
end

events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
events:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        if not AuctionHouseFrame then return end
        ahOpen = true
        if window then window:Hide() end
        createTab()
        -- Scan on open, a moment after Blizzard's own favorites query so the results don't cross.
        C_Timer.After(1, function() if ahOpen then SP.Scan() end end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen, pending = false, false
    elseif pending then
        readResults()
    end
end)

SLASH_SMELTPROFIT1 = "/smelt"
SlashCmdList.SMELTPROFIT = SP.Show
