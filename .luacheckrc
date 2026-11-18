std = "lua51"
max_line_length = 120
exclude_files = { ".git", "Libs" }

-- Globals the addon defines.
globals = {
    "BiscuitBreakDB",
    "SLASH_BISCUITBREAK1",
    "SLASH_BISCUITBREAK2",
    "SlashCmdList",
}

-- Game API the addon reads.
read_globals = {
    "C_Container",
    "C_CurveUtil",
    "C_Item",
    "C_Secrets",
    "C_Timer",
    "C_UnitAuras",
    "GetTime",
    "UIParent",
    "UnitHealthPercent",
    "UnitPowerPercent",
    "geterrorhandler",
    "Constants",
    "CreateFrame",
    "CreateMacro",
    "EditMacro",
    "Enum",
    "GameTooltip",
    "GetMacroIndexByName",
    "GetMacroInfo",
    "GetNumMacros",
    "InCombatLockdown",
    "LibStub",
    "MAX_ACCOUNT_MACROS",
    "NUM_BAG_SLOTS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    "Settings",
    "UnitHealthMax",
    "UnitLevel",
    "UnitPowerMax",
    "issecretvalue",
    "wipe",
}

-- Tests run in a stock Lua interpreter, outside the game.
files["tests"] = { std = "max" }
