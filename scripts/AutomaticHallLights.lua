AutomaticHallLights = {}

AutomaticHallLights.initialDelay = 5000
AutomaticHallLights.checkInterval = 10000
AutomaticHallLights.rescanInterval = 60000
AutomaticHallLights.fallbackActivateMinute = 19 * 60
AutomaticHallLights.fallbackDeactivateMinute = 6 * 60
AutomaticHallLights.timer = 0
AutomaticHallLights.rescanTimer = 0
AutomaticHallLights.hasInitialRun = false
AutomaticHallLights.targetPlaceables = nil
AutomaticHallLights.placeableCount = -1

local targetWords = {
    "halle", "hall", "shed", "shelter", "unterstand", "remise", "garage",
    "vehicleshed", "vehicle_shed", "fahrzeughalle", "fahrzeugunterstand",
    "hoermann", "hörmann", "grainhall", "getreidehalle", "schüttgut halle",
    "greenshelter", "cornershed", "garagecontractor", "storagelarge", "shedstorage"
}

local blockWords = {
    "waage", "weightstation", "silo", "tank", "windturbine", "watergate", "washingstation"
}

local function ahlText(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function ahlLower(value)
    return string.lower(ahlText(value))
end

local function ahlContainsAny(value, words)
    local text = ahlLower(value)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function ahlPcall(fn, fallback)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return fallback
end

local function ahlGetName(object)
    if type(object) ~= "table" then
        return ahlText(object)
    end

    local name = ahlPcall(function()
        if object.getName ~= nil then
            return object:getName()
        end
        return nil
    end, nil)

    if name ~= nil and name ~= "" then
        return tostring(name)
    end
    if object.name ~= nil and object.name ~= "" then
        return tostring(object.name)
    end
    if object.storeItem ~= nil and object.storeItem.name ~= nil then
        return tostring(object.storeItem.name)
    end

    return "unknown"
end

local function ahlGetFile(object)
    if type(object) ~= "table" then
        return ""
    end
    return ahlText(object.configFileName or object.xmlFilename or object.customEnvironment or object.baseDirectory)
end

local function ahlGetPlaceables()
    if g_currentMission == nil or g_currentMission.placeableSystem == nil then
        return nil
    end

    local placeableSystem = g_currentMission.placeableSystem
    if type(placeableSystem.placeables) == "table" then
        return placeableSystem.placeables
    end
    if type(placeableSystem.placeablesToSave) == "table" then
        return placeableSystem.placeablesToSave
    end
    if type(placeableSystem.placeableById) == "table" then
        return placeableSystem.placeableById
    end

    return nil
end

local function ahlCountTable(values)
    local count = 0
    if type(values) == "table" then
        for _ in pairs(values) do
            count = count + 1
        end
    end
    return count
end

local function ahlGetMinuteOfDay()
    if g_currentMission == nil or g_currentMission.environment == nil then
        return nil
    end

    local env = g_currentMission.environment

    if type(env.currentMinute) == "number" and type(env.currentHour) == "number" then
        return env.currentHour * 60 + env.currentMinute
    end

    if type(env.dayTime) == "number" then
        return math.floor((env.dayTime / 1000) / 60) % 1440
    end

    return nil
end

local function ahlTimeValueToMinute(value)
    if type(value) ~= "number" then
        return nil
    end
    return math.floor(value) % 1440
end

local function ahlGetGroupTiming(group)
    if type(group) == "table" then
        local activate = ahlTimeValueToMinute(group.activateMinute)
        local deactivate = ahlTimeValueToMinute(group.deactivateMinute)
        if activate ~= nil and deactivate ~= nil and activate ~= deactivate then
            return activate, deactivate
        end
    end

    return AutomaticHallLights.fallbackActivateMinute, AutomaticHallLights.fallbackDeactivateMinute
end

local function ahlStateForInterval(minute, activateMinute, deactivateMinute)
    if activateMinute > deactivateMinute then
        return minute >= activateMinute or minute < deactivateMinute
    end
    return minute >= activateMinute and minute < deactivateMinute
end

local function ahlIsTargetPlaceable(placeable)
    local text = ahlGetName(placeable) .. " " .. ahlGetFile(placeable)
    if ahlContainsAny(text, blockWords) then
        return false
    end
    return ahlContainsAny(text, targetWords)
end

local function ahlIsServer()
    if g_currentMission ~= nil and type(g_currentMission.getIsServer) == "function" then
        return ahlPcall(function() return g_currentMission:getIsServer() end, g_server ~= nil) == true
    end
    return g_server ~= nil
end

local function ahlIsMultiplayer()
    if g_currentMission ~= nil and g_currentMission.missionDynamicInfo ~= nil then
        return g_currentMission.missionDynamicInfo.isMultiplayer == true
    end
    return g_server ~= nil and g_client ~= nil
end

local function ahlSwitchPlaceableLights(placeable, minute)
    if type(placeable) ~= "table" or type(placeable.spec_lights) ~= "table" or type(placeable.spec_lights.groups) ~= "table" then
        return
    end

    if type(placeable.setGroupIsActive) ~= "function" then
        return
    end

    local noEventSend = not ahlIsMultiplayer()

    for groupIndex, group in ipairs(placeable.spec_lights.groups) do
        if type(group) == "table" and group.hasManualLights then
            local activateMinute, deactivateMinute = ahlGetGroupTiming(group)
            local targetState = ahlStateForInterval(minute, activateMinute, deactivateMinute)

            if group.isActive ~= targetState then
                ahlPcall(function()
                    placeable:setGroupIsActive(group.index or groupIndex, targetState, noEventSend)
                    return true
                end, false)
            end
        end
    end
end

function AutomaticHallLights:loadMap()
    self.timer = 0
    self.rescanTimer = 0
    self.hasInitialRun = false
    self.targetPlaceables = nil
    self.placeableCount = -1
end

function AutomaticHallLights:deleteMap()
    self.targetPlaceables = nil
    self.placeableCount = -1
    self.timer = 0
    self.rescanTimer = 0
    self.hasInitialRun = false
end

function AutomaticHallLights:refreshTargets(force)
    local placeables = ahlGetPlaceables()
    if type(placeables) ~= "table" then
        self.targetPlaceables = nil
        self.placeableCount = -1
        return false
    end

    local currentCount = ahlCountTable(placeables)
    if not force and self.targetPlaceables ~= nil and currentCount == self.placeableCount then
        return true
    end

    local targets = {}
    for _, placeable in pairs(placeables) do
        if ahlIsTargetPlaceable(placeable) then
            table.insert(targets, placeable)
        end
    end

    self.targetPlaceables = targets
    self.placeableCount = currentCount
    return true
end

function AutomaticHallLights:update(dt)
    if not ahlIsServer() then
        return
    end

    self.timer = self.timer + dt
    self.rescanTimer = self.rescanTimer + dt

    if not self.hasInitialRun then
        if self.timer < self.initialDelay then
            return
        end
        self.hasInitialRun = true
        self.timer = 0
        self.rescanTimer = 0
        self:refreshTargets(true)
    elseif self.timer < self.checkInterval then
        return
    else
        self.timer = 0
    end

    if self.targetPlaceables == nil or self.rescanTimer >= self.rescanInterval then
        self.rescanTimer = 0
        self:refreshTargets(false)
    end

    local minute = ahlGetMinuteOfDay()
    if minute ~= nil then
        self:applyAutomaticLights(minute)
    end
end

function AutomaticHallLights:applyAutomaticLights(minute)
    if type(self.targetPlaceables) ~= "table" then
        return
    end

    for _, placeable in ipairs(self.targetPlaceables) do
        ahlSwitchPlaceableLights(placeable, minute)
    end
end

addModEventListener(AutomaticHallLights)
