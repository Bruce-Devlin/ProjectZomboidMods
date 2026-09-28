AgeConfig = AgeConfig or {}

local DEFAULT_STARTING_AGE = 30
local DEFAULT_YEAR_LENGTH = 365
local DEFAULT_DEADLY_AGE = 85
local DEFAULT_YEARS_UNTIL_DEATH = 5

local function sandboxBoolean(name, defaultValue)
    if SandboxVars and SandboxVars.GettingOld and SandboxVars.GettingOld[name] ~= nil then
        local value = SandboxVars.GettingOld[name]
        return value ~= false and value ~= 0 and string.lower(tostring(value)) ~= "false"
    end

    return defaultValue
end

local function isLeapYear(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

function AgeConfig.daysInMonth(month, year)
    if month == 2 then
        if year == nil then
            return 29
        end
        return isLeapYear(year) and 29 or 28
    end

    if month == 4 or month == 6 or month == 9 or month == 11 then
        return 30
    end

    return 31
end

function AgeConfig.useRandomStartingAge()
    return sandboxBoolean("RandomStartingAge", true)
end

function AgeConfig.getStartingAge()
    if AgeConfig.useRandomStartingAge() then
        return ZombRand(25, 35)
    end

    if SandboxVars and SandboxVars.GettingOld and SandboxVars.GettingOld.StartingAge then
        local value = tonumber(SandboxVars.GettingOld.StartingAge)
        if value then
            return math.floor(value)
        end
    end

    return DEFAULT_STARTING_AGE
end

function AgeConfig.useRandomBirthday()
    return sandboxBoolean("RandomBirthday", false)
end

function AgeConfig.getBirthday(birthYear)
    local month = ZombRand(1, 13)
    local day = ZombRand(1, AgeConfig.daysInMonth(month, birthYear) + 1)
    return month, day
end

function AgeConfig.validateBirthday(month, day)
    month = tonumber(month)
    day = tonumber(day)

    if not month or not day then return nil, nil end
    if month ~= math.floor(month) or day ~= math.floor(day) then return nil, nil end
    if month < 1 or month > 12 then return nil, nil end
    if day < 1 or day > AgeConfig.daysInMonth(month) then return nil, nil end

    return month, day
end

function AgeConfig.getYearLengthDays()
    if SandboxVars and SandboxVars.GettingOld and SandboxVars.GettingOld.YearLengthDays then
        local value = SandboxVars.GettingOld.YearLengthDays
        if value and value > 0 then
            DevTools.debugLog("Getting Old", "Year length from sandbox options = " .. tostring(value))
            return value
        end
    end

    DevTools.debugLog("Getting Old", "Year length fallback = " .. DEFAULT_YEAR_LENGTH)
    return DEFAULT_YEAR_LENGTH
end

function AgeConfig.getDeadlyAge()
    if SandboxVars and SandboxVars.GettingOld and SandboxVars.GettingOld.DeadlyAge ~= nil then
        local value = tonumber(SandboxVars.GettingOld.DeadlyAge)
        if value then
            return math.max(0, math.floor(value))
        end
    end

    return DEFAULT_DEADLY_AGE
end

function AgeConfig.getYearsUntilDeath()
    if SandboxVars and SandboxVars.GettingOld and SandboxVars.GettingOld.YearsUntilDeath ~= nil then
        local value = tonumber(SandboxVars.GettingOld.YearsUntilDeath)
        if value and value > 0 then
            return math.floor(value)
        end
    end

    return DEFAULT_YEARS_UNTIL_DEATH
end

function AgeConfig.areDeadlyAgeHeartAttacksEnabled()
    return sandboxBoolean("DeadlyAgeHeartAttacks", false)
end

function AgeConfig.areBirthdayHatsEnabled()
    return sandboxBoolean("EnableBirthdayHats", true)
end
