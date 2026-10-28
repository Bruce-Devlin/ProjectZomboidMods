require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
local Runtime = require "ProjectPeople/SurvivorRuntime"
local Party = require "ProjectPeople/Party"
local Theme = require "ProjectPeople/UITheme"
local Portraits = require "ProjectPeople/UIPortraits"
local C = Theme.colors
local UI = {}
ProjectPeople.PartyUI = UI
local Panel = ISPanel:derive "ProjectPeoplePartyPanel"
local current, toggleButton, refreshAt = nil, nil, 0

local function plain(value, length)
    return tostring(value or ""):gsub("[<>\r\n]", ""):sub(1, length or 80)
end

function UI.direction(origin, target)
    if not target then
        return "Unknown"
    end
    local dx, dy = target.x - origin.x, target.y - origin.y
    local distance = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
    local floor = target.z - math.floor(origin.z)
    local height = floor > 0 and " / upstairs" or floor < 0 and " / downstairs" or ""
    if distance < 2 then
        return "Here" .. height
    end
    local ns = dy < 0 and "N" or "S"
    local ew = dx < 0 and "W" or "E"
    local bearing = math.abs(dx) < math.abs(dy) * 0.414 and ns or math.abs(dy) < math.abs(dx) * 0.414 and ew or ns .. ew
    return bearing .. " / " .. distance .. " tiles" .. height
end

local function settings()
    local player = getSpecificPlayer(0)
    if not player then
        return nil
    end
    local data = player:getModData()
    data.ProjectPeoplePartyUI = data.ProjectPeoplePartyUI or { visible = true, pinned = true }
    return data.ProjectPeoplePartyUI
end

local function child(parent, value)
    value:initialise()
    Theme.widget(value)
    parent:addChild(value)
    return value
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    self.pin = child(
        self,
        ISButton:new(self.width - 118, 7, 56, 22, "Unpin", self, function(panel)
            local saved = settings()
            saved.pinned = not saved.pinned
            panel.moveWithMouse = not saved.pinned
            panel.pin:setTitle(saved.pinned and "Unpin" or "Pin")
        end)
    )
    child(
        self,
        ISButton:new(self.width - 57, 7, 49, 22, "Hide", self, function()
            UI.toggle(false)
        end)
    )
    self.motion = child(
        self,
        ISButton:new(self.width - 170, 7, 46, 22, "2D", self, function(panel)
            local saved = settings()
            saved.portraits = saved.portraits == false
            panel.motion:setTitle(saved.portraits and "2D" or "3D")
            if not saved.portraits then
                Portraits.clear(panel)
            end
        end)
    )
    self.motion.tooltip = "Switch animated portraits / static initials"
    self.list = child(self, ISScrollingListBox:new(10, 60, self.width - 20, self.height - 88))
    self.list.itemheight = 100
    self.list.font = UIFont.Small
    self.list.drawBorder = false
    self.list.doDrawItem = function(list, y, item)
        local row = item.item
        local health = row.health
        local color = Theme.health(health, not row.missing and row.danger)
        local right = list.width - 14
        Theme.row(list, y, item, list.itemheight - 4)
        Theme.rect(list, 2, y + 6, 2, 82, color)
        Theme.rect(list, 10, y + 8, 64, 78, C.base)
        if not self.portraitRows or not self.portraitRows[row.id] then
            local initials = Theme.initials(row.name)
            Theme.text(list, initials, 24, y + 31, 44, C.muted, UIFont.Medium)
        end
        Theme.text(list, row.name, 86, y + 8, right - 86)
        Theme.text(
            list,
            row.missing and "Unavailable" or row.danger and "In danger" or row.activity,
            86,
            y + 29,
            right - 86,
            color
        )
        Theme.text(list, row.direction, 86, y + 49, right - 86, C.muted)
        Theme.rect(list, 86, y + 78, math.max(0, right - 138), 4, C.base)
        if health then
            Theme.rect(list, 86, y + 78, math.max(0, right - 138) * math.max(0, math.min(1, health / 100)), 4, color)
        end
        Theme.text(list, health and math.floor(health + 0.5) .. "%" or "--", right - 44, y + 70, 44, color)
        return y + list.itemheight
    end
    self.list:setOnMouseDownFunction(self, function(panel, row)
        if row and ProjectPeople.Interface then
            ProjectPeople.Interface.open(row.id)
        end
    end)
end

function Panel:refresh()
    local player, view = getSpecificPlayer(0), Runtime.view()
    local fresh = view and getTimestampMs() - (Runtime.viewAt or 0) < 5000
    self.rows = {}
    if player and view and view.world then
        local origin = { x = player:getX(), y = player:getY(), z = player:getZ() }
        for _, id in ipairs(Party.members(view.world, view.personId)) do
            local p = view.world.people[id]
            local known = fresh and not p.missing and p.location ~= nil
            self.rows[#self.rows + 1] = {
                id = id,
                name = p.name,
                missing = not known,
                health = known and p.health or nil,
                activity = known and p.activity or "Location unavailable",
                danger = p.partyDanger or p.interactionDanger,
                direction = UI.direction(origin, known and p.location or nil),
            }
        end
    end
    self.count = #self.rows
    self.limit = view and view.status and view.status.followerLimit or 3
    local scroll = self.list.getYScroll and self.list:getYScroll() or 0
    local selected = self.list.items[self.list.selected or -1]
    local selectedId = selected and selected.item.id
    self.list:clear()
    for _, row in ipairs(self.rows) do
        self.list:addItem(row.name, row)
        if row.id == selectedId then
            self.list.selected = #self.list.items
        end
    end
    if self.list.setYScroll then
        self.list:setYScroll(math.max(math.min(0, self.list.height - self.count * self.list.itemheight), scroll))
    end
    self.portraitActors = Portraits.resolve(Runtime, self.rows)
    self.message = self.count == 0 and "Invite someone to travel with you." or nil
    local saved = settings()
    if saved then
        saved.x, saved.y = self.x, self.y
        self.moveWithMouse = not saved.pinned
        self.pin:setTitle(saved.pinned and "Unpin" or "Pin")
        self.motion:setTitle(saved.portraits == false and "3D" or "2D")
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    Portraits.sync(self, settings() and settings().portraits ~= false, function(id)
        if ProjectPeople.Interface then
            ProjectPeople.Interface.open(id)
        end
    end)
end

function Panel:render()
    Theme.text(self, "Party", 13, 9, self.width - 190)
    Theme.text(
        self,
        tostring(self.count or 0) .. " / " .. tostring(self.limit or 3) .. " companions",
        13,
        36,
        self.width - 26,
        C.muted
    )
    Theme.rule(self, 55)
    Theme.text(
        self,
        self.count == 0 and "People / Cooperate / Travel together" or "Select a companion to open their profile",
        13,
        self.height - 22,
        self.width - 26,
        C.muted
    )
    if self.message then
        if not self.camp and getTexture then
            self.camp = getTexture "media/textures/ProjectPeople/UI/party-camp.png"
        end
        local size = math.min(150, self.list.height - 58)
        if self.camp and size > 24 then
            self:drawTextureScaled(self.camp, (self.width - size) / 2, 69, size, size, 0.9, 1, 1, 1)
        end
        Theme.text(self, "No companions yet", 22, 78 + math.max(24, size), self.width - 44)
        Theme.text(self, self.message, 22, 101 + math.max(24, size), self.width - 44, C.muted)
    end
end

local function ensure()
    local saved = settings()
    if not saved then
        return
    end
    if not toggleButton then
        toggleButton = ISButton:new(
            getPlayerScreenLeft(0) + 76,
            getPlayerScreenTop(0) + 45,
            76,
            25,
            "Party",
            UI,
            function()
                UI.toggle()
            end
        )
        toggleButton:initialise()
        Theme.button(toggleButton)
        toggleButton:addToUIManager()
    end
    if not current then
        local left, top = getPlayerScreenLeft(0), getPlayerScreenTop(0)
        local w = math.min(356, getPlayerScreenWidth(0) - 40)
        local h = math.min(390, getPlayerScreenHeight(0) - 100)
        local x = math.max(
            left,
            math.min(saved.x or left + getPlayerScreenWidth(0) - w - 18, left + getPlayerScreenWidth(0) - w)
        )
        local y = math.max(top, math.min(saved.y or top + 80, top + getPlayerScreenHeight(0) - h))
        current = Panel:new(x, y, w, h)
        Theme.panel(current)
        current:initialise()
        current:addToUIManager()
        current:refresh()
    end
    current:setVisible(saved.visible ~= false)
end

function UI.toggle(wanted)
    local saved = settings()
    if not saved then
        return
    end
    if wanted == nil then
        wanted = saved.visible == false
    end
    saved.visible = wanted
    if not wanted and current then
        Portraits.clear(current)
    end
    ensure()
    if wanted then
        current:bringToTop()
    end
end

function UI.observe()
    return {
        open = current and current:getIsVisible() or false,
        rows = current and current.rows or {},
        pinned = settings() and settings().pinned,
        panel = current,
    }
end

Events.OnGameStart.Add(ensure)
Events.OnTick.Add(function()
    if getTimestampMs() < refreshAt then
        return
    end
    refreshAt = getTimestampMs() + 500
    ensure()
    if current and current:getIsVisible() then
        current:refresh()
    end
end)
return UI
