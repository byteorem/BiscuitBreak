-- Minimap: the minimap button. A click opens the settings page. LibDBIcon
-- draws and drags it, and saves its place in ns.db.minimap.

local addonName, ns = ...

local Minimap = {}
ns.Minimap = Minimap

local L = ns.L
local ICON = "Interface\\Icons\\inv_misc_food_73cinnamonroll"

local launcher

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
                ns.Options.Open()
            end,
            OnTooltipShow = function(tooltip)
                tooltip:SetText(addonName)
                tooltip:AddLine(L["Click to open the settings."], 1, 1, 1)
                tooltip:AddLine(L["Drag to move this button."], 1, 1, 1)
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
