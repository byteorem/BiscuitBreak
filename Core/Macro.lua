-- Macro: keeps one account-wide macro, "BiscuitBreak", pointed at the food and
-- drink Scan picked. Body and LooksLikeOurs are pure functions, tested in
-- tests/macro_test.lua.
-- Rules learned from other addons (see plan.md, "Writing the macro"):
--   * find the macro by name before every write: the game sorts macros by
--     name, so a stored index goes stale when any macro is created or deleted;
--   * write only when the text differs from what the macro holds now, because
--     every write makes the action bars refresh;
--   * never create or edit in combat: the game blocks it.

local _, ns = ...

local Macro = {}
ns.Macro = Macro

local L = ns.L

local NAME = "BiscuitBreak"
-- A fixed icon and no #showtooltip line, so the button always looks the same.
local ICON = "inv_misc_food_73cinnamonroll"
local MAX_LENGTH = 255

local ready = false -- the game has loaded its macros
local stale = false -- a write is waiting for combat to end
local warned = {}

-- The macro text for a food and a drink item ID. Either can be nil. One item
-- that is both gets one line.
function Macro.Body(food, drink)
    local lines = {}
    if food then lines[#lines + 1] = "/use item:" .. food end
    if drink and drink ~= food then lines[#lines + 1] = "/use item:" .. drink end
    return table.concat(lines, "\n")
end

-- True when a macro's text is something this addon would have written: empty,
-- or nothing but "/use item:<number>" lines. A macro of the same name with
-- any other text belongs to the player and is left alone.
function Macro.LooksLikeOurs(text)
    if text == nil or text == "" then return true end
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        if line ~= "" and not line:match("^/use item:%d+$") then return false end
    end
    return true
end

local function WarnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    ns.Print(message)
end

local function AccountLimit()
    return (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS)
        or MAX_ACCOUNT_MACROS
        or 120
end

local function Create(body)
    -- GetNumMacros returns the account-wide count first.
    if (GetNumMacros()) >= AccountLimit() then
        WarnOnce("full", L["Your general macro slots are full, so the BiscuitBreak macro was not created."])
        return
    end
    -- A nil fourth argument makes the macro account-wide (the General tab).
    local ok, err = pcall(CreateMacro, NAME, ICON, body, nil)
    if ok then
        ns.Print(L["Created the BiscuitBreak macro. Open /macro, find it on the General tab and drag it to a bar."])
    else
        WarnOnce("create", string.format(L["Could not create the macro: %s"], tostring(err)))
    end
end

-- Brings the macro in line with Scan's picks. Safe to call at any time: it
-- does nothing until the game's macros have loaded and a scan has run, and it
-- waits out combat.
function Macro.Update()
    if not ready or not ns.Scan.ran then return end
    if not (ns.db and ns.db.useMacro) then return end
    if InCombatLockdown() then
        stale = true
        return
    end
    stale = false

    local body = Macro.Body(ns.Scan.picks.food, ns.Scan.picks.drink)
    if #body > MAX_LENGTH then return end

    -- 0, not nil, means there is no macro of that name.
    local index = GetMacroIndexByName(NAME)
    if index == 0 then
        Create(body)
        return
    end
    local _, _, current = GetMacroInfo(index)
    if current == body then return end
    if not Macro.LooksLikeOurs(current) then
        WarnOnce(
            "foreign",
            L["A macro named BiscuitBreak already exists with other text, so it was left alone. Rename or delete it."]
        )
        return
    end
    -- nil name and icon keep the ones the macro has.
    local ok, err = pcall(EditMacro, index, nil, nil, body)
    if not ok then WarnOnce("edit", string.format(L["Could not update the macro: %s"], tostring(err))) end
end

-- Combat ended: do the write that was waiting.
function Macro.Flush()
    if stale then Macro.Update() end
end

-- The game's macros are loaded. Called on the first UPDATE_MACROS and again
-- two seconds after entering the world, whichever comes first. Creating
-- before the macros load would make a duplicate.
function Macro.SetReady()
    if ready then return end
    ready = true
    Macro.Update()
end
