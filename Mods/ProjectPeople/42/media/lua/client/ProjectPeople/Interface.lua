-- Original client UI. Every gameplay request goes through the injected runtime
-- API with the displayed world revision. This module never changes native actors.
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISRichTextPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTickBox"
require "ISUI/ISComboBox"
local InteractionMenu = require "ProjectPeople/InteractionMenu"
local Interaction = require "ProjectPeople/Interaction"
local InteractionDanger = require "ProjectPeople/InteractionDanger"

ProjectPeople = ProjectPeople or {}
local Interface = { VERSION = 1 }
ProjectPeople.Interface = Interface
local api, window, peopleButton, nextRefresh, sequence = nil, nil, nil, 0, 0
local Panel = ISPanel:derive "ProjectPeoplePanel"
local reasons = {
    needs_rest = "They need a safe break before taking on more travel.",
    too_shaken = "They need time somewhere safe to settle their nerves.",
    family_needs_care = "They are worried about a relative they saw injured. Help their family before asking them to leave.",
    needs_safer_plan = "They need a safer plan or confidence in your judgement before accepting this danger.",
    needs_encouragement = "They are losing hope. Give them time, company and achievable work before asking for more travel.",
    living_survivors_disabled = "Personal conversations are disabled in this world's sandbox settings.",
    cooperation_agreed = "They agreed to cooperate at home.",
    travel_agreed = "They agreed to travel with you.",
    prefers_home = "They prefer to contribute at home.",
    needs_trust = "They need more trust before travelling with you.",
    prefers_temporary_cooperation = "They are willing to travel together, but are not ready to settle here.",
    trust_broken = "Fear or broken trust prevents agreement.",
    committed_to_community = "They will not abandon their community commitments.",
    declines_lethal_risk = "They declined an assignment where death is possible.",
    needs_help = "They need help before taking on this request.",
    already_committed = "They already have a commitment that needs to be resolved.",
    another_commander = "They already follow another living commander.",
    home_required = "They need an established community home before agreeing to residence.",
    social_event_recorded = "You helped secure Mara's home. Owen noticed and is more willing to travel.",
    event_already_recorded = "They remember your help with this door.",
    no_open_household_door_nearby = "Stand next to an open door in the household's room to help secure it.",
    move_next_to_open_door = "Move next to the open door first.",
    conversation_unconfirmed = "Move close enough to speak with this person.",
    not_authorised = "You do not have permission to direct this person or assignment.",
    travel_agreement_required = "Ask them to travel with you before requesting follow.",
    person_unavailable = "This person is currently unavailable.",
    participant_unavailable = "One of the named people is no longer available for this assignment.",
    duty_requested = "Request recorded. Their actual activity will be shown when the runtime observes it.",
    assignment_proposed = "Proposal recorded. Review the named people and danger before accepting.",
    assignment_authorised = "Assignment accepted. Departure has not been confirmed yet.",
    cancelled_before_departure = "The assignment was cancelled before departure.",
    return_requested_risk_continues = "Return requested. Accepted danger continues until safe arrival is confirmed.",
    assignment_not_recallable = "This assignment is not currently recallable.",
    stale_revision = "The situation changed. Review the refreshed information and choose again.",
    explicit_risk_acceptance_required = "Explicitly accept the stated danger for the named people first.",
    request_outcome_unknown = "The response could not be confirmed. Check the current status before trying again.",
    runtime_unavailable = "People are not ready yet.",
    proposal_required = "Select a current proposal first.",
}
local stages = {
    proposed = "Awaiting acceptance",
    authorised = "Accepted; departure unconfirmed",
    away = "Away",
    returning = "Returning; safe arrival unconfirmed",
    safe = "Safe return confirmed",
    cancelled = "Cancelled before departure",
}

local function plain(value)
    return tostring(value or ""):gsub("[<>]", ""):sub(1, 1200)
end

local function readable(code)
    return reasons[code] or plain(code):gsub("_", " ")
end

local function line(value)
    return plain(value) .. " <LINE> "
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function invoke(name, ...)
    if not api or type(api[name]) ~= "function" then
        return false, "runtime_unavailable"
    end
    return pcall(api[name], ...)
end

local function widget(parent, value, group)
    value:initialise()
    parent:addChild(value)
    if group then
        group[#group + 1] = value
    end
    return value
end

local function rich(parent, x, y, w, h, group)
    local value = widget(parent, ISRichTextPanel:new(x, y, w, h), group)
    value.background = false
    value.clip = true
    value.autosetheight = false
    value.marginLeft = 5
    value.marginRight = 8
    value:addScrollBars()
    return value
end

local function setRich(target, text)
    if target.text == text then
        return
    end
    target.text = text
    target:paginate()
end

local function showGroup(group, visible)
    for _, value in ipairs(group) do
        value:setVisible(visible)
    end
end

function Panel:allowed(kind)
    local status = self.runtimeStatus or {}
    if self.busy or status.ready ~= true then
        return false, readable(status.blocked or "runtime_unavailable")
    end
    local action = status.actions and status.actions[kind]
    if action == false then
        return false, "This action is not available yet."
    end
    if type(action) == "table" and action.enabled == false then
        return false, plain(action.reason or "This action is not available yet.")
    end
    return true
end

function Panel:enable(button, kind, condition, reason)
    local allowed, disabled = self:allowed(kind)
    button:setEnable(allowed and condition == true)
    button.tooltip = not allowed and disabled or (condition ~= true and reason or nil)
end

function Panel:person()
    return self.world and self.world.people and self.world.people[self.selectedPersonId]
end

function Panel:canCommand(person)
    if not person or not self.localId then
        return false
    end
    if person.commanderId == self.localId then
        return true
    end
    local me = self.world.people[self.localId]
    local community = person.communityId and self.world.communities[person.communityId]
    return me
            and me.communityId == person.communityId
            and community
            and community.commanders
            and community.commanders[self.localId] == true
        or false
end

function Panel:namedParticipants(participants)
    local names = {}
    for _, id in ipairs(sortedKeys(participants)) do
        local person = self.world and self.world.people[id]
        names[#names + 1] = plain(person and person.name or "Unavailable person")
    end
    return table.concat(names, ", ")
end

function Panel:submit(kind, fields, displayedRevision)
    local allowed, reason = self:allowed(kind)
    if not allowed then
        self.notice = reason
        self:updateContent()
        return
    end
    local revision = displayedRevision or (self.world and self.world.revision)
    if type(revision) ~= "number" then
        self.notice = "The current situation is unavailable."
        return
    end
    self.busy = true
    local ok, result = invoke("request", kind, fields, revision)
    self.busy = false
    if not ok or type(result) ~= "table" then
        result = { ok = false, code = "request_outcome_unknown", detail = ok and "missing_result" or tostring(result) }
    end
    self.lastResult = result
    self.requestCount = (self.requestCount or 0) + 1
    self.notice = result.pending and "Request sent. Waiting for the authority's response."
        or (result.message and plain(result.message) or readable(result.code or "request_outcome_unknown"))
    if result.detail and self.world.people[result.detail] then
        self.notice = plain(self.world.people[result.detail].name) .. ": " .. self.notice
    end
    if fields.personId then
        self.replies[fields.personId] = self.notice
    end
    if result.ok and kind == "mission.propose" then
        self.selectedMissionId = result.missionId or fields.missionId
    end
    self:refresh()
end

function Panel:interactionView()
    local nearby = {}
    for id in pairs(self.nearby) do
        nearby[#nearby + 1] = id
    end
    return { world = self.world, personId = self.localId, nearby = nearby, status = self.runtimeStatus }
end

function Panel:openGroup(group, control)
    if not self:person() then
        return
    end
    local view = self:interactionView()
    local context = ISContextMenu.get(0, control:getAbsoluteX(), control:getAbsoluteY() + control.height)
    InteractionMenu.group(
        context,
        view,
        self.selectedPersonId,
        getSpecificPlayer(0),
        group,
        function(id, kind, fields, revision)
            self:submit(kind, fields, revision)
        end
    )
    -- Household assistance belongs with cooperation in both entry points.
    if group == "Cooperate" then
        InteractionMenu.group(
            context,
            view,
            self.selectedPersonId,
            getSpecificPlayer(0),
            "At home",
            function(id, kind, fields, revision)
                self:submit(kind, fields, revision)
            end
        )
    end
end

function Panel:selectPerson(personId)
    self.selectedPersonId = personId
    self:updateContent()
end

function Panel:setTab(tab)
    self.tab = tab
    self:updateContent()
end

function Panel:toggleParticipant()
    local person = self:person()
    if not person then
        return
    end
    if self.draftParticipants[person.id] then
        self.draftParticipants[person.id] = nil
    elseif
        person.life ~= "dead"
        and person.controller
        and person.controller.kind == "ai"
        and self:canCommand(person)
    then
        self.draftParticipants[person.id] = true
    else
        self.notice = "Select an available person you can command."
    end
    self:updateContent()
end

function Panel:propose()
    local participants = sortedKeys(self.draftParticipants)
    local objective = self.objective:getText():match "^%s*(.-)%s*$"
    local destination = self.destination:getText():match "^%s*(.-)%s*$"
    local endpoint = self.safeEndpoint:getText():match "^%s*(.-)%s*$"
    if #participants == 0 or objective == "" or destination == "" or endpoint == "" then
        self.notice = "Choose named people, an objective, destination and safe return point."
        self:updateContent()
        return
    end
    sequence = sequence + 1
    local missionId = "mission:"
        .. tostring(self.localId):sub(1, 96)
        .. ":"
        .. tostring(getTimestampMs())
        .. ":"
        .. sequence
    self:submit("mission.propose", {
        missionId = missionId,
        objective = objective,
        destination = destination,
        safeEndpoint = endpoint,
        participants = participants,
        deathPossible = self.danger:isSelected(1),
        operatingLimits = { instructions = self.limits:getText() },
        retreatRules = { instructions = self.retreat:getText() },
    })
end

function Panel:acceptMission()
    local mission = self.world and self.world.missions[self.selectedMissionId]
    if not mission or mission.stage ~= "proposed" then
        self.notice = readable "proposal_required"
        return
    end
    if mission.deathPossible and not self.riskConsent:isSelected(1) then
        self.notice = readable "explicit_risk_acceptance_required"
        self:updateContent()
        return
    end
    -- This is a separate click after the persisted proposal and named danger
    -- have been displayed. A stale world revision is rejected by authority.
    self:submit("mission.authorise", { missionId = mission.id, acceptRisk = mission.deathPossible == true })
end

function Panel:refresh()
    local hasReply, reply = invoke "lastReply"
    if hasReply and type(reply) == "table" and reply.requestId ~= self.lastReplyId then
        self.lastReplyId = reply.requestId
        self.lastResult = reply
        self.notice = reply.message and plain(reply.message) or readable(reply.code)
        if reply.personId then
            self.replies[reply.personId] = self.notice
        end
    end
    local ok, status = invoke "status"
    self.runtimeStatus = ok and type(status) == "table" and status or { ready = false, blocked = "runtime_unavailable" }
    local hasWorld, world = invoke "snapshot"
    if not hasWorld or type(world) ~= "table" or type(world.people) ~= "table" then
        self.world = nil
        self.notice = "People information is unavailable."
        self:updateContent()
        return
    end
    self.world = world
    local hasId, id = invoke "localPersonId"
    self.localId = hasId and id or nil
    local identity = tostring(world.worldId) .. ":" .. tostring(world.timelineId) .. ":" .. tostring(self.localId)
    if identity ~= self.identity then
        self.identity = identity
        self.seen = {}
        self.draftParticipants = {}
        self.replies = {}
        self.selectedPersonId = nil
        self.selectedMissionId = nil
    end
    local hasNearby, nearby = invoke "nearby"
    self.nearby = {}
    if hasNearby and type(nearby) == "table" then
        for _, personId in ipairs(nearby) do
            self.nearby[personId] = true
            self.seen[personId] = true
        end
    end
    local me = world.people[self.localId]
    local people = {}
    for personId, person in pairs(world.people) do
        local familiar = self.seen[personId]
            or self.localId ~= nil and person.commanderId == self.localId
            or me and me.communityId ~= nil and person.communityId == me.communityId
        if personId ~= self.localId and familiar then
            people[#people + 1] = person
        end
    end
    table.sort(people, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    self.roster:clear()
    local selected
    for index, person in ipairs(people) do
        self.roster:addItem(person.name, person.id)
        if person.id == self.selectedPersonId then
            selected = index
        end
    end
    self.roster.selected = selected or (#people > 0 and 1 or -1)
    self.selectedPersonId = selected and self.selectedPersonId or (people[1] and people[1].id or nil)
    self.assignment:clear()
    self.assignment:addOptionWithData("New assignment", false)
    local selectedAssignment = 1
    for _, missionId in ipairs(sortedKeys(world.missions)) do
        local mission = world.missions[missionId]
        local known = mission.proposedBy == self.localId
        for personId in pairs(mission.participants or {}) do
            if self.seen[personId] then
                known = true
            end
        end
        if known then
            self.assignment:addOptionWithData(
                plain(mission.objective) .. " - " .. (stages[mission.stage] or plain(mission.stage)),
                missionId
            )
            if missionId == self.selectedMissionId then
                selectedAssignment = #self.assignment.options
            end
        end
    end
    self.assignment.selected = selectedAssignment
    if selectedAssignment == 1 then
        self.selectedMissionId = nil
    end
    self:updateContent()
end

function Panel:updateContent()
    if not self.details then
        return
    end
    local person = self:person()
    local personTab = self.tab == "person"
    local mission = self.world and self.selectedMissionId and self.world.missions[self.selectedMissionId]
    showGroup(self.personWidgets, personTab)
    self.assignment:setVisible(not personTab)
    showGroup(self.draftWidgets, not personTab and not mission)
    showGroup(self.missionWidgets, not personTab and mission ~= nil)
    local content = "Select a known person to speak with them."
    if person then
        content = "<H2> " .. line(person.name) .. "<TEXT> "
        if person.trust then
            content = content .. line("Trust in you: " .. person.trust.label .. " (" .. person.trust.value .. ")")
            if person.cooperation then
                content = content
                    .. line("Travel: " .. Interaction.reason(person.cooperation.travel.reason))
                    .. line("Home: " .. Interaction.reason(person.cooperation.resident.reason))
            end
            content = content .. line(person.trust.guidance)
            if (person.trust.travelHours or 0) > 0 then
                content = content
                    .. line(string.format("Time travelling together: %.1f hours", person.trust.travelHours))
            end
        end
        content = content .. line(person.background ~= "" and person.background or "No background has been shared.")
        local community = person.communityId and self.world.communities[person.communityId]
        if community then
            content = content .. line("Community: " .. community.name)
        end
        content = content
            .. line("Condition: " .. (person.missing and "Missing; whereabouts unresolved" or plain(person.life)))
        if person.duty then
            content = content .. line("Requested activity: " .. person.duty)
        end
        if person.activity then
            content = content .. line("Current activity: " .. person.activity)
        end
        if person.wellbeing then
            content = content .. line(person.wellbeing)
        end
        if person.missionId then
            local assignment = self.world.missions[person.missionId]
            if assignment then
                content = content
                    .. line(
                        "Assignment: "
                            .. assignment.objective
                            .. " - "
                            .. (stages[assignment.stage] or assignment.stage)
                    )
            end
        end
        local family = {}
        for relativeId in pairs(person.family or {}) do
            if self.seen[relativeId] and self.world.people[relativeId] then
                family[#family + 1] = self.world.people[relativeId].name
            end
        end
        if #family > 0 then
            content = content .. line("Family you know: " .. table.concat(family, ", "))
        end
        if not self.nearby[person.id] then
            content = content .. " <BR> " .. line "Speak with them nearby to ask for a new agreement."
        end
    end
    setRich(self.details, content)
    setRich(
        self.dialogue,
        person
                and ("<H2> " .. line("Conversation with " .. person.name) .. "<TEXT> " .. line(
                    person.interactionDanger and InteractionDanger.MESSAGE
                        or self.replies[person.id]
                        or "Choose Speak to ask about their thoughts, plans or trust. You can also invite them to travel together."
                ))
            or "Choose a person from the list."
    )
    local alive = person and person.life ~= "dead" and person.controller and person.controller.kind == "ai"
    local near = alive and self.nearby[person.id] == true
    local command = alive and self:canCommand(person)
    local choices = person and InteractionMenu.options(self:interactionView(), person.id, getSpecificPlayer(0)) or {}
    local groups = {}
    local travel = false
    for _, choice in ipairs(choices) do
        groups[choice.group] = true
        if choice.kind == "cooperation.request" and choice.fields.request == "travel" then
            travel = true
        end
    end
    self:enable(
        self.travel,
        "cooperation.request",
        near and travel,
        "A new travel agreement is not available right now."
    )
    self.travel:setTitle(
        person and person.partyId and person.commanderId == self.localId and "Travelling together"
            or "Ask to travel together"
    )
    if travel and person.cooperation then
        self.travel.tooltip = Interaction.reason(person.cooperation.travel.reason)
    end
    for group, control in pairs(self.conversationGroups) do
        control:setEnable(not self.busy and (groups[group] or group == "Cooperate" and groups["At home"]) == true)
        control.tooltip = not control.enable and "No nearby actions available in this group." or nil
    end
    local assignmentsEnabled, assignmentsReason = self:allowed "mission.propose"
    self.missionTab:setEnable(assignmentsEnabled)
    self.missionTab.tooltip = assignmentsReason
    self:enable(self.participant, "mission.propose", command, "Select a person you can command.")
    self.participant:setTitle(
        person and self.draftParticipants[person.id] and "Remove selected person" or "Add selected person"
    )
    setRich(
        self.participants,
        "<H2> Named people <LINE> <TEXT> "
            .. line(
                self:namedParticipants(self.draftParticipants) ~= "" and self:namedParticipants(self.draftParticipants)
                    or "Choose people in the roster, then add each person."
            )
    )
    self:enable(
        self.proposal,
        "mission.propose",
        #sortedKeys(self.draftParticipants) > 0,
        "Choose at least one named person."
    )
    if mission then
        local reviewKey = tostring(mission.id)
            .. ":"
            .. tostring(mission.revision)
            .. ":"
            .. self:namedParticipants(mission.participants)
            .. ":"
            .. tostring(mission.objective)
            .. ":"
            .. tostring(mission.destination)
            .. ":"
            .. tostring(mission.safeEndpoint)
            .. ":"
            .. tostring(mission.deathPossible)
        if reviewKey ~= self.reviewKey then
            self.reviewKey = reviewKey
            self.riskConsent:setSelected(1, false)
        end
        local text = "<H2> "
            .. line(mission.objective)
            .. "<TEXT> "
            .. line("Named people: " .. self:namedParticipants(mission.participants))
            .. line("Destination: " .. mission.destination)
            .. line("Safe return: " .. mission.safeEndpoint)
            .. line("Status: " .. (stages[mission.stage] or mission.stage))
        if mission.operatingLimits and mission.operatingLimits.instructions then
            text = text .. line("Limits: " .. mission.operatingLimits.instructions)
        end
        if mission.retreatRules and mission.retreatRules.instructions then
            text = text .. line("Retreat: " .. mission.retreatRules.instructions)
        end
        if mission.deathPossible then
            text = text
                .. " <BR> <RGB:1,0.6,0.4> "
                .. line "DEATH IS POSSIBLE for every named participant while this assignment is away."
                .. line "A recall request does not end this risk. Safe arrival must be confirmed."
                .. " <TEXT> "
        else
            text = text .. " <BR> " .. line "This proposal does not authorise background deaths."
        end
        setRich(self.missionDetails, text)
        self.riskConsent:setVisible(not personTab and mission.stage == "proposed" and mission.deathPossible == true)
        self.accept:setTitle(mission.deathPossible and "Accept risk for named people" or "Accept assignment")
        self:enable(
            self.accept,
            "mission.authorise",
            mission.stage == "proposed" and mission.proposedBy == self.localId,
            "Only the proposer can accept a current proposal."
        )
        local recall = (mission.stage == "authorised" or mission.stage == "away" or mission.stage == "returning")
            and mission.authorisedBy == self.localId
        self:enable(self.recall, "mission.recall", recall, "Only the authoriser can recall an active assignment.")
    end
    setRich(
        self.feedback,
        line(self.notice or "Choose a person. Requests are checked against their current situation.")
    )
end

function Panel:createChildren()
    ISPanel.createChildren(self)
    self.personWidgets = {}
    self.draftWidgets = {}
    self.missionWidgets = {}
    local right, width = 222, self.width - 236
    local function button(x, y, w, title, callback, group)
        return widget(self, ISButton:new(x, y, w, 27, title, self, callback), group)
    end
    button(self.width - 76, 10, 64, "Close", function()
        self:setVisible(false)
    end)
    button(right, 66, 120, "Conversation", function()
        self:setTab "person"
    end)
    self.missionTab = button(right + 128, 66, 120, "Assignments", function()
        self:setTab "mission"
    end)
    self.roster = widget(self, ISScrollingListBox:new(12, 66, 198, self.height - 128))
    self.roster.itemheight = 45
    self.roster.font = UIFont.Small
    self.roster:setOnMouseDownFunction(self, function(panel, id)
        panel:selectPerson(id)
    end)
    self.roster.doDrawItem = function(list, y, item)
        if list.selected == item.index then
            list:drawSelection(0, y, list.width, 44)
        end
        local person = self.world and self.world.people[item.item]
        list:drawText(plain(person and person.name or item.text), 8, y + 5, 1, 1, 1, 1, UIFont.Small)
        local subtitle = person
                and (person.life == "dead" and "Deceased" or person.trust and person.trust.label or self.nearby[person.id] and "Nearby" or "Known person")
            or ""
        list:drawText(subtitle, 8, y + 24, 0.7, 0.75, 0.8, 1, UIFont.Small)
        return y + 45
    end
    local profileHeight = math.min(178, math.floor((self.height - 280) * 0.55))
    self.details = rich(self, right, 104, width, profileHeight, self.personWidgets)
    self.dialogue = rich(self, right, 112 + profileHeight, width, self.height - 292 - profileHeight, self.personWidgets)
    self.dialogue.background = true
    self.dialogue.backgroundColor = { r = 0.08, g = 0.10, b = 0.12, a = 0.95 }
    self.travel = button(right, self.height - 168, width, "Ask to travel together", function()
        if self.selectedPersonId then
            self:submit("cooperation.request", { personId = self.selectedPersonId, request = "travel" })
        end
    end, self.personWidgets)
    self.travel.backgroundColor = { r = 0.16, g = 0.28, b = 0.22, a = 1 }
    self.conversationGroups = {}
    local half = math.floor((width - 8) / 2)
    for index, group in ipairs({ "Speak", "Cooperate", "Commands", "Confront" }) do
        local name = group
        local control
        control = button(
            right + ((index - 1) % 2) * (half + 8),
            self.height - 132 + math.floor((index - 1) / 2) * 36,
            half,
            name .. "...",
            function()
                self:openGroup(name, control)
            end,
            self.personWidgets
        )
        self.conversationGroups[name] = control
    end
    self.assignment = widget(
        self,
        ISComboBox:new(right, 106, width, 25, self, function(panel)
            panel.selectedMissionId = panel.assignment:getOptionData(panel.assignment.selected) or nil
            panel:updateContent()
        end)
    )
    self.participants = rich(self, right, 140, width, 60, self.draftWidgets)
    self.participant = button(right, 203, 210, "Add selected person", function()
        self:toggleParticipant()
    end, self.draftWidgets)
    local function entry(y)
        local value = widget(self, ISTextEntryBox:new("", right + 110, y, width - 110, 25), self.draftWidgets)
        value:setMaxTextLength(220)
        return value
    end
    self.objective = entry(242)
    self.destination = entry(278)
    self.safeEndpoint = entry(314)
    self.limits = entry(350)
    self.retreat = entry(386)
    self.danger = widget(self, ISTickBox:new(right, 424, width, 27, "", self, nil), self.draftWidgets)
    self.danger:addOption "Offscreen danger: death is possible"
    self.danger:setSelected(1, false)
    self.proposal = button(right, 466, width, "Create proposal for review", function()
        self:propose()
    end, self.draftWidgets)
    self.missionDetails = rich(self, right, 141, width, self.height - 286, self.missionWidgets)
    self.riskConsent =
        widget(self, ISTickBox:new(right, self.height - 132, width, 27, "", self, nil), self.missionWidgets)
    self.riskConsent:addOption "I accept possible death for every named person."
    self.accept = button(right, self.height - 96, math.floor(width * 0.65), "Accept assignment", function()
        self:acceptMission()
    end, self.missionWidgets)
    self.recall = button(
        right + math.floor(width * 0.65) + 8,
        self.height - 96,
        width - math.floor(width * 0.65) - 8,
        "Recall",
        function()
            if self.selectedMissionId then
                self:submit("mission.recall", { missionId = self.selectedMissionId })
            end
        end,
        self.missionWidgets
    )
    self.feedback = rich(self, 12, self.height - 54, self.width - 24, 45)
end

function Panel:render()
    self:drawText("People", 14, 12, 1, 1, 1, 1, UIFont.Medium)
    local status = self.runtimeStatus or {}
    self:drawText(
        plain(
            status.message
                or (
                    status.ready and "Conversations, companions and assignments"
                    or readable(status.blocked or "runtime_unavailable")
                )
        ),
        14,
        39,
        0.8,
        0.85,
        0.9,
        1,
        UIFont.Small
    )
    if self.tab == "mission" and not self.selectedMissionId then
        for _, label in ipairs({
            { "Objective", 247 },
            { "Destination", 283 },
            { "Safe return", 319 },
            { "Limits", 355 },
            { "Retreat rules", 391 },
        }) do
            self:drawText(label[1], 227, label[2], 0.85, 0.85, 0.85, 1, UIFont.Small)
        end
    end
end

function Panel:new(x, y, w, h)
    local value = ISPanel.new(self, x, y, w, h)
    value.tab = "person"
    value.seen = {}
    value.replies = {}
    value.nearby = {}
    value.draftParticipants = {}
    value.backgroundColor = { r = 0.06, g = 0.07, b = 0.08, a = 0.96 }
    value.borderColor = { r = 0.34, g = 0.4, b = 0.45, a = 1 }
    value.moveWithMouse = true
    return value
end

function Interface.open(personId)
    if not api then
        return { ok = false, code = "runtime_unavailable" }
    end
    if not window then
        local w = math.min(800, getPlayerScreenWidth(0) - 40)
        local h = math.min(640, getPlayerScreenHeight(0) - 40)
        if w < 650 or h < 460 then
            return { ok = false, code = "viewport_too_small" }
        end
        window = Panel:new(
            getPlayerScreenLeft(0) + (getPlayerScreenWidth(0) - w) / 2,
            getPlayerScreenTop(0) + (getPlayerScreenHeight(0) - h) / 2,
            w,
            h
        )
        window:initialise()
        window:addToUIManager()
    end
    window:refresh()
    if personId and window.world and window.world.people[personId] then
        window.selectedPersonId = personId
        window.tab = "person"
        window:updateContent()
    end
    window:setVisible(true)
    window:bringToTop()
    return { ok = true }
end

function Interface.close()
    if window then
        window:setVisible(false)
    end
end

function Interface.interact(personId, kind, fields, revision)
    local result = Interface.open(personId)
    if not result.ok then
        Interface.lastError = result.code
        return result
    end
    window:submit(kind, fields, revision)
    return window.lastResult
end

local function ensureButton()
    if not api or peopleButton or not getSpecificPlayer(0) then
        return
    end
    peopleButton = ISButton:new(
        getPlayerScreenLeft(0) + 76,
        getPlayerScreenTop(0) + 16,
        76,
        25,
        "People",
        Interface,
        function()
            local ok, result = pcall(Interface.open)
            if not ok then
                Interface.lastError = tostring(result)
            elseif not result.ok then
                Interface.lastError = result.code
            end
        end
    )
    peopleButton:initialise()
    peopleButton:addToUIManager()
end

function Interface.bind(binding)
    for _, name in ipairs({ "snapshot", "request", "localPersonId", "nearby", "status" }) do
        if type(binding) ~= "table" or type(binding[name]) ~= "function" then
            return { ok = false, code = "missing_ui_binding", detail = name }
        end
    end
    api = binding
    ensureButton()
    return { ok = true }
end

function Interface.observe()
    return {
        bound = api ~= nil,
        open = window and window:getIsVisible() or false,
        lastError = Interface.lastError,
        selectedPersonId = window and window.selectedPersonId,
        selectedMissionId = window and window.selectedMissionId,
        lastResult = window and window.lastResult,
        requestCount = window and window.requestCount or 0,
        displayedRevision = window and window.world and window.world.revision,
    }
end

Events.OnGameStart.Add(ensureButton)
Events.OnTick.Add(function()
    if not api or getTimestampMs() < nextRefresh then
        return
    end
    nextRefresh = getTimestampMs() + 500
    local ok, err = pcall(function()
        ensureButton()
        if window and window:getIsVisible() then
            window:refresh()
        end
    end)
    if not ok then
        Interface.lastError = tostring(err)
    end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, objects, testOnly)
    if testOnly or playerIndex ~= 0 or not api then
        return
    end
    local ok, err = pcall(function()
        local hasNearby, nearby = invoke "nearby"
        local hasWorld, world = invoke "snapshot"
        if not hasNearby or type(nearby) ~= "table" or not hasWorld or type(world) ~= "table" then
            return
        end
        local hasId, id = invoke "localPersonId"
        local hasStatus, status = invoke "status"
        if not hasId or not hasStatus then
            return
        end
        InteractionMenu.fill(
            playerIndex,
            context,
            objects,
            testOnly,
            { world = world, personId = id, nearby = nearby, status = status },
            Interface.open,
            Interface.interact,
            api.eachBody
        )
    end)
    if not ok then
        Interface.lastError = tostring(err)
    end
end)

return Interface
