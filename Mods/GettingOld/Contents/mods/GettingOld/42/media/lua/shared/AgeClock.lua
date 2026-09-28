require "AgeConfig"

AgeClock = {}

local function serialDay(year, month, day)
    local previous = year - 1
    local result = previous * 365 + math.floor(previous / 4)
        - math.floor(previous / 100) + math.floor(previous / 400)
    for m = 1, month - 1 do result = result + AgeConfig.daysInMonth(m, year) end
    return result + math.min(day, AgeConfig.daysInMonth(month, year)) - 1
end

local function calendarNow()
    local gt = getGameTime()
    return serialDay(gt:getYear(), gt:getMonth() + 1, gt:getDay() + 1)
        + gt:getTimeOfDay() / 24, gt:getYear()
end

-- February 29 anniversaries fall on February 28 in non-leap years.
-- Starting age already includes a birthday on the character's creation date.
local function nextBirthdayYear(md)
    local today, year = calendarNow()
    if serialDay(year, md.birthMonth, md.birthDay) <= math.floor(today) then year = year + 1 end
    return year
end

function AgeClock.initialize(player)
    local md = player:getModData()
    local length = math.max(1, AgeConfig.getYearLengthDays())
    md.startAge = md.Age
    md._GettingOldAgeHoursSurvivedAnchor = player:getHoursSurvived()
    md._GettingOldAgeCycleHoursAtAnchor = 0
    md._GettingOldAgeYearLengthDays = length
    md._GettingOldCalendarBirthdayYear = length == 365 and nextBirthdayYear(md) or nil
end

function AgeClock.advance(player)
    local md = player:getModData()
    local now = player:getHoursSurvived()
    local length = math.max(1, AgeConfig.getYearLengthDays())
    local oldLength = md._GettingOldAgeYearLengthDays or length
    if length == 365 then
        -- Calendar mode never derives age from birthYear: accelerated saves keep their age.
        local year = md._GettingOldCalendarBirthdayYear
        if oldLength ~= 365 or not year then year = nextBirthdayYear(md) end
        local today = calendarNow()
        local age = md.Age
        while serialDay(year, md.birthMonth, md.birthDay) <= today do
            age = age + 1
            year = year + 1
        end
        md._GettingOldCalendarBirthdayYear = year
        md._GettingOldAgeYearLengthDays = length
        md._GettingOldAgeHoursSurvivedAnchor = now
        md._GettingOldAgeCycleHoursAtAnchor = 0
        md.startAge = age
        return age
    end
    md._GettingOldCalendarBirthdayYear = nil
    if oldLength == 365 then
        -- Enabling a custom year starts its first full interval at the current age.
        AgeClock.initialize(player)
        return md.Age
    end
    local anchor = md._GettingOldAgeHoursSurvivedAnchor
    local cycle = tonumber(md._GettingOldAgeCycleHoursAtAnchor) or 0
    if not anchor then
        -- Legacy saves retain their current age and partial year, without replaying birthdays.
        local oldDays = md.birthDayCount and math.max(0, getGameTime():getDaysSurvived() - md.birthDayCount) or 0
        cycle = (oldDays % oldLength) * 24
        md.startAge = md.Age
        anchor = now
    end
    local years = (cycle + math.max(0, now - anchor)) / (oldLength * 24)
    local wholeYears = math.floor(years + 1e-10)
    local expectedAge = math.max(md.Age, (md.startAge or md.Age) + wholeYears)
    local fraction = math.max(0, years - wholeYears)
    md.startAge = expectedAge
    md._GettingOldAgeHoursSurvivedAnchor = now
    md._GettingOldAgeCycleHoursAtAnchor = fraction * length * 24
    md._GettingOldAgeYearLengthDays = length
    return expectedAge
end
