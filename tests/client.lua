--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

local H = dofile('tests/helpers.lua')

local Test, Equal, Assert, Raises, ExpectLine = H.Test, H.Equal, H.Assert, H.Raises, H.ExpectLine

local CAR, NPC = 300, 301
local SCROLL_DOWN, CONFIRM, BACK, CLICK = 242, 38, 177, 24

---Boots the client with a car 2 m ahead (networked as 40) and a ped at 5 m.
---@param overrides? table config values
---@return string[] lines
local function boot(overrides)
    H.Reset()
    H.Entity(CAR, {
        coords = vector3(0.0, 2.0, 0.0),
        model = joaat('sultan'),
        type = 2,
        netId = 40,
    })
    H.Entity(NPC, {
        coords = vector3(0.0, 5.0, 0.0),
        model = joaat('a_m_y_business_01'),
        type = 1,
    })

    return H.LoadClient(overrides)
end

---@param entity? integer
---@param coords? vector3
local function aim(entity, coords)
    H.Ray = {
        hit = true,
        entity = entity,
        coords = coords or (entity and GetEntityCoords(entity)) or vector3(0.0, 2.0, 0.0),
    }
end

local function press()
    H.Keybinds[1].onPressed()
    H.Advance(32)
end

local function release()
    H.Keybinds[1].onReleased()
end

---@param control integer
local function tap(control)
    H.Pressed[control] = true
    H.Advance(16)
end

---Presses a number key mapping for one frame.
---@param number integer
local function number(number)
    local binding = H.Keybinds[1 + number]

    binding.onPressed()
    binding.onReleased()
    H.Advance(16)
end

---@return string[] labels the page shows
local function shown()
    local payload = H.LastPage('options')
    local labels = {}

    for _, option in ipairs(payload and payload.options or {}) do
        labels[#labels + 1] = option.label .. (option.enabled and '' or (' (' .. tostring(option.reason) .. ')'))
    end

    return labels
end

print('boot')

Test('boot binds the configured key and prints one line', function()
    local lines = boot({
        key = 'F2',
    })

    Equal(H.Keybinds[1].name, 'target')
    Equal(H.Keybinds[1].defaultKey, 'F2')
    ExpectLine(lines, '[ug-target] Ready: hold, anchored.')
    Equal(H.LastPage('config').layout, 'anchored')
    Equal(H.Keybinds[2].name, 'pick_1')
    Equal(H.Keybinds[10].defaultKey, '9')
    Equal(H.LastPage('config').accent, nil, 'the page takes its colors from the ug-lib theme')
end)

Test('the page gets the look, the row colors and the merged theme', function()
    boot({
        look = {
            reticle = 'dot',
        },
        optionColors = { '#ffffff' },
        cursor = false,
        numberKeys = false,
        theme = {
            colors = {
                reticle = '1 1% 1%',
            },
        },
    })

    local config = H.LastPage('config')

    Equal(config.look.reticle, 'dot')
    Equal(config.optionColors, { '#ffffff' })
    Equal(config.cursor, false)
    Equal(config.numberKeys, false)
    Equal(config.theme.colors.reticle, '1 1% 1%')
    Equal(#H.Keybinds, 1, 'no number keys')
end)

Test('without the server config the client stays idle', function()
    H.Reset()

    H.Load('client')

    local lines = H.Capture(function()
        H.Advance(61000)
    end)

    Equal(#H.Keybinds, 0)
    ExpectLine(lines, '[ug-target] No config from the server.')
end)

print('options')

Test('model, global and zone options show by order, within distance', function()
    boot()
    H.Export('AddModel', 'garage', 'sultan', {
        {
            name = 'trunk',
            label = 'Trunk',
            onSelect = function() end,
            order = 2,
        },
        {
            name = 'far',
            label = 'Far',
            onSelect = function() end,
            distance = 1.0,
        },
    })
    H.Export('AddGlobalVehicle', 'keys', {
        label = 'Lock',
        icon = 'lock',
        onSelect = function() end,
        order = 1,
    })
    H.Export('AddSphereZone', 'garage', {
        coords = vector3(0.0, 2.0, 0.0),
        radius = 1.0,
        options = {
            label = 'Park',
            event = 'garage:park',
        },
    })
    aim(CAR)
    press()

    Equal(shown(), { 'Park', 'Lock', 'Trunk' })
    Equal(H.LastPage('options').kind, 'vehicle')
    Equal(H.LastPage('aim'), {
        active = true,
        layout = 'anchored',
    })
    Equal(H.LastPage('anchor'), {
        visible = true,
        x = 0.5,
        y = 0.4,
    })
    Equal(#H.CallsOf('SetEntityDrawOutline'), 1)
end)

Test('the menu follows the player out of a zone and into another while held', function()
    boot()

    local function near(center, radius)
        return function()
            local p = GetEntityCoords(PlayerPedId())

            local dx, dy = p.x - center.x, p.y - center.y

            return dx * dx + dy * dy <= radius * radius
        end
    end

    H.Export('AddSphereZone', 'shop', {
        coords = vector3(0.0, 3.0, 0.0), radius = 2.0,
        options = {
            label = 'Clothes',
            distance = 5.0,
            onSelect = function() end,
            canInteract = near(vector3(0.0, 3.0, 0.0), 4.0),
        },
    })
    H.Export('AddSphereZone', 'shop', {
        coords = vector3(20.0, 3.0, 0.0), radius = 2.0,
        options = {
            label = 'Barber',
            distance = 5.0,
            onSelect = function() end,
            canInteract = near(vector3(20.0, 3.0, 0.0), 4.0),
        },
    })
    aim(nil, vector3(0.0, 3.0, 0.0))
    press()

    Equal(shown(), { 'Clothes' })

    H.PedPosition = vector3(0.0, -6.0, 0.0)
    aim(nil, vector3(0.0, -9.0, 0.0))
    H.Advance(300)
    H.Advance(16)

    Equal(shown(), {}, 'left the store')

    H.PedPosition = vector3(20.0, 0.0, 0.0)
    aim(nil, vector3(20.0, 3.0, 0.0))
    H.Advance(300)
    H.Advance(16)

    Equal(shown(), { 'Barber' }, 'entered another store')
end)

Test('peds are never outlined', function()
    boot()
    H.Export('AddModel', 'shop', 'a_m_y_business_01', {
        label = 'Talk',
        distance = 6.0,
        onSelect = function() end,
    })
    aim(NPC)
    press()

    Equal(shown(), { 'Talk' })
    Equal(#H.CallsOf('SetEntityDrawOutline'), 0)
end)

Test('failed conditions show the reason, canInteract hides', function()
    boot()
    H.Export('AddEntity', 'police', 40, {
        {
            label = 'Impound',
            onSelect = function() end,
            conditions = {
                job = 'police',
            },
        },
        {
            label = 'Hidden',
            onSelect = function() end,
            canInteract = function() return false end,
        },
        {
            label = 'Broken',
            onSelect = function() end,
            canInteract = function() error('oops') end,
        },
        {
            label = 'Seen',
            onSelect = function(_) end,
            canInteract = function(context) return context.netId == 40 end,
        },
    })
    aim(CAR)
    press()

    Equal(shown(), { 'Impound (job)', 'Seen' })

    LocalPlayer.state['ug-core:Job'] = {
        name = 'police',
        grade = 1,
    }
    H.Advance(300)

    Equal(shown(), { 'Impound', 'Seen' })
end)

Test('showDisabled false hides failed options', function()
    boot({
        showDisabled = false,
    })
    H.Export('AddModel', 'police', 'sultan', {
        label = 'Impound',
        onSelect = function() end,
        conditions = {
            job = 'police',
        },
    })
    aim(CAR)
    press()

    Equal(shown(), {})
end)

Test('a number key runs the option with its context and closes', function()
    boot()

    ---@type table
    local got = {}

    H.Export('AddModel', 'garage', 'sultan', {
        {
            label = 'One',
            onSelect = function() end,
        },
        {
            name = 'two',
            label = 'Two',
            data = {
                slot = 3,
            },
            onSelect = function(context) got = context end,
        },
    })
    aim(CAR)
    press()
    number(2)

    Equal(got.name, 'two')
    Equal(got.kind, 'vehicle')
    Equal(got.entity, CAR)
    Equal(got.netId, 40)
    Equal(got.data, {
        slot = 3,
    })
    Equal(H.PageMessages()[#H.PageMessages()].action, 'close')
    Equal(H.Events[#H.Events], {
        name = 'ug-target:Toggled',
        args = { false },
    })
end)

Test('scroll moves the selection and confirm runs it; event, command and export effects', function()
    boot()

    local exported = nil

    H.Remote.bank = {
        Open = function(_, context) exported = context.name end,
    }
    H.Export('AddModel', 'garage', 'sultan', {
        {
            label = 'One',
            event = 'garage:one',
        },
        {
            name = 'two',
            label = 'Two',
            command = 'emote sit',
            export = 'bank.Open',
        },
    })
    aim(CAR)
    press()
    tap(SCROLL_DOWN)

    Equal(H.LastPage('select'), {
        index = 2,
    })

    tap(CONFIRM)

    Equal(H.Executed, { 'emote sit' })
    Equal(exported, 'two')
end)

Test('submenus open and go back', function()
    boot()
    H.Export('AddModel', 'garage', 'sultan', {
        {
            label = 'Doors',
            openMenu = 'doors',
        },
        {
            label = 'Front left',
            menu = 'doors',
            onSelect = function() end,
        },
        {
            label = 'Front right',
            menu = 'doors',
            onSelect = function() end,
        },
    })
    aim(CAR)
    press()

    Equal(shown(), { 'Doors' })

    number(1)

    Equal(shown(), { 'Front left', 'Front right' })
    Equal(H.LastPage('options').depth, 1)

    tap(BACK)

    Equal(shown(), { 'Doors' })
end)

Test('hold options run only when held long enough', function()
    boot()

    local runs = 0

    H.Export('AddModel', 'garage', 'sultan', {
        label = 'Hotwire',
        hold = 1000,
        onSelect = function() runs = runs + 1 end,
    })
    aim(CAR)
    press()
    H.Held[CONFIRM] = true
    tap(CONFIRM)

    Equal(H.LastPage('hold'), {
        index = 1,
        duration = 1000,
    })

    H.Advance(500)
    H.Held[CONFIRM] = nil
    H.Advance(16)

    Equal(H.LastPage('hold'), {}, 'released early')
    Equal(runs, 0)

    H.Held[CONFIRM] = true
    tap(CONFIRM)
    H.Advance(1100)

    Equal(runs, 1)
end)

Test('server actions call Begin for holds, then Run, then onResult', function()
    boot()

    local result = nil

    H.Respond['ug-target:Begin'] = function() return { ok = true } end
    H.Respond['ug-target:Run'] = function() return { ok = true, value = 42 } end
    H.Export('AddEntity', 'police', 40, {
        label = 'Lockpick', hold = 500, serverAction = 'ug-police:Lockpick',
        onResult = function(ok, value, errorCode) result = { ok, value, errorCode } end,
    })
    aim(CAR)
    press()
    H.Keybinds[2].onPressed()
    H.Advance(600)

    Equal(H.Requests[1], {
        name = 'ug-target:Begin',
        args = {
            'ug-police:Lockpick',
            {
                netId = 40,
            },
        },
    })
    Equal(H.Requests[2], {
        name = 'ug-target:Run',
        args = {
            'ug-police:Lockpick',
            {
                netId = 40,
            },
        },
    })
    Equal(result, { true, 42, nil })
end)

Test('releasing a number key cancels its hold, and left click no longer picks', function()
    boot()

    local runs = 0

    H.Export('AddModel', 'garage', 'sultan', {
        label = 'Repair',
        hold = 500,
        onSelect = function() runs = runs + 1 end,
    })
    aim(CAR)
    press()
    H.Keybinds[2].onPressed()
    H.Advance(100)
    H.Keybinds[2].onReleased()
    H.Advance(600)

    Equal(runs, 0)
    Equal(H.LastPage('hold'), {})

    local function holds()
        local count = 0

        for _, message in ipairs(H.PageMessages()) do
            count = count + (message.action == 'hold' and 1 or 0)
        end

        return count
    end

    local before = holds()

    -- Left click also fires 176, cellphone select. It MUST NOT pick.
    H.Pressed[176] = true
    tap(CLICK)
    H.Advance(600)

    Equal(holds(), before, 'no hold started')
    Equal(runs, 0)
    Equal(H.LastPage('cursor'), {
        active = true,
    })
end)

Test('a refused Begin cancels the hold', function()
    boot()
    H.Respond['ug-target:Begin'] = function() return { ok = false, error = 'no_permission' } end
    H.Export('AddEntity', 'police', 40, {
        label = 'Lockpick',
        hold = 500,
        serverAction = 'ug-police:Lockpick',
        keepOpen = true,
    })
    aim(CAR)
    press()
    H.Held[CONFIRM] = true
    tap(CONFIRM)
    H.Advance(600)

    Equal(H.LastPage('result'), {
        index = 1,
        ok = false,
        error = 'no_permission',
    })
    Equal(#H.Requests, 1, 'Run never sent')
end)

Test('cooldowns disable the option with a countdown', function()
    boot()
    H.Export('AddModel', 'garage', 'sultan', {
        label = 'Honk',
        cooldown = 5000,
        keepOpen = true,
        onSelect = function() end,
    })
    aim(CAR)
    press()
    tap(CONFIRM)

    Equal(shown(), { 'Honk (cooldown)' })
    Assert(H.LastPage('options').options[1].cooldown > 4000)

    tap(CONFIRM)

    Equal(H.LastPage('result'), {
        index = 1,
        ok = false,
        reason = 'cooldown',
    })

    H.Advance(5300)

    Equal(shown(), { 'Honk' })
end)

Test('releasing the key closes, aiming away changes the menu', function()
    boot()
    H.Export('AddModel', 'garage', 'sultan', {
        label = 'Trunk',
        onSelect = function() end,
    })
    H.Export('AddGlobalPed', 'talk', {
        label = 'Talk',
        onSelect = function() end,
        distance = 6.0,
    })
    aim(CAR)
    press()

    Equal(shown(), { 'Trunk' })

    aim(NPC)
    H.Advance(32)

    Equal(shown(), { 'Talk' })

    release()

    Equal(H.PageMessages()[#H.PageMessages()].action, 'close')
    Equal(UgTarget.Internal.Target.IsOpen(), false)
end)

Test('toggle mode opens and closes on presses', function()
    boot({
        trigger = 'toggle',
    })
    aim(CAR)
    press()
    release()

    Assert(UgTarget.Internal.Target.IsOpen())

    press()

    Assert(not UgTarget.Internal.Target.IsOpen())
end)

Test('Tab locks the menu: the page picks, back closes in hold mode', function()
    boot()

    local runs = 0

    H.Export('AddModel', 'garage', 'sultan', {
        {
            label = 'One',
            onSelect = function() end,
        },
        {
            label = 'Two',
            keepOpen = true,
            onSelect = function() runs = runs + 1 end,
        },
    })
    aim(CAR)
    press()
    tap(CLICK)

    Equal(H.CallsOf('SetNuiFocus')[1].args, { true, true })
    Equal(H.LastPage('cursor'), {
        active = true,
    })

    release()

    Assert(UgTarget.Internal.Target.IsOpen(), 'release is ignored while locked')
    Equal(H.PostNui('pick', {
        index = 2,
    }), {
        ok = true,
    })
    Equal(runs, 1)
    Equal(H.PostNui('pick', {
        index = 'x',
    }), {
        ok = false,
    })
    Equal(H.PostNui('pick', {
        index = 99,
    }), {
        ok = false,
    })

    H.PostNui('back', {})

    Assert(not UgTarget.Internal.Target.IsOpen())
    Equal(H.CallsOf('SetNuiFocus')[2].args, { false, false })
end)

Test('the owner MAY turn the cursor off: left click does nothing', function()
    boot({
        cursor = false,
    })

    H.Export('AddModel', 'garage', 'sultan', {
        {
            label = 'One',
            onSelect = function() end,
        },
    })
    aim(CAR)
    press()
    tap(CLICK)

    Equal(#H.CallsOf('SetNuiFocus'), 0)
    Equal(H.PostNui('pick', {
        index = 1,
    }).ok, true, 'a valid body, but the menu is not locked')
    Assert(UgTarget.Internal.Target.IsOpen(), 'nothing ran')
end)

Test('sounds come from the owner map, and a missing entry is silent', function()
    boot({
        sounds = true,
        soundEffects = {
            hover = {
                name = 'TICK',
                set = 'MY_SET',
            },
        },
    })

    H.Export('AddModel', 'garage', 'sultan', {
        {
            label = 'One',
            onSelect = function() end,
        },
        {
            label = 'Two',
            onSelect = function() end,
        },
    })
    aim(CAR)
    press()
    tap(SCROLL_DOWN)
    H.Pressed[SCROLL_DOWN] = nil
    tap(CONFIRM)

    local calls = H.CallsOf('PlaySoundFrontend')

    Equal(#calls, 1, 'select has no entry')
    Equal(calls[1].args, { -1, 'TICK', 'MY_SET', true })
end)

Test('Disable blocks targeting while any resource asks', function()
    boot()
    H.Export('Disable', 'ug-phone', true)
    press()

    Assert(not UgTarget.Internal.Target.IsOpen())

    H.Export('Disable', 'ug-phone', false)
    press()

    Assert(UgTarget.Internal.Target.IsOpen())
    Equal(H.Export('IsActive'), true)
end)

Test('downed players cannot aim unless allowed', function()
    boot()
    LocalPlayer.state['ug-core:DeathState'] = UgCore.Enums.DeathState.Downed
    press()

    Assert(not UgTarget.Internal.Target.IsOpen())
end)

print('api')

Test('options raise with the export name', function()
    boot()

    Raises(function() H.Export('AddModel', 'x', 'sultan', { label = 'A' }) end, 'AddModel option 1: set onSelect')
    Raises(function() H.Export('AddModel', 'x', 'sultan', { label = 'A', onSelect = 1 }) end, 'onSelect MUST be a function')
    Raises(function() H.Export('AddModel', 'x', 'sultan', { label = 'A', onSelect = print, onSelct = print }) end, 'Did you mean "onSelect"?')
    Raises(function() H.Export('AddModel', 'x', 'sultan', { label = 'A', serverAction = 'nope' }) end, 'serverAction MUST be')
    Raises(function() H.Export('AddSphereZone', 'x', { coords = vector3(0.0, 0.0, 0.0), options = { label = 'A', onSelect = print } }) end, 'AddSphereZone: radius MUST be')
    Raises(function() H.Export('AddPolyZone', 'x', { points = { vector2(0.0, 0.0) }, options = { label = 'A', onSelect = print } }) end, 'points MUST list 3')
end)

Test('remove by name, by resource stop, and zones by name', function()
    boot()
    H.Export('AddModel', 'garage', 'sultan', {
        {
            name = 'a',
            label = 'A',
            onSelect = print,
        },
        {
            name = 'b',
            label = 'B',
            onSelect = print,
        },
    })
    H.Export('AddModel', 'keys', 'sultan', {
        name = 'a',
        label = 'Keys A',
        onSelect = print,
    })

    Equal(H.Export('RemoveModel', 'garage', 'sultan', 'a'), 1, 'only the caller')

    local id = H.Export('AddBoxZone', 'garage', {
        name = 'lot',
        coords = vector3(0.0, 2.0, 0.0),
        size = vector3(2.0, 2.0, 2.0),
        options = {
            label = 'Park',
            onSelect = print,
        },
    })

    Assert(math.type(id) == 'integer')
    Equal(H.Export('ZoneExists', 'x', 'lot'), true)
    Equal(H.Export('RemoveZone', 'other', id), false, 'only the owner removes a zone')

    aim(CAR)
    press()

    Equal(shown(), { 'B', 'Keys A', 'Park' })

    H.TriggerEvent('onClientResourceStop', nil, 'garage')
    H.Advance(300)

    Equal(shown(), { 'Keys A' })
    Equal(H.Export('ZoneExists', 'x', 'lot'), false)
end)

print('ox_target')

Test('ox_target options keep their callbacks and data', function()
    boot()

    ---@type table?, table
    local args, data = nil, {}

    H.Export('addModel', 'old-script', { 'sultan' }, {
        {
            name = 'ox_trunk', label = 'Trunk', icon = 'fa-solid fa-car', groups = {
                police = 0,
            }, items = 'lockpick',
            custom = 'value',
            canInteract = function(entity, distance, coords, name, bone)
                args = { entity, distance, name, bone }

                return true
            end,
            onSelect = function(value) data = value end,
        },
        {
            label = 'Event',
            event = 'old:event',
            extra = 1,
        },
        {
            label = 'Server',
            serverEvent = 'old:server',
        },
    })
    LocalPlayer.state['ug-core:Job'] = {
        name = 'police',
        grade = 0,
    }
    H.Items.lockpick = 1
    aim(CAR)
    press()

    Equal(shown(), { 'Trunk', 'Event', 'Server' })
    Equal(args, { CAR, 2.0, 'ox_trunk', nil })

    number(1)

    Equal(data.custom, 'value')
    Equal(data.entity, CAR)
    Equal(data.name, 'ox_trunk')

    press()
    number(2)

    Equal(H.Events[#H.Events].name, 'old:event')
    Equal(H.Events[#H.Events].args[1].extra, 1)

    press()
    number(3)

    Equal(H.ServerEvents[1].name, 'old:server')
    Equal(H.ServerEvents[1].args[1].entity, 40, 'server events get the network id')
end)

Test('ox_target zones and global options', function()
    boot()
    H.Export('addBoxZone', 'old-script', {
        coords = vector3(0.0, 2.0, 0.0),
        size = vector3(2.0, 2.0, 2.0),
        options = {
            {
                label = 'Box',
                onSelect = print,
            },
        },
    })
    H.Export('addGlobalOption', 'old-script', {
        label = 'Everywhere',
        onSelect = print,
    })
    aim(CAR)
    press()

    Equal(shown(), { 'Box', 'Everywhere' })

    H.Export('disableTargeting', 'old-script', true)
    H.Advance(32)

    Assert(not UgTarget.Internal.Target.IsOpen())
end)

H.Done()
