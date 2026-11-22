-- Dev check, not in the .toc: `lua check.lua` from the addon folder. Runs in the release workflow too.
dofile("Recipes.lua")
local SP = SmeltProfit
local function eval(bar, prices, deposit) return SP.Evaluate(SP.recipeFor[bar], prices, { [bar] = deposit }) end
local function result(id, minPrice, qty) return { itemKey = { itemID = id }, minPrice = minPrice, totalQuantity = qty } end

-- Evaluate --------------------------------------------------------------

-- Copper: ore 10c, bar 100c sells for 95c after the cut, 3c deposit.
local buy, sell, deposit, profit = eval(2840, { [2770] = 10, [2840] = 100 }, 3)
assert(buy == 10 and sell == 95 and deposit == 3 and profit == 82, "copper")

-- Bronze yields 2 bars; Copper Bar is cheaper bought (5c) than smelted (10c), Tin via its ore (8c).
buy, sell, deposit, profit = eval(2841, { [2770] = 10, [2840] = 5, [2771] = 8, [2841] = 20 }, 1)
assert(buy == 7 and sell == 19 and profit == 11, "bronze per bar")

-- Steel uses the cheapest Iron: smelting the ore (30c) beats buying the bar (50c).
buy = eval(3859, { [2772] = 30, [3575] = 50, [3857] = 10, [3859] = 200 }, 1)
assert(buy == 40, "steel via iron ore")

-- Dark Iron takes 8 ore, Azerothium 2 Pitchblende and a Coal.
assert(eval(11371, { [11370] = 100, [11371] = 1000 }, 0) == 800, "dark iron")
assert(eval(249726, { [249426] = 100, [3857] = 7, [249726] = 1000 }, 0) == 207, "azerothium")

-- Missing listing: no buy price means no profit, sell still shown.
buy, sell, deposit, profit = eval(3859, { [3575] = 50, [3859] = 200 }, 1)
assert(buy == nil and sell == 190 and profit == nil, "steel without coal")

-- Unknown deposit: no profit rather than a too rosy one.
buy, sell, deposit, profit = eval(2840, { [2770] = 10, [2840] = 100 }, nil)
assert(buy == 10 and profit == nil, "copper without deposit")

-- PricesFromResults ------------------------------------------------------

-- Our scan: listed items get their price, "None available" (qty 0, minPrice 0) gets none.
local prices = SP.PricesFromResults({ result(2770, 10, 500), result(7911, 0, 0) })
assert(prices and prices[2770] == 10 and prices[7911] == nil, "none available is not free")

-- Someone else's search (favorites with a non-mining item) is ignored, even if it holds an ore.
assert(SP.PricesFromResults({ result(2770, 10, 500), result(12345, 99, 1) }) == nil, "foreign results")
assert(SP.PricesFromResults({}) == nil, "empty results")

-- Rows -------------------------------------------------------------------

local rows = SP.Rows({ [2770] = 10, [2840] = 100, [2775] = 50, [2842] = 40 }, { [2840] = 1, [2842] = 1 })
assert(#rows == #SP.recipes, "a row per recipe")
assert(rows[1].r.bar == 2840 and rows[1].profit == 84, "best profit first")
assert(rows[2].r.bar == 2842 and rows[2].profit == -13, "loss after profit")
for i = 3, #rows do assert(rows[i].profit == nil, "unknown last") end
for i = 4, #rows do assert(rows[i - 1].r.skill <= rows[i].r.skill, "unknowns by skill") end

-- Data -------------------------------------------------------------------

for _, r in ipairs(SP.recipes) do
    assert(SP.items[r.bar], "no name for bar " .. r.bar)
    for id in pairs(r.mats) do assert(SP.items[id], "no name for mat " .. id) end
end
print("ok")
