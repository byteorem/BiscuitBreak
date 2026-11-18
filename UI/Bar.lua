-- One meal timer with health and mana ticks. The client positions each tick
-- and reveals the full-resource overlay without exposing current HP or mana.
-- The bar is drawn flat: a plain fill inside a dark edge, under a soft shade.
-- Every still piece is sized and placed on whole screen pixels, so its edges
-- stay sharp at any scale, and the client moves the fill itself.

local _, ns = ...

local Bar = {}
ns.Bar = Bar

local L = ns.L

local FLAT = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_POINT = { "CENTER", "CENTER", 0, -180 }
local MANA = Enum.PowerType.Mana

-- The saved font name that means the game's own font.
local STOCK_FONT = "Default"
local HEALTH_COLOR = { 1.0, 0.2, 0.2 }
local MANA_COLOR = { 0.25, 0.6, 1.0 }
local BACK_COLOR = { 0.14, 0.14, 0.14 }
local EDGE_COLOR = { 0.03, 0.03, 0.03 }
-- How dark the shade gets at the bottom of the bar.
local SHADE = 0.35
local SPARK_ALPHA = 0.7

-- Sizes before they are rounded to whole screen pixels.
local EDGE = 1
local TICK_WIDTH = 2
local SPARK_WIDTH = 1
local ICON_GAP = 3

-- A duration this long stands still: the sample bar.
local FROZEN = 1e6

-- How a tick moves to a new place, where the client can ease it.
local GLIDE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

-- The longest the health tick keeps sliding on its own after the last health
-- update, so a wrong rate or a pause in healing cannot carry it far.
local PREDICT_LIMIT = 5

local SAMPLE_ICON = "Interface\\Icons\\inv_misc_food_73cinnamonroll"
-- Space kept clear around the preview inside its box.
local PREVIEW_PAD = 12

local main -- the bar on screen, built on first use
local preview -- the copy in the bar settings, if they have been opened
local step -- 1 at a full resource, else 0
local short -- 0 at a full resource, else 1
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

-- True when the client can move a fill through time by itself.
local function CanTimeFill(statusBar)
    return C_DurationUtil ~= nil
        and C_DurationUtil.CreateDuration ~= nil
        and statusBar.SetTimerDuration ~= nil
        and Enum.StatusBarTimerDirection ~= nil
        and Enum.StatusBarInterpolation ~= nil
end

-- Created once and reused.
local function Curves()
    if step then return end
    step = C_CurveUtil.CreateCurve()
    if Enum.LuaCurveType then step:SetType(Enum.LuaCurveType.Step) end
    step:AddPoint(0, 0)
    step:AddPoint(1, 1)
    short = C_CurveUtil.CreateCurve()
    if Enum.LuaCurveType then short:SetType(Enum.LuaCurveType.Step) end
    short:AddPoint(0, 1)
    short:AddPoint(1, 0)
end

-- A hidden maximum counts as having mana.
local function UsesMana()
    local max = UnitPowerMax("player", MANA)
    if issecretvalue and issecretvalue(max) then return true end
    return max ~= nil and max > 0
end

-- The size of one screen pixel in a frame's own units.
local function Pixel(frame)
    local _, screenHeight = GetPhysicalScreenSize()
    local scale = frame:GetEffectiveScale()
    if not screenHeight or screenHeight <= 0 or scale <= 0 then return 1 end
    return 768 / screenHeight / scale
end

-- A length rounded to whole pixels, and never to none.
local function Snap(length, pixel)
    return math.max(1, math.floor(length / pixel + 0.5)) * pixel
end

-- Moves a placed frame the fraction of a pixel that puts its corner on one.
-- It stays anchored to anchor, so it follows it.
local function AlignToPixels(frame, anchor)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    local anchorLeft, anchorBottom = anchor:GetLeft(), anchor:GetBottom()
    if not (left and bottom and anchorLeft and anchorBottom) then return end
    local pixel = Pixel(frame)
    -- The anchor's corner in the frame's units.
    local ratio = anchor:GetEffectiveScale() / frame:GetEffectiveScale()
    left = math.floor(left / pixel + 0.5) * pixel - anchorLeft * ratio
    bottom = math.floor(bottom / pixel + 0.5) * pixel - anchorBottom * ratio
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", left, bottom)
end

-- Lets a moving piece glide between pixels instead of stepping across them.
local function Glide(texture)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
end

local function Paint(texture, color, alpha)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

-- A clear status bar whose fill ends where the tick belongs. anchor: the
-- side of the tick that sits on that spot, so the health tick (RIGHT) and
-- the mana tick (LEFT) lie side by side when both mark the same moment.
-- Placed later, by Size.
local function NewMarker(timer, level, color, anchor)
    local track = CreateFrame("StatusBar", nil, timer)
    track:SetFrameLevel(level)
    track:SetStatusBarTexture(FLAT)
    track:SetStatusBarColor(0, 0, 0, 0)
    track:SetMinMaxValues(0, 1)
    track.tick = track:CreateTexture(nil, "OVERLAY", nil, 7)
    Paint(track.tick, color)
    track.tick:SetPoint(anchor, track:GetStatusBarTexture(), "RIGHT")
    track.fresh = true
    return track
end

-- Makes the next update put the track's tick straight in its place, with no
-- glide from wherever it was left.
local function Forget(track)
    track.fresh = true
end

-- The widgets of one bar. Nothing here places it on screen or watches the
-- game, so the same build serves the bar itself and the preview in its
-- settings. name: the frame's global name, or nil.
local function NewBar(parent, name)
    local bar = {}
    local frame = CreateFrame("Frame", name, parent)
    bar.frame = frame

    -- The dark edge is the frame itself, showing around the timer set into it.
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    Paint(edge, EDGE_COLOR)

    -- Look gives the timer its texture and colour.
    local timer = CreateFrame("StatusBar", nil, frame)
    timer:SetMinMaxValues(0, 1)
    timer:SetValue(0)
    timer.back = timer:CreateTexture(nil, "BACKGROUND")
    timer.back:SetAllPoints()
    Paint(timer.back, BACK_COLOR)
    bar.timer = timer
    if CanTimeFill(timer) then bar.duration = C_DurationUtil.CreateDuration() end

    -- A bright line on the fill's leading edge. Drawn by the timer, so the
    -- green layer covers it once you are full.
    bar.spark = timer:CreateTexture(nil, "OVERLAY")
    Paint(bar.spark, { 1, 1, 1 }, SPARK_ALPHA)
    Glide(bar.spark)

    -- The icon sits left of the bar inside the same dark edge.
    bar.iconEdge = frame:CreateTexture(nil, "BACKGROUND")
    Paint(bar.iconEdge, EDGE_COLOR)
    bar.icon = frame:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The green layer: health gate > mana gate > green texture over the timer.
    bar.gateHealth = CreateFrame("Frame", nil, timer)
    bar.gateHealth:SetAllPoints(timer)
    bar.gateMana = CreateFrame("Frame", nil, bar.gateHealth)
    bar.gateMana:SetAllPoints(timer)
    bar.green = bar.gateMana:CreateTexture(nil, "ARTWORK")
    bar.green:SetAllPoints()

    -- Above the green layer: the shade, then the ticks, then the text.
    local level = bar.gateMana:GetFrameLevel()
    local art = CreateFrame("Frame", nil, timer)
    art:SetAllPoints(timer)
    art:SetFrameLevel(level + 1)
    -- Clear at the top and darker towards the bottom, over fill and
    -- background alike, so the flat colours get some depth.
    local shade = art:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints()
    shade:SetColorTexture(1, 1, 1, 1)
    shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, SHADE), CreateColor(0, 0, 0, 0))

    -- Transparent status bars let the client position ticks from secret values.
    bar.healthMark = NewMarker(timer, level + 2, HEALTH_COLOR, "RIGHT")
    bar.manaMark = NewMarker(timer, level + 2, MANA_COLOR, "LEFT")

    local overlay = CreateFrame("Frame", nil, timer)
    overlay:SetAllPoints(timer)
    overlay:SetFrameLevel(level + 3)

    -- A font string needs its font at creation: SetText without one is an
    -- error on this client.
    bar.nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.nameText:SetPoint("LEFT", 4, 0)
    bar.nameText:SetJustifyH("LEFT")
    bar.timeText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timeText:SetPoint("RIGHT", -4, 0)
    bar.nameText:SetPoint("RIGHT", bar.timeText, "LEFT", -4, 0)
    bar.nameText:SetWordWrap(false)

    return bar
end

-- Gives a bar its saved texture, colours, font and icon.
local function Look(bar)
    local db = ns.db
    local timer = bar.timer
    local texture = ns.Media.Fetch("statusbar", db.barTexture) or FLAT
    timer:SetStatusBarTexture(texture)
    timer:SetStatusBarColor(db.barColor[1], db.barColor[2], db.barColor[3])
    -- Setting the texture can hand the timer a new fill, so what hangs off
    -- the fill is put back on it.
    local fill = timer:GetStatusBarTexture()
    Glide(fill)
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    bar.spark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    bar.green:SetTexture(texture)
    bar.green:SetVertexColor(db.fullColor[1], db.fullColor[2], db.fullColor[3])

    local stock = GameFontHighlightSmall:GetFont()
    local font = db.barFont ~= STOCK_FONT and ns.Media.Fetch("font", db.barFont) or stock
    for _, text in ipairs({ bar.nameText, bar.timeText }) do
        -- A font file that will not load leaves the text on the game's font.
        if text:SetFont(font, db.barFontSize, db.barFontOutline) == false then
            text:SetFont(stock, db.barFontSize, db.barFontOutline)
        end
    end

    bar.icon:SetShown(db.barIcon)
    bar.iconEdge:SetShown(db.barIcon)
end

-- Scales a bar and sizes its pieces from the saved width and height, each
-- rounded to whole screen pixels at that scale.
local function Size(bar, scale)
    local frame, timer = bar.frame, bar.timer
    frame:SetScale(scale)
    local pixel = Pixel(frame)
    local width, height = Snap(ns.db.barWidth, pixel), Snap(ns.db.barHeight, pixel)
    local edge = Snap(EDGE, pixel)
    frame:SetSize(width, height)
    timer:ClearAllPoints()
    timer:SetPoint("TOPLEFT", edge, -edge)
    timer:SetPoint("BOTTOMRIGHT", -edge, edge)
    bar.spark:SetWidth(Snap(SPARK_WIDTH, pixel))

    bar.iconEdge:ClearAllPoints()
    bar.iconEdge:SetPoint("TOPRIGHT", frame, "TOPLEFT", -Snap(ICON_GAP, pixel), 0)
    bar.iconEdge:SetSize(height, height)
    bar.icon:ClearAllPoints()
    bar.icon:SetPoint("TOPLEFT", bar.iconEdge, "TOPLEFT", edge, -edge)
    bar.icon:SetPoint("BOTTOMRIGHT", bar.iconEdge, "BOTTOMRIGHT", -edge, edge)

    -- The tracks stop a tick short of each end of the timer, so a tick at
    -- either end stays inside the edge.
    local tickWidth = Snap(TICK_WIDTH, pixel)
    for _, track in ipairs({ bar.healthMark, bar.manaMark }) do
        track:ClearAllPoints()
        track:SetPoint("TOPLEFT", timer, "TOPLEFT", tickWidth, 0)
        track:SetPoint("BOTTOMRIGHT", timer, "BOTTOMRIGHT", -tickWidth, 0)
        track.tick:SetSize(tickWidth, height - 2 * edge)
    end
end

-- Runs a bar's fill from start for span seconds. The client moves it when
-- it can; otherwise OnUpdate does.
local function RunFill(bar, start, span)
    if bar.duration then
        bar.duration:SetTimeFromStart(start, span)
        bar.timer:SetTimerDuration(bar.duration, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.ElapsedTime)
    else
        bar.timer:SetMinMaxValues(0, span)
        bar.timer:SetValue(GetTime() - start)
    end
end

-- Stands a bar's fill still at a fraction of the way along.
local function HoldFill(bar, fraction)
    RunFill(bar, GetTime() - fraction * FROZEN, FROZEN)
end

-- A made-up meal part of the way through, with neither resource full.
local function ShowSample(bar, name, time)
    bar.healthMark:Show()
    bar.manaMark:Show()
    bar.healthMark.tick:SetAlpha(1)
    bar.manaMark.tick:SetAlpha(1)
    HoldFill(bar, 0.35)
    bar.healthMark:SetValue(0.65)
    bar.manaMark:SetValue(0.85)
    -- The sample has moved the ticks off the places a meal gave them.
    Forget(bar.healthMark)
    Forget(bar.manaMark)
    bar.gateHealth:SetAlpha(0)
    bar.gateMana:SetAlpha(0)
    bar.icon:SetTexture(SAMPLE_ICON)
    bar.nameText:SetText(name)
    bar.timeText:SetText(time)
end

-- Sits the preview in the middle of its box at the bar's own scale, or
-- smaller when the bar would not fit.
local function FitPreview()
    local frame, box = preview.frame, preview.box
    local width, height = ns.db.barWidth, ns.db.barHeight
    -- The icon hangs off the left of the frame.
    local iconSpace = ns.db.barIcon and height + ICON_GAP or 0
    local scale = math.min(
        ns.db.barScale,
        (box:GetWidth() - 2 * PREVIEW_PAD) / (width + iconSpace),
        (box:GetHeight() - 2 * PREVIEW_PAD) / height
    )
    Look(preview)
    Size(preview, scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", box, "CENTER", iconSpace / 2, 0)
    AlignToPixels(frame, box)
end

-- Builds the preview inside box, a frame of a set size: a copy of the bar
-- showing a sample meal, which follows the saved sizes.
function Bar.NewPreview(box)
    preview = NewBar(box)
    preview.box = box
    FitPreview()
    ShowSample(preview, L["Preview"], "12.0")
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
    AlignToPixels(frame, UIParent)
end

-- Applies the saved look and sizes to the bar and to the preview.
function Bar.Apply()
    if main then
        Look(main)
        Size(main, ns.db.barScale)
        ApplyPosition()
    end
    if preview then FitPreview() end
end

-- The game's own figure for what you regain each second, or nil when the
-- client hides it.
local function Regen(isMana)
    local regen
    if isMana then
        regen = GetManaRegen and GetManaRegen()
    else
        regen = GetHealthRegen and GetHealthRegen()
    end
    if regen == nil or (issecretvalue and issecretvalue(regen)) then return nil end
    return regen
end

-- What you regain each second during the meal. The game's figure counts your
-- own regeneration together with the flat gain of the food or drink (seen on
-- 1.60.1: 68.7 a second on a 49.8 drink), so it replaces the flat part when
-- it is the larger. The listed rate alone is too low. A percent gain is a
-- separate effect and is added on top.
local function Rate(rates, maximum, isMana)
    local flat = (isMana and rates.mp or rates.hp) or 0
    local percent = maximum * ((isMana and rates.mpPct or rates.hpPct) or 0) / 100
    return math.max(flat, Regen(isMana) or 0) + percent
end

-- Puts a tick as far from the end of the bar as the resource is from full,
-- in the bar's own seconds: it slides up the bar as you fill and gets to the
-- end the moment you are full. So a tick ahead of the timer's fill means full
-- before the meal ends, and one behind it means the meal ends first.
-- The place depends on how full you are, so a wrong rate stretches or
-- shrinks the distance left; it cannot turn the tick round, and the error is
-- gone by the time the tick arrives. Only the health tick also looks at the
-- clock, for the few seconds between health updates (see Place).
-- Health and mana are hidden from addon code, so the place is a curve from
-- your share of the resource to a share of the bar, built from numbers addon
-- code may read; the client evaluates it and the status bar takes the answer.
--
-- reach: the share of the resource that spans the whole bar. ahead: a share
-- of the resource counted as already regained, which slides the tick on.
local function Shape(curve, reach, ahead)
    curve:ClearPoints()
    local leaves = 1 - reach - ahead -- where the tick leaves the start
    local arrives = 1 - ahead -- where it gets to the end
    if arrives <= 0 then
        curve:AddPoint(0, 1)
    elseif leaves > 0 then
        -- Further from full than the bar is long: the tick waits at the start.
        curve:AddPoint(0, 0)
        curve:AddPoint(leaves, 0)
    else
        curve:AddPoint(0, -leaves / reach)
    end
    if arrives > 0 and arrives < 1 then curve:AddPoint(arrives, 1) end
    curve:AddPoint(1, 1)
end

-- Moves a shown tick to its place. The client keeps mana up to date many
-- times a second, but health only changes when the server sends it, every
-- few seconds. So between health updates the health tick is moved on by what
-- you should have regained since the last one, which keeps it sliding like
-- the mana tick instead of jumping each time health arrives.
local function Place(track, isMana)
    local now = GetTime()
    -- A tick that was not showing goes straight to its place; after that it
    -- glides, which also eases it back if it ran ahead of your real health.
    local glide = not track.fresh and GLIDE or nil
    if track.fresh then track.since = now end
    track.fresh = false
    local ahead = 0
    if not isMana then
        local since = math.min(math.max(now - track.since, 0), PREDICT_LIMIT)
        ahead = track.perSecond * since
    end
    Shape(track.curve, track.reach, ahead)
    if isMana then
        track:SetValue(UnitPowerPercent("player", MANA, false, track.curve), glide)
        -- A full resource has nothing left to wait for, so its tick goes.
        track.tick:SetAlpha(UnitPowerPercent("player", MANA, false, short))
    else
        track:SetValue(UnitHealthPercent("player", false, track.curve), glide)
        track.tick:SetAlpha(UnitHealthPercent("player", false, short))
    end
end

local function UpdateMarker(track, maximum, rates, isMana)
    local perSecond
    if not (issecretvalue and issecretvalue(maximum)) and maximum and maximum > 0 then
        perSecond = Rate(rates, maximum, isMana) / maximum
    end
    if not perSecond or perSecond <= 0 then
        track:Hide()
        track.reach = nil
        Forget(track)
        return
    end
    track.perSecond = perSecond
    track.reach = perSecond * (current.finish - current.start)
    if not track.curve then track.curve = C_CurveUtil.CreateCurve() end
    Place(track, isMana)
    track:Show()
end

local function UpdateResources()
    if unlocked and not current then return end
    if not step or not current then return end
    if tracking.health then
        UpdateMarker(main.healthMark, UnitHealthMax("player"), current.health, false)
        main.gateHealth:SetAlpha(UnitHealthPercent("player", false, step))
    else
        -- Not being restored: it must not hold the green layer back.
        main.gateHealth:SetAlpha(1)
    end
    if tracking.mana then
        UpdateMarker(main.manaMark, UnitPowerMax("player", MANA), current.mana, true)
        main.gateMana:SetAlpha(UnitPowerPercent("player", MANA, false, step))
    else
        main.gateMana:SetAlpha(1)
    end
end

local function OnUpdate()
    if not current then return end
    local now = GetTime()
    if not main.duration then main.timer:SetValue(now - current.start) end
    local health = main.healthMark
    if tracking.health and health.reach and health:IsShown() then Place(health, false) end
    local left = current.finish - now
    if left < 0 then left = 0 end
    main.timeText:SetFormattedText("%.1f", left)
end

local function OnEvent(_, event, _, powerType)
    if event == "UNIT_POWER_FREQUENT" and powerType ~= "MANA" then return end
    -- Fresh health from the server: stop counting it as regained ahead.
    if event == "UNIT_HEALTH" then main.healthMark.since = GetTime() end
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
        ApplyPosition()
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
    Bar.Apply()
end

local function ShowMeal(meal)
    local resources = step ~= nil
    tracking.health = resources and meal.health
    tracking.mana = resources and meal.mana and UsesMana()
    if not tracking.health then
        main.healthMark:Hide()
        Forget(main.healthMark)
    end
    if not tracking.mana then
        main.manaMark:Hide()
        Forget(main.manaMark)
    end
    if not resources then
        -- No curve functions: countdown only, never green.
        main.gateHealth:SetAlpha(0)
    end
    RunFill(main, meal.start, math.max(meal.finish - meal.start, 0.1))
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
    if main then
        Forget(main.healthMark)
        Forget(main.manaMark)
        Render()
    end
end

-- Unlocked: the bar shows (with a sample when you are not eating), sits above
-- the settings windows and can be dragged.
function Bar.SetUnlocked(on)
    unlocked = on and true or false
    -- The settings window may have moved since the preview was last placed.
    if unlocked and preview then FitPreview() end
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
