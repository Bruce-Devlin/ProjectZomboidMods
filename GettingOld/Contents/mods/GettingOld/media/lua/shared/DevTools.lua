------------------------------------
-- Devlin's shared tool library
--
-- Just functions that I can use across several mods to make my life easier.
------------------------------------
DevTools = DevTools or {}
DevTools.debugMode = false

function DevTools.debugLog(modName, msg)
    if DevTools.debugMode then
        print("[" .. modName .. "] " .. tostring(msg))
    end
end

function DevTools.saySafe(player, text)
    if not player then return end

    if isClient() then
        sendClientCommand("chat", "sendPlayerSay", { text = text })
    else
        player:addLineChatElement(text)
    end
end

function DevTools.waitSeconds(seconds, callback)
    local ticks = 0
    local delayTicks = seconds * 60

    local function delayedActions()
        ticks = ticks + 1
        if ticks >= delayTicks then
            Events.OnTick.Remove(delayedActions)
            if callback then
                callback()
            end
        end
    end

    Events.OnTick.Add(delayedActions)
end

_G.DevToolsGlobalTests = _G.DevToolsGlobalTests or {}
DevTools._tests = _G.DevToolsGlobalTests

function DevTools.addTest(name, fn)
    if not name or not fn then return end
    DevTools._tests[name] = fn
end

function DevTools.clearTests()
    DevTools._tests = {}
end

function DevTools.assertTrue(value, msg)
    if not value then
        error(msg or "assertTrue failed", 2)
    end
end

function DevTools.assertEquals(expected, actual, msg)
    if expected ~= actual then
        error(msg or ("assertEquals failed: expected=" .. tostring(expected) .. " actual=" .. tostring(actual)), 2)
    end
end

function DevTools.runTests(opts)
    opts = opts or {}
    local filter = opts.filter
    local total, passed, failed = 0, 0, 0

    for name, fn in pairs(DevTools._tests) do
        if not filter or (type(filter) == "string" and string.find(name, filter, 1, true)) or (type(filter) == "function" and filter(name)) then
            total = total + 1
            local ok, err = pcall(fn)
            if ok then
                passed = passed + 1
                print("[DevTools][Test] PASS: " .. tostring(name))
            else
                failed = failed + 1
                print("[DevTools][Test] FAIL: " .. tostring(name) .. " | " .. tostring(err))
            end
        end
    end

    print(string.format("[DevTools][Test] Complete: total=%d passed=%d failed=%d", total, passed, failed))
    return { total = total, passed = passed, failed = failed }
end
