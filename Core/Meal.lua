-- Meal: watches the food and drink effects on you and tells the bar what to
-- show. It decides; UI/Bar.lua draws.
-- Reading effects is not safe by default on this client: in combat and in
-- some instances the game hides them, the read can throw, and single fields
-- (the spell ID, the end time) can be hidden values that must not be compared
-- or used as table keys. So every read checks for that first and runs inside
-- pcall. "Cannot read" is treated as "no meal".

local _, ns = ...

local Meal = {}
ns.Meal = Meal

-- More effects than a player can have; stops a runaway loop.
local MAX_AURAS = 255

-- Seconds between a food leaving your bags and its effect starting for the
-- two to be matched.
local MATCH_WINDOW = 3

local meal = { names = {}, icons = {}, items = {} } -- reused for every update
local active = false
local queued = false
local reported = false

-- The effect alone does not say which item was eaten: many foods share one.
-- So the bags are counted, and the food whose count fell when the effect
-- started is taken as the one eaten.
local counts = {} -- item ID -> how many were carried at the last count
local spare = {} -- the other count table, swapped in on each count
local dropped = {} -- item ID -> when its count last fell
local eaten = {} -- aura spell ID -> { start, item } once matched

local function Hidden(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Counts the food and drink in your bags and notes which went down.
local function CountBags()
    local food = ns.Food
    wipe(spare)
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and food[id] then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                spare[id] = (spare[id] or 0) + (info and info.stackCount or 1)
            end
        end
    end
    local fell = false
    local now = GetTime()
    for id, count in pairs(counts) do
        if (spare[id] or 0) < count then
            dropped[id] = now
            fell = true
        end
    end
    counts, spare = spare, counts
    return fell
end

local function HasAura(item, spell)
    local auras = ns.Food[item].auras
    for i = 1, #auras do
        if auras[i] == spell then return true end
    end
    return false
end

-- The item that started the effect spell at start, or nil when no food left
-- your bags then.
local function EatenItem(spell, start)
    local known = eaten[spell]
    if known and math.abs(known.start - start) < 0.5 then return known.item end
    local best, bestGap
    for item, when in pairs(dropped) do
        local gap = math.abs(when - start)
        if gap < MATCH_WINDOW and HasAura(item, spell) and (not best or gap < bestGap) then
            best, bestGap = item, gap
        end
    end
    if best then eaten[spell] = { start = start, item = best } end
    return best
end

-- Fills out with the running meal, or leaves out.start nil when there is none.
-- Can throw when the game hides effects mid-read.
local function Read(out)
    out.start, out.finish, out.icon = nil, nil, nil
    out.health, out.mana = nil, nil
    out.healthEnd, out.manaEnd = nil, nil
    for i = #out.names, 1, -1 do
        out.names[i] = nil
    end
    for i = #out.items, 1, -1 do
        out.items[i] = nil
    end

    for i = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local id = aura.spellId
        local rates = not Hidden(id) and ns.Auras[id] or nil
        local finish, duration = aura.expirationTime, aura.duration
        if rates and not Hidden(finish) and not Hidden(duration) and finish and duration and duration > 0 then
            local start = finish - duration
            -- The bar runs from the earliest start to the latest end, so a
            -- second food or drink eaten mid-meal extends it.
            if not out.start or start < out.start then out.start = start end
            if not out.finish or finish > out.finish then out.finish = finish end
            if (rates.hp or rates.hpPct) and (not out.healthEnd or finish > out.healthEnd) then
                out.health, out.healthEnd = rates, finish
            end
            if (rates.mp or rates.mpPct) and (not out.manaEnd or finish > out.manaEnd) then
                out.mana, out.manaEnd = rates, finish
            end
            -- One small icon per food or drink, for the row above the bar: the
            -- item's own when it is known, else the effect's.
            local item = EatenItem(id, start)
            local icon = item and C_Item.GetItemIconByID(item)
            if not icon and not Hidden(aura.icon) then icon = aura.icon end
            if icon then
                out.icon = out.icon or icon
                local known = false
                for n = 1, #out.items do
                    local other = out.items[n]
                    if item and other.item == item or not item and other.spell == id then known = true end
                end
                if not known then out.items[#out.items + 1] = { icon = icon, item = item, spell = id } end
            end

            local name = aura.name
            -- Test for hidden first: a hidden value cannot even be truth-tested.
            if not Hidden(name) and name then
                local known = false
                for n = 1, #out.names do
                    if out.names[n] == name then known = true end
                end
                if not known then out.names[#out.names + 1] = name end
            end
        end
    end
end

-- True when the read worked. A failure other than hidden effects is handed to
-- the error handler once, so it is never silent.
local function Scan()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return false end
    local ok, err = pcall(Read, meal)
    if not ok and not reported then
        reported = true
        geterrorhandler()(err)
    end
    return ok
end

local function Update()
    queued = false
    if not active then return end
    if Scan() and meal.start then
        meal.text = table.concat(meal.names, " & ")
        ns.Bar.Show(meal)
    else
        ns.Bar.End()
    end
end

-- Asks for an update on the next frame. Effect events come in bursts; this
-- collapses a burst into one read of the whole list.
function Meal.Request()
    if not active or queued then return end
    queued = true
    C_Timer.After(0, Update)
end

-- The bags changed: count them, and look again at the meal if a food or
-- drink was used up.
function Meal.BagsChanged()
    if active and CountBags() then Meal.Request() end
end

-- Turns the watching on or off (the "Show the eating bar" setting).
function Meal.SetActive(on)
    active = on and true or false
    if active then
        CountBags()
        Meal.Request()
    else
        ns.Bar.End()
    end
end
