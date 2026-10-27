-- Backgrounds and current plans. Saved people retain their existing background.
local Stories = {
    plans = {
        escaping = "We are trying to get our family away from the outbreak.",
        seeking_refuge = "We are looking for somewhere defensible to stay.",
        settling = "We are working out how to make a life here.",
        established = "We have survived this long by keeping a routine and looking after each other.",
        relocating = "It is time to consider somewhere safer. We are planning our next move.",
    },
    absentRelative = "Separated from adult relatives during the outbreak; current whereabouts are unknown.",
    separatedFamily = "Survived the outbreak but became separated from some adult relatives.",
    backgrounds = {
        outbreakFamily = "Escaped with adult relatives when their neighbourhood became unsafe.",
        outbreakSolo = "Left an ordinary life behind when the outbreak reached home.",
        aftermath = "Has moved between temporary refuges since the outbreak.",
        longTerm = "Has lived through years or seasons of the outbreak, learning routines that keep a survivor going.",
    },
}

function Stories.background(era, family)
    return era == "outbreak" and (family and Stories.backgrounds.outbreakFamily or Stories.backgrounds.outbreakSolo)
        or era == "aftermath" and Stories.backgrounds.aftermath
        or Stories.backgrounds.longTerm
end

return Stories
