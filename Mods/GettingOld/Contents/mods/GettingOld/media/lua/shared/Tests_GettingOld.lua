if not DevTools or not DevTools.addTest or not AgeSystem then return end

DevTools.addTest("GettingOld_B41_GroupYoungBounds", function()
    DevTools.assertEquals("Young", AgeSystem.getGroup(18))
    DevTools.assertEquals("Young", AgeSystem.getGroup(25))
end)

DevTools.addTest("GettingOld_B41_GroupAdultBounds", function()
    DevTools.assertEquals("Adult", AgeSystem.getGroup(26))
    DevTools.assertEquals("Adult", AgeSystem.getGroup(45))
end)

DevTools.addTest("GettingOld_B41_GroupMiddleBounds", function()
    DevTools.assertEquals("Middle", AgeSystem.getGroup(46))
    DevTools.assertEquals("Middle", AgeSystem.getGroup(60))
end)

DevTools.addTest("GettingOld_B41_GroupElderlyBounds", function()
    DevTools.assertEquals("Elderly", AgeSystem.getGroup(61))
    DevTools.assertEquals("Elderly", AgeSystem.getGroup(90))
end)

DevTools.addTest("GettingOld_B41_GroupDefaultAdult", function()
    DevTools.assertEquals("Adult", AgeSystem.getGroup(5))
end)
