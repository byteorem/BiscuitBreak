-- Tests for Scan.Rank, the pure ranking function. Run from the addon folder:
--     lua tests/rank_test.lua
-- No game needed: the files are loaded with a stand-in for the addon's table.

local ns = {}
local function Load(path)
    local chunk = assert(loadfile(path))
    chunk("BiscuitBreak", ns)
end
Load("Data/Food.lua")
Load("Core/Scan.lua")

local Rank = ns.Scan.Rank
local failures, count = 0, 0

local function Check(name, got, want)
    count = count + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
    end
end

local function Carry(...)
    local items = {}
    local arguments = { ... }
    for i = 1, #arguments, 2 do
        items[#items + 1] = { id = arguments[i], count = arguments[i + 1] }
    end
    return items
end

-- Item IDs used below, with the values the generated list should hold.
local JERKY, RYE, QUAIL = 117, 1114, 8952 -- 61, 552 and 2148 health
local WATER, DEW = 159, 8766 -- 151 and 2934 mana
local MUTTON = 3770 -- 552 health, the same as Conjured Rye
local BREAD = 282018 -- Restorative Bread: 100% of health and mana
local ROOT = 3448 -- Senggin Root: 294 health and 294 mana
local RAW_FISH, RATION, BISCUIT = 6289, 19062, 13724 -- all left out of the list

Check("list holds Tough Jerky", ns.Food[JERKY].hp, 61)
Check("list holds Conjured Rye", ns.Food[RYE].hp, 552)
Check("list holds Roasted Quail", ns.Food[QUAIL].hp, 2148)
Check("list holds Morning Glory Dew", ns.Food[DEW].mp, 2934)
Check("list holds Restorative Bread", ns.Food[BREAD].hpPct, 100)
Check("raw fish is left out", ns.Food[RAW_FISH], nil)
Check("battleground ration is left out", ns.Food[RATION], nil)
Check("reputation food is left out", ns.Food[BISCUIT], nil)

local food, drink, found

food, drink = Rank(Carry(JERKY, 5, RYE, 20, WATER, 10), 60, 3000, 3000, true, ns.Food)
Check("strongest food wins", food, RYE)
Check("only drink wins", drink, WATER)

food = Rank(Carry(JERKY, 5, RYE, 20, QUAIL, 3), 20, 1000, 1000, true, ns.Food)
Check("food above your level is skipped", food, RYE)

food = Rank(Carry(QUAIL, 3), 20, 1000, 1000, true, ns.Food)
Check("no usable food gives nil", food, nil)

food = Rank(Carry(RYE, 20, MUTTON, 4), 60, 3000, 3000, true, ns.Food)
Check("a tie goes to the smaller stack", food, MUTTON)

food = Rank(Carry(RYE, 4, MUTTON, 4), 60, 3000, 3000, true, ns.Food)
Check("an exact tie goes to the lower ID", food, RYE)

food, drink = Rank(Carry(QUAIL, 5, DEW, 5, BREAD, 2), 60, 5000, 5000, true, ns.Food)
Check("percentage food wins at high health", food, BREAD)
Check("percentage drink wins at high mana", drink, BREAD)

food, drink = Rank(Carry(QUAIL, 5, DEW, 5, BREAD, 2), 60, 1500, 1500, true, ns.Food)
Check("flat food wins at low health", food, QUAIL)
Check("flat drink wins at low mana", drink, DEW)

food, drink = Rank(Carry(ROOT, 5), 60, 3000, 3000, true, ns.Food)
Check("one item can be the food", food, ROOT)
Check("and the drink too", drink, ROOT)

food, drink = Rank(Carry(RYE, 5, WATER, 5), 60, 3000, 0, false, ns.Food)
Check("no mana still picks food", food, RYE)
Check("no mana picks no drink", drink, nil)

food, drink, found = Rank(Carry(12345678, 5, RYE, 0), 60, 3000, 3000, true, ns.Food)
Check("unknown items are ignored", food, nil)
Check("a zero count is ignored", drink, nil)
Check("nothing found", #found, 0)

found = select(3, Rank(Carry(JERKY, 5, QUAIL, 2, WATER, 3), 10, 1000, 1000, true, ns.Food))
Check("found lists every carried item", #found, 3)
Check("found is strongest first", found[1].id, QUAIL)
Check("found marks food you can't use yet", found[1].usable, false)

local Order = ns.Scan.Order
local order

food, drink, found = Rank(Carry(JERKY, 5, RYE, 20, MUTTON, 4, QUAIL, 2, WATER, 3), 20, 1000, 1000, true, ns.Food)
order = Order(found, "health")
Check("order lists only what restores health", #order, 4)
Check("order starts with the pick", order[1].id, food)
Check("order breaks a tie like the pick", order[2].id, RYE)
Check("order ends the usable food with the weakest", order[3].id, JERKY)
Check("order puts food above your level last", order[4].id, QUAIL)
order = Order(found, "mana")
Check("order lists only what restores mana", #order, 1)
Check("order starts with the drink pick", order[1].id, drink)

order = Order(select(3, Rank(Carry(ROOT, 5), 60, 3000, 3000, true, ns.Food)), "mana")
Check("one item is on both orders", order[1].id, ROOT)

print(string.format("%d checks, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
