-- Tests for the pure parts of Core/Macro.lua. Run from the addon folder:
--     lua tests/macro_test.lua

local ns = {}
local function Load(path)
    local chunk = assert(loadfile(path))
    chunk("BiscuitBreak", ns)
end
Load("Core/Locale.lua")
Load("Core/Macro.lua")

local Body = ns.Macro.Body
local failures, count = 0, 0

local function Check(name, got, want)
    count = count + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

Check("food and drink", Body(1114, 3772), "/use item:1114\n/use item:3772")
Check("food only", Body(1114, nil), "/use item:1114")
Check("drink only", Body(nil, 3772), "/use item:3772")
Check("nothing", Body(nil, nil), "")
Check("one item that is both", Body(3448, 3448), "/use item:3448")

local Items = ns.Macro.Items
Check("reads both items back", table.concat(Items(Body(1114, 3772)), ","), "1114,3772")
Check("reads one item back", table.concat(Items(Body(nil, 3772)), ","), "3772")
Check("reads no items from other text", #Items("/cast Fireball"), 0)

local account = { { name = "BiscuitBreak", body = "/cast Fireball" } }
local personal = { name = "_BB_Meal", body = "/cast Blink" }
local combat = false
function GetNumMacros() return #account, 1 end
function GetMacroInfo(i)
    local macro = i == 121 and personal or account[i]
    if macro then return macro.name, "icon", macro.body end
end
function CreateMacro(name, _, body)
    account[#account + 1] = { name = name, body = body }
    return #account
end
function EditMacro(i, name, _, body)
    account[i].name = name or account[i].name
    account[i].body = body
    table.sort(account, function(a, b) return a.name < b.name end)
end
function InCombatLockdown() return combat end
ns.Print = function() end
ns.Scan = { ran = true, picks = { food = 1114 } }
ns.db = { useMacro = true }
ns.Macro.SetReady()
Check("leaves untracked legacy macro alone", account[1].body, "/cast Fireball")
Check("uses fixed name on General tab", account[2].name, "_BB_Meal")
Check("creates one General macro", #account, 2)
ns.Macro.Update()
Check("reuses fixed name", #account, 2)
account[2].body = "/cast Blizzard"
ns.Macro.Update()
Check("overwrites player edits", account[2].body, Body(1114))
Check("no numbered duplicate", #account, 2)
Check("reports the macro's items", table.concat(ns.Macro.Current(), ","), "1114")

local legacy = { name = "BiscuitBreak", body = Body(159) }
account = { legacy, { name = "Other", body = "" } }
ns.db = { useMacro = true, lastMacroBody = legacy.body }
personal.name = "BiscuitBreak"
combat = true
ns.Macro.Update()
Check("defers migration during combat", legacy.name, "BiscuitBreak")
combat = false
ns.Macro.Flush()
Check("renames managed legacy macro in place", legacy.name, "_BB_Meal")
Check("clears migration state", ns.db.lastMacroBody, nil)
Check("updates migrated body", legacy.body, Body(1114))
Check("preserves character macro", personal.body, "/cast Blink")
Check("migration uses no additional slot", #account, 2)

legacy.name = "_BB_Meal2"
ns.db.macroName, ns.db.lastMacroBody = legacy.name, legacy.body
ns.Macro.Update()
Check("migrates numbered macro", legacy.name, "_BB_Meal")

print(string.format("%d checks, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
