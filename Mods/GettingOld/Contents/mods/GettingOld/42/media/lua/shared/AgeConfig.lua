AgeConfig = AgeConfig or {}

local DEFAULT_YEAR_LENGTH = 365

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