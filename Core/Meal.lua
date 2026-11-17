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

local meal = { names = {} } -- reused for every update
local active = false
local queued = false
local reported = false

local function Hidden(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Fills out with the running meal, or leaves out.start nil when there is none.
-- Can throw when the game hides effects mid-read.
local function Read(out)
    out.start, out.finish, out.icon = nil, nil, nil
    out.health, out.mana = false, false
    for i = #out.names, 1, -1 do
        out.names[i] = nil
    end

    for i = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local id = aura.spellId
        local kind = not Hidden(id) and ns.Auras[id] or nil
        local finish, duration = aura.expirationTime, aura.duration
        if kind and not Hidden(finish) and not Hidden(duration) and finish and duration and duration > 0 then
            local start = finish - duration
            -- The bar runs from the earliest start to the latest end, so a
            -- second food or drink eaten mid-meal extends it.
            if not out.start or start < out.start then out.start = start end
            if not out.finish or finish > out.finish then out.finish = finish end
            if kind ~= "mp" then out.health = true end
            if kind ~= "hp" then out.mana = true end
            if not Hidden(aura.icon) then out.icon = out.icon or aura.icon end

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

-- Turns the watching on or off (the "Show the eating bar" setting).
function Meal.SetActive(on)
    active = on and true or false
    if active then
        Meal.Request()
    else
        ns.Bar.End()
    end
end
