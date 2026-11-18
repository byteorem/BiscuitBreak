-- Minimap: the minimap button. A click opens the settings window. LibDBIcon
-- draws and drags it, and saves its place in ns.db.minimap.

local addonName, ns = ...

local Minimap = {}
ns.Minimap = Minimap

local L = ns.L
local ICON = "Interface\\AddOns\\BiscuitBreak\\Media\\Icon.tga"

local launcher

-- The tooltip of the minimap button and of the addon compartment entry.
local function FillTooltip(tooltip)
    tooltip:SetText("|T" .. ICON .. ":16|t " .. addonName, 1, 1, 1)
    tooltip:AddLine(L["Your best food and drink on one button."], nil, nil, nil, true)
    tooltip:AddLine(" ")
    tooltip:AddLine(L["Click to open the settings."], 0.1, 1, 0.1)
end

-- Applies the "Show the minimap button" setting. Called at ADDON_LOADED and
-- whenever the setting changes.
function Minimap.Sync()
    local db = ns.db.minimap
    if type(db) ~= "table" then
        db = {}
        ns.db.minimap = db
    end

    if not launcher then
        launcher = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
            type = "launcher",
            text = addonName,
            icon = ICON,
            OnClick = function()
                ns.Options.Toggle()
            end,
            OnTooltipShow = function(tooltip)
                FillTooltip(tooltip)
                tooltip:AddLine(L["Drag to move this button."], 0.1, 1, 0.1)
            end,
        })
    end

    local icons = LibStub("LibDBIcon-1.0")
    if icons:IsRegistered(addonName) then
        icons:Refresh(addonName, db)
    elseif not db.hide then
        -- A hidden button is never created: LibDBIcon shows new buttons until
        -- login, long enough for a button collector to pick one up.
        icons:Register(addonName, launcher, db)
    end
end

-- The addon compartment, the game's list of addons under the minimap. The
-- .toc names these.
function BiscuitBreak_OnAddonCompartmentClick()
    ns.Options.Toggle()
end

function BiscuitBreak_OnAddonCompartmentEnter(_, owner)
    GameTooltip:SetOwner(owner or UIParent, "ANCHOR_LEFT")
    FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function BiscuitBreak_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
