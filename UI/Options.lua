-- Options: one tabbed window built from the game's own templates, and a page
-- in the game's AddOns settings that opens it.
--
-- Every setting sits on one grid: its name right-aligned in a left column,
-- its control in a right column, one row each, in sections under a gold
-- heading. Hovering a row explains the setting. Changes apply at once.

local addonName, ns = ...

local Options = {}
ns.Options = Options

local L = ns.L
local LOGO = "Interface\\AddOns\\BiscuitBreak\\Media\\Icon.tga"
local QUESTION_ICON = 134400

local WINDOW_WIDTH, WINDOW_HEIGHT = 520, 638
local PAD = 20
-- Pages start under the title bar and the tabs.
local PAGE_TOP = -65

-- The settings grid, in each row's own units: where a name ends and where
-- its control starts.
local ROW_HEIGHT = 28
local HEADING_HEIGHT = 34
local LABEL_RIGHT, CONTROL_LEFT, CONTROL_WIDTH = 150, 170, 250

-- The food and drink lists: rows visible before a list scrolls.
local LIST_HEADER, LIST_ROW, LIST_ROWS = 28, 22, 9

-- A dropdown with more choices than this scrolls.
local MENU_ROWS, MENU_ROW_HEIGHT = 15, 20
local OUTLINES = {
    { "None", "" },
    { "Outline", "OUTLINE" },
    { "Thick outline", "THICKOUTLINE" },
}

local window
local lists = {}
-- One function per control that sets it from ns.db.
local syncs = {}
local applyQueued = false
local refreshQueued = false

local function Sound(name)
    local id = SOUNDKIT and SOUNDKIT[name]
    if id then PlaySound(id) end
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

---------------------------------------------------------------------------
-- The settings grid
---------------------------------------------------------------------------

-- The row's name in white over its explanation in gold, beside the row.
local function ShowRowHelp(row)
    if not row.help then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.title, 1, 1, 1)
    GameTooltip:AddLine(row.help, nil, nil, nil, true)
    GameTooltip:Show()
end

local function HideHelp()
    GameTooltip:Hide()
end

-- Hovering control explains its row too.
local function Explain(control, row)
    control:HookScript("OnEnter", function() ShowRowHelp(row) end)
    control:HookScript("OnLeave", HideHelp)
end

-- A form lays rows down a page from top, each under the last.
local function NewForm(page, top)
    return { page = page, y = top }
end

-- A gold section name over a faint rule.
local function Heading(form, text)
    local page = form.page
    local label = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", PAD, form.y - 12)
    label:SetText(text)
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.12)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", PAD, form.y - 29)
    rule:SetPoint("TOPRIGHT", -PAD, form.y - 29)
    form.y = form.y - HEADING_HEIGHT
end

-- One row of the grid with its name in the left column. The caller puts a
-- control at CONTROL_LEFT. Hovering anywhere on the row shows help; clicks
-- pass through to the window, so it still drags.
local function Row(form, title, help)
    local row = CreateFrame("Frame", nil, form.page)
    row:SetPoint("TOPLEFT", PAD, form.y)
    row:SetPoint("TOPRIGHT", -PAD, form.y)
    row:SetHeight(ROW_HEIGHT)
    form.y = form.y - ROW_HEIGHT

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetPoint("RIGHT", row, "LEFT", LABEL_RIGHT, 0)
    row.label:SetJustifyH("RIGHT")
    row.label:SetText(title)
    row.title, row.help = title, help

    if row.SetMouseMotionEnabled then
        row:SetMouseMotionEnabled(true)
    else
        row:EnableMouse(true)
    end
    row:SetScript("OnEnter", ShowRowHelp)
    row:SetScript("OnLeave", HideHelp)
    return row
end

-- get and set for one saved setting.
local function Saved(key)
    return function() return ns.db[key] end, function(value) ns.db[key] = value end
end

-- A checkbox. Clicking anywhere on its row toggles it. apply runs on the
-- next frame: changes are never applied from inside a settings click.
local function Checkbox(form, title, help, get, set, apply)
    local row = Row(form, title, help)
    local box = CreateFrame("CheckButton", nil, row, "SettingsCheckBoxTemplate")
    box:SetSize(21, 20)
    box:SetPoint("LEFT", CONTROL_LEFT, 0)
    box.HoverBackground = nil
    box:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        set(on)
        if apply then C_Timer.After(0, apply) end
    end)
    Explain(box, row)

    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then box:Click() end
    end)

    syncs[#syncs + 1] = function() box:SetChecked(get()) end
    return box
end

local function FormatPixels(value)
    return string.format("%d", math.floor(value + 0.5))
end

local function FormatPercent(value)
    return string.format("%d%%", math.floor(value * 100 + 0.5))
end

-- A slider for one saved number, from min to max in steps of step. The
-- mouse wheel over its row moves it a step. Like a checkbox it applies on
-- the next frame: once, however many changes a drag sends.
local function Slider(form, title, help, key, min, max, step, format)
    local row = Row(form, title, help)
    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(CONTROL_WIDTH, 20)
    slider:SetPoint("LEFT", CONTROL_LEFT, 0)
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
    if slider.Slider then Explain(slider.Slider, row) end

    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        local value = math.min(max, math.max(min, ns.db[key] + delta * step))
        slider:SetValue(value)
    end)

    syncs[#syncs + 1] = function() slider:SetValue(ns.db[key]) end
    return slider
end

-- A dropdown for one saved choice. choices returns { { text, value }, ... }
-- and is asked each time the menu opens, so it offers what other addons have
-- added since. preview(button, value), if given, styles each choice's line.
-- onChange, if given, runs after a new choice is saved.
local function Dropdown(form, title, help, key, choices, preview, onChange)
    local row = Row(form, title, help)
    local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(CONTROL_WIDTH)
    dropdown:SetPoint("LEFT", CONTROL_LEFT, 0)
    local function IsChosen(value)
        return ns.db[key] == value
    end
    local function Choose(value)
        ns.db[key] = value
        QueueApply()
        if onChange then onChange() end
    end
    dropdown:SetupMenu(function(_, root)
        local list = choices()
        if #list > MENU_ROWS then root:SetScrollMode(MENU_ROWS * MENU_ROW_HEIGHT) end
        for _, choice in ipairs(list) do
            local radio = root:CreateRadio(choice[1], IsChosen, Choose, choice[2])
            if preview then
                radio:AddInitializer(function(button) preview(button, choice[2]) end)
            end
        end
    end)
    Explain(dropdown, row)

    syncs[#syncs + 1] = function() dropdown:GenerateMenu() end
    return dropdown
end

-- A square of one saved colour with its name beside it. Left-click opens
-- the game's colour picker, where cancelling puts the colour back.
-- Right-click puts back the default.
local function Swatch(row, key, text, x)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", x, 0)
    swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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

    local function Show()
        color:SetColorTexture(ns.db[key][1], ns.db[key][2], ns.db[key][3])
    end
    local function Set(r, g, b)
        ns.db[key] = { r, g, b }
        Show()
        QueueApply()
    end
    swatch:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local default = ns.DEFAULTS[key]
            Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
            Set(default[1], default[2], default[3])
            return
        end
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
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
    -- The edge lights up under the mouse.
    swatch:HookScript("OnEnter", function() edge:SetColorTexture(0.8, 0.8, 0.8) end)
    swatch:HookScript("OnLeave", function() edge:SetColorTexture(0, 0, 0) end)
    Explain(swatch, row)

    Show()
    syncs[#syncs + 1] = Show
    return swatch
end

-- A button that fits its text.
local function NewButton(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelDynamicResizeButtonTemplate")
    button:SetText(text)
    DynamicResizeButton_Resize(button)
    button:SetScript("OnClick", onClick)
    return button
end

local function StyleChoices()
    return { { L["Blizzard"], "Blizzard" }, { L["Flat"], "Flat" } }
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

-- Writes each font's name in that font.
local function PreviewFont(button, value)
    if not button.fontString then return end
    local stock = GameFontHighlight:GetFont()
    local file = value ~= "Default" and ns.Media.Fetch("font", value) or stock
    local _, size = button.fontString:GetFont()
    if button.fontString:SetFont(file, size or 12, "") == false then
        button.fontString:SetFont(stock, size or 12, "")
    end
end

local function OutlineChoices()
    local list = {}
    for i, outline in ipairs(OUTLINES) do
        list[i] = { L[outline[1]], outline[2] }
    end
    return list
end

---------------------------------------------------------------------------
-- The food and drink lists
---------------------------------------------------------------------------

local function Shade(row, shade)
    row.place:SetTextColor(shade, shade, shade)
    row.text:SetTextColor(shade, shade, shade)
    row.value:SetTextColor(shade, shade, shade)
end

local function ShowItemTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(entry.item.id)
    GameTooltip:AddLine(" ")
    if entry.item.excluded then
        GameTooltip:AddLine(L["Click to use it in the macro again."], 0.1, 1, 0.1)
    else
        GameTooltip:AddLine(L["Click to leave it out of the macro."], 0.1, 1, 0.1)
    end
    GameTooltip:Show()
end

-- The parts of a list row: its place, an icon, the item with its count, and
-- on the right what it restores. Built once per row frame the list makes.
local function BuildItemRow(row)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    row:GetHighlightTexture():SetAlpha(0.6)

    row.place = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.place:SetPoint("LEFT", 4, 0)
    row.place:SetWidth(18)
    row.place:SetJustifyH("RIGHT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(LIST_ROW - 4, LIST_ROW - 4)
    row.icon:SetPoint("LEFT", row.place, "RIGHT", 6, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.value:SetPoint("RIGHT", -4, 0)

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        local item = self.entry and self.entry.item
        if not item then return end
        Sound(item.excluded and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        ns.db.excludedItems[item.id] = not ns.db.excludedItems[item.id] or nil
        ns.Scan.Run(true)
        -- The rows have been refilled: explain whatever is under the mouse now.
        if GameTooltip:IsOwned(self) then ShowItemTooltip(self) end
    end)
    row:SetScript("OnEnter", ShowItemTooltip)
    row:SetScript("OnLeave", HideHelp)
end

-- Fills a row from entry: { item, place, key }. The pick, in place 1, is
-- the brightest. An item above your level has no place and is greyed.
local function InitItemRow(row, entry)
    if not row.icon then BuildItemRow(row) end
    row.entry = entry
    local item, key = entry.item, entry.key
    row.icon:SetTexture(C_Item.GetItemIconByID(item.id) or QUESTION_ICON)
    row.icon:SetDesaturated(item.excluded or not item.usable)
    local name = C_Item.GetItemNameByID(item.id)
    if not name then
        -- Not loaded yet: GET_ITEM_INFO_RECEIVED refreshes the window.
        C_Item.RequestLoadItemDataByID(item.id)
        name = L["Loading..."]
    end
    row.text:SetText(string.format("%s |cff999999x%d|r", name, item.count))
    if item.excluded then
        row.place:SetText("")
        row.value:SetText(L["Excluded"])
        Shade(row, 0.5)
    elseif item.usable then
        row.place:SetText(entry.place .. ".")
        -- Percentage food gives fractions; %d wants a whole number.
        local amount = math.floor(item[key] + 0.5)
        row.value:SetText(string.format(key == "health" and L["%d health"] or L["%d mana"], amount))
        Shade(row, entry.place == 1 and 1 or 0.75)
    else
        row.place:SetText("")
        row.value:SetText(string.format(L["Needs level %d"], item.level))
        Shade(row, 0.5)
    end
end

-- A list: its name over a scrolling list of items. The scroll bar shows
-- only when the items do not fit.
local function NewList(page, title, top)
    local list = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
    list:SetPoint("TOPLEFT", PAD, top)
    list:SetPoint("TOPRIGHT", -PAD, top)
    list:SetHeight(LIST_HEADER + LIST_ROWS * LIST_ROW + 8)

    local label = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 12, -9)
    label:SetText(title)

    list.empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    list.empty:SetPoint("CENTER", 0, -LIST_HEADER / 2)

    list.scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    list.scrollBar = CreateFrame("EventFrame", nil, list, "WowTrimScrollBar")
    list.scrollBar:SetPoint("TOPRIGHT", -4, -LIST_HEADER)
    list.scrollBar:SetPoint("BOTTOMRIGHT", -4, 4)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(LIST_ROW)
    view:SetElementInitializer("Button", InitItemRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(list.scrollBox, list.scrollBar, view)

    local withBar = { "TOPLEFT", 8, -LIST_HEADER, "BOTTOMRIGHT", -26, 4 }
    local withoutBar = { "TOPLEFT", 8, -LIST_HEADER, "BOTTOMRIGHT", -8, 4 }
    if ScrollUtil.AddManagedScrollBarVisibilityBehavior and CreateAnchor then
        local function Anchors(a)
            return {
                CreateAnchor(a[1], list, a[1], a[2], a[3]),
                CreateAnchor(a[4], list, a[4], a[5], a[6]),
            }
        end
        ScrollUtil.AddManagedScrollBarVisibilityBehavior(list.scrollBox, list.scrollBar,
            Anchors(withBar), Anchors(withoutBar))
    else
        list.scrollBox:SetPoint(withBar[1], withBar[2], withBar[3])
        list.scrollBox:SetPoint(withBar[4], withBar[5], withBar[6])
    end
    return list
end

-- Fills a list with items, already in priority order.
local function ShowList(list, items, key, emptyText)
    local entries = {}
    local place = 0
    for i, item in ipairs(items) do
        if item.usable and not item.excluded then place = place + 1 end
        entries[i] = { item = item, key = key, place = place }
    end
    list.empty:SetText(emptyText)
    list.empty:SetShown(#items == 0)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    list.scrollBox:SetDataProvider(CreateDataProvider(entries), retain)
end

local NOTHING = {}

-- Repaints the lists from what Scan knows. Cheap, and a no-op while hidden.
function Options.Refresh()
    if not window or not window:IsVisible() then return end
    local found = ns.Scan.found
    ShowList(lists.food, ns.Scan.Order(found, "health"), "health", L["No food in your bags"])
    if ns.Scan.hasMana then
        ShowList(lists.drink, ns.Scan.Order(found, "mana"), "mana", L["No drink in your bags"])
    else
        ShowList(lists.drink, NOTHING, "mana", L["Your class does not use mana"])
    end
end

-- Item names arrive one event each: repaint once for a burst of them.
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        Options.Refresh()
    end)
end

-- Puts every control back in line with the saved settings.
function Options.Sync()
    if not window then return end
    for i = 1, #syncs do
        syncs[i]()
    end
    Options.Refresh()
end

---------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------

local function BuildItemsPage(page)
    local intro = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", PAD + 2, -12)
    intro:SetPoint("TOPRIGHT", -PAD - 2, -12)
    intro:SetJustifyH("LEFT")
    intro:SetTextColor(0.8, 0.8, 0.8)
    intro:SetText(L["The macro uses the first item on each list. "
        .. "Click an item to leave it out, and click it again to bring it back."])

    local listTop = -44
    lists.food = NewList(page, L["Food"], listTop)
    lists.drink = NewList(page, L["Drink"], listTop - lists.food:GetHeight() - 8)
end

local function BuildBarPage(page)
    local box = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
    -- A set size: the preview inside fits itself to it.
    box:SetSize(WINDOW_WIDTH - 2 * PAD, 72)
    box:SetPoint("TOPLEFT", PAD, -8)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Recovery bar"], 1, 1, 1)
        GameTooltip:AddLine(L["The bar counts down your meal. "
            .. "The red tick reaches the end when your health is full, and the blue tick when your mana is. "
            .. "The bar turns green once everything the meal restores is full."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", HideHelp)
    ns.Bar.NewPreview(box)

    local form = NewForm(page, -80)
    Heading(form, L["Display"])
    local showGet, showSet = Saved("showBar")
    Checkbox(form, L["Show bar"], L["Show the recovery bar while you eat or drink."], showGet, showSet, ns.SyncBar)
    local iconGet, iconSet = Saved("barIcon")
    Checkbox(form, L["Show icon"], L["Show the food or drink's icon at the left of the bar."], iconGet, iconSet,
        ns.Bar.Apply)
    local itemsGet, itemsSet = Saved("barItems")
    Checkbox(form, L["Show items"],
        L["Show a small icon for each food and drink above the right end of the bar."], itemsGet, itemsSet,
        ns.Bar.Apply)

    Heading(form, L["Size"])
    Slider(form, L["Scale"], L["Scale the whole bar, icon and text included."], "barScale", 0.5, 2, 0.05,
        FormatPercent)
    Slider(form, L["Width"], nil, "barWidth", 100, 400, 10, FormatPixels)
    Slider(form, L["Height"], nil, "barHeight", 10, 40, 1, FormatPixels)

    Heading(form, L["Look"])
    Dropdown(form, L["Style"], L["Blizzard draws the bar like the game's own cast bar. "
        .. "Flat draws it plain, with the texture and colors below."], "barStyle", StyleChoices, nil,
        function() Options.Sync() end)
    local texture = Dropdown(form, L["Texture"],
        L["The texture of the bar's fill. Textures from other addons appear here too."],
        "barTexture", TextureChoices)
    Dropdown(form, L["Font"], L["The font of the bar's text. Fonts from other addons appear here too."],
        "barFont", FontChoices, PreviewFont)
    Slider(form, L["Font size"], nil, "barFontSize", 8, 20, 1, FormatPixels)
    Dropdown(form, L["Outline"], nil, "barFontOutline", OutlineChoices)
    local colors = Row(form, L["Colors"], L["Left-click a color to change it. Right-click it to restore the default."])
    local barSwatch = Swatch(colors, "barColor", L["Counting down"], CONTROL_LEFT)
    local fullSwatch = Swatch(colors, "fullColor", L["Full"], CONTROL_LEFT + 150)

    -- The texture and colours only apply to the Flat style: grey them out
    -- for the Blizzard one.
    syncs[#syncs + 1] = function()
        local flat = ns.db.barStyle ~= "Blizzard"
        texture:SetEnabled(flat)
        for _, swatch in ipairs({ barSwatch, fullSwatch }) do
            swatch:SetEnabled(flat)
            swatch:SetAlpha(flat and 1 or 0.4)
        end
        colors.label:SetAlpha(flat and 1 or 0.4)
    end

    -- Move bar unlocks the bar so it can be dragged; the same button locks it.
    local moving = false
    local move, hint
    local function SetMoving(on)
        moving = on
        ns.Bar.SetUnlocked(on)
        move:SetText(on and L["Lock bar"] or L["Move bar"])
        DynamicResizeButton_Resize(move)
        hint:SetShown(on)
    end
    move = NewButton(page, L["Move bar"], function()
        Sound(moving and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
        SetMoving(not moving)
    end)
    move:SetPoint("BOTTOMLEFT", PAD, 16)
    local reset = NewButton(page, L["Reset position"], function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
        ns.Bar.ResetPosition()
    end)
    reset:SetPoint("LEFT", move, "RIGHT", 6, 0)
    hint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    hint:SetText(L["Drag the bar on your screen to move it."])
    hint:Hide()

    -- The window may have moved since the preview was last placed.
    page:SetScript("OnShow", ns.Bar.FitPreview)
    -- Leaving the tab or closing the window locks the bar, so a sample bar is
    -- never left behind.
    page:SetScript("OnHide", function()
        if moving then SetMoving(false) end
    end)
end

-- The addon's icon, name, version and what it does, in a strip.
local function NewCard(parent)
    local card = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    card:SetHeight(76)

    local logo = card:CreateTexture(nil, "ARTWORK")
    logo:SetSize(52, 52)
    logo:SetPoint("LEFT", 12, 0)
    logo:SetTexture(LOGO)

    local name = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
    name:SetText(addonName)

    local version = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 8, 2)
    version:SetText("v" .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))

    local notes = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    notes:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    notes:SetPoint("RIGHT", -12, 0)
    notes:SetJustifyH("LEFT")
    notes:SetTextColor(0.8, 0.8, 0.8)
    notes:SetText(L["Your best food and drink on one button."])
    return card
end

local function BuildGeneralPage(page)
    local card = NewCard(page)
    card:SetPoint("TOPLEFT", PAD, -8)
    card:SetPoint("TOPRIGHT", -PAD, -8)

    local form = NewForm(page, -84)
    Heading(form, L["Macro"])
    local macroGet, macroSet = Saved("useMacro")
    Checkbox(form, L["Update the macro"],
        string.format(L["Keep the %s macro pointed at your best food and drink. "
            .. "It changes after combat, because the game blocks macro edits during a fight."], ns.Macro.NAME),
        macroGet, macroSet, ns.Macro.Update)
    if ShowMacroFrame then
        local row = Row(form, L["Action bar"],
            string.format(L["Drag %s from the General tab of the macro window to an action bar."], ns.Macro.NAME))
        local open = NewButton(row, L["Open macros"], function() ShowMacroFrame() end)
        open:SetPoint("LEFT", CONTROL_LEFT, 0)
        Explain(open, row)
    end

    Heading(form, L["Minimap"])
    -- Saved the way LibDBIcon reads it: ns.db.minimap.hide.
    Checkbox(form, L["Minimap button"], L["Show a button on the minimap that opens this window."], function()
        return not ns.db.minimap.hide
    end, function(value)
        ns.db.minimap.hide = not value
    end, ns.Minimap.Sync)

    local reset = NewButton(page, L["Reset all settings"], function()
        StaticPopup_Show("BISCUITBREAK_RESET")
    end)
    reset:SetPoint("BOTTOMLEFT", PAD, 16)
    local hint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -PAD, 22)
    hint:SetText(L["/bb opens this window"])
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The game's own titled window, draggable, closed by its X or by Escape.
local function NewWindow(name, title)
    local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    -- Hidden before it has scripts, so the first Show runs OnShow.
    frame:Hide()
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
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
    -- The wheel scrolls lists and sliders, never the camera behind.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function() end)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    return frame
end

local TABS = {
    { "Food & Drink", BuildItemsPage },
    { "Recovery Bar", BuildBarPage },
    { "General", BuildGeneralPage },
}

local function Build()
    window = NewWindow("BiscuitBreakOptions", addonName)
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

    for i, spec in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 0, PAGE_TOP)
        page:SetPoint("BOTTOMRIGHT")
        page:Hide()
        pages[i] = page

        local tab = CreateFrame("Button", nil, window, "PanelTopTabButtonTemplate")
        tab:SetText(L[spec[1]])
        PanelTemplates_TabResize(tab, 15, nil, 90)
        if i == 1 then
            tab:SetPoint("TOPLEFT", PAD, -27)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 5, 0)
        end
        tabs[i] = tab
        tab:SetScript("OnClick", function()
            Sound("IG_CHARACTER_INFO_TAB")
            SelectPage(i)
        end)
        spec[2](page)
    end
    SelectPage(1)

    window:SetScript("OnShow", function(self)
        Sound("IG_CHARACTER_INFO_OPEN")
        -- Shrink to fit a short screen.
        self:SetScale(math.min(1, UIParent:GetHeight() * 0.95 / WINDOW_HEIGHT))
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        Options.Sync()
        -- Bags may have changed while the window was closed.
        ns.Scan.Run(true)
    end)
    window:SetScript("OnHide", function(self)
        Sound("IG_CHARACTER_INFO_CLOSE")
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end)
    window:SetScript("OnEvent", QueueRefresh)
end

-- Opens the window, or closes it if it is open. Built on first use.
function Options.Toggle()
    if not window then Build() end
    window:SetShown(not window:IsShown())
end

StaticPopupDialogs.BISCUITBREAK_RESET = {
    text = L["Reset every BiscuitBreak setting, including the items you left out and where the bar sits?"],
    button1 = L["Reset"],
    button2 = CANCEL,
    OnAccept = function() ns.ResetSettings() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Adds a page to the game's settings window that points at this one. Called
-- once, at ADDON_LOADED.
function Options.Register()
    local page = CreateFrame("Frame")
    -- The settings window calls these on every canvas page.
    page.OnCommit = function() end
    page.OnDefault = function() end
    page.OnRefresh = function() end

    local card = NewCard(page)
    card:SetPoint("TOPLEFT", 10, -10)
    card:SetPoint("TOPRIGHT", -10, -10)

    local open = NewButton(page, L["Open settings"], Options.Toggle)
    open:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -12)
    local hint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", open, "RIGHT", 10, 0)
    hint:SetText(L["/bb opens this window"])

    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, addonName))
end
