-- Scan: finds the food and drink in your bags and picks the strongest of each.
-- Rank is a pure function (no game calls) so it can be tested outside the game;
-- see tests/rank_test.lua. Run gathers the inputs from the game and calls it.
-- The scan asks the game only for item IDs and counts. What an item restores
-- and the level it needs come from Data/Food.lua, so nothing here waits for
-- item data to load.

local _, ns = ...

local Scan = {}
ns.Scan = Scan

-- Seconds a burst of bag events is collapsed into one scan.
local DELAY = 0.5

Scan.ran = false -- a scan has finished, so picks can be trusted
Scan.picks = {} -- { food = itemID or nil, drink = itemID or nil }
Scan.found = {} -- every food and drink carried, strongest first
Scan.hasMana = true
Scan.hasPercent = false -- a percentage food is carried, so maximum health matters

-- True when a beats b for the given value: the higher value wins, then the
-- item you carry fewer of (so leftovers get used up), then the lower ID so the
-- result never flips between two equal items.
local function Beats(a, b, key)
    if not b then return true end
    if a[key] ~= b[key] then return a[key] > b[key] end
    if a.count ~= b.count then return a.count < b.count end
    return a.id < b.id
end

-- carried: array of { id = itemID, count = number }.
-- food: the ns.Food table.
-- Returns the food item ID or nil, the drink item ID or nil, and a list of
-- every carried food and drink with its values.
function Scan.Rank(carried, level, maxHealth, maxMana, hasMana, food)
    local found = {}
    local bestFood, bestDrink
    for i = 1, #carried do
        local id, count = carried[i].id, carried[i].count
        local entry = food[id]
        if entry and count > 0 then
            local item = {
                id = id,
                count = count,
                level = entry.level,
                usable = entry.level <= level,
                health = (entry.hp or 0) + (entry.hpPct or 0) / 100 * maxHealth,
                mana = (entry.mp or 0) + (entry.mpPct or 0) / 100 * maxMana,
                percent = (entry.hpPct or entry.mpPct) and true or false,
            }
            found[#found + 1] = item
            if item.usable then
                if item.health > 0 and Beats(item, bestFood, "health") then bestFood = item end
                if hasMana and item.mana > 0 and Beats(item, bestDrink, "mana") then bestDrink = item end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.health ~= b.health then return a.health > b.health end
        if a.mana ~= b.mana then return a.mana > b.mana end
        return a.id < b.id
    end)
    return bestFood and bestFood.id, bestDrink and bestDrink.id, found
end

-- found: the list Rank returns. key: "health" or "mana".
-- Returns every item on it that restores key, in the order the macro would
-- turn to them: the pick first, then what it falls back to as stacks run
-- out. Items above your level come last.
function Scan.Order(found, key)
    local list = {}
    for i = 1, #found do
        if found[i][key] > 0 then list[#list + 1] = found[i] end
    end
    table.sort(list, function(a, b)
        if a.usable ~= b.usable then return a.usable end
        return Beats(a, b, key)
    end)
    return list
end

-- Hidden ("secret") values cannot be compared, not even to nil, so test for
-- them before anything else.
local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return value ~= nil
end

local levelFromEvent = 0
local lastHealth, lastMana = 0, 0
local lastSignature

-- PLAYER_LEVEL_UP carries the new level; UnitLevel can still return the old one.
function Scan.SetLevel(level)
    if type(level) == "number" and level > levelFromEvent then levelFromEvent = level end
end

local function PlayerLevel()
    local level = UnitLevel("player")
    if not Readable(level) or type(level) ~= "number" then level = 0 end
    return math.max(level, levelFromEvent)
end

-- Maximum health and mana, for percentage food. When the game hides one, the
-- last value read stands in. A hidden maximum mana counts as having mana.
local function Maximums()
    local health = UnitHealthMax("player")
    if Readable(health) then lastHealth = health end
    local mana = UnitPowerMax("player", Enum.PowerType.Mana)
    local hasMana = true
    if Readable(mana) then
        lastMana = mana
        hasMana = mana > 0
    end
    return lastHealth, lastMana, hasMana
end

local carried = {}
local seen = {}

local function ReadBags()
    wipe(carried)
    wipe(seen)
    local food = ns.Food
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and food[id] and not seen[id] then
                seen[id] = true
                carried[#carried + 1] = { id = id, count = C_Item.GetItemCount(id, false) or 0 }
            end
        end
    end
    table.sort(carried, function(a, b) return a.id < b.id end)
    return carried
end

local function Signature(items, level, maxHealth, maxMana, hasMana)
    local parts = { level, hasMana and 1 or 0 }
    local percent = false
    for i = 1, #items do
        local entry = ns.Food[items[i].id]
        if entry.hpPct or entry.mpPct then percent = true end
        parts[#parts + 1] = items[i].id .. "x" .. items[i].count
    end
    -- The maximums change the result only while a percentage food is carried.
    if percent then
        parts[#parts + 1] = maxHealth
        parts[#parts + 1] = maxMana
    end
    return table.concat(parts, ","), percent
end

-- Scans now. force skips the "nothing changed" shortcut.
function Scan.Run(force)
    local items = ReadBags()
    local level = PlayerLevel()
    local maxHealth, maxMana, hasMana = Maximums()
    local signature, percent = Signature(items, level, maxHealth, maxMana, hasMana)
    Scan.hasPercent = percent
    if not force and signature == lastSignature then return end
    lastSignature = signature

    local food, drink, found = Scan.Rank(items, level, maxHealth, maxMana, hasMana, ns.Food)
    Scan.picks.food, Scan.picks.drink = food, drink
    Scan.found = found
    Scan.hasMana = hasMana
    Scan.ran = true

    if ns.Macro then ns.Macro.Update() end
    if ns.Options then ns.Options.Refresh() end
end

local queued = false

-- Asks for a scan soon. Calls made while one is waiting are dropped, so a
-- burst of events costs one scan.
function Scan.Request()
    if queued then return end
    queued = true
    C_Timer.After(DELAY, function()
        queued = false
        Scan.Run()
    end)
end
