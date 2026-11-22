-- Smelt recipes and profit math. Pure Lua, no WoW API, so check.lua can run it.
SmeltProfit = SmeltProfit or {}
local SP = SmeltProfit

SP.AH_CUT = 0.05 -- auction house cut on sales; tweak if Forever differs
SP.DURATION = 1 -- index in the AH duration menu; 1 = 2 hours

-- Fallback names; the client's own (localized) name wins when it is cached.
SP.items = {
    [2770] = "Copper Ore",       [2840] = "Copper Bar",
    [2771] = "Tin Ore",          [3576] = "Tin Bar",
                                 [2841] = "Bronze Bar",
    [2775] = "Silver Ore",       [2842] = "Silver Bar",
    [2772] = "Iron Ore",         [3575] = "Iron Bar",
    [2776] = "Gold Ore",         [3577] = "Gold Bar",
    [3857] = "Coal",             [3859] = "Steel Bar",
    [3858] = "Mithril Ore",      [3860] = "Mithril Bar",
    [7911] = "Truesilver Ore",   [6037] = "Truesilver Bar",
    [11370] = "Dark Iron Ore",   [11371] = "Dark Iron Bar",
    [10620] = "Thorium Ore",     [12359] = "Thorium Bar",
    [249426] = "Pitchblende",    [249726] = "Azerothium Bar",
    [248815] = "Heavy Thorium Ore", [251291] = "Heavy Thorium Bar",
}

-- Source: wowhead.com/forever mining guide and spell pages (2026-11-22).
SP.recipes = {
    { bar = 2840, out = 1, skill = 1, mats = { [2770] = 1 } },
    { bar = 3576, out = 1, skill = 65, mats = { [2771] = 1 } },
    { bar = 2841, out = 2, skill = 65, mats = { [2840] = 1, [3576] = 1 } },
    { bar = 2842, out = 1, skill = 75, mats = { [2775] = 1 } },
    { bar = 3575, out = 1, skill = 125, mats = { [2772] = 1 } },
    { bar = 3577, out = 1, skill = 155, mats = { [2776] = 1 } },
    { bar = 3859, out = 1, skill = 165, mats = { [3575] = 1, [3857] = 1 } },
    { bar = 3860, out = 1, skill = 175, mats = { [3858] = 1 } },
    { bar = 6037, out = 1, skill = 230, mats = { [7911] = 1 } },
    { bar = 11371, out = 1, skill = 230, mats = { [11370] = 8 } },
    { bar = 12359, out = 1, skill = 250, mats = { [10620] = 1 } },
    { bar = 249726, out = 1, skill = 275, mats = { [249426] = 2, [3857] = 1 } },
    { bar = 251291, out = 1, skill = 300, mats = { [248815] = 1 }, note = "Molten Foundry" },
}

SP.recipeFor = {}
for _, r in ipairs(SP.recipes) do SP.recipeFor[r.bar] = r end

local matsCost

-- Cheapest way to get one of this item: buy it, or smelt it from what you can buy.
-- That makes Bronze and Steel count Copper/Tin/Iron ore when the ore beats the bar.
local function cost(id, prices)
    local best = prices[id]
    local r = SP.recipeFor[id]
    local smelt = r and matsCost(r, prices)
    if smelt then
        smelt = smelt / r.out
        if not best or smelt < best then best = smelt end
    end
    return best
end

-- Cost of the reagents for one smelt, nil if any reagent has no price.
function matsCost(r, prices)
    local total = 0
    for id, qty in pairs(r.mats) do
        local c = cost(id, prices)
        if not c then return nil end
        total = total + c * qty
    end
    return total
end

-- Per bar: what the mats cost, what a bar sells for after the AH cut, the deposit to list it,
-- and what is left. Any of them is nil when a needed price or deposit is unknown.
function SP.Evaluate(r, prices, deposits)
    local mats = matsCost(r, prices)
    local buy = mats and math.floor(mats / r.out + 0.5)
    local sell = prices[r.bar] and math.floor(prices[r.bar] * (1 - SP.AH_CUT))
    local deposit = deposits[r.bar]
    local profit = buy and sell and deposit and sell - buy - deposit
    return buy, sell, deposit, profit
end

-- Prices from C_AuctionHouse.GetBrowseResults(), or nil when the results are another search's
-- (Blizzard favorites, Auctionator) because they hold items we did not ask for.
function SP.PricesFromResults(results)
    local prices, ours = {}, 0
    for _, result in ipairs(results) do
        local id = result.itemKey.itemID
        if SP.items[id] then
            ours = ours + 1
            -- "None available" items come back with minPrice 0; they have no price, not a free one.
            if result.totalQuantity > 0 then prices[id] = result.minPrice end
        end
    end
    if ours == 0 or ours < #results then return nil end
    return prices
end

-- Rows for the overview, best profit first and unknown profit last.
function SP.Rows(prices, deposits)
    local rows = {}
    for _, r in ipairs(SP.recipes) do
        local buy, sell, deposit, profit = SP.Evaluate(r, prices, deposits)
        rows[#rows + 1] = { r = r, buy = buy, sell = sell, deposit = deposit, profit = profit }
    end
    table.sort(rows, function(a, b)
        if (a.profit == nil) ~= (b.profit == nil) then return a.profit ~= nil end
        if a.profit ~= b.profit then return (a.profit or 0) > (b.profit or 0) end
        return a.r.skill < b.r.skill -- stable order for ties and unknowns
    end)
    return rows
end
