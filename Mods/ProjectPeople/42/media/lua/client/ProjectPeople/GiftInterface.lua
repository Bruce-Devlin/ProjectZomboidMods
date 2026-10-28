local Theme = require "ProjectPeople/UITheme"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISRichTextPanel"
local Runtime = require "ProjectPeople/SurvivorRuntime"
local Panel = ISPanel:derive "ProjectPeopleGiftPanel"
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

function Panel:createChildren()
    ISPanel.createChildren(self)
    self.list = child(self, ISScrollingListBox:new(12, 94, self.width - 24, self.height - 204))
    self.list.itemheight = 34
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = function(box, y, row)
        local e = row.item
        if box.selected == row.index then
            Theme.row(box, y, row, box.itemheight)
        end
        box:drawText(clean(e.name):sub(1, math.floor((box.width - 30) / 7)), 8, y + 1, 1, 1, 1, 1, UIFont.Small)
        box:drawText(
            string.format(
                "%.2f wt | condition %d%s%s",
                e.weight,
                e.condition,
                e.equipped and " | unequip first" or "",
                e.favorite and " | unfavorite first" or ""
            ),
            8,
            y + 17,
            0.7,
            0.75,
            0.8,
            1,
            UIFont.Small
        )
        return y + box.itemheight
    end
    self.give = child(
        self,
        ISButton:new(12, self.height - 100, 210, 26, "Gift selected item", self, function(p)
            local row = p.list.items[p.list.selected]
            if row then
                p:request("inventory.gift", { itemId = row.item.id })
            end
        end)
    )
    Theme.button(self.give, true)
    self.refresh = child(
        self,
        ISButton:new(234, self.height - 100, 90, 26, "Refresh", self, function(p)
            p:request("gift.open", {})
        end)
    )
    child(
        self,
        ISButton:new(self.width - 82, self.height - 100, 70, 26, "Close", self, function(p)
            p:removeFromUIManager()
            current = nil
        end)
    )
    self.noticePanel = child(self, ISRichTextPanel:new(12, self.height - 65, self.width - 24, 53))
    self.noticePanel.background = false
    self.noticePanel.autosetheight = false
    self.noticePanel.clip = true
    self.noticePanel:addScrollBars()
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

function Panel:populate(data)
    local old = self.list.items[self.list.selected]
    local id = old and old.item.id
    self.data = data
    self.list:clear()
    for _, entry in ipairs(data.items) do
        self.list:addItem(entry.name, entry)
        if entry.id == id then
            self.list.selected = #self.list.items
        end
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    Theme.header(self, "Gift / " .. clean(self.data.name), "bag")
    self:drawText("Your weapons, clothing and wearable bags", 12, 42, 0.8, 0.85, 0.9, 1, UIFont.Small)
    self:drawText("They equip gifts only when they lack similar equipment.", 12, 62, 0.7, 0.75, 0.8, 1, UIFont.Small)
    local row = self.list.items[self.list.selected]
    self.give:setEnable(
        not self.pending and not self.needsRefresh and row ~= nil and not row.item.equipped and not row.item.favorite
    )
    self.refresh:setEnable(not self.pending)
end

local function open(data)
    if current and current.data.personId ~= data.personId then
        current:removeFromUIManager()
        current = nil
    end
    if not current then
        local width = math.min(640, getCore():getScreenWidth() - 32)
        local height = math.min(580, getCore():getScreenHeight() - 32)
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
    current.needsRefresh = false
    current:notice(
        current.resultMessage
            or (
                #data.items == 0 and "You have no weapons, clothing or wearable bags to offer."
                or "Gifts transfer ownership. A bag and all its contents are given together."
            )
    )
    current.resultMessage = nil
end
Events.OnTick.Add(function()
    if current and current.pending and getTimestampMs() - (current.pendingAt or 0) > 15000 then
        current.pending = nil
        current.needsRefresh = true
        current:notice "Response not confirmed. Refresh before offering another gift."
    end
    local reply = Runtime.reply
    if not reply or reply.requestId == lastReply then
        return
    end
    lastReply = reply.requestId
    if reply.gift then
        open(reply.gift)
        current.pending = nil
    elseif current and current.pending == reply.requestId then
        current.pending = nil
        current:notice(reply.message or clean(reply.code):gsub("_", " "))
        if reply.ok then
            current.resultMessage = reply.message
            current:request("gift.open", {})
        end
    end
end)
return Panel
