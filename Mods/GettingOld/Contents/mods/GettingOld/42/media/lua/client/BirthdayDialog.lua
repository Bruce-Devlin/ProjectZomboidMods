require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"

local MOD_ID = "GettingOld"
local MONTHS = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
}

GettingOldBirthdayDialog = ISPanel:derive("GettingOldBirthdayDialog")
local activeDialog = nil
local waitingForServer = false

function GettingOldBirthdayDialog:initialise()
    ISPanel.initialise(self)

    local comboHeight = 28
    self.monthCombo = ISComboBox:new(24, 100, 240, comboHeight, self, GettingOldBirthdayDialog.onMonthChanged)
    self.monthCombo:initialise()
    for _, monthName in ipairs(MONTHS) do
        self.monthCombo:addOption(monthName)
    end
    self:addChild(self.monthCombo)

    self.dayCombo = ISComboBox:new(276, 100, 100, comboHeight)
    self.dayCombo:initialise()
    self:addChild(self.dayCombo)
    self:populateDays(1)

    self.confirmButton = ISButton:new(125, 150, 150, 30, getText("UI_GettingOld_Birthday_Confirm"), self, GettingOldBirthdayDialog.onConfirm)
    self.confirmButton:initialise()
    self.confirmButton:instantiate()
    self:addChild(self.confirmButton)
end

function GettingOldBirthdayDialog:populateDays(month)
    local previousDay = self.dayCombo.selected > 0 and self.dayCombo.selected or 1
    self.dayCombo:clear()
    local maximum = AgeConfig.daysInMonth(month)
    for day = 1, maximum do
        self.dayCombo:addOption(tostring(day))
    end
    self.dayCombo.selected = math.min(previousDay, maximum)
end

function GettingOldBirthdayDialog:onMonthChanged()
    self:populateDays(self.monthCombo.selected)
end

function GettingOldBirthdayDialog:prerender()
    ISPanel.prerender(self)
    self:drawTextCentre(getText("UI_GettingOld_Birthday_Title"), self.width / 2, 18, 1, 1, 1, 1, UIFont.Medium)
    self:drawTextCentre(getText("UI_GettingOld_Birthday_Description"), self.width / 2, 52, 0.85, 0.85, 0.85, 1, UIFont.Small)
    self:drawText(getText("UI_GettingOld_Birthday_Month"), 24, 81, 1, 1, 1, 1, UIFont.Small)
    self:drawText(getText("UI_GettingOld_Birthday_Day"), 276, 81, 1, 1, 1, 1, UIFont.Small)
end

function GettingOldBirthdayDialog:onConfirm()
    local month = self.monthCombo.selected
    local day = self.dayCombo.selected
    local player = self.player
    if not player or not month or not day then return end

    local md = player:getModData()
    md._GettingOldBirthdayChoicePending = true
    waitingForServer = true

    if isClient() then
        sendClientCommand(MOD_ID, "SetBirthday", { month = month, day = day })
    else
        md._GettingOldBirthdayMonth = month
        md._GettingOldBirthdayDay = day
    end

    self:setVisible(false)
    self:removeFromUIManager()
    activeDialog = nil
end

function GettingOldBirthdayDialog:new(player)
    local width = 400
    local height = 204
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local o = ISPanel.new(self, x, y, width, height)
    o.player = player
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 1 }
    o.moveWithMouse = true
    return o
end

local function showBirthdayDialog(player)
    player = player or getPlayer()
    if not player or activeDialog then return end

    local md = player:getModData()
    if md._AgeAssigned then
        waitingForServer = false
        return
    end

    if md._GettingOldBirthdayChoicePending then return end

    if AgeConfig.useRandomBirthday() then
        if isClient() and not waitingForServer then
            sendClientCommand(MOD_ID, "RequestAgeInit", {})
            waitingForServer = true
        end
        return
    end

    if waitingForServer then return end

    activeDialog = GettingOldBirthdayDialog:new(player)
    activeDialog:initialise()
    activeDialog:addToUIManager()
end

Events.OnPlayerUpdate.Add(showBirthdayDialog)
