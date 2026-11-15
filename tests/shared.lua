--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

local H = dofile('tests/helpers.lua')

local Test, Equal, Assert, Raises = H.Test, H.Equal, H.Assert, H.Raises

H.Reset()
H.Load('server')

local Shapes = UgTarget.Internal.Shapes
local Conditions = UgTarget.Internal.Conditions
local Shape = UgTarget.Enums.Shape
local Reason = UgTarget.Enums.Reason

print('shapes')

Test('sphere contains points within the radius', function()
    local zone = {
        shape = Shape.Sphere,
        coords = vector3(10.0, 10.0, 10.0),
        radius = 2.0,
    }

    Assert(Shapes.Contains(zone, vector3(11.0, 11.0, 10.0)))
    Assert(not Shapes.Contains(zone, vector3(12.0, 12.0, 10.0)))
end)

Test('box honors size and rotation', function()
    local zone = {
        shape = Shape.Box,
        coords = vector3(0.0, 0.0, 0.0),
        size = vector3(4.0, 1.0, 2.0),
        rotation = 0.0,
    }

    Assert(Shapes.Contains(zone, vector3(1.9, 0.0, 0.0)))
    Assert(not Shapes.Contains(zone, vector3(0.0, 0.9, 0.0)))
    Assert(not Shapes.Contains(zone, vector3(0.0, 0.0, 1.5)))

    zone.rotation = 90.0

    Assert(Shapes.Contains(zone, vector3(0.0, 1.9, 0.0)))
    Assert(not Shapes.Contains(zone, vector3(1.9, 0.0, 0.0)))
end)

Test('poly uses even-odd and its height', function()
    local zone = {
        shape = Shape.Poly, coords = vector3(0.0, 0.0, 0.0), minZ = 0.0, maxZ = 3.0,
        points = { vector2(0.0, 0.0), vector2(4.0, 0.0), vector2(4.0, 4.0), vector2(2.0, 1.0), vector2(0.0, 4.0) },
    }

    Assert(Shapes.Contains(zone, vector3(1.0, 0.5, 1.0)))
    Assert(not Shapes.Contains(zone, vector3(2.0, 3.0, 1.0)), 'the notch is outside')
    Assert(not Shapes.Contains(zone, vector3(1.0, 0.5, 4.0)), 'above the ceiling')
    Equal(Shapes.PolyCenter({
        vector2(0.0, 0.0),
        vector2(2.0, 0.0),
        vector2(2.0, 2.0),
        vector2(0.0, 2.0),
    }, 0.0, 2.0), vector3(1.0, 1.0, 1.0))
end)

print('conditions')

Test('normalize accepts names, lists and maps', function()
    local result = Conditions.Normalize('Test', {
        job = 'police',
        gang = { 'vagos', 'ballas' },
        groups = {
            ems = 2,
        },
        items = {
            lockpick = 2,
        },
    })

    Equal(result, {
        jobs = {
            police = 0,
        }, gangs = {
            vagos = 0,
            ballas = 0,
        }, groups = {
            ems = 2,
        }, items = {
            lockpick = 2,
        },
    })
    Equal(Conditions.Normalize('Test', nil), nil)
    Equal(Conditions.Normalize('Test', {}), nil)
end)

Test('normalize raises on mistakes', function()
    Raises(function() Conditions.Normalize('AddModel', { jobs = 'police' }) end, 'AddModel: unknown condition "jobs"')
    Raises(function() Conditions.Normalize('AddModel', { onDuty = 'yes' }) end, 'conditions.onDuty MUST be a boolean')
    Raises(function() Conditions.Normalize('AddModel', { items = { lockpick = 0 } }) end, 'items.lockpick MUST be an integer from 1')
    Raises(function() Conditions.Normalize('AddModel', { job = 5 }) end, 'job MUST be a name')
end)

---@param overrides? table
---@return UgTargetFacts
local function facts(overrides)
    local value = {
        job = {
            name = 'police',
            grade = 2,
            onDuty = true,
        },
        gang = nil,
        inVehicle = false,
        count = function(item)
            return ({
                lockpick = 1,
                bandage = 3,
            })[item] or 0
        end,
    }

    for key, item in pairs(overrides or {}) do
        value[key] = item
    end

    return value
end

Test('check passes and names the first failed reason', function()
    local check = function(input, overrides)
        local ok, reason = Conditions.Check(Conditions.Normalize('Test', input), facts(overrides))

        return { ok, reason }
    end

    Equal(check({
        job = {
            police = 2,
        },
        onDuty = true,
    }), { true, nil })
    Equal(check({
        job = {
            police = 3,
        },
    }), { false, Reason.Job })
    Equal(check({
        gang = 'vagos',
    }), { false, Reason.Gang })
    Equal(check({
        groups = {
            police = 1,
            vagos = 0,
        },
    }), { true, nil })
    Equal(check({
        onDuty = true,
    }, {
        job = {
            name = 'police',
            grade = 2,
            onDuty = false,
        },
    }), { false, Reason.Duty })
    Equal(check({
        inVehicle = true,
    }), { false, Reason.Vehicle })
    Equal(check({
        items = {
            lockpick = 1,
            bandage = 5,
        },
    }), { false, Reason.Items })
    Equal(check({
        items = {
            lockpick = 1,
            bandage = 5,
        },
        anyItem = true,
    }), { true, nil })
    Equal(check({
        items = 'drill',
        anyItem = true,
    }), { false, Reason.Items })
end)

H.Done()
