-- Options: the one settings page, under Esc > Options > AddOns > BiscuitBreak.
-- It holds no logic of its own: it shows what Scan picked and flips switches.
-- The page is a canvas (free layout) because the picks display needs an icon
-- and text placed by hand.

local addonName, ns = ...

local Options = {}
ns.Options = Options

local L = ns.L
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_SIZE = 32
local LEFT = 16

local panel, categoryID
local rows = {}
local checkboxes = {}
local wantUnlocked = false

-- One line of the picks display: an icon, a label ("Food") and the item.
local function NewRow(parent, label, anchor, offsetY)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(420, ICON_SIZE)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.label:SetText(label)

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)

    -- Hovering the row shows the item's own tooltip.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- A checkbox. get returns its state and set stores it. apply runs on the next
-- frame: changes are never applied from inside a settings click.
local function NewCheckbox(parent, text, anchor, offsetY, get, set, apply)
    local box = CreateFrame("CheckButton", nil, parent, "SettingsCheckBoxTemplate")
    box:SetSize(21, 20)
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    box.HoverBackground = nil
    box.text = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    box.text:SetPoint("LEFT", box, "RIGHT", 4, 0)
    box.text:SetText(text)
    -- Make the label clickable too.
    box:SetHitRectInsets(0, -box.text:GetStringWidth(), 0, 0)
    box:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        if apply then C_Timer.After(0, apply) end
    end)
    box.get = get
    checkboxes[#checkboxes + 1] = box
    return box
end

-- A checkbox for one saved setting.
local function NewSetting(parent, key, text, anchor, offsetY, apply)
    return NewCheckbox(parent, text, anchor, offsetY, function()
        return ns.db[key]
    end, function(value)
        ns.db[key] = value
    end, apply)
end

local function ShowPick(row, itemID, emptyText)
    row.itemID = itemID
    if not itemID then
        row.icon:SetTexture(QUESTION_ICON)
        row.icon:SetDesaturated(true)
        row.text:SetText(emptyText)
        return
    end
    row.icon:SetTexture(C_Item.GetItemIconByID(itemID) or QUESTION_ICON)
    row.icon:SetDesaturated(false)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        -- Not loaded yet: GET_ITEM_INFO_RECEIVED refreshes the page.
        C_Item.RequestLoadItemDataByID(itemID)
        name = L["Loading..."]
    end
    row.text:SetText(string.format("%s  x%d", name, C_Item.GetItemCount(itemID, false) or 0))
end

-- Repaints the page from what Scan knows. Cheap, and a no-op while hidden.
function Options.Refresh()
    if not panel or not panel:IsVisible() then return end
    local picks = ns.Scan.picks
    ShowPick(rows.food, picks.food, L["No food in your bags"])
    if ns.Scan.hasMana then
        ShowPick(rows.drink, picks.drink, L["No drink in your bags"])
    else
        ShowPick(rows.drink, nil, L["Your class does not use mana"])
    end
    for i = 1, #checkboxes do
        checkboxes[i]:SetChecked(checkboxes[i].get())
    end
end

-- Prints every food and drink the scan found, strongest first.
local function ListFound()
    local found = ns.Scan.found
    if #found == 0 then
        ns.Print(L["No food or drink found in your bags."])
        return
    end
    ns.Print(L["Food and drink in your bags, strongest first:"])
    for i = 1, #found do
        local item = found[i]
        local name = C_Item.GetItemNameByID(item.id) or ("item:" .. item.id)
        local parts = {}
        -- Percentage food gives fractions; %d wants a whole number.
        if item.health > 0 then
            parts[#parts + 1] = string.format(L["%d health"], math.floor(item.health + 0.5))
        end
        if item.mana > 0 then parts[#parts + 1] = string.format(L["%d mana"], math.floor(item.mana + 0.5)) end
        local line = string.format("  %s x%d: %s", name, item.count, table.concat(parts, ", "))
        if not item.usable then line = line .. " " .. string.format(L["(needs level %d)"], item.level) end
        print(line)
    end
end

local function Build()
    panel = CreateFrame("Frame")
    -- The settings window calls these on every canvas page.
    panel.OnCommit = function() end
    panel.OnDefault = function() end
    panel.OnRefresh = function() end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", LEFT, -16)
    title:SetText("BiscuitBreak")

    local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetWidth(560)
    intro:SetJustifyH("LEFT")
    intro:SetText(L["Your BiscuitBreak macro always uses the strongest food and drink in your bags."])

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
    heading:SetText(L["Current picks"])

    rows.food = NewRow(panel, L["Food"], heading, -10)
    rows.drink = NewRow(panel, L["Drink"], rows.food, -8)

    local list = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    list:SetSize(160, 24)
    list:SetPoint("TOPLEFT", rows.drink, "BOTTOMLEFT", 0, -20)
    list:SetText(L["List food found"])
    list:SetScript("OnClick", ListFound)

    local settings = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    settings:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -24)
    settings:SetText(L["Settings"])

    local useMacro =
        NewSetting(panel, "useMacro", L["Keep the BiscuitBreak macro up to date"], settings, -10, ns.Macro.Update)
    local showBar = NewSetting(panel, "showBar", L["Show the eating bar"], useMacro, -8, ns.SyncBar)

    -- Not saved: the bar locks again when the page closes.
    local unlockText = L["Unlock bar (drag it where you want it)"]
    local unlock = NewCheckbox(panel, unlockText, showBar, -8, ns.Bar.IsUnlocked, function(value)
        wantUnlocked = value
    end, function()
        ns.Bar.SetUnlocked(wantUnlocked)
    end)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(160, 24)
    reset:SetPoint("TOPLEFT", unlock, "BOTTOMLEFT", 0, -12)
    reset:SetText(L["Reset bar position"])
    reset:SetScript("OnClick", ns.Bar.ResetPosition)

    panel:SetScript("OnShow", function(self)
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        -- Bags may have changed while the page was closed.
        ns.Scan.Run(true)
        Options.Refresh()
    end)
    panel:SetScript("OnHide", function(self)
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        -- Leaving the page locks the bar, so a sample bar is never left behind.
        wantUnlocked = false
        ns.Bar.SetUnlocked(false)
    end)
    panel:SetScript("OnEvent", Options.Refresh)
end

-- Adds the page to the game's settings window. Called once, at ADDON_LOADED.
function Options.Register()
    if panel then return end
    Build()
    local category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
    Settings.RegisterAddOnCategory(category)
    categoryID = category:GetID()
end

function Options.Open()
    -- The game blocks opening the settings window in combat.
    if InCombatLockdown() then
        ns.Print(L["The settings can't open in combat. Try again after the fight."])
        return
    end
    if categoryID then Settings.OpenToCategory(categoryID) end
end
