if WOW_PROJECT_ID ~= WOW_PROJECT_CLASSIC then
    return
end

local ADDON_NAME = ...
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")

if string.sub(ADDON_VERSION, 1, 1) == "v" then
    ADDON_VERSION = string.sub(ADDON_VERSION, 2)
end

local HealComm = LibStub("LibHealComm-4.0")
local HealComm_OVERTIME_HEALS = bit.bor(HealComm.HOT_HEALS, HealComm.CHANNEL_HEALS)

local bit = bit
local format = format
local min = min
local max = max
local pairs = pairs
local ipairs = ipairs
local select = select
local wipe = wipe
local tinsert = tinsert
local unpack = unpack
local next = next

local GetTime = GetTime
local SetCVar = SetCVar
local C_Timer = C_Timer
local C_NamePlate = C_NamePlate

local UnitGUID = UnitGUID
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitCanAssist = UnitCanAssist
local UnitIsUnit = UnitIsUnit
local UnitBuff = UnitBuff
local CastingInfo = CastingInfo
local GetSpellPowerCost = GetSpellPowerCost
local GetSpellInfo = GetSpellInfo

local function UnitCastingInfo(unit)
    assert(unit and UnitIsUnit("player", unit))
    return CastingInfo()
end

_G.UnitCastingInfo = UnitCastingInfo

local CompactUnitFrameUtil_UpdateFillBar = CompactUnitFrameUtil_UpdateFillBar
local UnitFrameUtil_UpdateFillBar = UnitFrameUtil_UpdateFillBar
local UnitFrameUtil_UpdateManaFillBar = UnitFrameUtil_UpdateManaFillBar
local UnitFrameManaBar_Update = UnitFrameManaBar_Update

local MAX_PARTY_MEMBERS = MAX_PARTY_MEMBERS
local MAX_RAID_MEMBERS = MAX_RAID_MEMBERS

local PlayerFrame = PlayerFrame
local PetFrame = PetFrame
local TargetFrame = TargetFrame
local PartyMemberFrame = {}
local PartyMemberFramePetFrame = {}

for i = 1, MAX_PARTY_MEMBERS do
    PartyMemberFrame[i] = _G["PartyMemberFrame" .. i]
    PartyMemberFramePetFrame[i] = _G["PartyMemberFrame" .. i .. "PetFrame"]
end

local PARTY = {}
local PARTYPET = {}

for i = 1, MAX_PARTY_MEMBERS do
    tinsert(PARTY, "party" .. i)
    tinsert(PARTYPET, "partypet" .. i)
end

PARTY[0] = "player"
PARTYPET[0] = "pet"

local RAID = {}
local RAIDPET = {}
local RAIDTARGET = {}
local RAIDTARGETTARGET = {}

for i = 1, MAX_RAID_MEMBERS do
    tinsert(RAID, "raid" .. i)
    tinsert(RAIDPET, "raidpet" .. i)
    tinsert(RAIDTARGET, "raid" .. i .. "target")
    tinsert(RAIDTARGETTARGET, "raid" .. i .. "targettarget")
end

local function toggleValue(value, bool)
    if bool == true then
        value = max(value, -(value + 1))
    elseif bool == false then
        value = min(value, -(value + 1))
    elseif bool == nil then
        value = -(value + 1)
    end
    return value
end

local function rgbToHsl(r, g, b, a)
    local max, min = max(r, g, b), min(r, g, b)
    local h, s, l

    l = (max + min) / 2

    if max == min then
        h, s = 0, 0
    else
        local d = max - min

        if l > 0.5 then
            s = d / (2 - max - min)
        else
            s = d / (max + min)
        end

        if max == r then
            h = (g - b) / d

            if g < b then
                h = h + 6
            end
        elseif max == g then
            h = (b - r) / d + 2
        elseif max == b then
            h = (r - g) / d + 4
        end

        h = h / 6
    end

    return h, s, l, a or 1
end

local function hslToRgb(h, s, l, a)
    local r, g, b

    if s == 0 then
        r, g, b = l, l, l
    else
        local function f(p, q, t)
            if t < 0 then
                t = t + 1
            elseif t > 1 then
                t = t - 1
            end

            if t < 1 / 6 then
                return p + (q - p) * 6 * t
            end

            if t < 1 / 2 then
                return q
            end

            if t < 2 / 3 then
                return p + (q - p) * (2 / 3 - t) * 6
            end

            return p
        end

        local q
        if l < 0.5 then
            q = l * (1 + s)
        else
            q = l + s - l * s
        end
        local p = 2 * l - q

        r = f(p, q, h + 1 / 3)
        g = f(p, q, h)
        b = f(p, q, h - 1 / 3)
    end

    return r, g, b, a or 1
end

local function dimColor(x, r, g, b, a)
    local h, s, l = rgbToHsl(r, g, b, a)
    return hslToRgb(h, s, x * l, a)
end

local function gradient(r, g, b, a)
    return r, g, b, a, dimColor(0.667, r, g, b, a)
end

local function complementaryColor(r, g, b, a)
    local h, s, l = rgbToHsl(r, g, b, a)

    if h < 0.333 then
        h = h * 1.5
    else
        h = (h - 0.333) * 0.5 + 0.5
    end

    h = (h + 0.5) % 1

    if h < 0.5 then
        h = h * 0.667
    else
        h = (h - 0.5) * 1.333 + 0.333
    end

    return hslToRgb(h % 1, s, l, a)
end

local function tappend(tbl, ...)
    for i = 1, select("#", ...) do
        local x = select(i, ...)
        tinsert(tbl, x)
    end

    return tbl
end

local ClassicHealPrediction = {}
_G.ClassicHealPrediction = ClassicHealPrediction

local ClassicHealPredictionDefaultSettings = {
    myFilter = toggleValue(HealComm.ALL_HEALS, true),
    otherFilter = toggleValue(HealComm.ALL_HEALS, true),
    myDelta = toggleValue(3, false),
    otherDelta = toggleValue(3, false),
    overhealThreshold = toggleValue(0.2, false),
    colors = {
        {gradient(0.043, 0.533, 0.412, 1.0)},
        {gradient(0.043, 0.533, 0.412, 0.5)},
        {gradient(complementaryColor(0.043, 0.533, 0.412, 1.0))},
        {gradient(complementaryColor(0.043, 0.533, 0.412, 0.5))},
        {gradient(0.082, 0.349, 0.282, 1.0)},
        {gradient(0.082, 0.349, 0.282, 0.5)},
        {gradient(complementaryColor(0.082, 0.349, 0.282, 1.0))},
        {gradient(complementaryColor(0.082, 0.349, 0.282, 0.5))},
        {gradient(0.0, 0.827, 0.765, 1.0)},
        {gradient(0.0, 0.827, 0.765, 0.5)},
        {gradient(complementaryColor(0.0, 0.827, 0.765, 1.0))},
        {gradient(complementaryColor(0.0, 0.827, 0.765, 0.5))},
        {gradient(0.0, 0.631, 0.557, 1.0)},
        {gradient(0.0, 0.631, 0.557, 0.5)},
        {gradient(complementaryColor(0.0, 0.631, 0.557, 1.0))},
        {gradient(complementaryColor(0.0, 0.631, 0.557, 0.5))},
        {gradient(0.0, 0.447, 1.0, 1.0)}
    },
    showManaCostPrediction = true,
    raidFramesMaxOverflow = toggleValue(0.05, true),
    unitFramesMaxOverflow = toggleValue(0.0, true)
}
local ClassicHealPredictionSettings = ClassicHealPredictionDefaultSettings

local function getOtherEndTime()
    local delta = ClassicHealPredictionSettings.otherDelta

    if delta >= 0 then
        return GetTime() + delta
    end

    return nil
end

local function getChild(frame, ...)
    for i = 1, select("#", ...) do
        frame = select(select(i, ...), frame:GetChildren())
    end

    return frame
end

local function getTexture(frame, name)
    while not frame:GetName() do
        frame = frame:GetParent()
    end

    name = name and string.gsub(name, "%$parent", frame:GetName())
    return name and _G[name] and _G["_CHP_" .. name]
end

local function createTexture(frame, name, layer, subLayer)
    return getTexture(frame, name) or frame:CreateTexture(name and "_CHP_" .. name, layer, nil, subLayer)
end

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy

    if orig_type == "table" then
        copy = {}

        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end

        setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end

    return copy
end

local function deepmerge(tbl1, tbl2)
    for k, v in pairs(tbl2) do
        if tbl1[k] == nil then
            if type(v) == "table" then
                tbl1[k] = {}
                deepmerge(tbl1[k], v)
            else
                tbl1[k] = v
            end
        end
    end
end

local tickIntervals

local guidToUnitFrame = {}
local guidToCompactUnitFrame = {}
local guidToNameplateFrame = {}

local lastFrameTime = -1
local deferredUnitFrames = {}
local deferredCompactUnitFrames = {}

local loadedSettings = false
local loadedFrame = false
local checkBoxes
local checkBox2
local slider
local slider2
local slider3
local slider4
local sliderCheckBox
local sliderCheckBox2
local sliderCheckBox3
local sliderCheckBox4
local colorSwatches = {}

local function getIncomingHeals(unit)
    if not unit or not UnitCanAssist("player", unit) then
        return 0, 0, 0, 0
    end

    local unitGUID = UnitGUID(unit)
    local playerGUID = UnitGUID("player")
    local modifier = HealComm:GetHealModifier(unitGUID) or 1.0
    local myAmount = HealComm:GetHealAmount(unitGUID, HealComm.DIRECT_HEALS, nil, playerGUID) or 0
    local myAmount2 = HealComm:GetHealAmount(unitGUID, HealComm_OVERTIME_HEALS, nil, playerGUID) or 0
    local myAmount3 = 0

    if ClassicHealPredictionSettings.otherDelta >= 0 then
        if myAmount2 > 0 then
            local myDelta = 0

            for i = 1, 40 do
                local name, _, _, _, _, _, source = UnitBuff(unit, i)

                if name then
                    if source and UnitIsUnit("player", source) then
                        myDelta = max(myDelta, tickIntervals[name] or 1)
                    end

                    if myDelta == 3 then
                        break
                    end
                else
                    break
                end
            end

            local myEndTime = myDelta + GetTime()
            myAmount3 = HealComm:GetHealAmount(unitGUID, HealComm_OVERTIME_HEALS, myEndTime, playerGUID) or 0
        end

        local otherFilter = ClassicHealPredictionSettings.otherFilter
        local otherDelta = ClassicHealPredictionSettings.otherDelta
        local otherEndTime = otherDelta + GetTime()

        local otherAmount = HealComm:GetOthersHealAmount(unitGUID, otherFilter, otherEndTime) or 0
        local otherAmount2 = HealComm:GetOthersHealAmount(unitGUID, otherFilter) or 0

        return (myAmount + myAmount3) * modifier, (myAmount2 - myAmount3) * modifier, otherAmount * modifier, (otherAmount2 - otherAmount) * modifier
    else
        local otherFilter = ClassicHealPredictionSettings.otherFilter
        local otherFilter1 = bit.band(otherFilter, HealComm.DIRECT_HEALS)
        local otherFilter2 = bit.band(otherFilter, HealComm_OVERTIME_HEALS)
        local otherAmount = otherFilter1 ~= 0 and HealComm:GetOthersHealAmount(unitGUID, otherFilter1) or 0
        local otherAmount2 = otherFilter2 ~= 0 and HealComm:GetOthersHealAmount(unitGUID, otherFilter2) or 0
        local otherAmount3 = 0

        if myAmount2 > 0 or otherAmount2 > 0 then
            local myDelta = 0
            local otherDelta = 0

            for i = 1, 40 do
                local name, _, _, _, _, _, source = UnitBuff(unit, i)

                if name then
                    if source and UnitIsUnit("player", source) then
                        myDelta = max(myDelta, tickIntervals[name] or 1)
                    else
                        otherDelta = max(otherDelta, tickIntervals[name] or 1)
                    end

                    if myDelta == 3 and otherDelta == 3 then
                        break
                    end
                else
                    break
                end
            end

            if myAmount2 > 0 then
                local myEndTime = myDelta + GetTime()
                myAmount3 = HealComm:GetHealAmount(unitGUID, HealComm_OVERTIME_HEALS, myEndTime, playerGUID) or 0
            end

            if otherAmount2 > 0 then
                local otherEndTime = otherDelta + GetTime()
                otherAmount3 = HealComm:GetOthersHealAmount(unitGUID, otherFilter2, otherEndTime) or 0
            end
        end

        return (myAmount + myAmount3) * modifier, (myAmount2 - myAmount3) * modifier, (otherAmount + otherAmount3) * modifier, (otherAmount2 - otherAmount3) * modifier
    end
end

local function updateHealPrediction(frame, unit, cutoff, gradient, colorPalette, colorPalette2, updateFillBar)
    if not frame._CHP_myHealPrediction then
        return
    end

    local _, maxHealth = frame._CHP_healthBar:GetMinMaxValues()
    local health = frame._CHP_healthBar:GetValue()

    if maxHealth <= 0 then
        frame._CHP_myHealPrediction:Hide()
        frame._CHP_myHealPrediction2:Hide()
        frame._CHP_otherHealPrediction:Hide()
        frame._CHP_otherHealPrediction2:Hide()
        frame._CHP_totalAbsorb:Hide()
        frame._CHP_totalAbsorbOverlay:Hide()
        frame._CHP_healAbsorb:Hide()
        frame._CHP_healAbsorbLeftShadow:Hide()
        frame._CHP_healAbsorbRightShadow:Hide()
        frame._CHP_overAbsorbGlow:Hide()
        frame._CHP_overHealAbsorbGlow:Hide()
        return
    end

    local myIncomingHeal1, myIncomingHeal2, otherIncomingHeal1, otherIncomingHeal2 = getIncomingHeals(unit)
    local totalAbsorb = 0
    local currentHealAbsorb = 0

    local healAbsorb = frame._CHP_healAbsorb

    if healAbsorb then
        currentHealAbsorb = 0

        if health < currentHealAbsorb then
            frame._CHP_overHealAbsorbGlow:Show()
            currentHealAbsorb = health
        else
            frame._CHP_overHealAbsorbGlow:Hide()
        end
    end

    local overhealing = maxHealth <= 0 and 0 or max((health - currentHealAbsorb + myIncomingHeal1 + otherIncomingHeal1) / maxHealth - 1, 0)

    do
        local overhealThreshold = ClassicHealPredictionSettings.overhealThreshold

        if overhealThreshold >= 0 and overhealing > overhealThreshold then
            colorPalette = colorPalette2
        end
    end

    local colors = ClassicHealPredictionSettings.colors

    local myHealPrediction1 = frame._CHP_myHealPrediction
    local myHealPrediction2 = frame._CHP_myHealPrediction2
    local otherHealPrediction1 = frame._CHP_otherHealPrediction
    local otherHealPrediction2 = frame._CHP_otherHealPrediction2

    if gradient then
        local r, g, b, a, r2, g2, b2

        r, g, b, a, r2, g2, b2 = unpack(colors[colorPalette[1]])

        if a == 0 then
            myIncomingHeal1 = 0
        else
            myHealPrediction1:SetGradientAlpha("VERTICAL", r2, g2, b2, a, r, g, b, a)
        end

        r, g, b, a, r2, g2, b2 = unpack(colors[colorPalette[2]])

        if a == 0 then
            myIncomingHeal2 = 0
        else
            myHealPrediction2:SetGradientAlpha("VERTICAL", r2, g2, b2, a, r, g, b, a)
        end

        r, g, b, a, r2, g2, b2 = unpack(colors[colorPalette[3]])

        if a == 0 then
            otherIncomingHeal1 = 0
        else
            otherHealPrediction1:SetGradientAlpha("VERTICAL", r2, g2, b2, a, r, g, b, a)
        end

        r, g, b, a, r2, g2, b2 = unpack(colors[colorPalette[4]])

        if a == 0 then
            otherIncomingHeal2 = 0
        else
            otherHealPrediction2:SetGradientAlpha("VERTICAL", r2, g2, b2, a, r, g, b, a)
        end
    else
        local r, g, b, a

        r, g, b, a = unpack(colors[colorPalette[1]])

        if a == 0 then
            myIncomingHeal1 = 0
        else
            myHealPrediction1:SetVertexColor(r, g, b, a)
        end

        r, g, b, a = unpack(colors[colorPalette[2]])

        if a == 0 then
            myIncomingHeal2 = 0
        else
            myHealPrediction2:SetVertexColor(r, g, b, a)
        end

        r, g, b, a = unpack(colors[colorPalette[3]])

        if a == 0 then
            otherIncomingHeal1 = 0
        else
            otherHealPrediction1:SetVertexColor(r, g, b, a)
        end

        r, g, b, a = unpack(colors[colorPalette[4]])

        if a == 0 then
            otherIncomingHeal2 = 0
        else
            otherHealPrediction2:SetVertexColor(r, g, b, a)
        end
    end

    local myIncomingHeal = myIncomingHeal1 + myIncomingHeal2
    local otherIncomingHeal = otherIncomingHeal1 + otherIncomingHeal2
    local allIncomingHeal = myIncomingHeal + otherIncomingHeal

    if cutoff then
        allIncomingHeal = min(allIncomingHeal, maxHealth * cutoff - health + currentHealAbsorb)
    end

    local incomingHeal1 = myIncomingHeal1 + otherIncomingHeal1
    local incomingHeal2

    incomingHeal1 = min(incomingHeal1, allIncomingHeal)
    incomingHeal2 = allIncomingHeal - incomingHeal1
    myIncomingHeal1 = min(myIncomingHeal1, incomingHeal1)
    myIncomingHeal2 = min(myIncomingHeal2, incomingHeal2)
    otherIncomingHeal1 = incomingHeal1 - myIncomingHeal1
    otherIncomingHeal2 = incomingHeal2 - myIncomingHeal2

    local overAbsorb = false

    if health - currentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth or health + totalAbsorb >= maxHealth then
        if totalAbsorb > 0 then
            overAbsorb = true
        end

        if allIncomingHeal > currentHealAbsorb then
            totalAbsorb = max(0, maxHealth - (health - currentHealAbsorb + allIncomingHeal))
        else
            totalAbsorb = max(0, maxHealth - health)
        end
    end

    if overAbsorb then
        frame._CHP_overAbsorbGlow:Show()
    else
        frame._CHP_overAbsorbGlow:Hide()
    end

    local healthTexture = frame._CHP_healthBar:GetStatusBarTexture()
    local currentHealAbsorbPercent = 0
    local healAbsorbTexture

    if healAbsorb then
        currentHealAbsorbPercent = currentHealAbsorb / maxHealth

        if currentHealAbsorb > allIncomingHeal then
            local shownHealAbsorb = currentHealAbsorb - allIncomingHeal
            local shownHealAbsorbPercent = shownHealAbsorb / maxHealth

            healAbsorbTexture = updateFillBar(frame, healthTexture, healAbsorb, shownHealAbsorb, -shownHealAbsorbPercent)

            if allIncomingHeal > 0 then
                frame._CHP_healAbsorbLeftShadow:Hide()
            else
                frame._CHP_healAbsorbLeftShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPLEFT", 0, 0)
                frame._CHP_healAbsorbLeftShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMLEFT", 0, 0)
                frame._CHP_healAbsorbLeftShadow:Show()
            end

            if totalAbsorb > 0 then
                frame._CHP_healAbsorbRightShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPRIGHT", -8, 0)
                frame._CHP_healAbsorbRightShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMRIGHT", -8, 0)
                frame._CHP_healAbsorbRightShadow:Show()
            else
                frame._CHP_healAbsorbRightShadow:Hide()
            end
        else
            healAbsorb:Hide()
            frame._CHP_healAbsorbLeftShadow:Hide()
            frame._CHP_healAbsorbRightShadow:Hide()
        end
    end

    local incomingHealsTexture = updateFillBar(frame, healthTexture, myHealPrediction1, myIncomingHeal1, -currentHealAbsorbPercent)
    incomingHealsTexture = updateFillBar(frame, incomingHealsTexture, otherHealPrediction1, otherIncomingHeal1)
    incomingHealsTexture = updateFillBar(frame, incomingHealsTexture, myHealPrediction2, myIncomingHeal2)
    incomingHealsTexture = updateFillBar(frame, incomingHealsTexture, otherHealPrediction2, otherIncomingHeal2)

    local appendTexture = healAbsorbTexture or incomingHealsTexture
    updateFillBar(frame, appendTexture, frame._CHP_totalAbsorb, totalAbsorb)
end

local CompactUnitFrame_UpdateHealPrediction
local UnitFrameHealPredictionBars_Update

do
    local compactUnitFrameColorPalette = {1, 2, 5, 6}
    local compactUnitFrameColorPalette2 = {3, 4, 7, 8}
    local unitFrameColorPalette = {9, 10, 13, 14}
    local unitFrameColorPalette2 = {11, 12, 15, 16}

    function CompactUnitFrame_UpdateHealPrediction(frame)
        local cutoff
        local maxOverflow = ClassicHealPredictionSettings.raidFramesMaxOverflow

        if maxOverflow >= 0 then
            cutoff = 1.0 + maxOverflow
        end

        updateHealPrediction(frame, frame.displayedUnit, cutoff, frame._CHP_setGradient, compactUnitFrameColorPalette, compactUnitFrameColorPalette2, CompactUnitFrameUtil_UpdateFillBar)
    end

    function UnitFrameHealPredictionBars_Update(frame)
        local cutoff
        local maxOverflow = ClassicHealPredictionSettings.unitFramesMaxOverflow

        if maxOverflow >= 0 then
            cutoff = 1.0 + maxOverflow
        end

        updateHealPrediction(frame, frame.unit, cutoff, false, unitFrameColorPalette, unitFrameColorPalette2, UnitFrameUtil_UpdateFillBar)
    end
end

local function defer_CompactUnitFrame_UpdateHealPrediction(frame)
    if GetTime() > lastFrameTime then
        deferredCompactUnitFrames[frame] = true
    else
        CompactUnitFrame_UpdateHealPrediction(frame)
    end
end

local function defer_UnitFrameHealPredictionBars_Update(frame)
    if GetTime() > lastFrameTime then
        deferredUnitFrames[frame] = true
    else
        UnitFrameHealPredictionBars_Update(frame)
    end
end

local function UnitFrameManaCostPredictionBars_Update(frame, isStarting, startTime, endTime, spellID)
    if frame.unit ~= "player" or not frame.manabar or not frame.myManaCostPredictionBar then
        return
    end

    if not ClassicHealPredictionSettings.showManaCostPrediction then
        frame.myManaCostPredictionBar:Hide()
        return
    end

    local cost = 0

    if not isStarting or startTime == endTime then
        local currentSpellID = select(9, CastingInfo())

        if currentSpellID and frame.predictedPowerCost then
            cost = frame.predictedPowerCost
        else
            frame.predictedPowerCost = nil
        end
    else
        local costTable = GetSpellPowerCost(spellID)

        for _, costInfo in pairs(costTable) do
            if costInfo.type == frame.manabar.powerType then
                cost = costInfo.cost
                break
            end
        end

        frame.predictedPowerCost = cost
    end

    local manaBarTexture = frame.manabar:GetStatusBarTexture()

    local r, g, b, a = unpack(ClassicHealPredictionSettings.colors[17])
    frame.myManaCostPredictionBar:SetVertexColor(r, g, b, a)

    UnitFrameManaBar_Update(frame.manabar, "player")
    UnitFrameUtil_UpdateManaFillBar(frame, manaBarTexture, frame.myManaCostPredictionBar, cost)
end

_G.UnitFrameManaCostPredictionBars_Update = UnitFrameManaCostPredictionBars_Update

local function UnitFrameHealPredictionBars_UpdateSize(self)
    if not self._CHP_myHealPrediction or not self._CHP_otherHealPrediction then
        return
    end

    defer_UnitFrameHealPredictionBars_Update(self)
end

hooksecurefunc(
    "CompactUnitFrame_OnEvent",
    function(self, event, ...)
        if event == self.updateAllEvent and (not self.updateAllFilter or self.updateAllFilter(self, event, ...)) then
            return
        end

        local unit = ...

        if unit == self.unit or unit == self.displayedUnit then
            if event == "UNIT_MAXHEALTH" then
                defer_CompactUnitFrame_UpdateHealPrediction(self)
            elseif event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" then
                defer_CompactUnitFrame_UpdateHealPrediction(self)
            end
        end
    end
)

hooksecurefunc(
    "CompactUnitFrame_UpdateAll",
    function(frame)
        local unit = frame.displayedUnit

        do
            local unitGUID = frame._CHP_unitGUID
            local newUnitGUID = unit and UnitGUID(unit)

            if newUnitGUID ~= unitGUID then
                if unitGUID then
                    guidToCompactUnitFrame[unitGUID][frame] = nil

                    if next(guidToCompactUnitFrame[unitGUID]) == nil then
                        guidToCompactUnitFrame[unitGUID] = nil
                    end
                end

                if newUnitGUID then
                    guidToCompactUnitFrame[newUnitGUID] = guidToCompactUnitFrame[newUnitGUID] or {}
                    guidToCompactUnitFrame[newUnitGUID][frame] = true
                end

                frame._CHP_unitGUID = newUnitGUID
            end
        end

        if UnitExists(unit) then
            defer_CompactUnitFrame_UpdateHealPrediction(frame)
        end
    end
)

hooksecurefunc("CompactUnitFrame_UpdateMaxHealth", defer_CompactUnitFrame_UpdateHealPrediction)

local function unitFrame_Update(self)
    do
        local unit = self.unit
        local unitGUID = self._CHP_unitGUID
        local newUnitGUID = unit and UnitGUID(unit)

        if newUnitGUID ~= unitGUID then
            if unitGUID then
                guidToUnitFrame[unitGUID][self] = nil

                if next(guidToUnitFrame[unitGUID]) == nil then
                    guidToUnitFrame[unitGUID] = nil
                end
            end

            if newUnitGUID then
                guidToUnitFrame[newUnitGUID] = guidToUnitFrame[newUnitGUID] or {}
                guidToUnitFrame[newUnitGUID][self] = true
            end

            self._CHP_unitGUID = newUnitGUID
        end
    end

    defer_UnitFrameHealPredictionBars_Update(self)
    UnitFrameManaCostPredictionBars_Update(self)
end

hooksecurefunc("UnitFrame_SetUnit", unitFrame_Update)

hooksecurefunc("UnitFrame_Update", unitFrame_Update)

hooksecurefunc(
    "UnitFrame_OnEvent",
    function(self, event, unit)
        if unit == self.unit then
            if event == "UNIT_MAXHEALTH" then
                defer_UnitFrameHealPredictionBars_Update(self)
            end
        end
    end
)

hooksecurefunc(
    "UnitFrameHealthBar_OnUpdate",
    function(self)
        if not self.disconnected and not self.lockValues then
            local currValue = UnitHealth(self.unit)

            if currValue ~= self._CHP_currValue then
                if not self.ignoreNoUnit or UnitGUID(self.unit) then
                    self._CHP_currValue = currValue
                    defer_UnitFrameHealPredictionBars_Update(self:GetParent())
                end
            end
        end
    end
)

hooksecurefunc(
    "UnitFrameHealthBar_Update",
    function(statusbar, unit)
        if not statusbar or statusbar.lockValues then
            return
        end

        if unit == statusbar.unit then
            local maxValue = UnitHealthMax(unit)

            if statusbar.disconnected then
                statusbar._CHP_currValue = maxValue
            else
                local currValue = UnitHealth(unit)
                statusbar._CHP_currValue = currValue
            end
        end

        defer_UnitFrameHealPredictionBars_Update(statusbar:GetParent())
    end
)

local function UpdateHealPredictionAll()
    for _, unitFrames in pairs(guidToUnitFrame) do
        if unitFrames then
            for unitFrame in pairs(unitFrames) do
                defer_UnitFrameHealPredictionBars_Update(unitFrame)
            end
        end
    end

    for _, compactUnitFrames in pairs(guidToCompactUnitFrame) do
        if compactUnitFrames then
            for compactUnitFrame in pairs(compactUnitFrames) do
                defer_CompactUnitFrame_UpdateHealPrediction(compactUnitFrame)
            end
        end
    end

    for _, namePlateFrame in pairs(guidToNameplateFrame) do
        if namePlateFrame then
            defer_CompactUnitFrame_UpdateHealPrediction(namePlateFrame)
        end
    end
end

local function UpdateHealPrediction(...)
    for j = 1, select("#", ...) do
        local unitGUID = select(j, ...)

        do
            local unitFrames = guidToUnitFrame[unitGUID]

            if unitFrames then
                for unitFrame in pairs(unitFrames) do
                    defer_UnitFrameHealPredictionBars_Update(unitFrame)
                end
            end
        end

        do
            local compactUnitFrames = guidToCompactUnitFrame[unitGUID]

            if compactUnitFrames then
                for compactUnitFrame in pairs(compactUnitFrames) do
                    defer_CompactUnitFrame_UpdateHealPrediction(compactUnitFrame)
                end
            end
        end

        do
            local namePlateFrame = guidToNameplateFrame[unitGUID]

            if namePlateFrame then
                defer_CompactUnitFrame_UpdateHealPrediction(namePlateFrame)
            end
        end
    end
end

local function ClassicHealPrediction_OnEvent(event, arg1)
    local namePlateUnitToken = arg1

    if not UnitCanAssist("player", namePlateUnitToken) then
        return
    end

    local unitGUID = UnitGUID(namePlateUnitToken)

    if event == "NAME_PLATE_UNIT_ADDED" then
        local namePlate = C_NamePlate.GetNamePlateForUnit(namePlateUnitToken)
        local namePlateFrame = namePlate and namePlate.UnitFrame
        guidToNameplateFrame[unitGUID] = namePlateFrame

        if namePlateFrame then
            defer_CompactUnitFrame_UpdateHealPrediction(namePlateFrame)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        guidToNameplateFrame[unitGUID] = nil
    end
end

local function ClassicHealPrediction_OnUpdate()
    for frame in pairs(deferredUnitFrames) do
        UnitFrameHealPredictionBars_Update(frame)
    end

    for frame in pairs(deferredCompactUnitFrames) do
        CompactUnitFrame_UpdateHealPrediction(frame)
    end

    wipe(deferredUnitFrames)
    wipe(deferredCompactUnitFrames)

    lastFrameTime = GetTime()
end

do
    local function defaultCompactUnitFrameSetup(frame)
        if frame:IsForbidden() or frame._CHP_myHealPrediction then
            return
        end

        frame._CHP_setGradient = true
        frame._CHP_healthBar = frame.healthBar

        frame._CHP_myHealPrediction = createTexture(frame, "$parentMyHealPrediction", "BORDER", 5)
        frame._CHP_myHealPrediction:ClearAllPoints()
        frame._CHP_myHealPrediction:SetColorTexture(1, 1, 1)

        frame._CHP_myHealPrediction2 = createTexture(frame, "$parentMyHealPrediction2", "BORDER", 5)
        frame._CHP_myHealPrediction2:ClearAllPoints()
        frame._CHP_myHealPrediction2:SetColorTexture(1, 1, 1)

        frame._CHP_otherHealPrediction = createTexture(frame, "$parentOtherHealPrediction", "BORDER", 5)
        frame._CHP_otherHealPrediction:ClearAllPoints()
        frame._CHP_otherHealPrediction:SetColorTexture(1, 1, 1)

        frame._CHP_otherHealPrediction2 = createTexture(frame, "$parentOtherHealPrediction2", "BORDER", 5)
        frame._CHP_otherHealPrediction2:ClearAllPoints()
        frame._CHP_otherHealPrediction2:SetColorTexture(1, 1, 1)

        frame._CHP_totalAbsorb = createTexture(frame, "$parentTotalAbsorb", "BORDER", 5)
        frame._CHP_totalAbsorb:ClearAllPoints()
        frame._CHP_totalAbsorb:SetTexture("Interface\\RaidFrame\\Shield-Fill")

        frame._CHP_totalAbsorbOverlay = createTexture(frame, "$parentTotalAbsorbOverlay", "BORDER", 6)
        frame._CHP_totalAbsorb.overlay = frame._CHP_totalAbsorbOverlay
        frame._CHP_totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        frame._CHP_totalAbsorbOverlay:SetAllPoints(frame._CHP_totalAbsorb)
        frame._CHP_totalAbsorbOverlay.tileSize = 32

        frame._CHP_healAbsorb = createTexture(frame, "$parentMyHealAbsorb", "ARTWORK", 1)
        frame._CHP_healAbsorb:ClearAllPoints()
        frame._CHP_healAbsorb:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)

        frame._CHP_healAbsorbLeftShadow = createTexture(frame, "$parentMyHealAbsorbLeftShadow", "ARTWORK", 1)
        frame._CHP_healAbsorbLeftShadow:ClearAllPoints()
        frame._CHP_healAbsorbLeftShadow:SetTexture("Interface\\RaidFrame\\Absorb-Edge")

        frame._CHP_healAbsorbRightShadow = createTexture(frame, "$parentMyHealAbsorbRightShadow", "ARTWORK", 1)
        frame._CHP_healAbsorbRightShadow:ClearAllPoints()
        frame._CHP_healAbsorbRightShadow:SetTexture("Interface\\RaidFrame\\Absorb-Edge")
        frame._CHP_healAbsorbRightShadow:SetTexCoord(1, 0, 0, 1)

        frame._CHP_overAbsorbGlow = createTexture(frame, "$parentOverAbsorbGlow", "ARTWORK", 2)
        frame._CHP_overAbsorbGlow:ClearAllPoints()
        frame._CHP_overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        frame._CHP_overAbsorbGlow:SetBlendMode("ADD")
        frame._CHP_overAbsorbGlow:SetPoint("BOTTOMLEFT", frame._CHP_healthBar, "BOTTOMRIGHT", -7, 0)
        frame._CHP_overAbsorbGlow:SetPoint("TOPLEFT", frame._CHP_healthBar, "TOPRIGHT", -7, 0)
        frame._CHP_overAbsorbGlow:SetWidth(16)

        frame._CHP_overHealAbsorbGlow = createTexture(frame, "$parentOverHealAbsorbGlow", "ARTWORK", 2)
        frame._CHP_overHealAbsorbGlow:ClearAllPoints()
        frame._CHP_overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
        frame._CHP_overHealAbsorbGlow:SetBlendMode("ADD")
        frame._CHP_overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", frame._CHP_healthBar, "BOTTOMLEFT", 7, 0)
        frame._CHP_overHealAbsorbGlow:SetPoint("TOPRIGHT", frame._CHP_healthBar, "TOPLEFT", 7, 0)
        frame._CHP_overHealAbsorbGlow:SetWidth(16)
    end

    hooksecurefunc("DefaultCompactUnitFrameSetup", defaultCompactUnitFrameSetup)

    local defaultCompactMiniFrameSetup = defaultCompactUnitFrameSetup

    hooksecurefunc("DefaultCompactMiniFrameSetup", defaultCompactMiniFrameSetup)

    local compactRaidFrameReservation_GetFrame

    hooksecurefunc(
        "CompactRaidFrameReservation_GetFrame",
        function(self, key)
            compactRaidFrameReservation_GetFrame = self.reservations[key]
        end
    )

    local frameCreationSpecifiers = {
        raid = {mapping = UnitGUID, setUpFunc = defaultCompactUnitFrameSetup},
        pet = {setUpFunc = defaultCompactMiniFrameSetup},
        flagged = {mapping = UnitGUID, setUpFunc = defaultCompactUnitFrameSetup},
        target = {setUpFunc = defaultCompactMiniFrameSetup}
    }

    hooksecurefunc(
        "CompactRaidFrameContainer_GetUnitFrame",
        function(self, unit, frameType)
            if not compactRaidFrameReservation_GetFrame then
                local info = frameCreationSpecifiers[frameType]

                local mapping

                if info.mapping then
                    mapping = info.mapping(unit)
                else
                    mapping = unit
                end

                local frame = self.frameReservations[frameType].reservations[mapping]

                info.setUpFunc(frame)
            end
        end
    )

    hooksecurefunc(
        "DefaultCompactNamePlateFrameSetup",
        function(frame)
            if frame:IsForbidden() or frame._CHP_myHealPrediction then
                return
            end

            frame._CHP_healthBar = frame.healthBar

            frame._CHP_healthBar._CHP_myHealPrediction = createTexture(frame._CHP_healthBar, nil, "BORDER", 5)
            frame._CHP_myHealPrediction = frame._CHP_healthBar._CHP_myHealPrediction
            frame._CHP_myHealPrediction:ClearAllPoints()
            frame._CHP_myHealPrediction:SetTexture("Interface/TargetingFrame/UI-TargetingFrame-BarFill")

            frame._CHP_healthBar._CHP_otherHealPrediction = createTexture(frame._CHP_healthBar, nil, "BORDER", 5)
            frame._CHP_otherHealPrediction = frame._CHP_healthBar._CHP_otherHealPrediction
            frame._CHP_otherHealPrediction:ClearAllPoints()
            frame._CHP_otherHealPrediction:SetTexture("Interface/TargetingFrame/UI-TargetingFrame-BarFill")

            frame._CHP_healthBar._CHP_myHealPrediction2 = createTexture(frame._CHP_healthBar, nil, "BORDER", 5)
            frame._CHP_myHealPrediction2 = frame._CHP_healthBar._CHP_myHealPrediction2
            frame._CHP_myHealPrediction2:ClearAllPoints()
            frame._CHP_myHealPrediction2:SetTexture("Interface/TargetingFrame/UI-TargetingFrame-BarFill")

            frame._CHP_healthBar._CHP_otherHealPrediction2 = createTexture(frame._CHP_healthBar, nil, "BORDER", 5)
            frame._CHP_otherHealPrediction2 = frame._CHP_healthBar._CHP_otherHealPrediction2
            frame._CHP_otherHealPrediction2:ClearAllPoints()
            frame._CHP_otherHealPrediction2:SetTexture("Interface/TargetingFrame/UI-TargetingFrame-BarFill")

            frame._CHP_healthBar._CHP_totalAbsorb = createTexture(frame._CHP_healthBar, nil, "BORDER", 5)
            frame._CHP_totalAbsorb = frame._CHP_healthBar._CHP_totalAbsorb
            frame._CHP_totalAbsorb:ClearAllPoints()
            frame._CHP_totalAbsorb:SetTexture("Interface\\RaidFrame\\Shield-Fill")

            frame._CHP_healthBar._CHP_totalAbsorbOverlay = createTexture(frame._CHP_healthBar, nil, "BORDER", 6)
            frame._CHP_totalAbsorbOverlay = frame._CHP_healthBar._CHP_totalAbsorbOverlay
            frame._CHP_totalAbsorb.overlay = frame._CHP_totalAbsorbOverlay
            frame._CHP_totalAbsorbOverlay:SetAllPoints(frame._CHP_totalAbsorb)
            frame._CHP_totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
            frame._CHP_totalAbsorbOverlay.tileSize = 20

            frame._CHP_healthBar._CHP_healAbsorb = createTexture(frame._CHP_healthBar, nil, "ARTWORK", 1)
            frame._CHP_healAbsorb = frame._CHP_healthBar._CHP_healAbsorb
            frame._CHP_healAbsorb:ClearAllPoints()
            frame._CHP_healAbsorb:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)

            frame._CHP_healthBar._CHP_healAbsorbLeftShadow = createTexture(frame._CHP_healthBar, nil, "ARTWORK", 1)
            frame._CHP_healAbsorbLeftShadow = frame._CHP_healthBar._CHP_healAbsorbLeftShadow
            frame._CHP_healAbsorbLeftShadow:ClearAllPoints()
            frame._CHP_healAbsorbLeftShadow:SetTexture("Interface\\RaidFrame\\Absorb-Edge")

            frame._CHP_healthBar._CHP_healAbsorbRightShadow = createTexture(frame._CHP_healthBar, nil, "ARTWORK", 1)
            frame._CHP_healAbsorbRightShadow = frame._CHP_healthBar._CHP_healAbsorbRightShadow
            frame._CHP_healAbsorbRightShadow:ClearAllPoints()
            frame._CHP_healAbsorbRightShadow:SetTexture("Interface\\RaidFrame\\Absorb-Edge")
            frame._CHP_healAbsorbRightShadow:SetTexCoord(1, 0, 0, 1)

            frame._CHP_healthBar._CHP_overAbsorbGlow = createTexture(frame._CHP_healthBar, nil, "ARTWORK", 2)
            frame._CHP_overAbsorbGlow = frame._CHP_healthBar._CHP_overAbsorbGlow
            frame._CHP_overAbsorbGlow:ClearAllPoints()
            frame._CHP_overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
            frame._CHP_overAbsorbGlow:SetBlendMode("ADD")
            frame._CHP_overAbsorbGlow:SetPoint("BOTTOMLEFT", frame._CHP_healthBar, "BOTTOMRIGHT", -4, -1)
            frame._CHP_overAbsorbGlow:SetPoint("TOPLEFT", frame._CHP_healthBar, "TOPRIGHT", -4, 1)
            frame._CHP_overAbsorbGlow:SetHeight(8)

            frame._CHP_healthBar._CHP_overHealAbsorbGlow = createTexture(frame._CHP_healthBar, nil, "ARTWORK", 2)
            frame._CHP_overHealAbsorbGlow = frame._CHP_healthBar._CHP_overHealAbsorbGlow
            frame._CHP_overHealAbsorbGlow:ClearAllPoints()
            frame._CHP_overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
            frame._CHP_overHealAbsorbGlow:SetBlendMode("ADD")
            frame._CHP_overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", frame._CHP_healthBar, "BOTTOMLEFT", 2, -1)
            frame._CHP_overHealAbsorbGlow:SetPoint("TOPRIGHT", frame._CHP_healthBar, "TOPLEFT", 2, -1)
            frame._CHP_overHealAbsorbGlow:SetHeight(8)
        end
    )

    local function initUnitFrame(frame, createTextureArgs)
        local textures = {}

        for _, args in pairs(createTextureArgs) do
            local depth, name, layer, subLayer = unpack(args)
            textures[name] = createTexture(getChild(frame, unpack(depth)), name, layer, subLayer)
        end

        frame._CHP_healthBar = frame.healthbar

        frame.myManaCostPredictionBar = textures["$parentManaCostPredictionBar"]

        if frame.myManaCostPredictionBar then
            assert(frame.unit == "player")

            frame.myManaCostPredictionBar:ClearAllPoints()
            frame.myManaCostPredictionBar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")

            frame:RegisterUnitEvent("UNIT_SPELLCAST_START", frame.unit)
            frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", frame.unit)
            frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", frame.unit)
            frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", frame.unit)
        end

        frame._CHP_myHealPrediction = textures["$parentMyHealPredictionBar"]

        if not frame._CHP_myHealPrediction then
            UnitFrame_Update(frame)
            return
        end

        frame._CHP_myHealPrediction:ClearAllPoints()
        frame._CHP_myHealPrediction:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")

        frame._CHP_myHealPrediction2 = textures["$parentMyHealPredictionBar2"]
        frame._CHP_myHealPrediction2:ClearAllPoints()
        frame._CHP_myHealPrediction2:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")

        frame._CHP_otherHealPrediction = textures["$parentOtherHealPredictionBar"]
        frame._CHP_otherHealPrediction:ClearAllPoints()
        frame._CHP_otherHealPrediction:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")

        frame._CHP_otherHealPrediction2 = textures["$parentOtherHealPredictionBar2"]
        frame._CHP_otherHealPrediction2:ClearAllPoints()
        frame._CHP_otherHealPrediction2:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")

        frame._CHP_totalAbsorb = textures["$parentTotalAbsorbBar"]
        frame._CHP_totalAbsorb:ClearAllPoints()
        frame._CHP_totalAbsorb:SetTexture("Interface\\RaidFrame\\Shield-Fill")

        frame._CHP_totalAbsorbOverlay = textures["$parentTotalAbsorbBarOverlay"]
        frame._CHP_totalAbsorb.overlay = frame._CHP_totalAbsorbOverlay
        frame._CHP_totalAbsorbOverlay:ClearAllPoints()
        frame._CHP_totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        frame._CHP_totalAbsorbOverlay:SetAllPoints(frame._CHP_totalAbsorb)
        frame._CHP_totalAbsorbOverlay.tileSize = 32

        frame._CHP_healAbsorb = textures["$parentHealAbsorbBar"]
        frame._CHP_healAbsorb:ClearAllPoints()
        frame._CHP_healAbsorb:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)

        frame._CHP_healAbsorbLeftShadow = textures["$parentHealAbsorbBarLeftShadow"]
        frame._CHP_healAbsorbLeftShadow:ClearAllPoints()
        frame._CHP_healAbsorbLeftShadow:SetTexture("Interface\\RaidFrame\\Absorb-Edge")

        frame._CHP_healAbsorbRightShadow = textures["$parentHealAbsorbBarRightShadow"]
        frame._CHP_healAbsorbRightShadow:ClearAllPoints()
        frame._CHP_healAbsorbRightShadow:SetTexture("Interface\\RaidFrame\\Absorb-Edge")
        frame._CHP_healAbsorbRightShadow:SetTexCoord(1, 0, 0, 1)

        frame._CHP_overAbsorbGlow = textures["$parentOverAbsorbGlow"]
        frame._CHP_overAbsorbGlow:ClearAllPoints()
        frame._CHP_overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        frame._CHP_overAbsorbGlow:SetBlendMode("ADD")
        frame._CHP_overAbsorbGlow:SetPoint("BOTTOMLEFT", frame._CHP_healthBar, "BOTTOMRIGHT", -7, 0)
        frame._CHP_overAbsorbGlow:SetPoint("TOPLEFT", frame._CHP_healthBar, "TOPRIGHT", -7, 0)
        frame._CHP_overAbsorbGlow:SetWidth(16)

        frame._CHP_overHealAbsorbGlow = textures["$parentOverHealAbsorbGlow"]
        frame._CHP_overHealAbsorbGlow:ClearAllPoints()
        frame._CHP_overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
        frame._CHP_overHealAbsorbGlow:SetBlendMode("ADD")
        frame._CHP_overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", frame._CHP_healthBar, "BOTTOMLEFT", 7, 0)
        frame._CHP_overHealAbsorbGlow:SetPoint("TOPRIGHT", frame._CHP_healthBar, "TOPLEFT", 7, 0)
        frame._CHP_overHealAbsorbGlow:SetWidth(16)

        frame:RegisterUnitEvent("UNIT_MAXHEALTH", frame.unit)

        frame._CHP_healthBar:SetScript(
            "OnSizeChanged",
            function(self)
                UnitFrameHealPredictionBars_UpdateSize(self:GetParent())
            end
        )

        UnitFrame_Update(frame)
    end

    initUnitFrame(
        PlayerFrame,
        {
            {{}, "$parentTotalAbsorbBar", "ARTWORK"},
            {{}, "$parentTotalAbsorbBarOverlay", "ARTWORK", 1},
            {{1, 1}, "$parentMyHealPredictionBar", "BACKGROUND"},
            {{1, 1}, "$parentOtherHealPredictionBar", "BACKGROUND"},
            {{1, 1}, "$parentMyHealPredictionBar2", "BACKGROUND"},
            {{1, 1}, "$parentOtherHealPredictionBar2", "BACKGROUND"},
            {{1, 1}, "$parentManaCostPredictionBar", "BACKGROUND"},
            {{1, 1}, "$parentHealAbsorbBar", "BACKGROUND"},
            {{1, 1}, "$parentHealAbsorbBarLeftShadow", "BACKGROUND"},
            {{1, 1}, "$parentHealAbsorbBarRightShadow", "BACKGROUND"},
            {{1, 1}, "$parentOverAbsorbGlow", "ARTWORK", 1},
            {{1, 1}, "$parentOverHealAbsorbGlow", "ARTWORK", 1}
        }
    )

    initUnitFrame(
        PetFrame,
        {
            {{}, "$parentTotalAbsorbBar", "ARTWORK"},
            {{}, "$parentTotalAbsorbBarOverlay", "ARTWORK", 1},
            {{2, 1}, "$parentMyHealPredictionBar", "BACKGROUND"},
            {{2, 1}, "$parentOtherHealPredictionBar", "BACKGROUND"},
            {{2, 1}, "$parentMyHealPredictionBar2", "BACKGROUND"},
            {{2, 1}, "$parentOtherHealPredictionBar2", "BACKGROUND"},
            {{2, 1}, "$parentHealAbsorbBar", "BACKGROUND"},
            {{2, 1}, "$parentHealAbsorbBarLeftShadow", "BACKGROUND"},
            {{2, 1}, "$parentHealAbsorbBarRightShadow", "BACKGROUND"},
            {{2, 1}, "$parentOverAbsorbGlow", "ARTWORK"},
            {{2, 1}, "$parentOverHealAbsorbGlow", "ARTWORK"}
        }
    )

    initUnitFrame(
        TargetFrame,
        {
            {{}, "$parentTotalAbsorbBar", "ARTWORK"},
            {{}, "$parentMyHealPredictionBar", "ARTWORK", 1},
            {{}, "$parentOtherHealPredictionBar", "ARTWORK", 1},
            {{}, "$parentMyHealPredictionBar2", "ARTWORK", 1},
            {{}, "$parentOtherHealPredictionBar2", "ARTWORK", 1},
            {{}, "$parentHealAbsorbBar", "ARTWORK", 1},
            {{}, "$parentHealAbsorbBarLeftShadow", "ARTWORK", 1},
            {{}, "$parentHealAbsorbBarRightShadow", "ARTWORK", 1},
            {{}, "$parentTotalAbsorbBarOverlay", "ARTWORK", 1},
            {{1}, "$parentOverAbsorbGlow", "ARTWORK", 1},
            {{1}, "$parentOverHealAbsorbGlow", "ARTWORK", 1}
        }
    )

    for i = 1, MAX_PARTY_MEMBERS do
        initUnitFrame(
            PartyMemberFrame[i],
            {
                {{}, "$parentTotalAbsorbBar", "ARTWORK"},
                {{}, "$parentTotalAbsorbBarOverlay", "ARTWORK", 1},
                {{2, 1}, "$parentMyHealPredictionBar", "BACKGROUND"},
                {{2, 1}, "$parentOtherHealPredictionBar", "BACKGROUND"},
                {{2, 1}, "$parentMyHealPredictionBar2", "BACKGROUND"},
                {{2, 1}, "$parentOtherHealPredictionBar2", "BACKGROUND"},
                {{2, 1}, "$parentHealAbsorbBar", "BACKGROUND"},
                {{2, 1}, "$parentHealAbsorbBarLeftShadow", "BACKGROUND"},
                {{2, 1}, "$parentHealAbsorbBarRightShadow", "BACKGROUND"},
                {{2, 1}, "$parentOverAbsorbGlow", "ARTWORK"},
                {{2, 1}, "$parentOverHealAbsorbGlow", "ARTWORK"}
            }
        )

        initUnitFrame(PartyMemberFramePetFrame[i], {})
    end
end

local function ClassicHealPredictionFrame_Refresh()
    if not loadedSettings or not loadedFrame then
        return
    end

    for i, checkBox in ipairs(checkBoxes) do
        if i == 1 then
            checkBox:SetChecked(ClassicHealPredictionSettings.otherFilter >= 0)
        else
            checkBox:SetChecked(bit.band(toggleValue(ClassicHealPredictionSettings.otherFilter, true), checkBox.flag) == checkBox.flag)
            checkBox:SetEnabled(ClassicHealPredictionSettings.otherFilter >= 0)

            if ClassicHealPredictionSettings.otherFilter >= 0 then
                checkBox.Text:SetTextColor(1.0, 1.0, 1.0)
            else
                checkBox.Text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end

    sliderCheckBox:SetChecked(ClassicHealPredictionSettings.otherDelta >= 0)
    sliderCheckBox:SetEnabled(ClassicHealPredictionSettings.otherFilter >= 0)

    if ClassicHealPredictionSettings.otherFilter >= 0 then
        sliderCheckBox.Text:SetTextColor(1.0, 1.0, 1.0)
    else
        sliderCheckBox.Text:SetTextColor(0.5, 0.5, 0.5)
    end

    slider:SetValue(toggleValue(ClassicHealPredictionSettings.otherDelta, true))
    slider:SetEnabled(ClassicHealPredictionSettings.otherFilter >= 0 and ClassicHealPredictionSettings.otherDelta >= 0)

    if ClassicHealPredictionSettings.otherFilter >= 0 and ClassicHealPredictionSettings.otherDelta >= 0 then
        slider.Text:SetTextColor(1.0, 1.0, 1.0)
        slider.Low:SetTextColor(1.0, 1.0, 1.0)
        slider.High:SetTextColor(1.0, 1.0, 1.0)
    else
        slider.Text:SetTextColor(0.5, 0.5, 0.5)
        slider.Low:SetTextColor(0.5, 0.5, 0.5)
        slider.High:SetTextColor(0.5, 0.5, 0.5)
    end

    sliderCheckBox2:SetChecked(ClassicHealPredictionSettings.overhealThreshold >= 0)

    slider2:SetValue(toggleValue(ClassicHealPredictionSettings.overhealThreshold, true) * 100)
    slider2:SetEnabled(ClassicHealPredictionSettings.overhealThreshold >= 0)

    if ClassicHealPredictionSettings.overhealThreshold >= 0 then
        slider2.Text:SetTextColor(1.0, 1.0, 1.0)
        slider2.Low:SetTextColor(1.0, 1.0, 1.0)
        slider2.High:SetTextColor(1.0, 1.0, 1.0)
    else
        slider2.Text:SetTextColor(0.5, 0.5, 0.5)
        slider2.Low:SetTextColor(0.5, 0.5, 0.5)
        slider2.High:SetTextColor(0.5, 0.5, 0.5)
    end

    sliderCheckBox3:SetChecked(ClassicHealPredictionSettings.raidFramesMaxOverflow >= 0)

    slider3:SetValue(toggleValue(ClassicHealPredictionSettings.raidFramesMaxOverflow, true) * 100)
    slider3:SetEnabled(ClassicHealPredictionSettings.raidFramesMaxOverflow >= 0)

    if ClassicHealPredictionSettings.raidFramesMaxOverflow >= 0 then
        slider3.Text:SetTextColor(1.0, 1.0, 1.0)
        slider3.Low:SetTextColor(1.0, 1.0, 1.0)
        slider3.High:SetTextColor(1.0, 1.0, 1.0)
    else
        slider3.Text:SetTextColor(0.5, 0.5, 0.5)
        slider3.Low:SetTextColor(0.5, 0.5, 0.5)
        slider3.High:SetTextColor(0.5, 0.5, 0.5)
    end

    sliderCheckBox4:SetChecked(ClassicHealPredictionSettings.unitFramesMaxOverflow >= 0)

    slider4:SetValue(toggleValue(ClassicHealPredictionSettings.unitFramesMaxOverflow, true) * 100)
    slider4:SetEnabled(ClassicHealPredictionSettings.unitFramesMaxOverflow >= 0)

    if ClassicHealPredictionSettings.unitFramesMaxOverflow >= 0 then
        slider4.Text:SetTextColor(1.0, 1.0, 1.0)
        slider4.Low:SetTextColor(1.0, 1.0, 1.0)
        slider4.High:SetTextColor(1.0, 1.0, 1.0)
    else
        slider4.Text:SetTextColor(0.5, 0.5, 0.5)
        slider4.Low:SetTextColor(0.5, 0.5, 0.5)
        slider4.High:SetTextColor(0.5, 0.5, 0.5)
    end

    checkBox2:SetChecked(ClassicHealPredictionSettings.showManaCostPrediction)

    for _, colorSwatch in ipairs(colorSwatches) do
        local r, g, b, a = unpack(ClassicHealPredictionSettings.colors[colorSwatch.index])
        colorSwatch:GetNormalTexture():SetVertexColor(r, g, b, a)
    end
end

local function ClassicHealPredictionFrame_OnEvent(self, event)
    if event == "ADDON_LOADED" then
        if not _G.ClassicHealPredictionSettings then
            _G.ClassicHealPredictionSettings = {}
        end

        deepmerge(_G.ClassicHealPredictionSettings, ClassicHealPredictionDefaultSettings)

        _G.ClassicHealPredictionSettings["version"] = ADDON_VERSION

        ClassicHealPredictionSettings = {}

        for k, v in pairs(_G.ClassicHealPredictionSettings) do
            ClassicHealPredictionSettings[k] = deepcopy(v)
        end

        SetCVar("predictedHealth", 1)

        loadedSettings = true

        self:UnregisterEvent("ADDON_LOADED")
    end
end

_G.ClassicHealPredictionFrame_OnEvent = ClassicHealPredictionFrame_OnEvent

local function ClassicHealPredictionFrame_Default()
    wipe(ClassicHealPredictionSettings)
    wipe(_G.ClassicHealPredictionSettings)

    for k, v in pairs(ClassicHealPredictionDefaultSettings) do
        ClassicHealPredictionSettings[k] = deepcopy(v)
        _G.ClassicHealPredictionSettings[k] = deepcopy(v)
    end

    ClassicHealPredictionSettings["version"] = ADDON_VERSION
    _G.ClassicHealPredictionSettings["version"] = ADDON_VERSION
end

_G.ClassicHealPredictionFrame_Default = ClassicHealPredictionFrame_Default

local function ClassicHealPredictionFrame_Okay()
    wipe(_G.ClassicHealPredictionSettings)

    for k, v in pairs(ClassicHealPredictionSettings) do
        _G.ClassicHealPredictionSettings[k] = deepcopy(v)
    end

    UpdateHealPredictionAll()
end

_G.ClassicHealPredictionFrame_Okay = ClassicHealPredictionFrame_Okay

local function ClassicHealPredictionFrame_Cancel()
    wipe(ClassicHealPredictionSettings)

    for k, v in pairs(_G.ClassicHealPredictionSettings) do
        ClassicHealPredictionSettings[k] = deepcopy(v)
    end
end

_G.ClassicHealPredictionFrame_Cancel = ClassicHealPredictionFrame_Cancel

local function ClassicHealPredictionFrame_OnLoad(self)
    self:RegisterEvent("ADDON_LOADED")

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    frame:SetScript(
        "OnEvent",
        function(_, ...)
            ClassicHealPrediction_OnEvent(...)
        end
    )

    frame:SetScript(
        "OnUpdate",
        function(_, ...)
            ClassicHealPrediction_OnUpdate(...)
        end
    )

    local title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText(ADDON_NAME)

    local version = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 5, 0)
    version:SetTextColor(0.5, 0.5, 0.5)
    version:SetText("v" .. ADDON_VERSION)

    checkBoxes = {}

    local sliderCheckBoxName = "ClassicHealPredictionSliderCheckbox"
    sliderCheckBox = CreateFrame("CheckButton", sliderCheckBoxName, self, "OptionsSmallCheckButtonTemplate")

    local sliderName = "ClassicHealPredictionSlider"
    slider = CreateFrame("Slider", sliderName, self, "OptionsSliderTemplate")

    for i, x in ipairs(
        {
            {"Show healing of others", HealComm.ALL_HEALS},
            {"Show direct healing", HealComm.DIRECT_HEALS},
            {"Show healing over time", HealComm.HOT_HEALS},
            {"Show channeled healing", HealComm.CHANNEL_HEALS}
        }
    ) do
        local text, flag = unpack(x)
        local name = format("ClassicHealPredictionCheckButton%d", i)
        local template

        if i == 1 then
            template = "OptionsCheckButtonTemplate"
        else
            template = "OptionsSmallCheckButtonTemplate"
        end

        local checkBox = CreateFrame("CheckButton", name, self, template)

        if i == 1 then
            checkBox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -15)
        else
            local anchor

            if i > 2 then
                anchor = "BOTTOMLEFT"
            else
                anchor = "BOTTOMRIGHT"
            end

            checkBox:SetPoint("TOPLEFT", checkBoxes[i - 1], anchor, 0, 0)
        end

        checkBox.Text = _G[name .. "Text"]
        checkBox.Text:SetText(text)
        checkBox.Text:SetTextColor(1, 1, 1)
        checkBox.flag = flag

        checkBox:SetScript(
            "OnClick",
            function(self)
                if self == checkBoxes[1] then
                    for j = 2, #checkBoxes do
                        checkBoxes[j]:SetEnabled(self:GetChecked())

                        if self:GetChecked() then
                            checkBoxes[j].Text:SetTextColor(1.0, 1.0, 1.0)
                        else
                            checkBoxes[j].Text:SetTextColor(0.5, 0.5, 0.5)
                        end
                    end

                    sliderCheckBox:SetEnabled(self:GetChecked())

                    if self:GetChecked() then
                        sliderCheckBox.Text:SetTextColor(1.0, 1.0, 1.0)
                    else
                        sliderCheckBox.Text:SetTextColor(0.5, 0.5, 0.5)
                    end

                    slider:SetEnabled(self:GetChecked() and sliderCheckBox:GetChecked())

                    if self:GetChecked() and sliderCheckBox:GetChecked() then
                        slider.Text:SetTextColor(1.0, 1.0, 1.0)
                        slider.Low:SetTextColor(1.0, 1.0, 1.0)
                        slider.High:SetTextColor(1.0, 1.0, 1.0)
                    else
                        slider.Text:SetTextColor(0.5, 0.5, 0.5)
                        slider.Low:SetTextColor(0.5, 0.5, 0.5)
                        slider.High:SetTextColor(0.5, 0.5, 0.5)
                    end

                    ClassicHealPredictionSettings.otherFilter = toggleValue(ClassicHealPredictionSettings.otherFilter, self:GetChecked())
                else
                    if self:GetChecked() then
                        ClassicHealPredictionSettings.otherFilter = bit.bor(toggleValue(ClassicHealPredictionSettings.otherFilter, true), self.flag)
                    else
                        ClassicHealPredictionSettings.otherFilter = bit.band(toggleValue(ClassicHealPredictionSettings.otherFilter, true), bit.bnot(self.flag))
                    end

                    ClassicHealPredictionSettings.otherFilter = toggleValue(ClassicHealPredictionSettings.otherFilter, checkBoxes[1]:GetChecked())
                end
            end
        )

        tinsert(checkBoxes, checkBox)
    end

    sliderCheckBox:SetPoint("TOPLEFT", checkBoxes[#checkBoxes], "BOTTOMLEFT", 0, 0)
    sliderCheckBox.Text = _G[sliderCheckBoxName .. "Text"]
    sliderCheckBox.Text:SetText("Set threshold for imminent healing to ... seconds")
    sliderCheckBox.Text:SetTextColor(1, 1, 1)

    slider:SetPoint("TOPLEFT", sliderCheckBox, "BOTTOMRIGHT", 0, -15)
    slider:SetWidth(300)
    slider:SetMinMaxValues(0.0, 30.0)
    slider:SetValueStep(0.1)
    slider:SetObeyStepOnDrag(true)
    slider.Text = _G[sliderName .. "Text"]
    slider.Low = _G[sliderName .. "Low"]
    slider.High = _G[sliderName .. "High"]
    slider.Text:SetText(format("%.1f", slider:GetValue()))
    slider.Low:SetText(format("%.1f", select(1, slider:GetMinMaxValues())))
    slider.High:SetText(format("%.1f", select(2, slider:GetMinMaxValues())))

    slider:SetScript(
        "OnValueChanged",
        function(self, event)
            self.Text:SetText(format("%.1f", event))
            ClassicHealPredictionSettings.otherDelta = toggleValue(event, ClassicHealPredictionSettings.otherDelta >= 0)
        end
    )

    sliderCheckBox:SetScript(
        "OnClick",
        function(self)
            if self:GetChecked() then
                slider.Text:SetTextColor(1.0, 1.0, 1.0)
                slider.Low:SetTextColor(1.0, 1.0, 1.0)
                slider.High:SetTextColor(1.0, 1.0, 1.0)
            else
                slider.Text:SetTextColor(0.5, 0.5, 0.5)
                slider.Low:SetTextColor(0.5, 0.5, 0.5)
                slider.High:SetTextColor(0.5, 0.5, 0.5)
            end

            slider:SetEnabled(self:GetChecked())
            ClassicHealPredictionSettings.otherDelta = toggleValue(ClassicHealPredictionSettings.otherDelta, self:GetChecked())
        end
    )

    local sliderCheckBoxName2 = "ClassicHealPredictionSliderCheckbox2"
    sliderCheckBox2 = CreateFrame("CheckButton", sliderCheckBoxName2, self, "OptionsCheckButtonTemplate")

    local sliderName2 = "ClassicHealPredictionSlider2"
    slider2 = CreateFrame("Slider", sliderName2, self, "OptionsSliderTemplate")

    sliderCheckBox2:SetPoint("TOPLEFT", checkBoxes[1], "BOTTOMLEFT", 0, -155)
    sliderCheckBox2.Text = _G[sliderCheckBoxName2 .. "Text"]
    sliderCheckBox2.Text:SetText("Use different colors if overhealing exceeds ... percent of max health")
    sliderCheckBox2.Text:SetTextColor(1, 1, 1)

    slider2:SetPoint("TOPLEFT", sliderCheckBox2, "BOTTOMRIGHT", 0, -15)
    slider2:SetWidth(300)
    slider2:SetMinMaxValues(0, 100)
    slider2:SetValueStep(1)
    slider2:SetObeyStepOnDrag(true)
    slider2.Text = _G[sliderName2 .. "Text"]
    slider2.Low = _G[sliderName2 .. "Low"]
    slider2.High = _G[sliderName2 .. "High"]
    slider2.Text:SetText(format("%d", slider2:GetValue()))
    slider2.Low:SetText(format("%d", select(1, slider2:GetMinMaxValues())))
    slider2.High:SetText(format("%d", select(2, slider2:GetMinMaxValues())))

    slider2:SetScript(
        "OnValueChanged",
        function(self, event)
            self.Text:SetText(format("%d", event))
            ClassicHealPredictionSettings.overhealThreshold = toggleValue(event / 100, ClassicHealPredictionSettings.overhealThreshold >= 0)
        end
    )

    sliderCheckBox2:SetScript(
        "OnClick",
        function(self)
            if self:GetChecked() then
                slider2.Text:SetTextColor(1.0, 1.0, 1.0)
                slider2.Low:SetTextColor(1.0, 1.0, 1.0)
                slider2.High:SetTextColor(1.0, 1.0, 1.0)
            else
                slider2.Text:SetTextColor(0.5, 0.5, 0.5)
                slider2.Low:SetTextColor(0.5, 0.5, 0.5)
                slider2.High:SetTextColor(0.5, 0.5, 0.5)
            end

            slider2:SetEnabled(self:GetChecked())
            ClassicHealPredictionSettings.overhealThreshold = toggleValue(ClassicHealPredictionSettings.overhealThreshold, self:GetChecked())
        end
    )

    local sliderCheckBoxName3 = "ClassicHealPredictionSliderCheckbox3"
    sliderCheckBox3 = CreateFrame("CheckButton", sliderCheckBoxName3, self, "OptionsCheckButtonTemplate")

    local sliderName3 = "ClassicHealPredictionSlider3"
    slider3 = CreateFrame("Slider", sliderName3, self, "OptionsSliderTemplate")

    sliderCheckBox3:SetPoint("TOPLEFT", sliderCheckBox2, "BOTTOMLEFT", 0, -50)
    sliderCheckBox3.Text = _G[sliderCheckBoxName3 .. "Text"]
    sliderCheckBox3.Text:SetText("Set max overflow in raid frames to ... percent of max health")
    sliderCheckBox3.Text:SetTextColor(1, 1, 1)

    slider3:SetPoint("TOPLEFT", sliderCheckBox3, "BOTTOMRIGHT", 0, -15)
    slider3:SetWidth(300)
    slider3:SetMinMaxValues(0, 100)
    slider3:SetValueStep(1)
    slider3:SetObeyStepOnDrag(true)
    slider3.Text = _G[sliderName3 .. "Text"]
    slider3.Low = _G[sliderName3 .. "Low"]
    slider3.High = _G[sliderName3 .. "High"]
    slider3.Text:SetText(format("%d", slider3:GetValue()))
    slider3.Low:SetText(format("%d", select(1, slider3:GetMinMaxValues())))
    slider3.High:SetText(format("%d", select(2, slider3:GetMinMaxValues())))

    slider3:SetScript(
        "OnValueChanged",
        function(self, event)
            self.Text:SetText(format("%d", event))
            ClassicHealPredictionSettings.raidFramesMaxOverflow = toggleValue(event / 100, ClassicHealPredictionSettings.raidFramesMaxOverflow >= 0)
        end
    )

    sliderCheckBox3:SetScript(
        "OnClick",
        function(self)
            if self:GetChecked() then
                slider3.Text:SetTextColor(1.0, 1.0, 1.0)
                slider3.Low:SetTextColor(1.0, 1.0, 1.0)
                slider3.High:SetTextColor(1.0, 1.0, 1.0)
            else
                slider3.Text:SetTextColor(0.5, 0.5, 0.5)
                slider3.Low:SetTextColor(0.5, 0.5, 0.5)
                slider3.High:SetTextColor(0.5, 0.5, 0.5)
            end

            slider3:SetEnabled(self:GetChecked())
            ClassicHealPredictionSettings.raidFramesMaxOverflow = toggleValue(ClassicHealPredictionSettings.raidFramesMaxOverflow, self:GetChecked())
        end
    )

    local sliderCheckBoxName4 = "ClassicHealPredictionSliderCheckbox4"
    sliderCheckBox4 = CreateFrame("CheckButton", sliderCheckBoxName4, self, "OptionsCheckButtonTemplate")

    local sliderName4 = "ClassicHealPredictionSlider4"
    slider4 = CreateFrame("Slider", sliderName4, self, "OptionsSliderTemplate")

    sliderCheckBox4:SetPoint("TOPLEFT", sliderCheckBox3, "BOTTOMLEFT", 0, -50)
    sliderCheckBox4.Text = _G[sliderCheckBoxName4 .. "Text"]
    sliderCheckBox4.Text:SetText("Set max overflow in unit frames to ... percent of max health")
    sliderCheckBox4.Text:SetTextColor(1, 1, 1)

    slider4:SetPoint("TOPLEFT", sliderCheckBox4, "BOTTOMRIGHT", 0, -15)
    slider4:SetWidth(300)
    slider4:SetMinMaxValues(0, 100)
    slider4:SetValueStep(1)
    slider4:SetObeyStepOnDrag(true)
    slider4.Text = _G[sliderName4 .. "Text"]
    slider4.Low = _G[sliderName4 .. "Low"]
    slider4.High = _G[sliderName4 .. "High"]
    slider4.Text:SetText(format("%d", slider4:GetValue()))
    slider4.Low:SetText(format("%d", select(1, slider4:GetMinMaxValues())))
    slider4.High:SetText(format("%d", select(2, slider4:GetMinMaxValues())))

    slider4:SetScript(
        "OnValueChanged",
        function(self, event)
            self.Text:SetText(format("%d", event))
            ClassicHealPredictionSettings.unitFramesMaxOverflow = toggleValue(event / 100, ClassicHealPredictionSettings.unitFramesMaxOverflow >= 0)
        end
    )

    sliderCheckBox4:SetScript(
        "OnClick",
        function(self)
            if self:GetChecked() then
                slider4.Text:SetTextColor(1.0, 1.0, 1.0)
                slider4.Low:SetTextColor(1.0, 1.0, 1.0)
                slider4.High:SetTextColor(1.0, 1.0, 1.0)
            else
                slider4.Text:SetTextColor(0.5, 0.5, 0.5)
                slider4.Low:SetTextColor(0.5, 0.5, 0.5)
                slider4.High:SetTextColor(0.5, 0.5, 0.5)
            end

            slider4:SetEnabled(self:GetChecked())
            ClassicHealPredictionSettings.unitFramesMaxOverflow = toggleValue(ClassicHealPredictionSettings.unitFramesMaxOverflow, self:GetChecked())
        end
    )

    local checkBoxName2 = format("ClassicHealPredictionCheckbox%d", #checkBoxes + 1)
    checkBox2 = CreateFrame("CheckButton", checkBoxName2, self, "OptionsCheckButtonTemplate")
    checkBox2:SetPoint("TOPLEFT", sliderCheckBox4, "BOTTOMLEFT", 0, -50)
    checkBox2.Text = _G[checkBoxName2 .. "Text"]
    checkBox2.Text:SetText("Show mana cost prediction")
    checkBox2.Text:SetTextColor(1, 1, 1)

    checkBox2:SetScript(
        "OnClick",
        function(self)
            ClassicHealPredictionSettings.showManaCostPrediction = self:GetChecked()
        end
    )

    for k, x in ipairs(
        {
            {"Raid Frames: My healing", {1, 2, 3, 4}},
            {"Raid Frames: Other healing", {5, 6, 7, 8}},
            {"Unit Frames: My healing", {9, 10, 11, 12}},
            {"Unit Frames: Other healing", {13, 14, 15, 16}},
            {"Unit Frames: My mana cost", {17}}
        }
    ) do
        local text, slots = unpack(x)

        local j = 1

        colorSwatches[k] = {}

        for _, i in pairs(slots) do
            local name = format("ClassicHealPredictionColorSwatch%d", i)
            local colorSwatch = CreateFrame("Button", name, self, "ClassicHealPredictionColorSwatchTemplate")

            colorSwatch.index = i

            if k == 1 and j == 1 then
                colorSwatch:SetPoint("TOPRIGHT", -245, -60)
            elseif k ~= 1 and j == 1 then
                colorSwatch:SetPoint("TOPLEFT", colorSwatches[k - 1][1], "BOTTOMLEFT", 0, -8)
            else
                colorSwatch:SetPoint("LEFT", colorSwatches[k][j - 1], "RIGHT", 0, 0)
            end

            j = j + 1

            local r, g, b, a = unpack(ClassicHealPredictionSettings.colors[colorSwatch.index])
            colorSwatch:GetNormalTexture():SetVertexColor(r, g, b, a)

            local function callback(previousValues)
                local newR, newG, newB, newA

                if previousValues then
                    newR, newG, newB, newA = unpack(previousValues)
                else
                    newA, newR, newG, newB = 1.0 - OpacitySliderFrame:GetValue(), ColorPickerFrame:GetColorRGB()
                end

                colorSwatch:GetNormalTexture():SetVertexColor(newR, newG, newB, newA)
                ClassicHealPredictionSettings.colors[colorSwatch.index] = {gradient(newR, newG, newB, newA)}
            end

            colorSwatch:SetScript(
                "OnClick",
                function(self)
                    local r, g, b, a = unpack(ClassicHealPredictionSettings.colors[colorSwatch.index])
                    ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = true, 1.0 - a
                    ColorPickerFrame.previousValues = {r, g, b, a}
                    ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = callback, callback, callback
                    ColorPickerFrame:SetColorRGB(r, g, b)
                    ColorPickerFrame:Hide()
                    ColorPickerFrame:Show()
                end
            )

            tinsert(colorSwatches[k], colorSwatch)
        end

        local textString = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        textString:SetPoint("LEFT", colorSwatches[k][#colorSwatches[k]], "RIGHT", 16 * (4 - #colorSwatches[k]) + 5, 0)
        textString:SetTextColor(1, 1, 1)
        textString:SetText(text)
    end

    local colorSwatches2 = colorSwatches
    colorSwatches = {}

    for _, t in ipairs(colorSwatches2) do
        for _, x in ipairs(t) do
            tappend(colorSwatches, x)
        end
    end

    self.name = ADDON_NAME
    self.default = ClassicHealPredictionFrame_Default
    self.refresh = ClassicHealPredictionFrame_Refresh
    self.okay = ClassicHealPredictionFrame_Okay
    self.cancel = ClassicHealPredictionFrame_Cancel

    InterfaceOptions_AddCategory(self)

    loadedFrame = true
end

_G.ClassicHealPredictionFrame_OnLoad = ClassicHealPredictionFrame_OnLoad

do
    local healComm = {}

    local Renew = GetSpellInfo(139)
    local GreaterHealHot = GetSpellInfo(22009)
    local Rejuvenation = GetSpellInfo(774)
    local Regrowth = GetSpellInfo(8936)
    local Tranquility = GetSpellInfo(740)

    tickIntervals = {
        [Renew] = 3,
        [GreaterHealHot] = 3,
        [Rejuvenation] = 3,
        [Regrowth] = 3,
        [Tranquility] = 2
    }

    function healComm:HealComm_HealStarted(event, casterGUID, spellID, type, endTime, ...)
        local predictEndTime = getOtherEndTime()

        if casterGUID == UnitGUID("player") or not predictEndTime or endTime <= predictEndTime then
            UpdateHealPrediction(...)
            return
        end

        if bit.band(type, HealComm_OVERTIME_HEALS) > 0 then
            local tickInterval = tickIntervals[GetSpellInfo(spellID)] or 1
            local delta = predictEndTime - GetTime()
            local duration = tickInterval - delta % tickInterval + 0.001

            if duration < tickInterval then
                local guids = {...}

                C_Timer.After(
                    duration,
                    function()
                        UpdateHealPrediction(unpack(guids))
                    end
                )
            end

            UpdateHealPrediction(...)
        else
            local duration = endTime - predictEndTime + 0.001
            local guids = {...}

            C_Timer.After(
                duration,
                function()
                    UpdateHealPrediction(unpack(guids))
                end
            )
        end
    end

    function healComm:HealComm_HealStopped(event, casterGUID, spellID, type, interrupted, ...)
        UpdateHealPrediction(...)
    end

    function healComm:HealComm_ModifierChanged(event, ...)
        UpdateHealPrediction(...)
    end

    HealComm.RegisterCallback(healComm, "HealComm_HealStarted")
    HealComm.RegisterCallback(healComm, "HealComm_HealStopped")
    HealComm.RegisterCallback(healComm, "HealComm_HealDelayed", "HealComm_HealStarted")
    HealComm.RegisterCallback(healComm, "HealComm_HealUpdated", "HealComm_HealStarted")
    HealComm.RegisterCallback(healComm, "HealComm_ModifierChanged")
    HealComm.RegisterCallback(healComm, "HealComm_GUIDDisappeared", "HealComm_ModifierChanged")
end
