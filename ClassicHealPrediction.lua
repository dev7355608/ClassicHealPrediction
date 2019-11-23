if WOW_PROJECT_ID ~= WOW_PROJECT_CLASSIC then
    return
end

local ADDON_NAME = ...
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")

if string.sub(ADDON_VERSION, 1, 1) == "v" then
    ADDON_VERSION = string.sub(ADDON_VERSION, 2)
end

local HealComm = LibStub("LibHealComm-4.0")

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

local GetTime = GetTime
local SetCVar = SetCVar
local GetCVarBool = GetCVarBool
local C_Timer = C_Timer
local C_NamePlate = C_NamePlate

local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsFriend = UnitIsFriend
local CastingInfo = CastingInfo
local GetSpellPowerCost = GetSpellPowerCost
local GetRaidRosterInfo = GetRaidRosterInfo
local GetSpellInfo = GetSpellInfo

local function UnitCastingInfo(unit)
    assert(unit == "player")
    return CastingInfo()
end

_G.UnitCastingInfo = UnitCastingInfo

local CompactRaidFrameContainer = CompactRaidFrameContainer
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

local ClassicHealPrediction = {}
_G.ClassicHealPrediction = ClassicHealPrediction

local ClassicHealPredictionDefaultSettings = {
    myFilter = toggleValue(HealComm.ALL_HEALS, true),
    otherFilter = toggleValue(HealComm.ALL_HEALS, true),
    myDelta = toggleValue(3, false),
    otherDelta = toggleValue(3, false)
}
local ClassicHealPredictionSettings = ClassicHealPredictionDefaultSettings

local function getMyFilter()
    return max(ClassicHealPredictionSettings.myFilter, 0)
end

local function getOtherFilter()
    return max(ClassicHealPredictionSettings.myFilter, 0)
end

local function getMyEndTime()
    local delta = ClassicHealPredictionSettings.myDelta

    if delta >= 0 then
        return GetTime() + delta
    end

    return nil
end

local function getOtherEndTime()
    local delta = ClassicHealPredictionSettings.otherDelta

    if delta >= 0 then
        return GetTime() + delta
    end

    return nil
end

local guidToUnitFrame = {}
local guidToNameplateFrame = {}

local loadedSettings = false
local loadedFrame = false
local checkBoxes
local slider
local sliderCheckBox

local function getIncomingHeals(unit)
    if not UnitIsFriend("player", unit) then
        return nil, nil
    end

    local unitGUID = UnitGUID(unit)

    local myFilter = getMyFilter()
    local myEndTime = getMyEndTime()
    local otherFilter = getOtherFilter()
    local otherEndTime = getOtherEndTime()

    local modifier = HealComm:GetHealModifier(unitGUID) or 1.0
    local myAmount = HealComm:GetHealAmount(unitGUID, myFilter, myEndTime, UnitGUID("player"))
    local otherAmount = HealComm:GetOthersHealAmount(unitGUID, otherFilter, otherEndTime)

    return myAmount and myAmount * modifier, otherAmount and otherAmount * modifier
end

local CompactUnitFrame_MAX_INC_HEAL_OVERFLOW = 1.05

local function CompactUnitFrame_UpdateHealPrediction(frame)
    if not frame.myHealPrediction then
        return
    end

    local _, maxHealth = frame.healthBar:GetMinMaxValues()
    local health = frame.healthBar:GetValue()

    if maxHealth <= 0 then
        return
    end

    local unit = frame.displayedUnit
    local myIncomingHeal, otherIncomingHeal = getIncomingHeals(unit)
    myIncomingHeal, otherIncomingHeal = myIncomingHeal or 0, otherIncomingHeal or 0
    local allIncomingHeal = myIncomingHeal + otherIncomingHeal
    local totalAbsorb = 0
    local myCurrentHealAbsorb = 0

    if health < myCurrentHealAbsorb then
        frame.overHealAbsorbGlow:Show()
        myCurrentHealAbsorb = health
    else
        frame.overHealAbsorbGlow:Hide()
    end

    if health - myCurrentHealAbsorb + allIncomingHeal > maxHealth * CompactUnitFrame_MAX_INC_HEAL_OVERFLOW then
        allIncomingHeal = maxHealth * CompactUnitFrame_MAX_INC_HEAL_OVERFLOW - health + myCurrentHealAbsorb
    end

    if allIncomingHeal >= myIncomingHeal then
        otherIncomingHeal = allIncomingHeal - myIncomingHeal
    else
        myIncomingHeal = allIncomingHeal
        otherIncomingHeal = 0
    end

    local overAbsorb = false

    if health - myCurrentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth or health + totalAbsorb >= maxHealth then
        if totalAbsorb > 0 then
            overAbsorb = true
        end

        if allIncomingHeal > myCurrentHealAbsorb then
            totalAbsorb = max(0, maxHealth - (health - myCurrentHealAbsorb + allIncomingHeal))
        else
            totalAbsorb = max(0, maxHealth - health)
        end
    end

    if overAbsorb then
        frame.overAbsorbGlow:Show()
    else
        frame.overAbsorbGlow:Hide()
    end

    local healthTexture = frame.healthBar:GetStatusBarTexture()
    local myCurrentHealAbsorbPercent = myCurrentHealAbsorb / maxHealth
    local healAbsorbTexture

    if myCurrentHealAbsorb > allIncomingHeal then
        local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal
        local shownHealAbsorbPercent = shownHealAbsorb / maxHealth

        healAbsorbTexture = CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.myHealAbsorb, shownHealAbsorb, -shownHealAbsorbPercent)

        if allIncomingHeal > 0 then
            frame.myHealAbsorbLeftShadow:Hide()
        else
            frame.myHealAbsorbLeftShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPLEFT", 0, 0)
            frame.myHealAbsorbLeftShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMLEFT", 0, 0)
            frame.myHealAbsorbLeftShadow:Show()
        end

        if totalAbsorb > 0 then
            frame.myHealAbsorbRightShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPRIGHT", -8, 0)
            frame.myHealAbsorbRightShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMRIGHT", -8, 0)
            frame.myHealAbsorbRightShadow:Show()
        else
            frame.myHealAbsorbRightShadow:Hide()
        end
    else
        frame.myHealAbsorb:Hide()
        frame.myHealAbsorbRightShadow:Hide()
        frame.myHealAbsorbLeftShadow:Hide()
    end

    local incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.myHealPrediction, myIncomingHeal, -myCurrentHealAbsorbPercent)
    incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, incomingHealsTexture, frame.otherHealPrediction, otherIncomingHeal)

    local appendTexture = healAbsorbTexture or incomingHealsTexture

    CompactUnitFrameUtil_UpdateFillBar(frame, appendTexture, frame.totalAbsorb, totalAbsorb)
end

local UnitFrame_MAX_INC_HEAL_OVERFLOW = 1.0

local function UnitFrameHealPredictionBars_Update(frame)
    if not frame.myHealPredictionBar then
        return
    end

    local _, maxHealth = frame.healthbar:GetMinMaxValues()
    local health = frame.healthbar:GetValue()

    if maxHealth <= 0 then
        return
    end

    local unit = frame.unit
    local myIncomingHeal, otherIncomingHeal = getIncomingHeals(unit)
    myIncomingHeal, otherIncomingHeal = myIncomingHeal or 0, otherIncomingHeal or 0
    local allIncomingHeal = myIncomingHeal + otherIncomingHeal
    local totalAbsorb = 0
    local myCurrentHealAbsorb = 0

    if frame.healAbsorbBar then
        myCurrentHealAbsorb = 0

        if health < myCurrentHealAbsorb then
            frame.overHealAbsorbGlow:Show()
            myCurrentHealAbsorb = health
        else
            frame.overHealAbsorbGlow:Hide()
        end
    end

    if health - myCurrentHealAbsorb + allIncomingHeal > maxHealth * UnitFrame_MAX_INC_HEAL_OVERFLOW then
        allIncomingHeal = maxHealth * UnitFrame_MAX_INC_HEAL_OVERFLOW - health + myCurrentHealAbsorb
    end

    if allIncomingHeal >= myIncomingHeal then
        otherIncomingHeal = allIncomingHeal - myIncomingHeal
    else
        myIncomingHeal = allIncomingHeal
        otherIncomingHeal = 0
    end

    local overAbsorb = false

    if health - myCurrentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth or health + totalAbsorb >= maxHealth then
        if totalAbsorb > 0 then
            overAbsorb = true
        end

        if allIncomingHeal > myCurrentHealAbsorb then
            totalAbsorb = max(0, maxHealth - (health - myCurrentHealAbsorb + allIncomingHeal))
        else
            totalAbsorb = max(0, maxHealth - health)
        end
    end

    if overAbsorb then
        frame.overAbsorbGlow:Show()
    else
        frame.overAbsorbGlow:Hide()
    end

    local healthTexture = frame.healthbar:GetStatusBarTexture()
    local myCurrentHealAbsorbPercent = 0
    local healAbsorbTexture = nil

    if frame.healAbsorbBar then
        myCurrentHealAbsorbPercent = myCurrentHealAbsorb / maxHealth

        if myCurrentHealAbsorb > allIncomingHeal then
            local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal
            local shownHealAbsorbPercent = shownHealAbsorb / maxHealth

            healAbsorbTexture = UnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.healAbsorbBar, shownHealAbsorb, -shownHealAbsorbPercent)

            if allIncomingHeal > 0 then
                frame.healAbsorbBarLeftShadow:Hide()
            else
                frame.healAbsorbBarLeftShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPLEFT", 0, 0)
                frame.healAbsorbBarLeftShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMLEFT", 0, 0)
                frame.healAbsorbBarLeftShadow:Show()
            end

            if totalAbsorb > 0 then
                frame.healAbsorbBarRightShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPRIGHT", -8, 0)
                frame.healAbsorbBarRightShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMRIGHT", -8, 0)
                frame.healAbsorbBarRightShadow:Show()
            else
                frame.healAbsorbBarRightShadow:Hide()
            end
        else
            frame.healAbsorbBar:Hide()
            frame.healAbsorbBarLeftShadow:Hide()
            frame.healAbsorbBarRightShadow:Hide()
        end
    end

    local incomingHealTexture = UnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.myHealPredictionBar, myIncomingHeal, -myCurrentHealAbsorbPercent)

    if myIncomingHeal > 0 then
        incomingHealTexture = UnitFrameUtil_UpdateFillBar(frame, incomingHealTexture, frame.otherHealPredictionBar, otherIncomingHeal)
    else
        incomingHealTexture = UnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.otherHealPredictionBar, otherIncomingHeal, -myCurrentHealAbsorbPercent)
    end

    local appendTexture

    if healAbsorbTexture then
        appendTexture = healAbsorbTexture
    else
        appendTexture = incomingHealTexture
    end

    UnitFrameUtil_UpdateFillBar(frame, appendTexture, frame.totalAbsorbBar, totalAbsorb)
end

local function UnitFrameManaCostPredictionBars_Update(frame, isStarting, startTime, endTime, spellID)
    if frame.unit ~= "player" or not frame.manabar or not frame.myManaCostPredictionBar then
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

    UnitFrameManaBar_Update(frame.manabar, "player")
    UnitFrameUtil_UpdateManaFillBar(frame, manaBarTexture, frame.myManaCostPredictionBar, cost)
end

_G.UnitFrameManaCostPredictionBars_Update = UnitFrameManaCostPredictionBars_Update

local function UnitFrameHealPredictionBars_UpdateSize(self)
    if not self.myHealPredictionBar or not self.otherHealPredictionBar then
        return
    end

    UnitFrameHealPredictionBars_Update(self)
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
                CompactUnitFrame_UpdateHealPrediction(self)
            elseif event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" then
                CompactUnitFrame_UpdateHealPrediction(self)
            end
        end
    end
)

hooksecurefunc(
    "CompactUnitFrame_UpdateAll",
    function(frame)
        local unit = frame.displayedUnit

        if UnitExists(unit) then
            CompactUnitFrame_UpdateHealPrediction(frame)
        end
    end
)

hooksecurefunc("CompactUnitFrame_UpdateMaxHealth", CompactUnitFrame_UpdateHealPrediction)

local function defaultCompactUnitFrameSetup(frame)
    if not frame.myHealPrediction then
        return
    end

    frame.myHealPrediction:ClearAllPoints()
    frame.myHealPrediction:SetColorTexture(1, 1, 1)
    frame.myHealPrediction:SetGradient("VERTICAL", 8 / 255, 93 / 255, 72 / 255, 11 / 255, 136 / 255, 105 / 255)
    frame.myHealAbsorb:ClearAllPoints()
    frame.myHealAbsorb:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)
    frame.myHealAbsorbLeftShadow:ClearAllPoints()
    frame.myHealAbsorbRightShadow:ClearAllPoints()
    frame.otherHealPrediction:ClearAllPoints()
    frame.otherHealPrediction:SetColorTexture(1, 1, 1)
    frame.otherHealPrediction:SetGradient("VERTICAL", 11 / 255, 53 / 255, 43 / 255, 21 / 255, 89 / 255, 72 / 255)
    frame.totalAbsorb:ClearAllPoints()
    frame.totalAbsorb:SetTexture("Interface\\RaidFrame\\Shield-Fill")
    frame.totalAbsorb.overlay = frame.totalAbsorbOverlay
    frame.totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    frame.totalAbsorbOverlay:SetAllPoints(frame.totalAbsorb)
    frame.totalAbsorbOverlay.tileSize = 32
    frame.overAbsorbGlow:ClearAllPoints()
    frame.overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
    frame.overAbsorbGlow:SetBlendMode("ADD")
    frame.overAbsorbGlow:SetPoint("BOTTOMLEFT", frame.healthBar, "BOTTOMRIGHT", -7, 0)
    frame.overAbsorbGlow:SetPoint("TOPLEFT", frame.healthBar, "TOPRIGHT", -7, 0)
    frame.overAbsorbGlow:SetWidth(16)
    frame.overHealAbsorbGlow:ClearAllPoints()
    frame.overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
    frame.overHealAbsorbGlow:SetBlendMode("ADD")
    frame.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMLEFT", 7, 0)
    frame.overHealAbsorbGlow:SetPoint("TOPRIGHT", frame.healthBar, "TOPLEFT", 7, 0)
    frame.overHealAbsorbGlow:SetWidth(16)
end

hooksecurefunc("DefaultCompactUnitFrameSetup", defaultCompactUnitFrameSetup)

local function defaultCompactMiniFrameSetup(frame)
    if not frame.myHealPrediction then
        return
    end

    frame.myHealPrediction:ClearAllPoints()
    frame.myHealPrediction:SetColorTexture(1, 1, 1)
    frame.myHealPrediction:SetGradient("VERTICAL", 8 / 255, 93 / 255, 72 / 255, 11 / 255, 136 / 255, 105 / 255)
    frame.myHealAbsorb:ClearAllPoints()
    frame.myHealAbsorb:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)
    frame.myHealAbsorbLeftShadow:ClearAllPoints()
    frame.myHealAbsorbRightShadow:ClearAllPoints()
    frame.otherHealPrediction:ClearAllPoints()
    frame.otherHealPrediction:SetColorTexture(1, 1, 1)
    frame.otherHealPrediction:SetGradient("VERTICAL", 3 / 255, 72 / 255, 5 / 255, 2 / 255, 101 / 255, 18 / 255)
    frame.totalAbsorb:ClearAllPoints()
    frame.totalAbsorb:SetTexture("Interface\\RaidFrame\\Shield-Fill")
    frame.totalAbsorb.overlay = frame.totalAbsorbOverlay
    frame.totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    frame.totalAbsorbOverlay:SetAllPoints(frame.totalAbsorb)
    frame.totalAbsorbOverlay.tileSize = 32
    frame.overAbsorbGlow:ClearAllPoints()
    frame.overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
    frame.overAbsorbGlow:SetBlendMode("ADD")
    frame.overAbsorbGlow:SetPoint("BOTTOMLEFT", frame.healthBar, "BOTTOMRIGHT", -7, 0)
    frame.overAbsorbGlow:SetPoint("TOPLEFT", frame.healthBar, "TOPRIGHT", -7, 0)
    frame.overAbsorbGlow:SetWidth(16)
    frame.overHealAbsorbGlow:ClearAllPoints()
    frame.overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
    frame.overHealAbsorbGlow:SetBlendMode("ADD")
    frame.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMLEFT", 7, 0)
    frame.overHealAbsorbGlow:SetPoint("TOPRIGHT", frame.healthBar, "TOPLEFT", 7, 0)
    frame.overHealAbsorbGlow:SetWidth(16)
end

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
        if frame.overAbsorbGlow then
            frame.overAbsorbGlow:ClearAllPoints()
            frame.overAbsorbGlow:SetPoint("BOTTOMLEFT", frame.healthbar, "BOTTOMRIGHT", -4, -1)
            frame.overAbsorbGlow:SetPoint("TOPLEFT", frame.healthbar, "TOPRIGHT", -4, 1)
            frame.overAbsorbGlow:SetHeight(8)
        end

        if frame.overHealAbsorbGlow then
            frame.overHealAbsorbGlow:ClearAllPoints()
            frame.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", frame.healthbar, "BOTTOMLEFT", 2, -1)
            frame.overHealAbsorbGlow:SetPoint("TOPRIGHT", frame.healthbar, "TOPLEFT", 2, -1)
            frame.overHealAbsorbGlow:SetHeight(8)
        end
    end
)

hooksecurefunc(
    "DefaultCompactNamePlateFrameSetupInternal",
    function(frame)
        if not frame.healthBar.myHealPrediction then
            return
        end

        frame.myHealPrediction = frame.healthBar.myHealPrediction
        frame.otherHealPrediction = frame.healthBar.otherHealPrediction
        frame.totalAbsorb = frame.healthBar.totalAbsorb
        frame.totalAbsorbOverlay = frame.healthBar.totalAbsorbOverlay
        frame.overAbsorbGlow = frame.healthBar.overAbsorbGlow
        frame.myHealAbsorb = frame.healthBar.myHealAbsorb
        frame.myHealAbsorbLeftShadow = frame.healthBar.myHealAbsorbLeftShadow
        frame.myHealAbsorbRightShadow = frame.healthBar.myHealAbsorbRightShadow
        frame.overHealAbsorbGlow = frame.healthBar.overHealAbsorbGlow
        frame.myHealPrediction:SetVertexColor(0.0, 0.659, 0.608)
        frame.myHealAbsorb:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)
        frame.otherHealPrediction:SetVertexColor(0.0, 0.659, 0.608)
        frame.totalAbsorb:SetTexture("Interface\\RaidFrame\\Shield-Fill")
        frame.totalAbsorb.overlay = frame.totalAbsorbOverlay
        frame.totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        frame.totalAbsorbOverlay.tileSize = 20
        frame.overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        frame.overAbsorbGlow:SetBlendMode("ADD")
        frame.overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
        frame.overHealAbsorbGlow:SetBlendMode("ADD")
        frame.myHealPrediction:ClearAllPoints()
        frame.myHealAbsorb:ClearAllPoints()
        frame.myHealAbsorbLeftShadow:ClearAllPoints()
        frame.myHealAbsorbRightShadow:ClearAllPoints()
        frame.otherHealPrediction:ClearAllPoints()
        frame.totalAbsorb:ClearAllPoints()
        frame.totalAbsorbOverlay:SetAllPoints(frame.totalAbsorb)
    end
)

hooksecurefunc(
    "UnitFrame_SetUnit",
    function(self)
        UnitFrameHealPredictionBars_Update(self)
        UnitFrameManaCostPredictionBars_Update(self)
    end
)

hooksecurefunc(
    "UnitFrame_Update",
    function(self)
        UnitFrameHealPredictionBars_Update(self)
        UnitFrameManaCostPredictionBars_Update(self)
    end
)

hooksecurefunc(
    "UnitFrame_OnEvent",
    function(self, event, unit)
        if unit == self.unit then
            if event == "UNIT_MAXHEALTH" then
                UnitFrameHealPredictionBars_Update(self)
            end
        end
    end
)

hooksecurefunc(
    "UnitFrameHealthBar_OnUpdate",
    function(self)
        if not self.disconnected and not self.lockValues then
            local currValue2 = UnitHealth(self.unit)

            if currValue2 ~= self.currValue2 then
                if not self.ignoreNoUnit or UnitGUID(self.unit) then
                    self.currValue2 = currValue2
                    UnitFrameHealPredictionBars_Update(self:GetParent())
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

        if not statusbar or statusbar.lockValues then
            return
        end

        if unit == statusbar.unit then
            local maxValue = UnitHealthMax(unit)

            if statusbar.disconnected then
                statusbar.currValue2 = maxValue
            else
                local currValue2 = UnitHealth(unit)
                statusbar.currValue2 = currValue2
            end
        end

        UnitFrameHealPredictionBars_Update(statusbar:GetParent())
    end
)

local function initUnitFrame(self, textures)
    if not self then
        return
    end

    local name = self:GetName()

    for _, texture in ipairs(textures) do
        local depths, textureName, layer, subLayer = texture[1], texture[2], texture[3], texture[4]
        local template = textureName .. "Template"

        if textureName == "ManaCostPredictionBar" then
            template = "MyManaCostPredictionBarTemplate"
        end

        local frame = self

        for _, depth in ipairs(depths) do
            frame = select(depth, frame:GetChildren())
        end

        frame:CreateTexture(name .. textureName, layer, template, subLayer)
    end

    self.myHealPredictionBar = _G[name .. "MyHealPredictionBar"]
    self.otherHealPredictionBar = _G[name .. "OtherHealPredictionBar"]
    self.totalAbsorbBar = _G[name .. "TotalAbsorbBar"]
    self.totalAbsorbBarOverlay = _G[name .. "TotalAbsorbBarOverlay"]
    self.overAbsorbGlow = _G[name .. "OverAbsorbGlow"]
    self.overHealAbsorbGlow = _G[name .. "OverHealAbsorbGlow"]
    self.healAbsorbBar = _G[name .. "HealAbsorbBar"]
    self.healAbsorbBarLeftShadow = _G[name .. "HealAbsorbBarLeftShadow"]
    self.healAbsorbBarRightShadow = _G[name .. "HealAbsorbBarRightShadow"]
    self.myManaCostPredictionBar = _G[name .. "ManaCostPredictionBar"]

    if self.myHealPredictionBar then
        self.myHealPredictionBar:ClearAllPoints()
    end

    if self.otherHealPredictionBar then
        self.otherHealPredictionBar:ClearAllPoints()
    end

    if self.totalAbsorbBar then
        self.totalAbsorbBar:ClearAllPoints()
    end

    if self.myManaCostPredictionBar then
        self.myManaCostPredictionBar:ClearAllPoints()
    end

    if self.totalAbsorbBarOverlay then
        self.totalAbsorbBar.overlay = self.totalAbsorbBarOverlay
        self.totalAbsorbBarOverlay:SetAllPoints(self.totalAbsorbBar)
        self.totalAbsorbBarOverlay.tileSize = 32
    end

    if self.overAbsorbGlow then
        self.overAbsorbGlow:ClearAllPoints()
        self.overAbsorbGlow:SetPoint("TOPLEFT", self.healthbar, "TOPRIGHT", -7, 0)
        self.overAbsorbGlow:SetPoint("BOTTOMLEFT", self.healthbar, "BOTTOMRIGHT", -7, 0)
    end

    if self.healAbsorbBar then
        self.healAbsorbBar:ClearAllPoints()
        self.healAbsorbBar:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)
    end

    if self.overHealAbsorbGlow then
        self.overHealAbsorbGlow:ClearAllPoints()
        self.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", self.healthbar, "BOTTOMLEFT", 7, 0)
        self.overHealAbsorbGlow:SetPoint("TOPRIGHT", self.healthbar, "TOPLEFT", 7, 0)
    end

    if self.healAbsorbBarLeftShadow then
        self.healAbsorbBarLeftShadow:ClearAllPoints()
    end

    if self.healAbsorbBarRightShadow then
        self.healAbsorbBarRightShadow:ClearAllPoints()
    end

    if self.myHealPredictionBar then
        self:RegisterUnitEvent("UNIT_MAXHEALTH", self.unit)
    end

    if self.myManaCostPredictionBar and self.unit == "player" then
        self:RegisterUnitEvent("UNIT_SPELLCAST_START", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", self.unit)
    end

    if self.myHealPredictionBar then
        _G[name .. "HealthBar"]:SetScript(
            "OnSizeChanged",
            function(self)
                UnitFrameHealPredictionBars_UpdateSize(self:GetParent())
            end
        )
    end

    UnitFrame_Update(self)
end

local function initNamePlateFrame(self, textures)
    if not self then
        return
    end

    for _, texture in ipairs(textures) do
        local name, layer, subLayer, file, texCoords = texture[1], texture[2], texture[3], texture[4], texture[5]

        texture = self:CreateTexture(nil, layer, nil, subLayer)

        if file then
            texture:SetTexture(file)
        end

        if texCoords then
            texture:SetTexCoord(unpack(texCoords))
        end

        self[name] = texture
    end
end

local function UpdateHealPrediction(...)
    for j = 1, select("#", ...) do
        local unitGUID = select(j, ...)

        if unitGUID == UnitGUID("player") then
            UnitFrameHealPredictionBars_Update(PlayerFrame)
        elseif unitGUID == UnitGUID("pet") then
            UnitFrameHealPredictionBars_Update(PetFrame)
        end

        if unitGUID == UnitGUID("target") then
            UnitFrameHealPredictionBars_Update(TargetFrame)
        end

        local unitFrames = guidToUnitFrame[unitGUID]
        local updateFunc

        if unitFrames then
            if IsInRaid() or GetCVarBool("useCompactPartyFrames") then
                updateFunc = CompactUnitFrame_UpdateHealPrediction
            elseif IsInGroup() then
                updateFunc = UnitFrameHealPredictionBars_Update
            end

            if updateFunc then
                for unitFrame in pairs(unitFrames) do
                    updateFunc(unitFrame)
                end
            end
        end

        do
            local namePlateFrame = guidToNameplateFrame[unitGUID]

            if namePlateFrame then
                CompactUnitFrame_UpdateHealPrediction(namePlateFrame)
            end
        end
    end
end

local function updateUnitFrames(updateHealPrediction)
    wipe(guidToUnitFrame)

    if IsInRaid() then
        local frameReservations = CompactRaidFrameContainer.frameReservations
        local raidReservations = frameReservations["raid"].reservations
        local petReservations = frameReservations["pet"].reservations
        local flaggedReservations = frameReservations["flagged"].reservations

        for i = 1, MAX_RAID_MEMBERS do
            do
                local unit = RAID[i]

                if UnitExists(unit) then
                    local unitGUID = UnitGUID(unit)
                    local unitFrame = raidReservations[unitGUID]

                    if unitFrame then
                        guidToUnitFrame[unitGUID] = guidToUnitFrame[unitGUID] or {}
                        guidToUnitFrame[unitGUID][unitFrame] = true
                    end
                end
            end

            do
                local unit = RAIDPET[i]

                if UnitExists(unit) then
                    local unitGUID = UnitGUID(unit)
                    local unitFrame = petReservations[unit]

                    if unitFrame then
                        guidToUnitFrame[unitGUID] = guidToUnitFrame[unitGUID] or {}
                        guidToUnitFrame[unitGUID][unitFrame] = true
                    end
                end
            end
        end

        for i = 1, MAX_RAID_MEMBERS do
            local unitName, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)

            if unitName and (role == "MAINTANK" or role == "MAINASSIST") then
                do
                    local unitGUID = UnitGUID(unitName)
                    local unitFrame = flaggedReservations[unitGUID]

                    if unitFrame then
                        guidToUnitFrame[unitGUID] = guidToUnitFrame[unitGUID] or {}
                        guidToUnitFrame[unitGUID][unitFrame] = true
                    end
                end
            end
        end
    elseif IsInGroup() then
        if GetCVarBool("useCompactPartyFrames") then
            local frameReservations = CompactRaidFrameContainer.frameReservations
            local raidReservations = frameReservations["raid"].reservations
            local petReservations = frameReservations["pet"].reservations

            for i = 0, MAX_PARTY_MEMBERS do
                do
                    local unit = PARTY[i]

                    if UnitExists(unit) then
                        local unitGUID = UnitGUID(unit)
                        local unitFrame = raidReservations[unitGUID]

                        if unitFrame then
                            guidToUnitFrame[unitGUID] = guidToUnitFrame[unitGUID] or {}
                            guidToUnitFrame[unitGUID][unitFrame] = true
                        end
                    end
                end

                do
                    local unit = PARTYPET[i]

                    if UnitExists(unit) then
                        local unitGUID = UnitGUID(unit)
                        local unitFrame = petReservations[unit]

                        if unitFrame then
                            guidToUnitFrame[unitGUID] = guidToUnitFrame[unitGUID] or {}
                            guidToUnitFrame[unitGUID][unitFrame] = true
                        end
                    end
                end
            end
        else
            for i = 1, MAX_PARTY_MEMBERS do
                do
                    local unit = PARTY[i]

                    if UnitExists(unit) then
                        local unitGUID = UnitGUID(unit)
                        local unitFrame = PartyMemberFrame[i]

                        if unitFrame then
                            guidToUnitFrame[unitGUID] = guidToUnitFrame[unitGUID] or {}
                            guidToUnitFrame[unitGUID][unitFrame] = true
                        end
                    end
                end

                do
                    local unit = PARTYPET[i]

                    if UnitExists(unit) then
                        local unitGUID = UnitGUID(unit)
                        local unitFrame = PartyMemberFramePetFrame[i]

                        if unitFrame then
                            guidToUnitFrame[unitGUID] = guidToUnitFrame[unitGUID] or {}
                            guidToUnitFrame[unitGUID][unitFrame] = true
                        end
                    end
                end
            end
        end
    end

    if updateHealPrediction then
        local unitGUIDs = {}

        for unitGUID in pairs(guidToUnitFrame) do
            tinsert(unitGUIDs, unitGUID)
        end

        UpdateHealPrediction(unpack(unitGUIDs))
    end
end

hooksecurefunc(
    "CompactRaidFrameManager_SetSetting",
    function()
        updateUnitFrames(true)
    end
)

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
                checkBox.text:SetTextColor(1.0, 1.0, 1.0)
            else
                checkBox.text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end

    sliderCheckBox:SetChecked(ClassicHealPredictionSettings.otherDelta >= 0)
    sliderCheckBox:SetEnabled(ClassicHealPredictionSettings.otherFilter >= 0)

    if ClassicHealPredictionSettings.otherFilter >= 0 then
        sliderCheckBox.text:SetTextColor(1.0, 1.0, 1.0)
    else
        sliderCheckBox.text:SetTextColor(0.5, 0.5, 0.5)
    end

    slider:SetValue(toggleValue(ClassicHealPredictionSettings.otherDelta, true))
    slider:SetEnabled(ClassicHealPredictionSettings.otherFilter >= 0 and ClassicHealPredictionSettings.otherDelta >= 0)

    if ClassicHealPredictionSettings.otherFilter >= 0 and ClassicHealPredictionSettings.otherDelta >= 0 then
        slider.text:SetTextColor(1.0, 1.0, 1.0)
        slider.textLow:SetTextColor(1.0, 1.0, 1.0)
        slider.textHigh:SetTextColor(1.0, 1.0, 1.0)
    else
        slider.text:SetTextColor(0.5, 0.5, 0.5)
        slider.textLow:SetTextColor(0.5, 0.5, 0.5)
        slider.textHigh:SetTextColor(0.5, 0.5, 0.5)
    end
end

local function ClassicHealPredictionFrame_OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" then
        if not _G.ClassicHealPredictionSettings then
            _G.ClassicHealPredictionSettings = {}
        end

        for k, v in pairs(ClassicHealPredictionDefaultSettings) do
            if not _G.ClassicHealPredictionSettings[k] then
                _G.ClassicHealPredictionSettings[k] = v
            end
        end

        _G.ClassicHealPredictionSettings["version"] = ADDON_VERSION

        ClassicHealPredictionSettings = {}

        for k, v in pairs(_G.ClassicHealPredictionSettings) do
            ClassicHealPredictionSettings[k] = v
        end

        SetCVar("predictedHealth", 1)

        loadedSettings = true
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
        updateUnitFrames()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_ACTIVE_BATTLEFIELD" or event == "CVAR_UPDATE" and arg1 == "USE_RAID_STYLE_PARTY_FRAMES" then
        updateUnitFrames(true)
    elseif event == "NAME_PLATE_CREATED" then
        local namePlate = arg1

        initNamePlateFrame(
            namePlate.UnitFrame.healthBar,
            {
                {"myHealPrediction", "BORDER", 5, "Interface/TargetingFrame/UI-TargetingFrame-BarFill"},
                {"otherHealPrediction", "BORDER", 5, "Interface/TargetingFrame/UI-TargetingFrame-BarFill"},
                {"totalAbsorb", "BORDER", 5},
                {"totalAbsorbOverlay", "BORDER", 6},
                {"myHealAbsorb", "ARTWORK", 1},
                {"myHealAbsorbLeftShadow", "ARTWORK", 1, "Interface\\RaidFrame\\Absorb-Edge"},
                {"myHealAbsorbRightShadow", "ARTWORK", 1, "Interface\\RaidFrame\\Absorb-Edge", {1, 0, 0, 1}},
                {"overAbsorbGlow", "ARTWORK", 2},
                {"overHealAbsorbGlow", "ARTWORK", 2}
            }
        )
    else
        local namePlateUnitToken = arg1

        if not UnitIsFriend("player", namePlateUnitToken) then
            return
        end

        local unitGUID = UnitGUID(namePlateUnitToken)

        if event == "NAME_PLATE_UNIT_ADDED" then
            local namePlate = C_NamePlate.GetNamePlateForUnit(namePlateUnitToken)
            local namePlateFrame = namePlate and namePlate.UnitFrame
            guidToNameplateFrame[unitGUID] = namePlateFrame

            if namePlateFrame then
                CompactUnitFrame_UpdateHealPrediction(namePlateFrame)
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            guidToNameplateFrame[unitGUID] = nil
        end
    end
end

_G.ClassicHealPredictionFrame_OnEvent = ClassicHealPredictionFrame_OnEvent

local function ClassicHealPredictionFrame_Default()
    wipe(ClassicHealPredictionSettings)
    wipe(_G.ClassicHealPredictionSettings)

    for k, v in pairs(ClassicHealPredictionDefaultSettings) do
        ClassicHealPredictionSettings[k] = v
        _G.ClassicHealPredictionSettings[k] = v
    end

    ClassicHealPredictionSettings["version"] = ADDON_VERSION
    _G.ClassicHealPredictionSettings["version"] = ADDON_VERSION
end

_G.ClassicHealPredictionFrame_Default = ClassicHealPredictionFrame_Default

local function ClassicHealPredictionFrame_Okay()
    wipe(_G.ClassicHealPredictionSettings)

    for k, v in pairs(ClassicHealPredictionSettings) do
        _G.ClassicHealPredictionSettings[k] = v
    end
end

_G.ClassicHealPredictionFrame_Okay = ClassicHealPredictionFrame_Okay

local function ClassicHealPredictionFrame_Cancel()
    wipe(ClassicHealPredictionSettings)

    for k, v in pairs(_G.ClassicHealPredictionSettings) do
        ClassicHealPredictionSettings[k] = v
    end
end

_G.ClassicHealPredictionFrame_Cancel = ClassicHealPredictionFrame_Cancel

local function ClassicHealPredictionFrame_OnLoad(self)
    self:RegisterEvent("ADDON_LOADED")

    initUnitFrame(
        PlayerFrame,
        {
            {{}, "TotalAbsorbBar", "ARTWORK"},
            {{}, "TotalAbsorbBarOverlay", "ARTWORK", 1},
            {{1, 1}, "MyHealPredictionBar", "BACKGROUND"},
            {{1, 1}, "OtherHealPredictionBar", "BACKGROUND"},
            {{1, 1}, "ManaCostPredictionBar", "BACKGROUND"},
            {{1, 1}, "HealAbsorbBar", "BACKGROUND"},
            {{1, 1}, "HealAbsorbBarLeftShadow", "BACKGROUND"},
            {{1, 1}, "HealAbsorbBarRightShadow", "BACKGROUND"},
            {{1, 1}, "OverAbsorbGlow", "ARTWORK", 1},
            {{1, 1}, "OverHealAbsorbGlow", "ARTWORK", 1}
        }
    )

    initUnitFrame(
        PetFrame,
        {
            {{}, "TotalAbsorbBar", "ARTWORK"},
            {{}, "TotalAbsorbBarOverlay", "ARTWORK", 1},
            {{2, 1}, "MyHealPredictionBar", "BACKGROUND"},
            {{2, 1}, "OtherHealPredictionBar", "BACKGROUND"},
            {{2, 1}, "HealAbsorbBar", "BACKGROUND"},
            {{2, 1}, "HealAbsorbBarLeftShadow", "BACKGROUND"},
            {{2, 1}, "HealAbsorbBarRightShadow", "BACKGROUND"},
            {{2, 1}, "OverAbsorbGlow", "ARTWORK"},
            {{2, 1}, "OverHealAbsorbGlow", "ARTWORK"}
        }
    )

    initUnitFrame(
        TargetFrame,
        {
            {{}, "TotalAbsorbBar", "ARTWORK"},
            {{}, "MyHealPredictionBar", "ARTWORK", 1},
            {{}, "OtherHealPredictionBar", "ARTWORK", 1},
            {{}, "HealAbsorbBar", "ARTWORK", 1},
            {{}, "HealAbsorbBarLeftShadow", "ARTWORK", 1},
            {{}, "HealAbsorbBarRightShadow", "ARTWORK", 1},
            {{}, "TotalAbsorbBarOverlay", "ARTWORK", 1},
            {{1}, "OverAbsorbGlow", "ARTWORK", 1},
            {{1}, "OverHealAbsorbGlow", "ARTWORK", 1}
        }
    )

    for i = 1, MAX_PARTY_MEMBERS do
        initUnitFrame(
            PartyMemberFrame[i],
            {
                {{}, "TotalAbsorbBar", "ARTWORK"},
                {{}, "TotalAbsorbBarOverlay", "ARTWORK", 1},
                {{2, 1}, "MyHealPredictionBar", "BACKGROUND"},
                {{2, 1}, "OtherHealPredictionBar", "BACKGROUND"},
                {{2, 1}, "HealAbsorbBar", "BACKGROUND"},
                {{2, 1}, "HealAbsorbBarLeftShadow", "BACKGROUND"},
                {{2, 1}, "HealAbsorbBarRightShadow", "BACKGROUND"},
                {{2, 1}, "OverAbsorbGlow", "ARTWORK"},
                {{2, 1}, "OverHealAbsorbGlow", "ARTWORK"}
            }
        )

        initUnitFrame(PartyMemberFramePetFrame[i], {})
    end

    local frame = CreateFrame("Frame")

    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UPDATE_ACTIVE_BATTLEFIELD")
    frame:RegisterEvent("NAME_PLATE_CREATED")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("CVAR_UPDATE")

    frame:SetScript(
        "OnEvent",
        function(_, ...)
            ClassicHealPredictionFrame_OnEvent(self, ...)
        end
    )

    local title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText(ADDON_NAME)

    local version = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 5, 0)
    version:SetTextColor(0.5, 0.5, 0.5)
    version:SetText("v" .. ADDON_VERSION)

    local description = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    description:SetTextColor(1.0, 1.0, 1.0)
    description:SetText("These options affect only the prediction of healing from sources other than yourself.")

    local description2 = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    description2:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -5)
    description2:SetTextColor(1.0, 1.0, 1.0)
    description2:SetText("The prediction of your own healing spells is always enabled without any restrictions.")

    checkBoxes = {}

    local sliderCheckBoxName = "ClassicHealPredictionSliderCheckbox"
    sliderCheckBox = CreateFrame("CheckButton", sliderCheckBoxName, self, "OptionsSmallCheckButtonTemplate")

    local sliderName = "ClassicHealPredictionSlider"
    slider = CreateFrame("Slider", sliderName, self, "OptionsSliderTemplate")

    for i, x in ipairs(
        {
            {"Enable prediction", nil, HealComm.ALL_HEALS},
            {"Show direct healing", nil, HealComm.DIRECT_HEALS},
            {"Show healing over time", nil, HealComm.HOT_HEALS},
            {"Show channeled healing", nil, HealComm.CHANNEL_HEALS}
        }
    ) do
        local text, tooltip, flag = unpack(x)
        local name = format("ClassicHealPredictionCheckButton%d", i)
        local template

        if i == 1 then
            template = "OptionsCheckButtonTemplate"
        else
            template = "OptionsSmallCheckButtonTemplate"
        end

        local checkBox = CreateFrame("CheckButton", name, self, template)

        if i == 1 then
            checkBox:SetPoint("TOPLEFT", description2, "BOTTOMLEFT", 0, -15)
        else
            local anchor

            if i > 2 then
                anchor = "BOTTOMLEFT"
            else
                anchor = "BOTTOMRIGHT"
            end

            checkBox:SetPoint("TOPLEFT", checkBoxes[i - 1], anchor, 0, 0)
        end

        checkBox.text = _G[name .. "Text"]
        checkBox.text:SetText(text)
        checkBox.text:SetTextColor(1, 1, 1)
        checkBox.tooltip = tooltip
        checkBox.flag = flag

        checkBox:SetScript(
            "OnClick",
            function(self)
                if self == checkBoxes[1] then
                    for j = 2, #checkBoxes do
                        checkBoxes[j]:SetEnabled(self:GetChecked())

                        if self:GetChecked() then
                            checkBoxes[j].text:SetTextColor(1.0, 1.0, 1.0)
                        else
                            checkBoxes[j].text:SetTextColor(0.5, 0.5, 0.5)
                        end
                    end

                    sliderCheckBox:SetEnabled(self:GetChecked())

                    if self:GetChecked() then
                        sliderCheckBox.text:SetTextColor(1.0, 1.0, 1.0)
                    else
                        sliderCheckBox.text:SetTextColor(0.5, 0.5, 0.5)
                    end

                    slider:SetEnabled(self:GetChecked() and sliderCheckBox:GetChecked())

                    if self:GetChecked() and sliderCheckBox:GetChecked() then
                        slider.text:SetTextColor(1.0, 1.0, 1.0)
                        slider.textLow:SetTextColor(1.0, 1.0, 1.0)
                        slider.textHigh:SetTextColor(1.0, 1.0, 1.0)
                    else
                        slider.text:SetTextColor(0.5, 0.5, 0.5)
                        slider.textLow:SetTextColor(0.5, 0.5, 0.5)
                        slider.textHigh:SetTextColor(0.5, 0.5, 0.5)
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
    sliderCheckBox.text = _G[sliderCheckBoxName .. "Text"]
    sliderCheckBox.text:SetText("Show only healing within the next ... seconds")
    sliderCheckBox.text:SetTextColor(1, 1, 1)

    slider:SetPoint("TOPLEFT", sliderCheckBox, "BOTTOMRIGHT", 0, -15)
    slider.text = _G[sliderName .. "Text"]
    slider.textLow = _G[sliderName .. "Low"]
    slider.textHigh = _G[sliderName .. "High"]
    slider:SetWidth(300)
    slider:SetMinMaxValues(0.0, 30.0)
    slider:SetValueStep(0.1)
    slider:SetObeyStepOnDrag(true)
    slider.minValue, slider.maxValue = slider:GetMinMaxValues()
    slider.text:SetText(format("%.1f", slider:GetValue()))
    slider.textLow:SetText(slider.minValue)
    slider.textHigh:SetText(slider.maxValue)

    slider:SetScript(
        "OnValueChanged",
        function(self, event)
            self.text:SetText(format("%.1f", event))
            ClassicHealPredictionSettings.otherDelta = toggleValue(event, ClassicHealPredictionSettings.otherDelta >= 0)
        end
    )

    sliderCheckBox:SetScript(
        "OnClick",
        function(self)
            if self:GetChecked() then
                slider.text:SetTextColor(1.0, 1.0, 1.0)
                slider.textLow:SetTextColor(1.0, 1.0, 1.0)
                slider.textHigh:SetTextColor(1.0, 1.0, 1.0)
            else
                slider.text:SetTextColor(0.5, 0.5, 0.5)
                slider.textLow:SetTextColor(0.5, 0.5, 0.5)
                slider.textHigh:SetTextColor(0.5, 0.5, 0.5)
            end

            slider:SetEnabled(self:GetChecked())
            ClassicHealPredictionSettings.otherDelta = toggleValue(ClassicHealPredictionSettings.otherDelta, self:GetChecked())
        end
    )

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
    local OVERTIME_HEALS = bit.bor(HealComm.HOT_HEALS, HealComm.CHANNEL_HEALS)

    local Renew = GetSpellInfo(139)
    local GreaterHealHot = GetSpellInfo(22009)
    local Rejuvenation = GetSpellInfo(774)
    local Regrowth = GetSpellInfo(8936)
    local Tranquility = GetSpellInfo(740)

    local tickIntervals = {
        [Renew] = 3,
        [GreaterHealHot] = 3,
        [Rejuvenation] = 3,
        [Regrowth] = 3,
        [Tranquility] = 2
    }

    function healComm:HealComm_HealStarted(event, casterGUID, spellID, type, endTime, ...)
        local predictEndTime

        if casterGUID == UnitGUID("player") then
            predictEndTime = getMyEndTime()
        else
            predictEndTime = getOtherEndTime()
        end

        if not predictEndTime or endTime <= predictEndTime then
            UpdateHealPrediction(...)
        elseif bit.band(type, OVERTIME_HEALS) > 0 then
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
