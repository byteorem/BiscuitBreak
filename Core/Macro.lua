-- Macro: keeps one account-wide macro, pointed at the food and
-- drink Scan picked.
-- Rules learned from other addons:
--   * find the macro by name before every write: the game sorts macros by
--     name, so a stored index goes stale when any macro is created or deleted;
--   * write only when the text differs from what the macro holds now, because
--     every write makes the action bars refresh;
--   * never create or edit in combat: the game blocks it.

local _, ns = ...

local Macro = {}
ns.Macro = Macro

local L = ns.L

local NAME = "_BB_Meal"
Macro.NAME = NAME
local LEGACY_NAME = "BiscuitBreak"
-- A fixed icon and no #showtooltip line, so the button always looks the same.
-- UI/Tooltip.lua fills in the tooltip.
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

-- The item IDs a macro text uses, in order.
function Macro.Items(body)
    local items = {}
    for id in body:gmatch("item:(%d+)") do
        items[#items + 1] = tonumber(id)
    end
    return items
end

local function GeneralMacroIndex(name)
    local count = GetNumMacros()
    for index = 1, count do
        if GetMacroInfo(index) == name then return index end
    end
end

-- The item IDs the macro holds right now, or nil when there is no macro. Read
-- from the macro and not from Scan's picks, because the two differ while a
-- write waits for combat to end.
function Macro.Current()
    local index = GeneralMacroIndex(NAME)
    if index then return Macro.Items(select(3, GetMacroInfo(index)) or "") end
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
    if ok and GeneralMacroIndex(NAME) then
        ns.db.macroName, ns.db.lastMacroBody = nil, nil
        ns.Print(string.format(L["Open /macro and drag %s from the General tab to your action bar."], NAME))
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

    local index = GeneralMacroIndex(NAME)
    local rename
    if not index then
        -- Reuse the old button if its saved contents identify it as ours.
        if ns.db.lastMacroBody then
            index = GeneralMacroIndex(ns.db.macroName or LEGACY_NAME)
        end
        if not index or (select(3, GetMacroInfo(index)) or "") ~= ns.db.lastMacroBody then
            Create(body)
            return
        end
        rename = NAME
    end

    if not rename and (select(3, GetMacroInfo(index)) or "") == body then
        ns.db.macroName, ns.db.lastMacroBody = nil, nil
        return
    end
    local ok, err = pcall(EditMacro, index, rename, nil, body)
    local updated = GeneralMacroIndex(NAME)
    if ok and updated and (select(3, GetMacroInfo(updated)) or "") == body then
        ns.db.macroName, ns.db.lastMacroBody = nil, nil
    else
        WarnOnce("edit", string.format(L["Could not update the macro: %s"], tostring(err)))
    end
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
