-- Tests for the pure parts of Core/Macro.lua. Run from the addon folder:
--     lua tests/macro_test.lua

local ns = {}
local function Load(path)
    local chunk = assert(loadfile(path))
    chunk("BiscuitBreak", ns)
end
Load("Core/Locale.lua")
Load("Core/Macro.lua")

local Body, LooksLikeOurs = ns.Macro.Body, ns.Macro.LooksLikeOurs
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

Check("empty text is ours", LooksLikeOurs(""), true)
Check("nil text is ours", LooksLikeOurs(nil), true)
Check("one line is ours", LooksLikeOurs("/use item:1114"), true)
Check("two lines are ours", LooksLikeOurs("/use item:1114\n/use item:3772"), true)
Check("a trailing newline is ours", LooksLikeOurs("/use item:1114\n"), true)
Check("windows line ends are ours", LooksLikeOurs("/use item:1114\r\n/use item:3772"), true)
Check("item names are not ours", LooksLikeOurs("/use Conjured Rye\n/use Conjured Spring Water"), false)
Check("a tooltip line is not ours", LooksLikeOurs("#showtooltip\n/use item:1114"), false)
Check("another command is not ours", LooksLikeOurs("/cast Fireball"), false)
Check("a conditional is not ours", LooksLikeOurs("/use [nocombat] item:1114"), false)
Check("what Body writes is ours", LooksLikeOurs(Body(1114, 3772)), true)

print(string.format("%d checks, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
