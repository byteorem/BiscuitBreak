-- Bar: the eating bar. A countdown of the food or drink, your health and mana
-- under it, and a green layer when you are full.
--
-- Addon code cannot read current health or mana on this client: they are
-- hidden values that must never be compared, tested or used in arithmetic.
-- The game does accept them in some widget calls, so everything here hands
-- them straight to a widget:
--   * UnitHealthPercent / UnitPowerPercent run a curve inside the game and
--     return the (still hidden) result;
--   * a linear curve result goes to StatusBar:SetValue to fill a bar;
--   * a step curve result (0 below 100%, 1 at 100%) goes to Frame:SetAlpha.
-- The green layer sits inside two nested frames, one per resource. The game
-- multiplies their alphas, so green shows only when both are 1.
-- The cost: the addon never learns the moment you are full, so there is no
-- sound and no "seconds until full".

local _, ns = ...

local Bar = {}
ns.Bar = Bar

local L = ns.L

local WIDTH, TIMER_HEIGHT, RESOURCE_HEIGHT, GAP = 220, 16, 5, 1
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_POINT = { "CENTER", "CENTER", 0, -180 }
local MANA = Enum.PowerType.Mana

local TIMER_COLOR = { 1.0, 0.7, 0.0 }
local FULL_COLOR = { 0.15, 0.75, 0.2 }
local HEALTH_COLOR = { 0.8, 0.15, 0.15 }
local MANA_COLOR = { 0.2, 0.45, 1.0 }

local frame, timer, healthBar, manaBar, gateHealth, gateMana, nameText, timeText, icon
local linear, step
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
    if linear then return end
    linear = C_CurveUtil.CreateCurve()
    linear:AddPoint(0, 0)
    linear:AddPoint(1, 1)
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

local function NewStatusBar(parent, height, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(WIDTH, height)
    bar:SetStatusBarTexture(TEXTURE)
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.6)
    return bar
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.db.barPosition = { point, relPoint, x, y }
end

local function ApplyPosition()
    local saved = ns.db.barPosition
    if type(saved) ~= "table" or type(saved[1]) ~= "string" then saved = DEFAULT_POINT end
    frame:ClearAllPoints()
    frame:SetPoint(saved[1], UIParent, saved[2] or saved[1], saved[3] or 0, saved[4] or 0)
end

-- Repaints the health and mana bars and the green layer from the game's
-- hidden values. Nothing here reads what it passes on.
local function UpdateResources()
    if unlocked and not current then return end
    if not linear then return end
    if tracking.health then
        healthBar:SetValue(UnitHealthPercent("player", false, linear))
        gateHealth:SetAlpha(UnitHealthPercent("player", false, step))
    else
        -- Not being restored: it must not hold the green layer back.
        gateHealth:SetAlpha(1)
    end
    if tracking.mana then
        manaBar:SetValue(UnitPowerPercent("player", MANA, false, linear))
        gateMana:SetAlpha(UnitPowerPercent("player", MANA, false, step))
    else
        gateMana:SetAlpha(1)
    end
end

local function OnUpdate()
    if not current then return end
    local now = GetTime()
    timer:SetValue(now - current.start)
    local left = current.finish - now
    if left < 0 then left = 0 end
    timeText:SetFormattedText("%.1f", left)
end

local function OnEvent(_, event, _, powerType)
    if event == "UNIT_POWER_FREQUENT" and powerType ~= "MANA" then return end
    UpdateResources()
end

local function Build()
    frame = CreateFrame("Frame", "BiscuitBreakBar", UIParent)
    frame:SetSize(WIDTH, TIMER_HEIGHT + 2 * (RESOURCE_HEIGHT + GAP))
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
    frame:Hide()
    ApplyPosition()

    timer = NewStatusBar(frame, TIMER_HEIGHT, TIMER_COLOR)
    timer:SetPoint("TOPLEFT")

    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TIMER_HEIGHT, TIMER_HEIGHT)
    icon:SetPoint("RIGHT", timer, "LEFT", -2, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    healthBar = NewStatusBar(frame, RESOURCE_HEIGHT, HEALTH_COLOR)
    healthBar:SetPoint("TOPLEFT", timer, "BOTTOMLEFT", 0, -GAP)
    manaBar = NewStatusBar(frame, RESOURCE_HEIGHT, MANA_COLOR)
    manaBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -GAP)

    -- The green layer: health gate > mana gate > green texture over the timer.
    gateHealth = CreateFrame("Frame", nil, timer)
    gateHealth:SetAllPoints(timer)
    gateMana = CreateFrame("Frame", nil, gateHealth)
    gateMana:SetAllPoints(timer)
    local green = gateMana:CreateTexture(nil, "ARTWORK")
    green:SetAllPoints()
    green:SetTexture(TEXTURE)
    green:SetVertexColor(FULL_COLOR[1], FULL_COLOR[2], FULL_COLOR[3])

    -- Text sits above the green layer. A font string needs its font at
    -- creation: SetText without one is an error on this client.
    local overlay = CreateFrame("Frame", nil, timer)
    overlay:SetAllPoints(timer)
    overlay:SetFrameLevel(gateMana:GetFrameLevel() + 1)
    nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    timeText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("RIGHT", -4, 0)
    nameText:SetPoint("RIGHT", timeText, "LEFT", -4, 0)
    nameText:SetWordWrap(false)

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
end

-- Lays out the resource bars for what is being restored.
local function Layout(showHealth, showMana)
    healthBar:SetShown(showHealth)
    manaBar:SetShown(showMana)
    manaBar:ClearAllPoints()
    manaBar:SetPoint("TOPLEFT", showHealth and healthBar or timer, "BOTTOMLEFT", 0, -GAP)
end

-- A made-up meal, shown while the bar is unlocked so there is something to drag.
local function ShowSample()
    tracking.health, tracking.mana = false, false
    Layout(true, true)
    timer:SetMinMaxValues(0, 1)
    timer:SetValue(0.6)
    healthBar:SetValue(0.7)
    manaBar:SetValue(0.4)
    gateHealth:SetAlpha(0)
    gateMana:SetAlpha(0)
    icon:SetTexture("Interface\\Icons\\inv_misc_food_73cinnamonroll")
    nameText:SetText(L["Drag me"])
    timeText:SetText("")
end

local function ShowMeal(meal)
    local resources = linear ~= nil
    tracking.health = resources and meal.health
    tracking.mana = resources and meal.mana and UsesMana()
    Layout(tracking.health, tracking.mana)
    if not resources then
        -- No curve functions: countdown only, never green.
        gateHealth:SetAlpha(0)
    end
    timer:SetMinMaxValues(0, math.max(meal.finish - meal.start, 0.1))
    icon:SetTexture(meal.icon)
    nameText:SetText(meal.text or "")
    OnUpdate()
    UpdateResources()
end

local function Render()
    if current then
        ShowMeal(current)
        frame:Show()
    elseif unlocked then
        ShowSample()
        frame:Show()
    else
        frame:Hide()
    end
end

-- meal: { start, finish, health, mana, text, icon } from Core/Meal.lua.
function Bar.Show(meal)
    if not frame then Build() end
    current = meal
    Render()
end

function Bar.End()
    current = nil
    if frame then Render() end
end

-- Unlocked: the bar shows (with a sample when you are not eating), sits above
-- the settings window and can be dragged.
function Bar.SetUnlocked(on)
    unlocked = on and true or false
    if not frame then
        if not unlocked then return end
        Build()
    end
    frame:EnableMouse(unlocked)
    frame:SetFrameStrata(unlocked and "FULLSCREEN_DIALOG" or "MEDIUM")
    Render()
end

function Bar.IsUnlocked()
    return unlocked
end

function Bar.ResetPosition()
    ns.db.barPosition = nil
    if frame then ApplyPosition() end
end
