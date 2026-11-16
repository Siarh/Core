-- Runtime regression test for stable ObjectId comparison.
group = {
    IsCreatureInGroup = function() return false end
}

dofile("Scripts/AoUMeterUtil.lua")

local first = {
    GetId = function() return 18051 end
}
local second = {
    GetId = function() return 18051 end
}
local different = {
    GetId = function() return 18052 end
}
local instanceFirst = {
    GetInstanceId = function() return "unit-18051" end
}
local instanceSecond = {
    GetInstanceId = function() return "unit-18051" end
}

assert(SameObjectId(18051, 18051), "numeric ObjectIds should match")
assert(SameObjectId("18051", "18051"), "string ObjectIds should match")
assert(SameObjectId(first, second), "separate wrappers for the same GetId must match")
assert(SameObjectId(instanceFirst, instanceSecond), "GetInstanceId wrappers must match")
assert(not SameObjectId(first, different), "different ObjectIds must not match")
assert(not SameObjectId(nil, nil), "missing ObjectIds must not match")

print("ObjectId identity regression tests passed")
