--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

local H = dofile('tests/helpers.lua')

local Test, Equal, Assert, Raises, ExpectLine = H.Test, H.Equal, H.Assert, H.Raises, H.ExpectLine

---@param files? table<string, string|false>
---@return string[] lines
local function boot(files)
    H.Reset()

    for path, content in pairs(files or {}) do
        H.Files[path] = content
    end

    return H.Load('server')
end

print('config')

Test('first start generates config.lua and replicates client values', function()
    local lines = boot()

    Assert(H.Saved['config.lua'] ~= nil)
    ExpectLine(lines, '[ug-target] v1.0.0 ready.')

    local shared = GlobalState['ug-target:Config']

    Equal(shared.key, 'LMENU')
    Equal(shared.actionMargin, nil, 'server-only values stay on the server')
    Equal(UgTarget.Internal.Config.Get().actionMargin, 1.5)
end)

Test('owner values merge key by key', function()
    boot({
        ['config.lua'] = "return { trigger = 'toggle', maxDistance = 10.0 }",
    })

    local config = UgTarget.Internal.Config.Get()

    Equal(config.trigger, 'toggle')
    Equal(config.maxDistance, 10.0)
    Equal(config.layout, 'anchored')
end)

Test('look merges field by field, sounds and colors replace', function()
    boot({ ['config.lua'] = [[
        return {
            look = { reticle = 'dot', cardWidth = 320 },
            soundEffects = { select = { name = 'OK', set = 'MY_SET' } },
            optionColors = { '#ffffff' },
            theme = { colors = { brandTo = '200 80% 50%' } },
        }
    ]] })

    local config = UgTarget.Internal.Config.Get()

    Equal(config.look.reticle, 'dot')
    Equal(config.look.cardWidth, 320)
    Equal(config.look.connector, true)
    Equal(config.soundEffects, {
        select = {
            name = 'OK',
            set = 'MY_SET',
        },
    })
    Equal(config.optionColors, { '#ffffff' })
    Equal(GlobalState['ug-target:Config'].theme.colors.brandTo, '200 80% 50%')
end)

Test('bad look, sound, color and theme values are reported', function()
    local lines = boot({ ['config.lua'] = [[
        return {
            look = { reticle = 'cross', cardWidth = 50 },
            soundEffects = { boom = { name = 'X', set = 'Y' } },
            optionColors = { 'red' },
            theme = { colors = { primary = '#ff0000' } },
        }
    ]] })

    ExpectLine(lines, 'look')
    ExpectLine(lines, 'soundEffects')
    ExpectLine(lines, 'optionColors')
    ExpectLine(lines, 'theme')
    Equal(GlobalState['ug-target:Config'], nil)
end)

Test('invalid config keeps ug-target idle with every error', function()
    local lines = boot({
        ['config.lua'] = "return { trigger = 'press', maxDistanse = 3, defaultDistance = 15.0 }",
    })

    ExpectLine(lines, 'config.lua: trigger')
    ExpectLine(lines, 'unknown key "maxDistanse". Did you mean "maxDistance"?')
    ExpectLine(lines, 'defaultDistance MUST NOT be greater than maxDistance')
    ExpectLine(lines, 'Config invalid: 3 error(s). ug-target stays idle.')
    Equal(GlobalState['ug-target:Config'], nil)
    Equal(H.Callbacks.Run, nil)
end)

Test('syntax errors are reported', function()
    local lines = boot({
        ['config.lua'] = 'return {',
    })

    ExpectLine(lines, 'config.lua:')
    ExpectLine(lines, 'ug-target stays idle.')
end)

Test('ug-core not ready keeps ug-target idle', function()
    H.Reset()
    H.CoreReady = false

    local lines = H.Load('server')

    ExpectLine(lines, 'ug-core did not become ready')
    Equal(H.Callbacks.Run, nil)
end)

print('actions')

local NET_VEHICLE, NET_PED, NET_PLAYER = 7, 8, 9

---Boots, places player 1 at the origin and a vehicle, a ped and player 2 nearby.
local function world()
    boot()
    H.PedCoords[1] = vector3(0.0, 0.0, 0.0)
    H.Entity(200, {
        coords = vector3(2.0, 0.0, 0.0),
        model = joaat('police'),
        type = 2,
        netId = NET_VEHICLE,
    })
    H.Entity(201, {
        coords = vector3(1.0, 1.0, 0.0),
        model = joaat('a_m_y_business_01'),
        type = 1,
        netId = NET_PED,
    })
    H.Entity(202, {
        coords = vector3(0.0, 1.5, 0.0),
        model = joaat('mp_m_freemode_01'),
        type = 1,
        player = 2,
        netId = NET_PLAYER,
    })
end

---@param name string
---@param options table
---@param handler? function
---@return string
local function register(name, options, handler)
    return H.Export('RegisterAction', 'ug-police', name, options, handler or function(source, context)
        return {
            source = source,
            kind = context.kind,
            netId = context.netId,
        }
    end)
end

Test('a registered action runs with the server-side context', function()
    world()

    local name = register('Impound', {
        distance = 3.0,
        kinds = { 'vehicle' },
        models = { 'police' },
    })

    Equal(name, 'ug-police:Impound')

    local result = H.Call('Run', 1, name, {
        netId = NET_VEHICLE,
    })

    Equal(result, {
        ok = true,
        value = {
            source = 1,
            kind = 'vehicle',
            netId = NET_VEHICLE,
        },
    })
    Equal(#H.Flags, 0)
end)

Test('registration raises on mistakes', function()
    world()

    Raises(function() register('Bad name', { distance = 2.0, kinds = { 'vehicle' } }) end, 'name MUST be')
    Raises(function() register('Far', { distance = 50.0, kinds = { 'vehicle' } }) end, 'distance MUST be')
    Raises(function() register('Nowhere', { distance = 2.0 }) end, 'set kinds, models or coords')
    Raises(function() register('Both', { distance = 2.0, kinds = { 'ped' }, coords = vector3(0.0, 0.0, 0.0) }) end, 'not both')
    Raises(function() register('Typo', { distance = 2.0, kinds = { 'ped' }, cooldwon = 5 }) end, 'unknown option "cooldwon"')
    Raises(function() register('Zone', { distance = 2.0, kinds = { 'zone' } }) end, 'kinds MUST be ped, vehicle, object or player')
end)

Test('unknown actions and gone entities are not found', function()
    world()
    register('Search', {
        distance = 2.0,
        kinds = { 'ped' },
    })

    Equal(H.Call('Run', 1, 'ug-police:Nope', {
        netId = NET_PED,
    }), {
        ok = false,
        error = 'not_found',
    })
    Equal(H.Call('Run', 1, 'ug-police:Search', {
        netId = 99,
    }), {
        ok = false,
        error = 'not_found',
    })
    Equal(H.Call('Run', 1, 'ug-police:Search', {}), {
        ok = false,
        error = 'not_found',
    })
end)

Test('wrong kind or model is refused and flagged', function()
    world()
    register('Impound', {
        distance = 3.0,
        models = { 'police' },
    })
    register('Cuff', {
        distance = 2.0,
        kinds = { 'player' },
    })

    Equal(H.Call('Run', 1, 'ug-police:Impound', {
        netId = NET_PED,
    }), {
        ok = false,
        error = 'invalid_args',
    })
    Equal(H.Call('Run', 1, 'ug-police:Cuff', {
        netId = NET_VEHICLE,
    }), {
        ok = false,
        error = 'invalid_args',
    })
    Equal(#H.Flags, 2)
    Equal(H.Flags[1].violation, UgCore.Enums.Violations.InvalidPayload)
end)

Test('players are targets, never the caller itself', function()
    world()
    register('Cuff', {
        distance = 2.0,
        kinds = { 'player' },
    }, function(_, context)
        return context.player
    end)

    Equal(H.Call('Run', 1, 'ug-police:Cuff', {
        netId = NET_PLAYER,
    }), {
        ok = true,
        value = 2,
    })

    H.Entities[202].player = 1

    Equal(H.Call('Run', 1, 'ug-police:Cuff', {
        netId = NET_PLAYER,
    }), {
        ok = false,
        error = 'invalid_args',
    })
end)

Test('distance uses the server ped and the margin', function()
    world()
    register('Search', {
        distance = 1.0,
        kinds = { 'ped' },
    })

    -- The ped is 1.41 m away: inside 1.0 + 1.5.
    Equal(H.Call('Run', 1, 'ug-police:Search', {
        netId = NET_PED,
    }).ok, true)

    H.PedCoords[1] = vector3(10.0, 10.0, 0.0)

    Equal(H.Call('Run', 1, 'ug-police:Search', {
        netId = NET_PED,
    }), {
        ok = false,
        error = 'no_permission',
    })
    Equal(H.Flags[1].violation, UgCore.Enums.Violations.OutOfRange)
end)

Test('place actions use the nearest point', function()
    world()
    register('Shop', {
        distance = 2.0,
        coords = { vector3(100.0, 0.0, 0.0), vector3(1.0, 0.0, 0.0) },
    }, function(_, context)
        return {
            kind = context.kind,
            coords = context.coords,
        }
    end)

    Equal(H.Call('Run', 1, 'ug-police:Shop', {}), {
        ok = true,
        value = {
            kind = 'zone',
            coords = vector3(1.0, 0.0, 0.0),
        },
    })
end)

Test('conditions are checked on the server', function()
    world()
    register('Armory', {
        distance = 3.0,
        kinds = { 'vehicle' },
        conditions = {
            job = {
                police = 2,
            },
            onDuty = true,
            items = 'keycard',
        },
    })

    Equal(H.Call('Run', 1, 'ug-police:Armory', {
        netId = NET_VEHICLE,
    }), {
        ok = false,
        error = 'no_permission',
    })

    H.Jobs[1] = {
        name = 'police',
        grade = 2,
        onDuty = true,
    }

    Equal(H.Call('Run', 1, 'ug-police:Armory', {
        netId = NET_VEHICLE,
    }), {
        ok = false,
        error = 'no_permission',
    }, 'no keycard')

    H.Items.keycard = 1

    Equal(H.Call('Run', 1, 'ug-police:Armory', {
        netId = NET_VEHICLE,
    }).ok, true)
end)

Test('downed players are refused unless allowed', function()
    world()
    register('Search', {
        distance = 2.0,
        kinds = { 'ped' },
    })
    register('Crawl', {
        distance = 2.0,
        kinds = { 'ped' },
        allowDowned = true,
    })
    H.DeathStates[1] = UgCore.Enums.DeathState.Downed

    Equal(H.Call('Run', 1, 'ug-police:Search', {
        netId = NET_PED,
    }), {
        ok = false,
        error = 'no_permission',
    })
    Equal(H.Call('Run', 1, 'ug-police:Crawl', {
        netId = NET_PED,
    }).ok, true)
end)

Test('cooldowns are per player and per action', function()
    world()
    register('Rob', {
        distance = 2.0,
        kinds = { 'ped' },
        cooldown = 5000,
    })

    Equal(H.Call('Run', 1, 'ug-police:Rob', {
        netId = NET_PED,
    }).ok, true)
    Equal(H.Call('Run', 1, 'ug-police:Rob', {
        netId = NET_PED,
    }), {
        ok = false,
        error = 'rate_limited',
    })

    H.PedCoords[2] = vector3(0.0, 0.0, 0.0)
    H.Entities[202].player = 3

    Equal(H.Call('Run', 2, 'ug-police:Rob', {
        netId = NET_PED,
    }).ok, true, 'another player')

    H.Now = H.Now + 5000

    Equal(H.Call('Run', 1, 'ug-police:Rob', {
        netId = NET_PED,
    }).ok, true)
end)

Test('hold actions need a Begin on the same target, long enough before', function()
    world()
    register('Lockpick', {
        distance = 3.0,
        kinds = { 'vehicle', 'ped' },
        hold = 3000,
    })

    Equal(H.Call('Run', 1, 'ug-police:Lockpick', {
        netId = NET_VEHICLE,
    }), {
        ok = false,
        error = 'no_permission',
    }, 'no Begin')
    Equal(H.Flags[#H.Flags].violation, UgCore.Enums.Violations.InvalidPayload)

    Equal(H.Call('Begin', 1, 'ug-police:Lockpick', {
        netId = NET_VEHICLE,
    }), {
        ok = true,
    })
    H.Now = H.Now + 1000
    Equal(H.Call('Run', 1, 'ug-police:Lockpick', {
        netId = NET_VEHICLE,
    }), {
        ok = false,
        error = 'no_permission',
    }, 'too early')

    Equal(H.Call('Begin', 1, 'ug-police:Lockpick', {
        netId = NET_VEHICLE,
    }), {
        ok = true,
    })
    H.Now = H.Now + 3000
    Equal(H.Call('Run', 1, 'ug-police:Lockpick', {
        netId = NET_PED,
    }), {
        ok = false,
        error = 'no_permission',
    }, 'other target')

    Equal(H.Call('Begin', 1, 'ug-police:Lockpick', {
        netId = NET_VEHICLE,
    }), {
        ok = true,
    })
    H.Now = H.Now + 2900
    Equal(H.Call('Run', 1, 'ug-police:Lockpick', {
        netId = NET_VEHICLE,
    }).ok, true, 'within the tolerance')
    Equal(H.Call('Run', 1, 'ug-police:Lockpick', {
        netId = NET_VEHICLE,
    }).ok, false, 'a Begin is used once')
end)

Test('a failing handler answers internal_error', function()
    world()
    register('Boom', {
        distance = 3.0,
        kinds = { 'vehicle' },
    }, function()
        error('boom')
    end)

    local lines = H.Capture(function()
        Equal(H.Call('Run', 1, 'ug-police:Boom', {
            netId = NET_VEHICLE,
        }), {
            ok = false,
            error = 'internal_error',
        })
    end)

    ExpectLine(lines, 'Action ug-police:Boom failed')
end)

Test('the schema rejects malformed requests', function()
    world()

    local _, errorCode = H.Call('Run', 1, 'no colon', {})

    Equal(errorCode, 'invalid_args')

    _, errorCode = H.Call('Run', 1, 'a:b', {
        netId = 1,
        extra = true,
    })

    Equal(errorCode, 'invalid_args')
    Equal(H.Callbacks.Run.options.requirePlayer, true)
end)

Test('actions leave with their resource, holds and cooldowns with the player', function()
    world()
    register('Rob', {
        distance = 2.0,
        kinds = { 'ped' },
        cooldown = 5000,
    })
    H.Call('Run', 1, 'ug-police:Rob', {
        netId = NET_PED,
    })
    H.TriggerEvent('playerDropped', 1)

    Equal(H.Call('Run', 1, 'ug-police:Rob', {
        netId = NET_PED,
    }).ok, true, 'cooldown forgotten')

    H.TriggerEvent('onResourceStop', nil, 'ug-police')

    Equal(H.Call('Run', 1, 'ug-police:Rob', {
        netId = NET_PED,
    }), {
        ok = false,
        error = 'not_found',
    })
end)

Test('RemoveAction takes a short or a full name', function()
    world()
    register('A', {
        distance = 2.0,
        kinds = { 'ped' },
    })
    register('B', {
        distance = 2.0,
        kinds = { 'ped' },
    })

    Equal(H.Export('RemoveAction', 'ug-police', 'A'), true)
    Equal(H.Export('RemoveAction', 'other', 'ug-police:B'), true)
    Equal(H.Export('RemoveAction', 'ug-police', 'A'), false)
end)

Test('ugtarget status lists actions', function()
    world()
    register('Lockpick', {
        distance = 3.0,
        kinds = { 'vehicle' },
        hold = 3000,
        conditions = {
            items = 'lockpick',
        },
    })

    local lines = H.RunCommand('ugtarget', 0, { 'status' })

    ExpectLine(lines, 'ug-target: 1 server action(s).')
    ExpectLine(lines, 'ug-police:Lockpick  3.0 m  hold 3000 ms, conditions')
    Equal(#H.RunCommand('ugtarget', 5, { 'status' }), 0, 'players get nothing')
end)

H.Done()
