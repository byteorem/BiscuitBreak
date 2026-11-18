-- One meal timer with health and mana ticks. The client positions each tick
-- and reveals the full-resource overlay without exposing current HP or mana.

local _, ns = ...

local Bar = {}
ns.Bar = Bar

local L = ns.L

-- The client's cast bar art.
local ART = {
    fill = "ui-castingbar-filling-standard",
    full = "ui-castingbar-filling-channel",
    back = "ui-castingbar-background",
    frame = "ui-castingbar-frame",
    spark = "ui-castingbar-pip",
}
-- How far the cast bar's frame art reaches below the timer.
local FRAME_REACH = 2
-- The plain look, for a client without that art.
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_POINT = { "CENTER", "CENTER", 0, -180 }
local MANA = Enum.PowerType.Mana

local TIMER_COLOR = { 1.0, 0.7, 0.0 }
local FULL_COLOR = { 0.15, 0.75, 0.2 }
local HEALTH_COLOR = { 0.8, 0.15, 0.15 }
local MANA_COLOR = { 0.2, 0.45, 1.0 }

local SAMPLE_ICON = "Interface\\Icons\\inv_misc_food_73cinnamonroll"
-- Space kept clear around the preview inside its box.
local PREVIEW_PAD = 12

local main -- the bar on screen, built on first use
local preview -- the copy in the bar settings, if they have been opened
local step
local hasArt -- the client has every piece of ART; nil until the first bar is built
local current -- the meal being shown, or nil
local unlocked = false
local tracking = { health = false, mana = false }

-- True when the game has the functions the health, mana and green parts need.
local function CanDrawResources()
    return C_CurveUtil ~= nil
        and C_CurveUtil.CreateCurve ~= nil
        and UnitHealthPercent ~= nil
        and UnitPowerPercent ~= nil
end

-- Created once and reused.
local function Curves()
    if step then return end
    step = C_CurveUtil.CreateCurve()
    if Enum.LuaCurveType then step:SetType(Enum.LuaCurveType.Step) end
    step:AddPoint(0, 0)
    step:AddPoint(1, 1)
end

-- A hidden maximum counts as having mana.
local function UsesMana()
    local max = UnitPowerMax("player", MANA)
    if issecretvalue and issecretvalue(max) then return true end
    return max ~= nil and max > 0
end

local function HasArt()
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    for _, name in pairs(ART) do
        if not C_Texture.GetAtlasInfo(name) then return false end
    end
    return true
end

-- Sized later, by Size.
local function NewStatusBar(parent, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(TEXTURE)
    if hasArt then
        -- Greyed, so the colour below tints it.
        local fill = bar:GetStatusBarTexture()
        fill:SetAtlas(ART.fill)
        fill:SetDesaturated(true)
    end
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.back = bar:CreateTexture(nil, "BACKGROUND")
    bar.back:SetAllPoints()
    bar.back:SetColorTexture(0, 0, 0, 0.6)
    return bar
end

-- The gap between the icon and the timer: wider past the frame art.
local function IconGap()
    return hasArt and 2 + FRAME_REACH or 2
end

local function NewMarker(timer, level, color, anchor)
    local track = CreateFrame("StatusBar", nil, timer)
    track:SetAllPoints(timer)
    track:SetFrameLevel(level)
    track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    track:SetStatusBarColor(0, 0, 0, 0)
    track:SetMinMaxValues(0, 1)
    track.tick = track:CreateTexture(nil, "OVERLAY")
    track.tick:SetColorTexture(color[1], color[2], color[3], 1)
    track.tick:SetPoint(anchor, track:GetStatusBarTexture(), "RIGHT")
    return track
end

-- The widgets of one bar. Nothing here places it on screen or watches the
-- game, so the same build serves the bar itself and the preview in its
-- settings. name: the frame's global name, or nil.
local function NewBar(parent, name)
    if hasArt == nil then hasArt = HasArt() end

    local bar = {}
    local frame = CreateFrame("Frame", name, parent)
    bar.frame = frame

    local timer = NewStatusBar(frame, TIMER_COLOR)
    timer:SetPoint("TOPLEFT")
    bar.timer = timer

    bar.icon = frame:CreateTexture(nil, "ARTWORK")
    bar.icon:SetPoint("RIGHT", timer, "LEFT", -IconGap(), 0)
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- The green layer: health gate > mana gate > green texture over the timer.
    bar.gateHealth = CreateFrame("Frame", nil, timer)
    bar.gateHealth:SetAllPoints(timer)
    bar.gateMana = CreateFrame("Frame", nil, bar.gateHealth)
    bar.gateMana:SetAllPoints(timer)
    local green = bar.gateMana:CreateTexture(nil, "ARTWORK")
    green:SetAllPoints()

    -- Transparent status bars let the client position ticks from secret values.
    bar.healthMark = NewMarker(timer, bar.gateMana:GetFrameLevel() + 1, HEALTH_COLOR, "BOTTOM")
    bar.manaMark = NewMarker(timer, bar.gateMana:GetFrameLevel() + 1, MANA_COLOR, "TOP")

    -- Frame art and text sit above the ticks.
    local overlay = CreateFrame("Frame", nil, timer)
    overlay:SetAllPoints(timer)
    overlay:SetFrameLevel(bar.healthMark:GetFrameLevel() + 1)

    if hasArt then
        -- The timer as the game's cast bar: its gold fill untinted, its
        -- background, a spark on the fill's edge and its frame over the lot.
        local fill = timer:GetStatusBarTexture()
        fill:SetDesaturated(false)
        timer:SetStatusBarColor(1, 1, 1)
        timer.back:SetAtlas(ART.back)
        timer.back:ClearAllPoints()
        timer.back:SetPoint("TOPLEFT", -1, 1)
        timer.back:SetPoint("BOTTOMRIGHT", 1, -1)
        green:SetAtlas(ART.full)
        -- Drawn by the timer, so the green layer covers it once you are full.
        bar.spark = timer:CreateTexture(nil, "OVERLAY")
        bar.spark:SetAtlas(ART.spark)
        bar.spark:SetPoint("CENTER", fill, "RIGHT", 0, -1)
        local border = overlay:CreateTexture(nil, "BORDER")
        border:SetAtlas(ART.frame)
        border:SetPoint("TOPLEFT", timer, "TOPLEFT", -FRAME_REACH, 0)
        border:SetPoint("BOTTOMRIGHT", timer, "BOTTOMRIGHT", FRAME_REACH, -FRAME_REACH)
    else
        green:SetTexture(TEXTURE)
        green:SetVertexColor(FULL_COLOR[1], FULL_COLOR[2], FULL_COLOR[3])
    end

    -- A font string needs its font at creation: SetText without one is an
    -- error on this client. The frame art's top rim covers the timer's top
    -- edge, so text sits a pixel lower to stay centred on what shows.
    local textY = hasArt and -1 or 0
    bar.nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.nameText:SetPoint("LEFT", 4, textY)
    bar.nameText:SetJustifyH("LEFT")
    bar.timeText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timeText:SetPoint("RIGHT", -4, textY)
    bar.nameText:SetPoint("RIGHT", bar.timeText, "LEFT", -4, 0)
    bar.nameText:SetWordWrap(false)

    return bar
end

-- Sizes a bar's pieces from the saved width and height.
local function Size(bar)
    local width, height = ns.db.barWidth, ns.db.barHeight
    bar.frame:SetSize(width, height)
    bar.timer:SetSize(width, height)
    bar.healthMark.tick:SetSize(3, height / 2 + 2)
    bar.manaMark.tick:SetSize(3, height / 2 + 2)
    bar.icon:SetSize(height, height)
    if bar.spark then bar.spark:SetSize(5, height + 4) end
end

-- A made-up meal part of the way through, with neither resource full.
local function ShowSample(bar, name, time)
    bar.healthMark:Show()
    bar.manaMark:Show()
    bar.timer:SetMinMaxValues(0, 1)
    bar.timer:SetValue(0.35)
    bar.healthMark:SetValue(0.65)
    bar.manaMark:SetValue(0.85)
    bar.gateHealth:SetAlpha(0)
    bar.gateMana:SetAlpha(0)
    bar.icon:SetTexture(SAMPLE_ICON)
    bar.nameText:SetText(name)
    bar.timeText:SetText(time)
end

-- Sits the preview in the middle of its box at the bar's own scale, or
-- smaller when the bar would not fit.
local function FitPreview()
    Size(preview)
    local frame, box = preview.frame, preview.box
    -- The icon hangs off the left of the frame.
    local iconSpace = ns.db.barHeight + IconGap()
    local scale = math.min(
        ns.db.barScale,
        (box:GetWidth() - 2 * PREVIEW_PAD) / (frame:GetWidth() + iconSpace),
        (box:GetHeight() - 2 * PREVIEW_PAD) / frame:GetHeight()
    )
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", box, "CENTER", iconSpace / 2, 0)
end

-- Builds the preview inside box, a frame of a set size: a copy of the bar
-- showing a sample meal, which follows the saved sizes.
function Bar.NewPreview(box)
    preview = NewBar(box)
    preview.box = box
    ShowSample(preview, L["Preview"], "12.0")
    FitPreview()
end

-- The position is saved in screen units, not the bar's own, so the bar stays
-- put when its scale changes.
local function SavePosition()
    local point, _, relPoint, x, y = main.frame:GetPoint()
    local scale = main.frame:GetScale()
    ns.db.barPosition = { point, relPoint, x * scale, y * scale }
end

local function ApplyPosition()
    local saved = ns.db.barPosition
    if type(saved) ~= "table" or type(saved[1]) ~= "string" then saved = DEFAULT_POINT end
    local frame = main.frame
    local scale = frame:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint(saved[1], UIParent, saved[2] or saved[1], (saved[3] or 0) / scale, (saved[4] or 0) / scale)
end

-- Applies the saved scale, width and height to the bar and to the preview.
function Bar.ApplySize()
    if main then
        main.frame:SetScale(ns.db.barScale)
        Size(main)
        ApplyPosition()
    end
    if preview then FitPreview() end
end

-- Map resource percent to the estimated time it will fill, capped at the
-- end of its own aura. Only the client evaluates the curve at player percent.
local function UpdateMarker(track, maximum, flatRate, percentRate, finish, isMana)
    if (issecretvalue and issecretvalue(maximum)) or not maximum or maximum <= 0 then
        track:Hide()
        return
    end
    local rate = (flatRate or 0) + maximum * (percentRate or 0) / 100
    local span = current.finish - current.start
    local remaining = math.max(0, finish - GetTime())
    local cap = (finish - current.start) / span
    local now = cap - remaining / span
    local fromEmpty = maximum / rate
    if not track.curve then track.curve = C_CurveUtil.CreateCurve() end
    local curve = track.curve
    curve:ClearPoints()
    curve:AddPoint(0, math.min(cap, now + fromEmpty / span))
    local threshold = 1 - remaining / fromEmpty
    if threshold > 0 and threshold < 1 then curve:AddPoint(threshold, cap) end
    curve:AddPoint(1, now)

    if isMana then
        track:SetValue(UnitPowerPercent("player", MANA, false, curve))
    else
        track:SetValue(UnitHealthPercent("player", false, curve))
    end
    track:Show()
end

local function UpdateResources()
    if unlocked and not current then return end
    if not step or not current then return end
    if tracking.health then
        UpdateMarker(main.healthMark, UnitHealthMax("player"), current.health.hp, current.health.hpPct,
            current.healthEnd, false)
        main.gateHealth:SetAlpha(UnitHealthPercent("player", false, step))
    else
        -- Not being restored: it must not hold the green layer back.
        main.gateHealth:SetAlpha(1)
    end
    if tracking.mana then
        UpdateMarker(main.manaMark, UnitPowerMax("player", MANA), current.mana.mp, current.mana.mpPct,
            current.manaEnd, true)
        main.gateMana:SetAlpha(UnitPowerPercent("player", MANA, false, step))
    else
        main.gateMana:SetAlpha(1)
    end
end

local function OnUpdate()
    if not current then return end
    local now = GetTime()
    main.timer:SetValue(now - current.start)
    local left = current.finish - now
    if left < 0 then left = 0 end
    main.timeText:SetFormattedText("%.1f", left)
end

local function OnEvent(_, event, _, powerType)
    if event == "UNIT_POWER_FREQUENT" and powerType ~= "MANA" then return end
    UpdateResources()
end

-- Builds the bar on screen: a bar that can be dragged and that follows the
-- game.
local function Build()
    main = NewBar(UIParent, "BiscuitBreakBar")
    local frame = main.frame
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:EnableMouse(false)

    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnEvent", OnEvent)
    -- Health and mana events are needed only while the bar is up.
    frame:SetScript("OnShow", function(self)
        self:RegisterUnitEvent("UNIT_HEALTH", "player")
        self:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("UNIT_HEALTH")
        self:UnregisterEvent("UNIT_POWER_FREQUENT")
    end)

    if CanDrawResources() then Curves() end
    Bar.ApplySize()
end

local function ShowMeal(meal)
    local resources = step ~= nil
    tracking.health = resources and meal.health
    tracking.mana = resources and meal.mana and UsesMana()
    if not tracking.health then main.healthMark:Hide() end
    if not tracking.mana then main.manaMark:Hide() end
    if not resources then
        -- No curve functions: countdown only, never green.
        main.gateHealth:SetAlpha(0)
    end
    main.timer:SetMinMaxValues(0, math.max(meal.finish - meal.start, 0.1))
    main.icon:SetTexture(meal.icon)
    main.nameText:SetText(meal.text or "")
    OnUpdate()
    UpdateResources()
end

local function Render()
    if current then
        ShowMeal(current)
        main.frame:Show()
    elseif unlocked then
        -- Something to drag while you are not eating.
        tracking.health, tracking.mana = false, false
        ShowSample(main, L["Drag me"], "")
        main.frame:Show()
    else
        main.frame:Hide()
    end
end

-- meal: { start, finish, health, mana, text, icon } from Core/Meal.lua.
function Bar.Show(meal)
    if not main then Build() end
    current = meal
    Render()
end

function Bar.End()
    current = nil
    if main then Render() end
end

-- Unlocked: the bar shows (with a sample when you are not eating), sits above
-- the settings windows and can be dragged.
function Bar.SetUnlocked(on)
    unlocked = on and true or false
    if not main then
        if not unlocked then return end
        Build()
    end
    main.frame:EnableMouse(unlocked)
    main.frame:SetFrameStrata(unlocked and "FULLSCREEN_DIALOG" or "MEDIUM")
    Render()
end

function Bar.ResetPosition()
    ns.db.barPosition = nil
    if main then ApplyPosition() end
end
