-- Media: the bar textures and fonts on offer. The game's own are always
-- there. LibSharedMedia adds every one another addon has registered, when
-- some addon has loaded that library.

local _, ns = ...

local Media = {}
ns.Media = Media

-- Named as LibSharedMedia names them, so a saved name means the same file
-- with the library and without it.
local BUILT_IN = {
    statusbar = {
        { "Solid", "Interface\\Buttons\\WHITE8X8" },
        { "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
        { "Blizzard Raid Bar", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
        { "Blizzard Character Skills Bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    },
    font = {
        { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
        { "Arial Narrow", "Fonts\\ARIALN.TTF" },
        { "Morpheus", "Fonts\\MORPHEUS.TTF" },
        { "Skurri", "Fonts\\SKURRI.TTF" },
    },
}

-- Looked up on each use: the addons that carry the library load after this one.
local function Shared()
    return LibStub("LibSharedMedia-3.0", true)
end

-- The names on offer, sorted. kind: "statusbar" or "font".
function Media.List(kind)
    local names, seen = {}, {}
    for _, entry in ipairs(BUILT_IN[kind]) do
        names[#names + 1] = entry[1]
        seen[entry[1]] = true
    end
    local shared = Shared()
    if shared then
        for _, name in ipairs(shared:List(kind)) do
            if not seen[name] then names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

-- The file behind a name, or nil when nothing offers it any more.
function Media.Fetch(kind, name)
    local shared = Shared()
    local file = shared and shared:Fetch(kind, name, true)
    if file then return file end
    for _, entry in ipairs(BUILT_IN[kind]) do
        if entry[1] == name then return entry[2] end
    end
    return nil
end
