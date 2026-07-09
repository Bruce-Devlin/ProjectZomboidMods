AgeSystem = AgeSystem or {}

AgeSystem.Groups = {
    Zoomer = { min = 12, max = 17 },
    Young = { min = 18, max = 25 },
    Adult = { min = 26, max = 45 },
    Middle = { min = 46, max = 60 },
    Elderly = { min = 61, max = 90 },
}

function AgeSystem.getGroup(age)
    for name, range in pairs(AgeSystem.Groups) do
        if age >= range.min and age <= range.max then
            return name
        end
    end
    return "Adult"
end
