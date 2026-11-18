-- BiscuitBreak core: startup, saved settings, the slash commands and the one
-- frame that listens for game events. Loaded last, so every other file's
-- table already hangs off ns.

local addonName, ns = ...

local DEFAULTS = {
    useMacro = true,
    showBar = true,
    barScale = 1,
    barWidth = 220,
    barHeight = 16,
    -- "Blizzard" (the game's cast bar art) or "Flat".
    barStyle = "Blizzard",
    -- Names from UI/Media.lua. "Default" is the game's own font. The texture
    -- and the colours are for the Flat style.
    barTexture = "Solid",
    barFont = "Default",
    barFontSize = 10,
    -- Font flags: "", "OUTLINE" or "THICKOUTLINE".
    barFontOutline = "",
    barIcon = true,
    -- Colours are { red, green, blue }, each from 0 to 1.
    barColor = { 1.0, 0.62, 0.0 },
    fullColor = { 0.2, 0.78, 0.3 },
}
ns.DEFAULTS = DEFAULTS

local L = ns.L
-- The blue of the addon's icon, lightened to read on chat.
local BRAND = "|cff7aa2e3"

local function IsColor(value)
    return type(value) == "table"
        and type(value[1]) == "number"
        and type(value[2]) == "number"
        and type(value[3]) == "number"
end

-- Seconds after entering the world at which the game's macros are taken as
-- loaded, if UPDATE_MACROS has not said so first.
local MACRO_WAIT = 2

function ns.Print(message)
    print(BRAND .. addonName .. "|r: " .. message)
end

local frame = CreateFrame("Frame")

local function LoadSettings()
    if type(BiscuitBreakDB) ~= "table" then BiscuitBreakDB = {} end
    for key, value in pairs(DEFAULTS) do
        local saved = BiscuitBreakDB[key]
        if type(value) == "table" then
            -- A copy, so changing the saved colour leaves the default alone.
            if not IsColor(saved) then BiscuitBreakDB[key] = { value[1], value[2], value[3] } end
        elseif type(saved) ~= type(value) then
            BiscuitBreakDB[key] = value
        end
    end
    ns.db = BiscuitBreakDB
    if type(ns.db.excludedItems) ~= "table" then ns.db.excludedItems = {} end
end

local handlers = {}

-- Applies the "Show the recovery bar" setting: the effect event is registered
-- only while the bar is wanted.
function ns.SyncBar()
    if ns.db.showBar then
        frame:RegisterUnitEvent("UNIT_AURA", "player")
    else
        frame:UnregisterEvent("UNIT_AURA")
    end
    ns.Meal.SetActive(ns.db.showBar)
end

function handlers.ADDON_LOADED(name)
    if name ~= addonName then return end
    frame:UnregisterEvent("ADDON_LOADED")
    -- Saved settings exist only from this event on, never at file scope.
    LoadSettings()
    ns.Options.Register()
    ns.Minimap.Sync()

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("UPDATE_MACROS")
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    frame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ns.SyncBar()
end

handlers.UNIT_AURA = ns.Meal.Request

function handlers.PLAYER_LEVEL_UP(level)
    ns.Scan.SetLevel(level)
    ns.Scan.Request()
end

-- Maximum health changes the result only for percentage food.
function handlers.UNIT_MAXHEALTH()
    if ns.Scan.hasPercent then ns.Scan.Request() end
end

-- Maximum mana also decides whether a drink is picked at all, so a scan that
-- read it as zero must run again once it changes. The power type in the event
-- is not read, in case the game hides it.
handlers.UNIT_MAXPOWER = ns.Scan.Request

function handlers.PLAYER_ENTERING_WORLD()
    ns.Scan.Request()
    ns.Meal.Request()
    C_Timer.After(MACRO_WAIT, ns.Macro.SetReady)
end

-- The first one after login means the game's macros are loaded.
function handlers.UPDATE_MACROS()
    frame:UnregisterEvent("UPDATE_MACROS")
    ns.Macro.SetReady()
end

-- Combat ended: write the macro if a change was waiting, and rescan in case
-- the bags changed during the fight.
function handlers.PLAYER_REGEN_ENABLED()
    ns.Macro.Flush()
    ns.Scan.Request()
end

handlers.BAG_UPDATE_DELAYED = ns.Scan.Request

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)
frame:RegisterEvent("ADDON_LOADED")

-- Puts every setting back to its default and redraws everything that shows
-- one. Asked for by the reset button and /bb reset, after a confirmation.
function ns.ResetSettings()
    wipe(BiscuitBreakDB)
    LoadSettings()
    ns.Minimap.Sync()
    ns.SyncBar()
    ns.Bar.ResetPosition()
    ns.Bar.Apply()
    ns.Scan.Run(true)
    ns.Macro.Update()
    ns.Options.Sync()
    ns.Print(L["Settings reset."])
end

local function Command(text)
    return "|cffffffff" .. text .. "|r"
end

local COMMANDS = {
    [""] = function() ns.Options.Toggle() end,
    reset = function() StaticPopup_Show("BISCUITBREAK_RESET") end,
    version = function()
        ns.Print(string.format(L["Version %s"], C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))
    end,
    help = function()
        ns.Print(L["Commands:"])
        print("  " .. Command("/bb") .. " - " .. L["open the settings"])
        print("  " .. Command("/bb reset") .. " - " .. L["reset every setting"])
        print("  " .. Command("/bb version") .. " - " .. L["show the version"])
    end,
}

SLASH_BISCUITBREAK1 = "/bb"
SLASH_BISCUITBREAK2 = "/biscuitbreak"
SlashCmdList.BISCUITBREAK = function(input)
    local command = COMMANDS[strtrim(input or ""):lower()]
    if command then
        command()
    else
        ns.Print(string.format(L["Unknown command. Type %s for a list."], Command("/bb help")))
    end
end
