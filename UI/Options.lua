-- Options: the settings window, opened by /bb and the minimap button, and the
-- eating bar's own settings window, opened by a button on it. They are the
-- addon's own windows, not pages of the game's settings, so they can sit
-- beside the bar while you size and place it, and they open in combat. The
-- page under Esc > Options > AddOns only has a button that opens the first.
-- Neither holds logic of its own: they show what Scan found and flip switches.

local addonName, ns = ...

local Options = {}
ns.Options = Options

local L = ns.L
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local LEFT = 16
local WINDOW_WIDTH = 420
local CONTENT_WIDTH = WINDOW_WIDTH - 2 * LEFT
-- The window's height without its two priority lists, which grow and shrink
-- with what you carry.
local STATIC_HEIGHT = 302
-- A priority list: its label, then up to MAX_ROWS rows.
local LABEL_HEIGHT, ROW_HEIGHT, ROW_GAP, MAX_ROWS = 16, 18, 3, 5
-- The bar's settings window, and the box in it that holds the preview.
local BAR_PANEL_HEIGHT, PREVIEW_HEIGHT = 300, 90

local window, barPanel
local lists = {}
local checkboxes = {}
local resizeQueued = false

-- One line of a priority list: its place, an icon, the item with its count,
-- and on the right what it restores.
local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)

    row.place = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.place:SetPoint("LEFT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    row.icon:SetPoint("LEFT", 18, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.value:SetPoint("RIGHT")

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

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

-- A priority list: a label ("Food") over its rows. ShowList sets its height
-- to the rows showing, so whatever is anchored under it moves with it.
local function NewList(parent, label, anchor, offsetY)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(CONTENT_WIDTH, LABEL_HEIGHT)
    list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)

    local text = list:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT")
    text:SetText(label)

    list.rows = {}
    for i = 1, MAX_ROWS do
        list.rows[i] = NewRow(list)
        list.rows[i]:SetPoint("TOPLEFT", 0, -(LABEL_HEIGHT + (i - 1) * (ROW_HEIGHT + ROW_GAP)))
    end
    return list
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

local function Resize()
    resizeQueued = false
    ns.Bar.ApplySize()
end

local function FormatPixels(value)
    return string.format("%d", math.floor(value + 0.5))
end

local function FormatPercent(value)
    return string.format("%d%%", math.floor(value * 100 + 0.5))
end

-- A slider for one saved size of the bar, from min to max in steps of step.
-- Like a checkbox, it applies on the next frame: once, however many changes a
-- drag sends.
local function NewSlider(parent, key, text, anchor, offsetY, min, max, step, format)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    label:SetText(text)

    local slider = CreateFrame("Slider", nil, parent, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(220, 20)
    slider:SetPoint("LEFT", label, "LEFT", 90, 0)
    local right = MinimalSliderWithSteppersMixin.Label.Right
    local steps = math.floor((max - min) / step + 0.5)
    slider:Init(ns.db[key], min, max, steps, { [right] = CreateMinimalSliderFormatter(right, format) })
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        -- The slider's value can sit a hair off a step.
        local rounded = math.floor(value / step + 0.5) * step
        if rounded == ns.db[key] then return end
        ns.db[key] = rounded
        if not resizeQueued then
            resizeQueued = true
            C_Timer.After(0, Resize)
        end
    end)
    return label
end

local function Shade(row, shade)
    row.place:SetTextColor(shade, shade, shade)
    row.text:SetTextColor(shade, shade, shade)
    row.value:SetTextColor(shade, shade, shade)
end

-- A row for the item in the given place on its list. The pick, in place 1,
-- is the brightest. An item above your level has no place and is greyed.
local function ShowItem(row, place, item, key)
    row.itemID = item.id
    row.icon:SetTexture(C_Item.GetItemIconByID(item.id) or QUESTION_ICON)
    row.icon:SetDesaturated(not item.usable)
    row.icon:Show()
    local name = C_Item.GetItemNameByID(item.id)
    if not name then
        -- Not loaded yet: GET_ITEM_INFO_RECEIVED refreshes the window.
        C_Item.RequestLoadItemDataByID(item.id)
        name = L["Loading..."]
    end
    row.text:SetText(string.format("%s  x%d", name, item.count))
    if item.usable then
        row.place:SetText(place .. ".")
        -- Percentage food gives fractions; %d wants a whole number.
        local amount = math.floor(item[key] + 0.5)
        row.value:SetText(string.format(key == "health" and L["%d health"] or L["%d mana"], amount))
        Shade(row, place == 1 and 1 or 0.75)
    else
        row.place:SetText("")
        row.value:SetText(string.format(L["Needs level %d"], item.level))
        Shade(row, 0.5)
    end
    row:Show()
end

-- A row of plain grey text, for an empty list or for what did not fit.
local function ShowNote(row, text)
    row.itemID = nil
    row.icon:Hide()
    row.place:SetText("")
    row.text:SetText(text)
    row.value:SetText("")
    Shade(row, 0.5)
    row:Show()
end

-- Fills a list with items, already in priority order.
local function ShowList(list, items, key, emptyText)
    local rows = list.rows
    local shown
    if #items == 0 then
        ShowNote(rows[1], emptyText)
        shown = 1
    else
        -- Too many for the rows: the last row says how many are left out.
        shown = #items > MAX_ROWS and MAX_ROWS - 1 or #items
        for i = 1, shown do
            ShowItem(rows[i], i, items[i], key)
        end
        if shown < #items then
            shown = shown + 1
            ShowNote(rows[shown], string.format(L["and %d more"], #items - shown + 1))
        end
    end
    for i = shown + 1, MAX_ROWS do
        rows[i]:Hide()
    end
    list:SetHeight(LABEL_HEIGHT + shown * (ROW_HEIGHT + ROW_GAP))
end

local NOTHING = {}

-- Repaints the window from what Scan knows. Cheap, and a no-op while hidden.
function Options.Refresh()
    if not window or not window:IsVisible() then return end
    local found = ns.Scan.found
    ShowList(lists.food, ns.Scan.Order(found, "health"), "health", L["No food in your bags"])
    if ns.Scan.hasMana then
        ShowList(lists.drink, ns.Scan.Order(found, "mana"), "mana", L["No drink in your bags"])
    else
        ShowList(lists.drink, NOTHING, "mana", L["Your class does not use mana"])
    end
    window:SetHeight(STATIC_HEIGHT + lists.food:GetHeight() + lists.drink:GetHeight())
    for i = 1, #checkboxes do
        checkboxes[i]:SetChecked(checkboxes[i].get())
    end
end

-- One of the addon's windows: the game's own titled window, draggable, closed
-- by its X or by Escape. The caller places it.
local function NewWindow(name, title, height)
    local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    -- Hidden before it has scripts, so the first Show runs OnShow.
    frame:Hide()
    frame:SetSize(WINDOW_WIDTH, height)
    -- Above the game's settings window, whose page has a button that opens ours.
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    frame.Inset:Hide()
    frame:SetTitle(title)
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    table.insert(UISpecialFrames, name)

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    return frame
end

-- The bar's own settings: a preview in a box, the sizes, and the position.
-- While it is open the bar itself is on screen and can be dragged.
local function BuildBarPanel()
    barPanel = NewWindow("BiscuitBreakBarOptions", L["BiscuitBreak eating bar"], BAR_PANEL_HEIGHT)
    -- Right of centre, the main window being left of it: the bar starts out
    -- below the middle of the screen, between the two.
    barPanel:SetPoint("LEFT", UIParent, "CENTER", 160, 0)

    local box = CreateFrame("Frame", nil, barPanel, "InsetFrameTemplate")
    box:SetSize(CONTENT_WIDTH, PREVIEW_HEIGHT)
    box:SetPoint("TOPLEFT", LEFT, -36)
    ns.Bar.NewPreview(box)

    local scale = NewSlider(barPanel, "barScale", L["Scale"], box, -16, 0.5, 2, 0.05, FormatPercent)
    local width = NewSlider(barPanel, "barWidth", L["Width"], scale, -14, 100, 400, 10, FormatPixels)
    local height = NewSlider(barPanel, "barHeight", L["Height"], width, -14, 10, 40, 1, FormatPixels)

    local hint = barPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", height, "BOTTOMLEFT", 0, -14)
    hint:SetWidth(CONTENT_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["The bar is on your screen while this window is open. Drag it where you want it."])

    local reset = CreateFrame("Button", nil, barPanel, "UIPanelButtonTemplate")
    reset:SetSize(160, 24)
    reset:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    reset:SetText(L["Reset bar position"])
    reset:SetScript("OnClick", ns.Bar.ResetPosition)

    barPanel:SetScript("OnShow", function() ns.Bar.SetUnlocked(true) end)
    -- Closing it locks the bar, so a sample bar is never left behind.
    barPanel:SetScript("OnHide", function() ns.Bar.SetUnlocked(false) end)
end

local function ToggleBarPanel()
    if not barPanel then BuildBarPanel() end
    barPanel:SetShown(not barPanel:IsShown())
end

local function Build()
    -- Options.Refresh adds the height of the priority lists.
    window = NewWindow("BiscuitBreakOptions", addonName, STATIC_HEIGHT)
    -- Left of centre: see BuildBarPanel.
    window:SetPoint("RIGHT", UIParent, "CENTER", -160, 0)

    local intro = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", LEFT, -36)
    intro:SetWidth(CONTENT_WIDTH)
    intro:SetJustifyH("LEFT")
    intro:SetText(L["Your BiscuitBreak macro always uses the strongest food and drink in your bags."])

    local heading = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
    heading:SetText(L["Priority"])

    lists.food = NewList(window, L["Food"], heading, -10)
    lists.drink = NewList(window, L["Drink"], lists.food, -10)

    local settings = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    settings:SetPoint("TOPLEFT", lists.drink, "BOTTOMLEFT", 0, -24)
    settings:SetText(L["Settings"])

    local useMacro =
        NewSetting(window, "useMacro", L["Keep the BiscuitBreak macro up to date"], settings, -10, ns.Macro.Update)
    -- Saved the way LibDBIcon reads it: ns.db.minimap.hide.
    local showButton = NewCheckbox(window, L["Show the minimap button"], useMacro, -8, function()
        return not ns.db.minimap.hide
    end, function(value)
        ns.db.minimap.hide = not value
    end, ns.Minimap.Sync)
    local showBar = NewSetting(window, "showBar", L["Show the eating bar"], showButton, -8, ns.SyncBar)

    local barButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    barButton:SetSize(160, 24)
    barButton:SetPoint("TOPLEFT", showBar, "BOTTOMLEFT", 0, -14)
    barButton:SetText(L["Eating bar settings"])
    barButton:SetScript("OnClick", ToggleBarPanel)

    window:SetScript("OnShow", function(self)
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        -- Bags may have changed while the window was closed.
        ns.Scan.Run(true)
        Options.Refresh()
    end)
    window:SetScript("OnHide", function(self)
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        -- The bar's settings are opened from here, so they close with it.
        if barPanel then barPanel:Hide() end
    end)
    window:SetScript("OnEvent", Options.Refresh)
end

-- Opens the window, or closes it if it is open. Built on first use.
function Options.Toggle()
    if not window then Build() end
    window:SetShown(not window:IsShown())
end

-- Adds a page to the game's settings window that points at this one. Called
-- once, at ADDON_LOADED.
function Options.Register()
    local page = CreateFrame("Frame")
    -- The settings window calls these on every canvas page.
    page.OnCommit = function() end
    page.OnDefault = function() end
    page.OnRefresh = function() end

    -- A centred stack: the name in big letters, the version, how to get to
    -- the settings, and a big button that opens them. Offsets are in each
    -- piece's own scale.
    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge3")
    title:SetScale(3)
    title:SetPoint("CENTER", 0, 30)
    title:SetText(addonName)

    local version = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    version:SetPoint("CENTER", 0, 28)
    version:SetTextColor(1, 1, 1)
    version:SetText(string.format(L["Version: %s"], C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))

    local text = page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge3")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1)
    text:SetText(L["Access settings with /bb"])

    -- The game's large button where the client has it.
    local template = "SharedButtonLargeTemplate"
    if not C_XMLUtil.GetTemplateInfo(template) then template = "UIPanelDynamicResizeButtonTemplate" end
    local open = CreateFrame("Button", nil, page, template)
    open:SetText(L["Open settings"])
    open.padding = 40
    DynamicResizeButton_Resize(open)
    open:SetScale(2)
    open:SetPoint("CENTER", 0, -30)
    open:SetScript("OnClick", Options.Toggle)

    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, addonName))
end

