local Theme = require "ProjectPeople/UITheme"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISRichTextPanel"
local Runtime = require "ProjectPeople/SurvivorRuntime"
local Panel = ISPanel:derive "ProjectPeopleHealthPanel"
local current, lastReply
local function clean(value)
    return tostring(value or ""):gsub("[<>\r\n]", "")
end
local function child(self, widget)
    widget:initialise()
    Theme.widget(widget)
    self:addChild(widget)
    return widget
end
function Panel.current()
    return current
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    self.info = child(self, ISRichTextPanel:new(12, 72, self.width - 24, 118))
    self.info.background = false
    self.info.autosetheight = false
    self.info.clip = true
    self.info:addScrollBars()
    self.list = child(self, ISScrollingListBox:new(12, 202, self.width - 24, self.height - 322))
    self.list.itemheight = 28
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.treat = child(
        self,
        ISButton:new(12, self.height - 108, 210, 28, "Treat with selected supply", self, function(p)
            local row = p.list.items[p.list.selected]
            if row then
                p:request("health.treat", { itemId = row.item.id })
            end
        end)
    )
    Theme.button(self.treat, true)
    self.refresh = child(
        self,
        ISButton:new(234, self.height - 108, 90, 28, "Refresh", self, function(p)
            p:request("health.open", {})
        end)
    )
    child(
        self,
        ISButton:new(self.width - 82, self.height - 108, 70, 28, "Close", self, function(p)
            p:removeFromUIManager()
            current = nil
        end)
    )
    self.message = child(self, ISRichTextPanel:new(12, self.height - 70, self.width - 24, 58))
    self.message.background = false
    self.message.autosetheight = false
    self.message.clip = true
    self.message:addScrollBars()
end
function Panel:notice(value)
    self.message.text = clean(value)
    self.message:paginate()
end
function Panel:request(kind, fields)
    if self.pending then
        return
    end
    fields.personId, fields.version = self.data.personId, self.data.version
    local view = Runtime.view()
    local result = Runtime.request(kind, fields, view and view.world and view.world.revision)
    self.pending, self.pendingAt = result.requestId, getTimestampMs()
    self:notice "Waiting for response..."
end
function Panel:populate(data)
    local row = self.list.items[self.list.selected]
    local selected = row and row.item.id
    self.data = data
    self.list:clear()
    for _, supply in ipairs(data.supplies) do
        self.list:addItem(clean(supply.name), supply)
        if supply.id == selected then
            self.list.selected = #self.list.items
        end
    end
    local state = data.health >= 99.9 and "No combat injuries."
        or string.format("Injured: %.0f health missing.", 100 - data.health)
    self.info.text = clean(state)
        .. " <LINE> "
        .. (data.onFire and "On fire. Put the fire out first. <LINE> " or "")
        .. (data.knockedDown and "Knocked down. <LINE> " or "")
        .. "Care takes 8 seconds and uses one clean bandage or ripped sheet to restore up to 15 health. Stay still and safe. "
        .. "<LINE> Overall injuries are shown here; this companion has no separate body-part wound chart."
    self.info:paginate()
    self:notice(
        data.treating and ("Providing care: " .. data.remaining .. " seconds remaining.")
            or data.cooldown > 0 and ("Recovering from care: " .. data.cooldown .. " seconds before another treatment.")
            or data.message
            or (
                #data.supplies == 0 and "Carry a clean bandage or ripped sheet to provide care."
                or "Choose one of your clean supplies below."
            )
    )
    self.nextRefresh = getTimestampMs() + 2000
    self.needsRefresh = false
end
function Panel:prerender()
    ISPanel.prerender(self)
    Theme.header(self, "Health / " .. clean(self.data.name), "health")
    self:drawRect(12, 45, self.width - 24, 16, 0.8, 0.2, 0.2, 0.2)
    Theme.rect(
        self,
        12,
        45,
        (self.width - 24) * math.max(0, math.min(1, self.data.health / 100)),
        16,
        Theme.health(self.data.health)
    )
    self:drawText(string.format("%.0f / 100", self.data.health), 20, 44, 1, 1, 1, 1, UIFont.Small)
    self.treat:setEnable(
        not self.pending
            and not self.needsRefresh
            and not self.data.treating
            and self.data.cooldown == 0
            and self.data.health < 99.9
            and self.list.items[self.list.selected] ~= nil
    )
    self.refresh:setEnable(not self.pending)
end
local function open(data)
    if current and current.data.personId ~= data.personId then
        current:removeFromUIManager()
        current = nil
    end
    if not current then
        local width = math.min(600, getCore():getScreenWidth() - 32)
        local height = math.min(560, getCore():getScreenHeight() - 32)
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
end
Events.OnTick.Add(function()
    if current then
        if current.pending and getTimestampMs() - current.pendingAt > 15000 then
            current.pending = nil
            current.needsRefresh = true
            current:notice "Response not confirmed. Refresh before providing care."
        elseif not current.pending and current.data.treating and getTimestampMs() >= current.nextRefresh then
            current:request("health.open", {})
        end
    end
    local reply = Runtime.reply
    if not reply or reply.requestId == lastReply then
        return
    end
    lastReply = reply.requestId
    if reply.health then
        open(reply.health)
        current.pending = nil
    elseif current and current.pending == reply.requestId then
        current.pending = nil
        current.needsRefresh = true
        current:notice(reply.message or clean(reply.code):gsub("_", " "))
    end
end)
return Panel
