local Theme = require "ProjectPeople/UITheme"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISRichTextPanel"
require "ISUI/ISTextEntryBox"
local Runtime = require "ProjectPeople/SurvivorRuntime"
local Access = require "ProjectPeople/DebugAccess"
local Debug = { showAll = false }
ProjectPeople.Debug = Debug
local Panel = ISPanel:derive "ProjectPeopleDebugPanel"
local current, tracked, pending, notice, refreshAt = nil, nil, nil, "Debug changes are saved.", 0

local function clean(value)
    return tostring(value or ""):gsub("[<>\r\n]", ""):sub(1, 240)
end

function Debug.data()
    local view = Runtime.view()
    if
        not Access.allowed(getSpecificPlayer(0))
        or not view
        or not view.debug
        or not view.debug.allowed
        or getTimestampMs() - (Runtime.viewAt or 0) > 5000
    then
        return nil
    end
    return view.debug
end

function Debug.row(id)
    local data = Debug.data()
    for _, row in ipairs(data and data.people or {}) do
        if row.id == id then
            return row
        end
    end
end

function Debug.covers(x, y, halfWidth, height)
    return current
            and x + halfWidth >= current.x
            and x - halfWidth <= current.x + current.width
            and y + height >= current.y
            and y <= current.y + current.height
        or false
end

function Debug.request(kind, fields)
    local data = Debug.data()
    if not data or pending then
        return
    end
    local result = Runtime.request(kind, fields, data.revision)
    pending = { id = result.requestId, at = getTimestampMs() }
    notice = "Waiting for the authority..."
end

local function submenu(parent, title)
    local option = parent:addOption(title)
    local child = ISContextMenu:getNew(parent)
    parent:addSubMenu(option, child)
    return child
end

function Debug.person(parent, id)
    local row = Debug.row(id)
    if not row then
        return
    end
    local root = submenu(parent, "Project People debug")
    root:addOption("Track " .. clean(row.name), nil, function()
        tracked = id
    end)
    root:addOption("Inspect NPC", nil, function()
        Debug.open(id)
    end)
    local trust = submenu(root, "Set trust toward me")
    for _, value in ipairs({ -100, -25, 0, 25, 60, 100 }) do
        local chosen = value
        trust:addOption(tostring(chosen), nil, function()
            Debug.request("debug.person", { personId = id, action = "trust", value = chosen })
        end).notAvailable = pending
            ~= nil
    end
    local commands = submenu(root, "Recruit and command this NPC")
    for _, entry in ipairs({
        { "Force recruit to me (this NPC only)", "recruit" },
        { "Follow me", "follow" },
        { "Wait here", "wait" },
        { "Return to recorded home", "base" },
        { "Release from recruitment", "release" },
    }) do
        local action = entry[2]
        commands:addOption(entry[1], nil, function()
            Debug.request("debug.person", { personId = id, action = action })
        end).notAvailable = pending
            ~= nil
    end
    local conditions = submenu(root, "Test conditions")
    for _, entry in ipairs({
        { "Calm and rested", "calm" },
        { "High strain (90)", "strain" },
        { "High stress (95)", "panic" },
        { "Heal native injuries (100%)", "health", 100 },
        { "Set native injury health to 25%", "health", 25 },
    }) do
        local action, value = entry[2], entry[3]
        conditions:addOption(entry[1], nil, function()
            Debug.request("debug.person", { personId = id, action = action, value = value })
        end).notAvailable = pending
            ~= nil
    end
end

function Debug.spawns(parent, position)
    local root = submenu(parent, "Spawn new NPCs")
    for _, entry in ipairs({
        { "Current world outbreak age", "current" },
        { "Early outbreak (day 3)", "outbreak" },
        { "Aftermath (day 60)", "aftermath" },
        { "Long-term survivors (day 365)", "long_term" },
    }) do
        local preset = entry[2]
        local era = submenu(root, entry[1])
        for size = 1, 3 do
            local count = size
            era:addOption(count == 1 and "Lone survivor" or "Group of " .. count, nil, function()
                local fields = { preset = preset, size = count }
                if position then
                    fields.x, fields.y, fields.z = position.x, position.y, position.z
                end
                Debug.request("debug.spawn", fields)
            end).notAvailable = pending
                ~= nil
        end
    end
end

local function child(self, widget)
    widget:initialise()
    Theme.widget(widget)
    self:addChild(widget)
    return widget
end

function Panel:selected()
    local item = self.list.items[self.list.selected]
    return item and item.item
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    local split = math.floor(self.width * 0.44)
    self.search = child(self, ISTextEntryBox:new("", 12, 58, split - 18, 26))
    self.search:setTooltip "Filter spawned NPCs by name or persistent ID"
    self.list = child(self, ISScrollingListBox:new(12, 90, split - 18, self.height - 216))
    self.list.itemheight, self.list.font, self.list.drawBorder = 44, UIFont.Small, true
    self.list.doDrawItem = function(list, y, item, alt)
        if list.selected == item.index then
            Theme.row(list, y, item, 44)
        end
        list:drawText(clean(item.item.name), 6, y + 3, 1, 1, 1, 1, UIFont.Small)
        list:drawText(item.text, 6, y + 22, 0.75, 0.85, 0.9, 1, UIFont.Small)
        return y + 44
    end
    self.info = child(self, ISRichTextPanel:new(split, 58, self.width - split - 12, self.height - 184))
    self.info.background, self.info.autosetheight, self.info.clip = false, false, true
    self.info:addScrollBars()
    local buttonWidth = math.floor((self.width - 36) / 4)
    local function button(index, title, callback)
        return child(
            self,
            ISButton:new(12 + (index - 1) * (buttonWidth + 4), self.height - 90, buttonWidth, 28, title, self, callback)
        )
    end
    self.actions = button(1, "NPC actions", function(p)
        local row = p:selected()
        if row then
            Debug.person(ISContextMenu.get(0, getMouseX(), getMouseY()), row.id)
        end
    end)
    self.track = button(2, "Track selected", function(p)
        local row = p:selected()
        tracked = row and (tracked ~= row.id and row.id or nil)
    end)
    self.markers = button(3, "Show all markers", function()
        Debug.showAll = not Debug.showAll
    end)
    self.spawn = button(4, "Spawn NPCs", function()
        Debug.spawns(ISContextMenu.get(0, getMouseX(), getMouseY()))
    end)
    child(
        self,
        ISButton:new(self.width - 76, 10, 64, 24, "Close", self, function(p)
            p:removeFromUIManager()
            current = nil
        end)
    )
    self.message = child(self, ISRichTextPanel:new(12, self.height - 54, self.width - 24, 44))
    self.message.background, self.message.autosetheight, self.message.clip = false, false, true
    self.message:addScrollBars()
end

function Panel:refresh()
    local data = Debug.data()
    if not data then
        return
    end
    local selected = self:selected()
    local selectedId = self.selectId or selected and selected.id
    self.selectId = nil
    local filter = string.lower(self.search:getText() or "")
    local player = getSpecificPlayer(0)
    local rows = {}
    for _, row in ipairs(data.people) do
        if filter == "" or string.find(string.lower(row.name .. " " .. row.id), filter, 1, true) then
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        local da = (a.x - player:getX()) ^ 2 + (a.y - player:getY()) ^ 2
        local db = (b.x - player:getX()) ^ 2 + (b.y - player:getY()) ^ 2
        return da == db and a.id < b.id or da < db
    end)
    self.list:clear()
    for _, row in ipairs(rows) do
        local distance = math.sqrt((row.x - player:getX()) ^ 2 + (row.y - player:getY()) ^ 2)
        self.list:addItem(string.format("%.0f tiles | floor %d | %.0f%% health", distance, row.z, row.health), row)
        if row.id == selectedId then
            self.list.selected = #self.list.items
        end
    end
    self.countText = #data.people
        .. " spawned / "
        .. data.saved
        .. " saved living | admission limit "
        .. data.physicalLimit
    self.ageText = "Outbreak day " .. math.floor(data.outbreakDays) .. " | " .. #rows .. " shown"
end

function Panel:prerender()
    ISPanel.prerender(self)
    Theme.header(self, "People / Debug", "people", self.width - 130)
    self:drawText(self.countText or "Waiting for NPC data", 12, 36, 0.8, 0.85, 0.9, 1, UIFont.Small)
    self:drawText(self.ageText or "", 12, self.height - 116, 0.8, 0.85, 0.9, 1, UIFont.Small)
    local row = self:selected()
    local text = "No spawned NPCs match this filter. Use Spawn NPCs on the ground floor."
    if row then
        text = clean(row.name)
            .. " <LINE> "
            .. clean(row.id)
            .. string.format(
                " <LINE> Position: %.1f, %.1f, floor %d | native %s",
                row.x,
                row.y,
                row.z,
                tostring(row.nativeId)
            )
            .. " <LINE> Activity: "
            .. clean(row.activity)
            .. " <LINE> Duty: "
            .. clean(row.duty or "independent")
            .. " <LINE> Commander: "
            .. clean(row.commanderId or "none")
            .. " <LINE> Trust toward me: "
            .. row.trust
            .. string.format(" <LINE> Health %.0f%% | strain %.0f | stress %.0f", row.health, row.strain, row.stress)
            .. " <LINE> Era: "
            .. clean(row.era or "authored")
            .. " | "
            .. clean(row.stage)
            .. " <LINE> Group: "
            .. clean(row.groupId or "none")
            .. " <LINE> Normal travel decision: "
            .. clean(row.travel)
            .. " <LINE> Normal residence decision: "
            .. clean(row.resident)
            .. " <LINE> Interaction danger: "
            .. tostring(row.danger)
            .. " <LINE> Busy: "
            .. clean(row.busy or "no")
            .. " <LINE> Cheats affect this NPC only. Normal family consent is unchanged."
    end
    if self.info.text ~= text then
        self.info.text = text
        self.info:paginate()
    end
    self.actions:setEnable(row ~= nil and not pending)
    self.track:setEnable(row ~= nil)
    self.spawn:setEnable(pending == nil)
    self.markers:setTitle(Debug.showAll and "Hide all markers" or "Show all markers")
    self.track:setTitle(row and row.id == tracked and "Stop tracking" or "Track selected")
    if self.message.text ~= notice then
        self.message.text = clean(notice)
        self.message:paginate()
    end
end

function Debug.open(id)
    if not Debug.data() then
        return
    end
    if not current then
        local core = getCore()
        local w, h = math.min(800, core:getScreenWidth() - 24), math.min(620, core:getScreenHeight() - 24)
        current =
            Panel:new(math.max(0, (core:getScreenWidth() - w) / 2), math.max(0, (core:getScreenHeight() - h) / 2), w, h)
        current:initialise()
        current.moveWithMouse = true
        Theme.panel(current)
        current:addToUIManager()
    end
    current.selectId = id
    current:refresh()
    return current
end

function Debug.current()
    return current
end

Events.OnTick.Add(function()
    if not Debug.data() then
        tracked, Debug.showAll, pending = nil, false, nil
        if current then
            current:removeFromUIManager()
            current = nil
        end
        return
    end
    if pending then
        local reply = Runtime.reply
        if reply and reply.requestId == pending.id then
            notice = reply.message or reply.code
            pending = nil
        elseif getTimestampMs() - pending.at > 10000 then
            notice = "Reply timed out. Refresh the roster before issuing another action."
            pending = nil
        end
    end
    if current and getTimestampMs() >= refreshAt then
        refreshAt = getTimestampMs() + 500
        current:refresh()
    end
end)

Events.OnFillWorldObjectContextMenu.Add(function(index, context, objects, test)
    if test or index ~= 0 or not Debug.data() then
        return
    end
    local root = submenu(context, "Project People debug")
    root:addOption("Spawned NPCs and diagnostics", nil, function()
        Debug.open()
    end)
    root:addOption(Debug.showAll and "Hide all NPC markers" or "Show all spawned NPC markers", nil, function()
        Debug.showAll = not Debug.showAll
    end)
    root:addOption("Stop tracking", nil, function()
        tracked = nil
    end).notAvailable = tracked == nil
    local player = getSpecificPlayer(0)
    local zoom, z = getCore():getZoom(0), player:getZ()
    local sq = getCell():getGridSquare(
        IsoUtils.XToIso(getMouseX() * zoom, getMouseY() * zoom, z),
        IsoUtils.YToIso(getMouseX() * zoom, getMouseY() * zoom, z),
        z
    )
    if sq then
        Debug.spawns(root, { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
    end
end)

Events.OnPreUIDraw.Add(function()
    local data = Debug.data()
    if not data or not tracked and not Debug.showAll then
        return
    end
    local player = getSpecificPlayer(0)
    local zoom = getCore():getZoom(0)
    local left, top = getPlayerScreenLeft(0), getPlayerScreenTop(0)
    local width, height = getPlayerScreenWidth(0), getPlayerScreenHeight(0)
    local found = false
    for _, row in ipairs(data.people) do
        if Debug.showAll or row.id == tracked then
            if row.id == tracked then
                found = true
            end
            local x = (IsoUtils.XToScreen(row.x, row.y, row.z, 0) - IsoCamera.getOffX()) / zoom + left
            local y = (IsoUtils.YToScreen(row.x, row.y, row.z, 0) - IsoCamera.getOffY() - 130) / zoom + top
            local outside = x < left + 110 or x > left + width - 110 or y < top + 25 or y > top + height - 45
            x, y =
                math.max(left + 110, math.min(left + width - 110, x)),
                math.max(top + 25, math.min(top + height - 45, y))
            local dist = math.sqrt((row.x - player:getX()) ^ 2 + (row.y - player:getY()) ^ 2)
            local direction = (row.y < player:getY() and "N" or "S") .. (row.x < player:getX() and "W" or "E")
            local text = (row.id == tracked and "[TRACK] " or "[NPC] ")
                .. clean(row.name)
                .. string.format(" | %.0f tiles %s | floor %d", dist, direction, row.z)
            if outside then
                text = text .. " [offscreen]"
            end
            local textManager = getTextManager()
            local halfWidth = textManager:MeasureStringX(UIFont.Small, text) / 2
            x = math.max(left + halfWidth + 8, math.min(left + width - halfWidth - 8, x))
            if not Debug.covers(x, y, halfWidth, 18) then
                textManager:DrawStringCentre(UIFont.Small, x + 1, y + 1, text, 0, 0, 0, 1)
                textManager:DrawStringCentre(UIFont.Small, x, y, text, 1, 0.85, 0.3, 1)
            end
        end
    end
    if tracked and not found then
        getTextManager():DrawStringCentre(
            UIFont.Small,
            left + width / 2,
            top + 25,
            "Tracked NPC is no longer spawned. Check the roster.",
            1,
            0.85,
            0.3,
            1
        )
    end
end)

return Debug
