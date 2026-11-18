-- Item priorities and recovery bar settings share one tabbed window.

local addonName, ns = ...

local Options = {}
ns.Options = Options

local L = ns.L
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local WINDOW_WIDTH, WINDOW_HEIGHT = 490, 650
local LEFT = 20
local CONTENT_WIDTH = WINDOW_WIDTH - 2 * LEFT
local LABEL_HEIGHT, ROW_HEIGHT, ROW_GAP, MAX_ROWS = 30, 20, 2, 5
-- Where a bar setting's control starts, right of its label.
local CONTROL_X, CONTROL_WIDTH = 90, 220
-- A dropdown with more choices than this scrolls.
local MENU_ROWS, MENU_ROW_HEIGHT = 15, 20
local OUTLINES = {
    { "None", "" },
    { "Outline", "OUTLINE" },
    { "Thick outline", "THICKOUTLINE" },
}

local window
local lists = {}
local checkboxes = {}
local applyQueued = false

-- One line of a priority list: its place, an icon, the item with its count,
-- and on the right what it restores.
local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(CONTENT_WIDTH - 24, ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")

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
    row:SetScript("OnClick", function(self)
        local id = self.itemID
        if not id then return end
        ns.db.excludedItems[id] = not ns.db.excludedItems[id] or nil
        ns.Scan.Run(true)
    end)
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
    local list = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    list:SetSize(CONTENT_WIDTH, LABEL_HEIGHT)
    list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)

    local text = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", 12, -8)
    text:SetText(label)

    list.page = 1
    list.nextPage = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    list.nextPage:SetSize(110, 20)
    list.nextPage:SetPoint("TOPRIGHT", -8, -4)
    list.nextPage:SetScript("OnClick", function()
        list.page = list.page % list.pages + 1
        Options.Refresh()
    end)

    list.rows = {}
    for i = 1, MAX_ROWS do
        list.rows[i] = NewRow(list)
        list.rows[i]:SetPoint("TOPLEFT", 12, -(LABEL_HEIGHT + (i - 1) * (ROW_HEIGHT + ROW_GAP)))
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

local function Apply()
    applyQueued = false
    ns.Bar.Apply()
end

-- Redraws the bar on the next frame: once, however many changes ask for it.
local function QueueApply()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0, Apply)
end

-- The name of a bar setting, at the left of its row.
local function NewLabel(parent, text, anchor, offsetY)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    label:SetText(text)
    return label
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
    local label = NewLabel(parent, text, anchor, offsetY)

    local slider = CreateFrame("Slider", nil, parent, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(CONTROL_WIDTH, 20)
    slider:SetPoint("LEFT", label, "LEFT", CONTROL_X, 0)
    local right = MinimalSliderWithSteppersMixin.Label.Right
    local steps = math.floor((max - min) / step + 0.5)
    slider:Init(ns.db[key], min, max, steps, { [right] = CreateMinimalSliderFormatter(right, format) })
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        -- The slider's value can sit a hair off a step.
        local rounded = math.floor(value / step + 0.5) * step
        if rounded == ns.db[key] then return end
        ns.db[key] = rounded
        QueueApply()
    end)
    return label
end

-- A dropdown for one saved choice of the bar. choices returns the list as
-- { { text, value }, ... } and is asked each time the menu opens, so it can
-- offer what other addons have added since.
local function NewDropdown(parent, key, text, anchor, offsetY, choices)
    local label = NewLabel(parent, text, anchor, offsetY)

    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(CONTROL_WIDTH)
    dropdown:SetPoint("LEFT", label, "LEFT", CONTROL_X, 0)
    local function IsChosen(value)
        return ns.db[key] == value
    end
    local function Choose(value)
        ns.db[key] = value
        QueueApply()
    end
    dropdown:SetupMenu(function(_, root)
        local list = choices()
        if #list > MENU_ROWS then root:SetScrollMode(MENU_ROWS * MENU_ROW_HEIGHT) end
        for _, choice in ipairs(list) do
            root:CreateRadio(choice[1], IsChosen, Choose, choice[2])
        end
    end)
    return label
end

-- A square of one saved colour of the bar, with its name beside it. A click
-- opens the game's colour picker; cancelling the picker puts the colour back.
local function NewSwatch(parent, key, text, anchor, offsetX)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", anchor, "LEFT", offsetX, 0)
    local edge = swatch:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0)
    local color = swatch:CreateTexture(nil, "ARTWORK")
    color:SetPoint("TOPLEFT", 1, -1)
    color:SetPoint("BOTTOMRIGHT", -1, 1)
    local name = swatch:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    name:SetText(text)
    swatch:SetHitRectInsets(0, -(6 + name:GetStringWidth()), 0, 0)

    local function Set(r, g, b)
        ns.db[key] = { r, g, b }
        color:SetColorTexture(r, g, b)
        QueueApply()
    end
    swatch:SetScript("OnClick", function()
        local r, g, b = ns.db[key][1], ns.db[key][2], ns.db[key][3]
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = function() Set(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() Set(r, g, b) end,
        })
    end)
    color:SetColorTexture(ns.db[key][1], ns.db[key][2], ns.db[key][3])
    return swatch
end

local function TextureChoices()
    local list = {}
    for _, name in ipairs(ns.Media.List("statusbar")) do
        list[#list + 1] = { name, name }
    end
    return list
end

-- The game's own font comes first, under a name of its own.
local function FontChoices()
    local list = { { L["Default"], "Default" } }
    for _, name in ipairs(ns.Media.List("font")) do
        list[#list + 1] = { name, name }
    end
    return list
end

local function OutlineChoices()
    local list = {}
    for i, outline in ipairs(OUTLINES) do
        list[i] = { L[outline[1]], outline[2] }
    end
    return list
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
    row:EnableMouse(true)
    row.icon:SetTexture(C_Item.GetItemIconByID(item.id) or QUESTION_ICON)
    row.icon:SetDesaturated(item.excluded or not item.usable)
    row.icon:Show()
    local name = C_Item.GetItemNameByID(item.id)
    if not name then
        -- Not loaded yet: GET_ITEM_INFO_RECEIVED refreshes the window.
        C_Item.RequestLoadItemDataByID(item.id)
        name = L["Loading..."]
    end
    row.text:SetText(string.format("%s  x%d", name, item.count))
    if item.excluded then
        row.place:SetText("")
        row.value:SetText(L["Excluded"])
        Shade(row, 0.5)
    elseif item.usable then
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
    row:EnableMouse(false)
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
    list.pages = math.max(1, math.ceil(#items / MAX_ROWS))
    list.page = math.min(list.page, list.pages)
    list.nextPage:SetShown(list.pages > 1)
    list.nextPage:SetText(string.format(L["Page %d/%d >"], list.page, list.pages))
    local offset = (list.page - 1) * MAX_ROWS
    local shown
    if #items == 0 then
        ShowNote(rows[1], emptyText)
        shown = 1
    else
        shown = math.min(MAX_ROWS, #items - offset)
        for i = 1, shown do
            ShowItem(rows[i], offset + i, items[offset + i], key)
        end
    end
    for i = shown + 1, MAX_ROWS do
        rows[i]:Hide()
    end
    list:SetHeight(LABEL_HEIGHT + shown * (ROW_HEIGHT + ROW_GAP) + 3)
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

local function BuildBarPanel(barPanel)
    local box = CreateFrame("Frame", nil, barPanel, "InsetFrameTemplate")
    box:SetSize(CONTENT_WIDTH, 108)
    box:SetPoint("TOPLEFT", LEFT, -10)
    ns.Bar.NewPreview(box)

    local show = NewSetting(barPanel, "showBar", L["Show the recovery bar"], box, -16, ns.SyncBar)
    local scale = NewSlider(barPanel, "barScale", L["Scale"], show, -20, 0.5, 2, 0.05, FormatPercent)
    local width = NewSlider(barPanel, "barWidth", L["Width"], scale, -22, 100, 400, 10, FormatPixels)
    local height = NewSlider(barPanel, "barHeight", L["Height"], width, -22, 10, 40, 1, FormatPixels)
    local texture = NewDropdown(barPanel, "barTexture", L["Texture"], height, -22, TextureChoices)
    local font = NewDropdown(barPanel, "barFont", L["Font"], texture, -22, FontChoices)
    local fontSize = NewSlider(barPanel, "barFontSize", L["Font size"], font, -22, 8, 20, 1, FormatPixels)
    local outline = NewDropdown(barPanel, "barFontOutline", L["Outline"], fontSize, -22, OutlineChoices)
    local colors = NewLabel(barPanel, L["Colors"], outline, -22)
    NewSwatch(barPanel, "barColor", L["Bar"], colors, CONTROL_X)
    NewSwatch(barPanel, "fullColor", L["Full"], colors, CONTROL_X + CONTROL_WIDTH / 2)
    local icon = NewSetting(barPanel, "barIcon", L["Show the icon"], colors, -14, ns.Bar.Apply)

    local hint = barPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
    hint:SetWidth(CONTENT_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Red is health and blue is mana. Each tick slides up the bar and reaches the end when you are full."]
        .. "\n" .. L["Drag the bar on your screen to move it."])

    local reset = CreateFrame("Button", nil, barPanel, "UIPanelButtonTemplate")
    reset:SetSize(160, 24)
    reset:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    reset:SetText(L["Reset bar position"])
    reset:SetScript("OnClick", ns.Bar.ResetPosition)

    barPanel:SetScript("OnShow", function() ns.Bar.SetUnlocked(true) end)
    -- Closing it locks the bar, so a sample bar is never left behind.
    barPanel:SetScript("OnHide", function() ns.Bar.SetUnlocked(false) end)
end

local function Build()
    window = NewWindow("BiscuitBreakOptions", addonName, WINDOW_HEIGHT)
    window:SetPoint("CENTER", UIParent, "CENTER", -150, 40)

    local pages, tabs = {}, {}
    local function SelectPage(selected)
        for i, tab in ipairs(tabs) do
            pages[i]:SetShown(i == selected)
            if i == selected then
                PanelTemplates_SelectTab(tab)
            else
                PanelTemplates_DeselectTab(tab)
            end
        end
    end

    for i, title in ipairs({ L["Food & Drink"], L["Recovery Bar"] }) do
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 0, -65)
        page:SetPoint("BOTTOMRIGHT")
        pages[i] = page

        local tab = CreateFrame("Button", nil, window, "PanelTopTabButtonTemplate")
        tab:SetText(title)
        PanelTemplates_TabResize(tab, 15, nil, 90)
        if i == 1 then
            tab:SetPoint("TOPLEFT", LEFT, -27)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 5, 0)
        end
        tabs[i] = tab
        tab:SetScript("OnClick", function() SelectPage(i) end)
    end

    local priority = pages[1]
    local intro = priority:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", LEFT, -10)
    intro:SetWidth(CONTENT_WIDTH)
    intro:SetJustifyH("LEFT")
    intro:SetText(L["Click a food or drink to exclude it from the macro. Click an excluded item to include it again."])

    lists.food = NewList(priority, L["Food"], intro, -12)
    lists.drink = NewList(priority, L["Drink"], lists.food, -8)

    local settings = priority:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    settings:SetPoint("BOTTOMLEFT", priority, "BOTTOMLEFT", LEFT, 78)
    settings:SetText(L["Settings"])

    local useMacro =
        NewSetting(priority, "useMacro", L["Keep the BiscuitBreak macro up to date"], settings, -10, ns.Macro.Update)
    -- Saved the way LibDBIcon reads it: ns.db.minimap.hide.
    NewCheckbox(priority, L["Show the minimap button"], useMacro, -8, function()
        return not ns.db.minimap.hide
    end, function(value)
        ns.db.minimap.hide = not value
    end, ns.Minimap.Sync)
    BuildBarPanel(pages[2])
    SelectPage(1)

    window:SetScript("OnShow", function(self)
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        -- Bags may have changed while the window was closed.
        ns.Scan.Run(true)
    end)
    window:SetScript("OnHide", function(self)
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
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

