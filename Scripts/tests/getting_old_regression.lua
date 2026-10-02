-- Run from the repository root with Lua 5.1+ (or Python lupa).
local root = "Mods/GettingOld/Contents/mods/GettingOld/42/media/lua/"
package.path = root .. "shared/?.lua;" .. package.path
local function event()
    local handlers = {}
    return { Add = function(fn) handlers[#handlers + 1] = fn end,
        fire = function(...) for _, fn in ipairs(handlers) do fn(...) end end }
end
local function resetEvents()
    Events = { OnTick = event(), OnPlayerUpdate = event(), OnClientCommand = event(),
        EveryHours = event(), OnServerCommand = event() }
end
resetEvents()
local server, client, now = false, false, 0
function isServer() return server end
function isClient() return client end
function getTimestampMs() return now end
local players = {}
function getNumActivePlayers() return #players end
function getSpecificPlayer(i) return players[i + 1] end
function getPlayer() return players[1] end
function getOnlinePlayers()
    return { size = function() return #players end, get = function(_, i) return players[i + 1] end }
end
local commands, warnings, speech = {}, {}, {}
function sendClientCommand(player, module, command, args)
    commands[#commands + 1] = { player = player, module = module, command = command, args = args }
end
function sendServerCommand(player, module, command, args)
    commands[#commands + 1] = { player = player, module = module, command = command, args = args }
end
function getText(key) return key end
HaloTextHelper = { addBadText = function(player, text) warnings[#warnings + 1] = {player, text} end }
DevTools = { debugLog = function() end, chance = function() return false end,
    saySafe = function(player, text) speech[#speech + 1] = {player, text} end,
    ageWarning = function(player, text) warnings[#warnings + 1] = {player, text} end }
SandboxVars = { GettingOld = { YearLengthDays = 7, RandomBirthday = false, RandomStartingAge = false } }
local gt = { year = 1993, month = 6, day = 8, hour = 0 }
function gt:getYear() return self.year end
function gt:getMonth() return self.month end
function gt:getDay() return self.day end
function gt:getTimeOfDay() return self.hour end
function gt:getDaysSurvived() return 0 end
function getGameTime() return gt end
local function player(index)
    local p = { md = {}, hours = 0, alive = true, index = index, syncs = 0 }
    function p:getModData() return self.md end
    function p:getHoursSurvived() return self.hours end
    function p:isAlive() return self.alive end
    function p:getPlayerNum() return self.index end
    function p:getOnlineID() return self.index + 100 end
    function p:hasTrait() return false end
    function p:transmitModData() self.syncs = self.syncs + 1 end
    function p:addLineChatElement(text) speech[#speech + 1] = {self, text} end
    return p
end
require "AgeClock"
local function newClock(length, month, day)
    SandboxVars.GettingOld.YearLengthDays = length
    local p = player(0)
    p.md = { Age = 30, birthMonth = month, birthDay = day }
    AgeClock.initialize(p)
    return p
end
local function advance(p, hours)
    p.hours = hours
    p.md.Age = AgeClock.advance(p)
    return p.md.Age
end
local clockPlayer = newClock(7, 7, 10) -- tomorrow's date is ignored in custom mode
assert(advance(clockPlayer, 24) == 30)
assert(advance(clockPlayer, 167.99) == 30)
assert(advance(clockPlayer, 168) == 31)
assert(advance(clockPlayer, 336) == 32)
assert(advance(clockPlayer, 336) == 32, "repeat update must not duplicate birthday")
clockPlayer = newClock(1, 7, 10)
assert(advance(clockPlayer, 23) == 30 and advance(clockPlayer, 24) == 31)
clockPlayer = newClock(7, 7, 10)
assert(advance(clockPlayer, 84) == 30)
SandboxVars.GettingOld.YearLengthDays = 14
assert(advance(clockPlayer, 84) == 30, "setting change must not retroactively age player")
assert(advance(clockPlayer, 251.99) == 30 and advance(clockPlayer, 252) == 31)
clockPlayer = newClock(365, 7, 10)
assert(advance(clockPlayer, 0) == 30)
gt.day = 9
assert(advance(clockPlayer, 24) == 31, "default year: tomorrow's birthday must arrive tomorrow")
assert(advance(clockPlayer, 24) == 31)
gt.year = 1994
assert(advance(clockPlayer, 24 + 365 * 24) == 32)
gt.year, gt.month, gt.day = 1995, 1, 27
clockPlayer = newClock(365, 2, 29)
assert(advance(clockPlayer, 0) == 30)
gt.year, gt.day = 1996, 27
assert(advance(clockPlayer, 365 * 24) == 30, "leap birthday waits for February 29")
gt.day = 28
assert(advance(clockPlayer, 366 * 24) == 31)
gt.year, gt.day = 1997, 27
assert(advance(clockPlayer, 731 * 24) == 32, "non-leap anniversary uses February 28")
-- A legacy accelerated save keeps age and partial progress, without replaying past years.
SandboxVars.GettingOld.YearLengthDays = 7
clockPlayer.md = {Age=42, startAge=40, _GettingOldAgeHoursSurvivedAnchor=0,
    _GettingOldAgeCycleHoursAtAnchor=2.5 * 7 * 24}
assert(advance(clockPlayer, 0) == 42)
assert(advance(clockPlayer, 84) == 43)
gt.year, gt.month, gt.day = 1993, 6, 8
print("PASS: calendar anniversaries, leap years, custom 1/7-day intervals, settings changes, legacy progress")
assert(not AgeConfig.isHumanPlayer(player(9)), "NPC must not count as player")
players = { player(0), player(1) }
assert(AgeConfig.isHumanPlayer(players[2]))

-- UI mock leaves lifecycle and submission logic running unchanged.
ISPanel = {}
function ISPanel:derive() local c = {}; c.__index = c; setmetatable(c, {__index=self}); return c end
package.loaded["ISUI/ISPanel"] = true
package.loaded["ISUI/ISButton"] = true
package.loaded["ISUI/ISComboBox"] = true
dofile(root .. "client/BirthdayDialog.lua")
local dialogs = {}
function GettingOldBirthdayDialog:new(p)
    local d = setmetatable({player=p, monthCombo={selected=7}, dayCombo={selected=10}}, self)
    dialogs[#dialogs + 1] = d
    return d
end
function GettingOldBirthdayDialog:initialise() end
function GettingOldBirthdayDialog:addToUIManager() self.visible = true end
function GettingOldBirthdayDialog:removeFromUIManager() self.visible = false end
function GettingOldBirthdayDialog:setVisible(value) self.visible = value end
client = true
Events.OnPlayerUpdate.fire(player(9))
assert(#dialogs == 0, "NPC update must not open birthday UI")
Events.OnTick.fire()
assert(#dialogs == 2, "split-screen players need independent dialogs")
dialogs[2]:onConfirm()
assert(commands[#commands].player == players[2], "submit must use owning player")
Events.OnTick.fire()
assert(#dialogs == 2, "pending selection must not reopen")
now = 6000
Events.OnTick.fire()
assert(#commands == 2, "missing acknowledgement must retry same choice")
players[2].md._AgeAssigned = true
Events.OnTick.fire()
now = 12000
Events.OnTick.fire()
assert(#commands == 2, "acknowledged choice must stop retrying")
players[1].alive = false
Events.OnTick.fire()
assert(not dialogs[1].visible, "dead character dialog must close")
players[1] = player(0)
players[1].md._GettingOldBirthdayChoicePending = true
Events.OnTick.fire()
assert(#dialogs == 3, "stale saved pending flag must not block replacement character")

-- Server ownership, invalid input and repeat delivery.
resetEvents()
client, server = false, true
package.loaded["GettingOld/Registries"] = {}
AgeSystem = { apply = function() end }
dofile(root .. "server/ServerAgeInit.lua")
local npc = player(9)
SandboxVars.GettingOld.RandomBirthday = true
function ZombRand(a, b) return a end
Events.OnPlayerUpdate.fire(npc)
assert(not npc.md._AgeAssigned, "NPC must not initialize")
SandboxVars.GettingOld.RandomBirthday = false
local p = players[1]
Events.OnClientCommand.fire("GettingOld", "SetBirthday", p, {month=2,day=30})
assert(not p.md._AgeAssigned)
Events.OnClientCommand.fire("GettingOld", "SetBirthday", p, {month=7,day=10})
assert(p.md._AgeAssigned and p.md.birthDay == 10)
local savedAnchor = p.md._GettingOldAgeHoursSurvivedAnchor
Events.OnClientCommand.fire("GettingOld", "SetBirthday", p, {month=1,day=1})
assert(p.md.birthDay == 10 and p.md._GettingOldAgeHoursSurvivedAnchor == savedAnchor and p.syncs == 2)

-- Hair must be restored after reload despite a persisted greying cache.
server = false
dofile(root .. "shared/AgeEffects.lua")
ImmutableColor = { new = function(r,g,b) return {r=r,g=g,b=b} end }
local updates = 0
local visual = {
    setHairColor = function(_, color) assert(math.abs(color.r - 0.6) < 1e-9); updates = updates + 1 end,
    setBeardColor = function() end }
function p:getHumanVisual() return visual end
function p:resetModelNextFrame() end
p.md = {Age=55, baseHairColor={r=0.2,g=0.2,b=0.2}, lastGreyFactor=0.5}
AgeSystem.updatePlayerHair(p)
AgeSystem.updatePlayerHair(p)
assert(updates == 1, "restore once per loaded character, not every update")
print("PASS: NPC exclusion, per-player dialogs, retries, server validation, reload hair restoration")

-- B42 server players have no transmitVisual method. Run the real apply path
-- for multiple players so a visual-sync error cannot abort the hourly loop.
server = true
SandboxVars.GettingOld.DeadlyAge = 0
CharacterStat = { ENDURANCE="endurance", FATIGUE="fatigue", PAIN="pain", STRESS="stress" }
AgeSystem.getGroup = function() return "Middle" end
local visualSyncs = {}
function sendHumanVisual(target) visualSyncs[#visualSyncs + 1] = target end
local effectPlayers = {p, player(1)}
effectPlayers[2].md = {Age=55, baseHairColor={r=0.2,g=0.2,b=0.2}}
for _, target in ipairs(effectPlayers) do
    function target:getHumanVisual() return visual end
    function target:resetModelNextFrame() end
    function target:getStats() return {get=function() return 0 end} end
    assert(target.transmitVisual == nil)
    local syncsBefore = target.syncs
    AgeSystem.apply(target)
    assert(target.syncs == syncsBefore + 1, "age mod data must still be replicated")
end
assert(#visualSyncs == 2 and visualSyncs[1] == p and visualSyncs[2] == effectPlayers[2])
server = false
AgeSystem.apply(p)
assert(#visualSyncs == 2, "singleplayer must not send server visual updates")
SandboxVars.GettingOld.DeadlyAge = nil
print("PASS: real age effects use B42 human visual sync for each server player")

-- Dedicated-server aging visits every connected player and replicates each awarded item once.
resetEvents()
server = true
SandboxVars.GettingOld.YearLengthDays = 7
players = {newClock(7, 7, 10), newClock(7, 7, 10)}
local replicated = 0
function sendAddItemToContainer(inventory, item)
    assert(inventory.item == item and item.name and item.tooltip)
    replicated = replicated + 1
end
DevTools.chance = function() return true end
AgeSystem = { apply = function() end, getGroup = function() return "Adult" end,
    removeNonFittingAgeTraits = function() end, addRandomAgeTrait = function() end }
for index, p in ipairs(players) do
    p.index = index - 1
    p.md._AgeAssigned, p.md.birthYear, p.hours = true, 1963, 168
    p.inventory = { AddItem = function(self)
        self.item = {setName = function(item, value) item.name = value end,
            setTooltip = function(item, value) item.tooltip = value end}
        return self.item
    end }
    function p:getInventory() return self.inventory end
    function p:getUsername() return "Player" .. self.index end
end
dofile(root .. "server/AgeUpdate.lua")
Events.EveryHours.fire()
Events.EveryHours.fire()
assert(players[1].md.Age == 31 and players[2].md.Age == 31 and replicated == 2)

-- Connection-wide messages must reach only their intended split-screen character.
resetEvents()
server, client = false, true
dofile(root .. "client/HeartAttackEffects.lua")
local count = #warnings
Events.OnServerCommand.fire("GettingOld", "AgeWarning",
    {textKey="UI_GettingOld_OldAge_Cause", onlineID=players[2]:getOnlineID()})
assert(#warnings == count + 1 and warnings[#warnings][1] == players[2])
Events.OnServerCommand.fire("GettingOld", "AgeWarning",
    {textKey="UI_GettingOld_OldAge_Cause", onlineID=999})
assert(#warnings == count + 1)
print("PASS: server player enumeration, single hat replication, warning ownership")
