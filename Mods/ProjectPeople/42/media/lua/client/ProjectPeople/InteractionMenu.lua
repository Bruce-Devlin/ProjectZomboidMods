local Interaction = require "ProjectPeople/Interaction"
-- The optional debug UI is bound by SurvivorInterface, after normal UI modules load.
local Debug = {
    row = function(id)
        return ProjectPeople and ProjectPeople.Debug and ProjectPeople.Debug.row(id)
    end,
    person = function(parent, id)
        if ProjectPeople and ProjectPeople.Debug then
            ProjectPeople.Debug.person(parent, id)
        end
    end,
}
local Menu = {}

local function plain(text)
    return tostring(text or "Survivor"):gsub("[<>\r\n]", ""):sub(1, 100)
end

local function submenu(parent, label)
    local option = parent:addOption(label)
    local child = ISContextMenu:getNew(parent)
    parent:addSubMenu(option, child)
    return child
end

function Menu.options(view, id, player)
    local person = view.world.people[id]
    local home = person and person.home
    local nearHome = home
            and type(home.x) == "number"
            and type(home.y) == "number"
            and home.z == player:getZ()
            and (home.x - player:getX()) ^ 2 + (home.y - player:getY()) ^ 2 <= 144
        or false
    return Interaction.options(view, id, nearHome)
end

local function addAction(parent, action, id, revision, submit)
    if action.confirm then
        parent = submenu(parent, action.label)
    end
    parent:addOption(action.confirm or action.label, nil, function()
        submit(id, action.kind, action.fields, revision)
    end)
end

function Menu.group(context, view, id, player, group, submit)
    for _, action in ipairs(Menu.options(view, id, player)) do
        if action.group == group then
            addAction(context, action, id, view.world.revision, submit)
        end
    end
end

function Menu.add(context, view, id, player, open, submit)
    local person = view.world.people[id]
    local options = Menu.options(view, id, player)
    if #options == 0 then
        local row = Debug.row(id)
        if row then
            Debug.person(submenu(context, plain(row.name)), id)
        end
        return
    end
    local root = submenu(context, plain(person.name))
    local groups = {}
    if person.trust then
        root:addOption("Trust: " .. person.trust.label .. " (" .. person.trust.value .. ")").notAvailable = true
    end
    for _, entry in ipairs(options) do
        local action = entry
        local parent = groups[action.group]
        if not parent then
            parent = submenu(root, action.group)
            groups[action.group] = parent
        end
        addAction(parent, action, id, view.world.revision, submit)
    end
    root:addOption("View person", nil, function()
        open(id)
    end)
    Debug.person(root, id)
end

function Menu.fill(playerIndex, context, objects, testOnly, view, open, submit, eachBody)
    -- Runtime currently binds one local player. Never issue player 0's orders
    -- from another split-screen player's context menu.
    if testOnly or playerIndex ~= 0 or not view or not view.world then
        return
    end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then
        return
    end
    local added = {}
    local function offer(actor)
        if not actor or not (instanceof(actor, "IsoPlayer") or instanceof(actor, "IsoZombie")) or actor:isDead() then
            return
        end
        local id = actor:getModData().ProjectPeoplePersonId
        if not id or added[id] or not view.world.people[id] and not Debug.row(id) then
            return
        end
        added[id] = true
        Menu.add(context, view, id, player, open, submit)
    end
    local function square(sq)
        if not sq then
            return
        end
        local moving = sq:getMovingObjects()
        for i = 0, moving:size() - 1 do
            offer(moving:get(i))
        end
    end
    -- Match the same camera projection as PeopleNames. The visible standing
    -- model extends above its ground square, so a head/torso click must not be
    -- converted straight to a different tile. Enumerate only owned bodies.
    if eachBody then
        local zoom = getCore():getZoom(playerIndex)
        local mx, my = getMouseX(), getMouseY()
        eachBody(function(actor)
            local sq = actor:getCurrentSquare()
            if
                actor:isDead()
                or not sq
                or not sq:getCanSee(playerIndex)
                or actor:getAlpha(playerIndex) <= 0.1
                or math.abs(actor:getZ() - player:getZ()) > 0.2
            then
                return
            end
            local x = (IsoUtils.XToScreen(actor:getX(), actor:getY(), actor:getZ(), 0) - IsoCamera.getOffX()) / zoom
                + getPlayerScreenLeft(playerIndex)
            local y = (IsoUtils.YToScreen(actor:getX(), actor:getY(), actor:getZ(), 0) - IsoCamera.getOffY()) / zoom
                + getPlayerScreenTop(playerIndex)
            if mx >= x - 24 / zoom and mx <= x + 24 / zoom and my >= y - 112 / zoom and my <= y + 8 / zoom then
                offer(actor)
            end
        end)
        for _ in pairs(added) do
            return
        end
    end
    for _, object in ipairs(objects or {}) do
        offer(object)
        square(object:getSquare())
    end
    -- Grounded in installed Build 42 DebugContextMenu.pickSquare. Characters
    -- need not be in worldObjects; also works when clicking bare ground at feet.
    local zoom = getCore():getZoom(playerIndex)
    local z = player:getZ()
    square(
        getCell():getGridSquare(
            IsoUtils.XToIso(getMouseX() * zoom, getMouseY() * zoom, z),
            IsoUtils.YToIso(getMouseX() * zoom, getMouseY() * zoom, z),
            z
        )
    )
end
return Menu
