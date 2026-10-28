local Theme = require "ProjectPeople/UITheme"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISRichTextPanel"
local Runtime = require "ProjectPeople/SurvivorRuntime"
local Panel = ISPanel:derive "ProjectPeopleEquipmentPanel"
local current, lastReply

function Panel.current()
    return current
end

local function clean(value)
    return tostring(value or ""):gsub("[<>\r\n]", "")
end

local function child(self, widget)
    widget:initialise()
    Theme.widget(widget)
    self:addChild(widget)
    return widget
end

local function selected(list)
    local row = list.items[list.selected]
    return row and row.item
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    local gap = 12
    local half = (self.width - 3 * gap) / 2
    local listHeight = self.height - 280
    self.playerList = child(self, ISScrollingListBox:new(gap, 78, half, listHeight))
    self.npcList = child(self, ISScrollingListBox:new(half + 2 * gap, 78, half, listHeight))
    for _, list in ipairs({ self.playerList, self.npcList }) do
        list.itemheight = 30
        list.font = UIFont.Small
        list.drawBorder = true
        list.doDrawItem = function(box, y, row, alt)
            if box.selected == row.index then
                Theme.row(box, y, row, box.itemheight)
            end
            local e = row.item
            box:drawText(
                clean(e.name):sub(1, math.max(10, math.floor((box.width - 40) / 7))),
                8 + math.min(e.depth, 4) * 8,
                y + 1,
                1,
                1,
                1,
                1,
                UIFont.Small
            )
            box:drawText(
                string.format(
                    "%.2f wt | condition %d%s%s",
                    e.weight,
                    e.condition,
                    e.equipped and " | equipped" or "",
                    e.ammo and " | ammo " .. e.ammo or ""
                ),
                8,
                y + 15,
                0.7,
                0.75,
                0.8,
                1,
                UIFont.Small
            )
            return y + box.itemheight
        end
    end
    local y = 78 + listHeight + 22
    self.playerDest = child(self, ISComboBox:new(gap, y, half, 24, self, nil))
    self.npcDest = child(self, ISComboBox:new(half + 2 * gap, y, half, 24, self, nil))
    self.buttons = {}
    local function button(x, by, w, label, fn)
        local b = child(self, ISButton:new(x, by, w, 25, label, self, fn))
        self.buttons[#self.buttons + 1] = b
        return b
    end
    button(gap, y + 30, half, "Give selected item >", function(p)
        p:transfer "give"
    end)
    button(half + 2 * gap, y + 30, half, "< Take selected item", function(p)
        p:transfer "take"
    end)
    local width = (self.width - 6 * gap) / 5
    for i, entry in ipairs({
        { "Use weapon", "weapon" },
        { "Wear", "wear" },
        { "Unequip", "unequip" },
        { "Move to bag", "stow" },
        { "Refresh", "refresh" },
    }) do
        local mode = entry[2]
        button(gap + (i - 1) * (width + gap), y + 60, width, entry[1], function(p)
            if mode == "refresh" then
                p:request("inventory.open", {})
            elseif mode == "stow" then
                p:transfer "stow"
            else
                local e = selected(p.npcList)
                if e then
                    p:request("equipment.set", { itemId = e.id, mode = mode })
                end
            end
        end)
    end
    button(gap, y + 90, half, "Give all unequipped items >", function(p)
        p:bulk "give"
    end)
    button(half + 2 * gap, y + 90, half, "< Take all unequipped items", function(p)
        p:bulk "take"
    end)
    self.noticePanel = child(self, ISRichTextPanel:new(gap, self.height - 47, self.width - 90, 42))
    self.noticePanel.background = false
    self.noticePanel.autosetheight = false
    self.noticePanel.clip = true
    self.noticePanel:addScrollBars()
    child(
        self,
        ISButton:new(self.width - 74, self.height - 37, 62, 25, "Close", self, function(p)
            p:removeFromUIManager()
            current = nil
        end)
    )
end

function Panel:notice(text)
    self.noticePanel.text = clean(text)
    self.noticePanel:paginate()
end

function Panel:request(kind, fields)
    if self.pending then
        return
    end
    fields.personId = self.data.personId
    fields.version = self.data.version
    local view = Runtime.view()
    local result = Runtime.request(kind, fields, view and view.world and view.world.revision)
    self.pending = result.requestId
    self.pendingAt = getTimestampMs()
    self:notice "Waiting for response..."
end

function Panel:transfer(direction)
    local entry = selected(direction == "give" and self.playerList or self.npcList)
    local combo = direction == "take" and self.playerDest or self.npcDest
    local container = combo.entries and combo.entries[combo.selected]
    if not entry or not container then
        self:notice "Select an item and a destination container."
        return
    end
    self:request("inventory.transfer", { direction = direction, itemId = entry.id, destination = container.id })
end

function Panel:bulk(direction)
    local inventory = direction == "give" and self.data.player or self.data.npc
    local combo = direction == "give" and self.npcDest or self.playerDest
    local destination = combo.entries[combo.selected]
    self.queue = {}
    self.queueDirection = direction
    self.queueDestination = destination.id
    for _, entry in ipairs(inventory.items) do
        -- A top-level bag moves together with its contents. Never enqueue its
        -- children as separate moves, or implicitly strip worn equipment.
        if entry.parent == "root" and not entry.equipped and not entry.favorite then
            self.queue[#self.queue + 1] = entry.id
        end
    end
    self:nextTransfer()
end

function Panel:nextTransfer()
    if not self.queue then
        return
    end
    local id = table.remove(self.queue, 1)
    if not id then
        self.queue = nil
        self:notice "Transfers finished."
        return
    end
    self:request(
        "inventory.transfer",
        { direction = self.queueDirection, itemId = id, destination = self.queueDestination }
    )
end

function Panel:populate(data)
    self.data = data
    for _, pair in ipairs({
        { self.playerList, self.playerDest, data.player },
        { self.npcList, self.npcDest, data.npc },
    }) do
        local list, combo, inventory = pair[1], pair[2], pair[3]
        local old = selected(list)
        local dest = combo.entries and combo.entries[combo.selected]
        list:clear()
        combo:clear()
        combo.entries = inventory.containers
        for _, entry in ipairs(inventory.items) do
            list:addItem(entry.name, entry)
            if old and old.id == entry.id then
                list.selected = #list.items
            end
        end
        for i, c in ipairs(inventory.containers) do
            combo:addOption(
                string.format(
                    "%s  %.1f / %.1f%s",
                    clean(c.name),
                    c.weight,
                    c.capacity,
                    c.reduction and " (" .. c.reduction .. "% reduction)" or ""
                )
            )
            if dest and dest.id == c.id then
                combo.selected = i
            end
        end
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    Theme.header(self, "Equipment / " .. clean(self.data.name), "bag")
    self:drawText("Your inventory", 12, 42, 0.8, 0.85, 0.9, 1, UIFont.Small)
    self:drawText(
        string.format("Their inventory: %.1f / %.1f", self.data.npc.weight, self.data.npc.capacity),
        self.npcList.x,
        42,
        0.8,
        0.85,
        0.9,
        1,
        UIFont.Small
    )
    self:drawText(
        "Select an item. Unequip worn items before transferring them.",
        12,
        60,
        0.65,
        0.7,
        0.75,
        1,
        UIFont.Small
    )
    self:drawText("Receive into:", 12, self.playerDest.y - 18, 0.8, 0.85, 0.9, 1, UIFont.Small)
    self:drawText("Give / move into:", self.npcDest.x, self.npcDest.y - 18, 0.8, 0.85, 0.9, 1, UIFont.Small)
    for _, b in ipairs(self.buttons) do
        b:setEnable(not self.pending)
    end
end

local function open(data)
    if current and current.data.personId ~= data.personId then
        current:removeFromUIManager()
        current = nil
    end
    if not current then
        local width = math.min(900, getCore():getScreenWidth() - 32)
        local height = math.min(640, getCore():getScreenHeight() - 32)
        current = Panel:new(
            (getCore():getScreenWidth() - width) / 2,
            (getCore():getScreenHeight() - height) / 2,
            width,
            height
        )
        current.data = data
        Theme.panel(current)
        current:initialise()
        current:addToUIManager()
        current.moveWithMouse = true
    end
    current:populate(data)
    current:notice "Trade requires trust and a safe, nearby companion. Bags retain their contents."
end
Events.OnTick.Add(function()
    if current and current.pending and getTimestampMs() - (current.pendingAt or 0) > 15000 then
        current.pending = nil
        current.queue = nil
        current:notice "Response not confirmed. Refresh to check the inventory before trying again."
    end
    local reply = Runtime.reply
    if not reply or reply.requestId == lastReply then
        return
    end
    lastReply = reply.requestId
    if reply.inventory then
        open(reply.inventory)
        current.pending = nil
        current:nextTransfer()
    elseif current and current.pending == reply.requestId then
        current.pending = nil
        current:notice(reply.message or clean(reply.code):gsub("_", " "))
        if reply.ok then
            current:request("inventory.open", {})
        else
            current.queue = nil
        end
    end
end)
return Panel
