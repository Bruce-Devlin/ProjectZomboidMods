-- Days Until Winter (B41 SP/MP)
-- By Devlin

DaysUntilWinter = DaysUntilWinter or {}
DaysUntilWinterUI = ISUIElement:derive("DaysUntilWinterUI")

DevTools.debugLog("Days Until Winter", "Client UI file loaded")

function DaysUntilWinterUI:new()
    local o = ISUIElement:new(20, getCore():getScreenHeight() - 60, 200, 40)
    setmetatable(o, self)
    self.__index = self
    o:setAlwaysOnTop(true)
    o:setCapture(false)
    return o
end

function DaysUntilWinter.getDaysUntilWinterFromDate(year, month, day)
    local winterStartMonth, winterStartDay = 10, 1 -- Nov 1
    local winterEndMonth, winterEndDay = 2, 28     -- Mar 1

    local daysInMonth = {31,28,31,30,31,30,31,31,30,31,30,31}

    local function isLeapYear(y)
        return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
    end
    if isLeapYear(year) then daysInMonth[2] = 29 end

    if (month > winterStartMonth or (month == winterStartMonth and day >= winterStartDay)) or
       (month < winterEndMonth or (month == winterEndMonth and day <= winterEndDay)) then
        return nil
    end

    local remaining = daysInMonth[month+1] - day
    for m = month+1, winterStartMonth-1 do
        remaining = remaining + daysInMonth[m+1]
    end
    return remaining + (winterStartDay - 1)
end

function DaysUntilWinter.getDaysUntilWinterFromGameTime(gt)
    if not gt then return nil end
    return DaysUntilWinter.getDaysUntilWinterFromDate(gt:getYear(), gt:getMonth(), gt:getDay())
end

function DaysUntilWinterUI:render()
    local days = DaysUntilWinter.getDaysUntilWinterFromGameTime(getGameTime())
    local text
    if days then
        text = string.format("%s: %d", "Days until winter", days)
    else
        text = "It is now winter"
    end

    self:drawText(text, 5, 5, 1,1,1,1, UIFont.AutoNormSmall, true)
end

function DaysUntilWinterUI:updatePosition()
    self:setX(20)
    self:setY(getCore():getScreenHeight() - self.height - 20)
end

local uiAdded = false
Events.OnTick.Add(function()
    if uiAdded then return end
    if uiAdded then
        ui:updatePosition()
    end
    if getPlayer() then
        local ui = DaysUntilWinterUI:new()
        ui:initialise()
        ui:addToUIManager()
        uiAdded = true
        DevTools.debugLog("Days Until Winter", "UI added to client")
    end
end)

require "client/Tests_DaysUntilWinter"
