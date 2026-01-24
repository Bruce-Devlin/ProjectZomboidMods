if not DevTools or not DevTools.addTest or not DaysUntilWinter then return end

DevTools.addTest("DaysUntilWinter_B41_WinterStartIsNil", function()
    DevTools.assertEquals(nil, DaysUntilWinter.getDaysUntilWinterFromDate(2025, 10, 1))
end)

DevTools.addTest("DaysUntilWinter_B41_WinterEndIsNil", function()
    DevTools.assertEquals(nil, DaysUntilWinter.getDaysUntilWinterFromDate(2025, 2, 28))
end)

DevTools.addTest("DaysUntilWinter_B41_SummerReturnsPositive", function()
    local days = DaysUntilWinter.getDaysUntilWinterFromDate(2025, 6, 1)
    DevTools.assertTrue(days ~= nil, "expected non-nil days in summer")
    DevTools.assertTrue(days > 0, "expected positive days in summer")
end)

DevTools.addTest("DaysUntilWinter_B41_FallReturnsPositive", function()
    local days = DaysUntilWinter.getDaysUntilWinterFromDate(2025, 9, 15)
    DevTools.assertTrue(days ~= nil, "expected non-nil days in fall")
    DevTools.assertTrue(days > 0, "expected positive days in fall")
end)
