-- Presentation only. Never changes vanilla classes or gameplay state.
local Theme = {}
-- Match installed ISPanel / ISButton / ISScrollingListBox defaults.
Theme.colors = {
    base = { r = 0, g = 0, b = 0, a = 0.85 },
    surface = { r = 0, g = 0, b = 0, a = 0.5 },
    raised = { r = 0.3, g = 0.3, b = 0.3, a = 1 },
    border = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
    buttonBorder = { r = 0.7, g = 0.7, b = 0.7, a = 1 },
    button = { r = 0, g = 0, b = 0, a = 1 },
    text = { r = 1, g = 1, b = 1, a = 1 },
    muted = { r = 0.7, g = 0.7, b = 0.7, a = 1 },
    selected = { r = 0.7, g = 0.35, b = 0.15, a = 0.3 },
    hover = { r = 1, g = 1, b = 1, a = 0.1 },
    healthy = { r = 0.35, g = 0.7, b = 0.35, a = 1 },
    warning = { r = 0.9, g = 0.7, b = 0.25, a = 1 },
    danger = { r = 0.9, g = 0.25, b = 0.2, a = 1 },
}

local C = Theme.colors
local function copy(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

function Theme.panel(panel)
    panel.backgroundColor, panel.borderColor = copy(C.base), copy(C.border)
    return panel
end

function Theme.button(button, primary)
    button.backgroundColor = copy(primary and C.selected or C.button)
    button.backgroundColorMouseOver = copy(C.raised)
    button.borderColor = copy(C.buttonBorder)
    button.textColor = copy(C.text)
    -- Native setEnable mutates these tables in place. Never share palette tables.
    button.borderColorEnabled = copy(button.borderColor)
    button.backgroundColorEnabled = copy(button.backgroundColor)
    return button
end

function Theme.widget(widget)
    widget.backgroundColor, widget.borderColor = copy(C.surface), copy(C.border)
    widget.textColor, widget.selectedTextColor = copy(C.text), copy(C.text)
    widget.selectionColor, widget.mouseOverHighlightColor = copy(C.selected), copy(C.hover)
    widget.backgroundColorMouseOver = copy(C.raised)
    -- Rich text uses these defaults, independently of button/list textColor.
    widget.textR, widget.textG, widget.textB = C.text.r, C.text.g, C.text.b
    if widget.isButton then
        Theme.button(widget)
    end
    return widget
end

function Theme.rect(ui, x, y, w, h, color)
    ui:drawRect(x, y, math.max(0, w), h, color.a, color.r, color.g, color.b)
end

function Theme.fit(text, width, font)
    text = tostring(text or ""):gsub("[<>\r\n]", "")
    width = math.max(0, width)
    local function measure(value)
        return getTextManager and getTextManager():MeasureStringX(font or UIFont.Small, value) or #value * 7
    end
    if measure(text) <= width then
        return text
    end
    while #text > 0 and measure(text .. "...") > width do
        -- Remove a whole UTF-8 codepoint, not an arbitrary trailing byte.
        local last = #text
        while last > 1 and text:byte(last) >= 128 and text:byte(last) < 192 do
            last = last - 1
        end
        text = text:sub(1, last - 1)
    end
    return measure "..." <= width and text .. "..." or ""
end

function Theme.initials(name)
    local initials, count = "", 0
    for word in tostring(name or "?"):gmatch "%S+" do
        initials = initials .. (word:match "^[\194-\244][\128-\191]*" or word:sub(1, 1))
        count = count + 1
        if count == 2 then
            break
        end
    end
    return initials
end

function Theme.text(ui, text, x, y, width, color, font)
    color, font = color or C.text, font or UIFont.Small
    ui:drawText(Theme.fit(text, width, font), x, y, color.r, color.g, color.b, color.a, font)
end

function Theme.rule(ui, y)
    Theme.rect(ui, 12, y, ui.width - 24, 1, C.border)
end

function Theme.header(ui, title, icon, width)
    Theme.text(ui, title, 12, 10, width or ui.width - 24, C.text, UIFont.Medium)
end

function Theme.row(ui, y, item, height)
    local selected = ui.selected == item.index
    Theme.rect(
        ui,
        0,
        y,
        ui.width,
        height - 2,
        selected and C.selected or ui.mouseoverselected == item.index and C.hover or C.surface
    )
end

function Theme.health(value, danger)
    return danger and C.danger
        or not value and C.muted
        or value <= 30 and C.danger
        or value <= 65 and C.warning
        or C.healthy
end

return Theme
