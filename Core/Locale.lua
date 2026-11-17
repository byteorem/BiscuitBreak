-- Locale: every text the addon shows goes through ns.L, keyed by the English
-- text. A missing key returns the key itself, so English needs no table and a
-- translation is one table of ["English"] = "translated" pairs.

local _, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
