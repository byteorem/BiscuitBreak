-- Tooltip: the game shows only the macro's name when you hover its button.
-- This replaces that with the items the macro uses and what each restores.

local _, ns = ...

local L = ns.L

local QUESTION_ICON = 134400

local function Carried(id)
    local found = ns.Scan.found
    for i = 1, #found do
        if found[i].id == id then return found[i] end
    end
end

-- "552 health", "835 mana", or both for an item that restores both.
local function Restores(item)
    local parts = {}
    -- Percentage food gives fractions; %d wants a whole number.
    if item.health > 0 then parts[#parts + 1] = string.format(L["%d health"], math.floor(item.health + 0.5)) end
    if item.mana > 0 and ns.Scan.hasMana then
        parts[#parts + 1] = string.format(L["%d mana"], math.floor(item.mana + 0.5))
    end
    return table.concat(parts, ", ")
end

local function AddItem(tooltip, id)
    local name = C_Item.GetItemNameByID(id)
    if not name then
        -- Not loaded yet. The game redraws the tooltip while you hover.
        C_Item.RequestLoadItemDataByID(id)
        name = L["Loading..."]
    end
    local icon = C_Item.GetItemIconByID(id) or QUESTION_ICON
    local item = Carried(id)
    local left = string.format("|T%s:0|t %s (%d)", icon, name, item and item.count or 0)
    if item then
        tooltip:AddDoubleLine(left, Restores(item), 1, 1, 1, 1, 1, 1)
    else
        -- Used up, and the macro has not moved on yet.
        tooltip:AddLine(left, 0.5, 0.5, 0.5)
    end
end

local function OnSetAction(tooltip, slot)
    if not slot or GetActionInfo(slot) ~= "macro" then return end
    local name = GetActionText(slot)
    -- A hidden ("secret") value cannot be compared.
    if issecretvalue and issecretvalue(name) then return end
    if name ~= ns.Macro.NAME then return end
    local items = ns.Macro.Current()
    if not items then return end

    tooltip:ClearLines()
    tooltip:AddLine(L["Meal"], 1, 1, 1)
    if #items == 0 then
        tooltip:AddLine(L["No food or drink in your bags"], 0.5, 0.5, 0.5)
    else
        for i = 1, #items do
            AddItem(tooltip, items[i])
        end
        tooltip:AddLine(L["Must remain seated while eating or drinking."], 1, 0.82, 0, true)
    end
    tooltip:Show()
end

hooksecurefunc(GameTooltip, "SetAction", OnSetAction)
