--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Test helpers: a tiny runner, CfxLua mocks, and the real ug-core and ug-lib shared code this resource relies on.
-- ug-core and ug-lib are read from the UG_CORE and UG_LIB paths, siblings of this repository by default.

---@class TestHelpers
local H = {}

H.CorePath = os.getenv('UG_CORE') or '../ug-core'
H.LibPath = os.getenv('UG_LIB') or '../ug-lib'

local passed, failed = 0, 0
local rawType = type
local vectorKinds = setmetatable({}, {
    __mode = 'k',
})

---The CfxLua `type` names vectors.
---@param value any
---@return string
type = function(value)
    return rawType(value) == 'table' and vectorKinds[value] or rawType(value)
end

---@param kind string
---@param components table
---@return table
local function newVector(kind, components)
    vectorKinds[components] = kind

    return components
end

function vector2(x, y) return newVector('vector2', { x = x, y = y }) end

function vector3(x, y, z) return newVector('vector3', { x = x, y = y, z = z }) end

function vector4(x, y, z, w) return newVector('vector4', { x = x, y = y, z = z, w = w }) end

vec2, vec3, vec4 = vector2, vector3, vector4

---@type table<string, string|false> resource files that replace the ones on disk, `false` for a missing file
H.Files = {}
---@type table<string, string> files saved with SaveResourceFile
H.Saved = {}
---@type table<string, { options: table, handler: fun(source: integer, ...: any): any }> server callbacks
H.Callbacks = {}
---@type table<string, { handler: fun(source: integer, args: string[]), restricted: boolean }>
H.Commands = {}
---@type table<string, function[]> FiveM event handlers
H.Handlers = {}
---@type { name: string, args: any[] }[] local events triggered
H.Events = {}
---@type { name: string, args: any[] }[] server events triggered by the client
H.ServerEvents = {}
---@type string[] commands run with ExecuteCommand
H.Executed = {}
---@type { source: integer, violation: string, detail: string? }[]
H.Flags = {}
---@type table<integer, { coords: vector3, model: any, type: integer, player?: integer }> entities by handle
H.Entities = {}
---@type table<integer, integer> entity handles by network id
H.NetEntities = {}
---@type table<integer, vector3> server-side ped coords by source
H.PedCoords = {}
---@type table<integer, string> death states by source
H.DeathStates = {}
---@type table<integer, table> jobs by source
H.Jobs = {}
---@type table<integer, table> gangs by source
H.Gangs = {}
---@type table<string, integer> item counts, shared by every player
H.Items = {}
---@type table<string, boolean>
H.Modules = {}
---@type table<string, function> exports of this resource
H.Exports = {}
---@type table<string, table<string, function>> exports of other resources
H.Remote = {}
---@type string? what GetInvokingResource answers
H.Invoking = nil
H.Now = 0
H.CoreReady = true

function GetCurrentResourceName()
    return 'ug-target'
end

function GetInvokingResource()
    return H.Invoking
end

---@param _ string
---@param path string
---@return string?
function LoadResourceFile(_, path)
    if H.Files[path] ~= nil then
        return H.Files[path] or nil
    end

    local handle = io.open(path, 'rb')

    if not handle then
        return nil
    end

    local content = handle:read('a')

    handle:close()

    return content
end

function SaveResourceFile(_, path, content)
    H.Saved[path] = content
    H.Files[path] = content

    return true
end

function GetResourceMetadata(_, key)
    return key == 'version' and '1.0.0' or nil
end

---@type { thread: thread, wakeAt: integer }[] threads waiting in Wait
local sleeping = {}

---@param thread thread
local function resume(thread)
    local ok, result = coroutine.resume(thread)

    if not ok then
        error(debug.traceback(thread, tostring(result)), 0)
    end

    if coroutine.status(thread) == 'suspended' then
        sleeping[#sleeping + 1] = {
            thread = thread,
            wakeAt = H.Now + math.max(result or 0, 1),
        }
    end
end

---Like FiveM: the thread runs at once until its first Wait.
function CreateThread(fn)
    resume(coroutine.create(fn))
end

---Yields until H.Advance reaches the time. Outside a thread it only moves the clock.
---@param ms? integer
function Wait(ms)
    if coroutine.isyieldable() then
        coroutine.yield(ms or 0)
    else
        H.Now = H.Now + (ms or 0)
    end
end

---Runs frames of 16 ms until `ms` passed, waking threads whose time came.
---@param ms integer
function H.Advance(ms)
    local target = H.Now + ms

    repeat
        H.Now = math.min(H.Now + 16, target)

        local ready = {}

        for index = #sleeping, 1, -1 do
            if sleeping[index].wakeAt <= H.Now then
                ready[#ready + 1] = table.remove(sleeping, index)
            end
        end

        for index = #ready, 1, -1 do
            resume(ready[index].thread)
        end
    until H.Now >= target
end

---Calls of mocked natives, in order: `{ name, args }`.
---@type { name: string, args: any[] }[]
H.Natives = {}

---@param name string
---@return { name: string, args: any[] }[]
function H.CallsOf(name)
    local list = {}

    for _, call in ipairs(H.Natives) do
        if call.name == name then
            list[#list + 1] = call
        end
    end

    return list
end

---@param name string
---@param ... any
local function record(name, ...)
    H.Natives[#H.Natives + 1] = {
        name = name,
        args = { ... },
    }
end

---@type table<string, any> answers of auto-mocked natives
H.NativeReturns = {}

-- Any other PascalCase global is a native: recorded, answering H.NativeReturns[name] or nil.
setmetatable(_G, {
    __index = function(_, name)
        if rawType(name) == 'string' and name:find('^%u') then
            return function(...)
                record(name, ...)

                local value = H.NativeReturns[name]

                if rawType(value) == 'function' then
                    return value(...)
                end

                return value
            end
        end

        return nil
    end,
})

function GetGameTimer()
    return H.Now
end

function joaat(name)
    return 'hash:' .. name
end

function RegisterCommand(name, handler, restricted)
    H.Commands[name] = {
        handler = handler,
        restricted = restricted,
    }
end

function AddEventHandler(name, handler)
    H.Handlers[name] = H.Handlers[name] or {}
    table.insert(H.Handlers[name], handler)
end

function TriggerEvent(name, ...)
    H.Events[#H.Events + 1] = {
        name = name,
        args = { ... },
    }
end

function TriggerServerEvent(name, ...)
    H.ServerEvents[#H.ServerEvents + 1] = {
        name = name,
        args = { ... },
    }
end

function ExecuteCommand(command)
    H.Executed[#H.Executed + 1] = command
end

exports = setmetatable({}, {
    __call = function(_, name, fn)
        H.Exports[name] = fn
    end,
    __index = function(_, resource)
        return H.Remote[resource]
    end,
})

---Calls an export of this resource as another resource.
---@param name string
---@param resource? string the calling resource, `other` by default
---@param ... any
---@return ...
function H.Export(name, resource, ...)
    local fn = assert(H.Exports[name], 'export not registered: ' .. name)

    H.Invoking = resource or 'other'

    local results = table.pack(pcall(fn, ...))

    H.Invoking = nil

    if not results[1] then
        error(results[2], 0)
    end

    return table.unpack(results, 2, results.n)
end

-- Entities: shared by the server and client mocks.

---@param entity integer
---@return boolean
function DoesEntityExist(entity)
    return H.Entities[entity] ~= nil
end

function GetEntityCoords(entity)
    local data = H.Entities[entity]

    if not data and entity == 1 then
        return H.PedPosition
    end

    return data and data.coords or vector3(0.0, 0.0, 0.0)
end

function GetEntityModel(entity)
    local data = H.Entities[entity]

    return data and data.model or 0
end

function GetEntityType(entity)
    local data = H.Entities[entity]

    return data and data.type or 0
end

function IsPedAPlayer(entity)
    local data = H.Entities[entity]

    return data ~= nil and data.player ~= nil
end

function NetworkGetEntityFromNetworkId(netId)
    return H.NetEntities[netId] or 0
end

function NetworkGetEntityOwner(entity)
    local data = H.Entities[entity]

    return data and data.player or -1
end

function NetworkGetEntityIsNetworked(entity)
    for _, handle in pairs(H.NetEntities) do
        if handle == entity then
            return true
        end
    end

    return false
end

function NetworkGetNetworkIdFromEntity(entity)
    for netId, handle in pairs(H.NetEntities) do
        if handle == entity then
            return netId
        end
    end

    return 0
end

---Adds an entity. `type` 1 ped, 2 vehicle, 3 object.
---@param entity integer
---@param data { coords: vector3, model: any, type: integer, player?: integer, netId?: integer }
function H.Entity(entity, data)
    H.Entities[entity] = data

    if data.netId then
        H.NetEntities[data.netId] = entity
    end
end

-- Server natives.

function GetPlayerPed(source)
    return 1000 + source
end

function GetVehiclePedIsIn()
    return 0
end

---Loads a Lua file into the global environment.
---@param path string
local function run(path)
    local chunk = assert(loadfile(path, 't'))

    chunk()
end

local function loadCore()
    for _, file in ipairs({
        'core/shared/init.lua',
        'core/shared/utils/init.lua',
        'core/shared/utils/table.lua',
        'core/shared/utils/string.lua',
        'core/shared/enums/init.lua',
        'core/shared/enums/lifecycle.lua',
        'core/shared/enums/violations.lua',
        'core/shared/enums/errors.lua',
        'core/shared/logger.lua',
        'core/shared/schema.lua',
        'core/shared/enums/events.lua',
        'core/shared/enums/hooks.lua',
        'core/shared/enums/statebags.lua',
        'modules/players/shared/enums.lua',
    }) do
        run(H.CorePath .. '/' .. file)
    end

    UgCore.Callback = {
        Register = function(name, options, handler)
            H.Callbacks[name] = {
                options = options,
                handler = handler,
            }
        end,
    }
    UgCore.Guard = {
        IsNear = function(target, coords, maxDistance)
            local ped = H.PedCoords[target]

            return ped ~= nil and math.sqrt((ped.x - coords.x) ^ 2 + (ped.y - coords.y) ^ 2 + (ped.z - coords.z) ^ 2) <= maxDistance
        end,
        Flag = function(target, violation, detail)
            H.Flags[#H.Flags + 1] = {
                source = target,
                violation = violation,
                detail = detail,
            }
        end,
    }
    UgCore.Players = {
        GetDeathState = function(target)
            return H.DeathStates[target] or UgCore.Enums.DeathState.Alive
        end,
    }
    UgCore.Jobs = {
        Get = function(target)
            return H.Jobs[target]
        end,
    }
    UgCore.Gangs = {
        Get = function(target)
            return H.Gangs[target]
        end,
    }
    UgCore.Inventory = {
        Count = function(target, name)
            if rawType(target) == 'string' then
                name = target
            end

            return H.Items[name] or 0
        end,
    }
    UgCore.Logger.Debug = function() end
    UgCore.Lifecycle = {
        Await = function()
            return H.CoreReady
        end,
    }
    UgCore.Modules = {
        IsEnabled = function(name)
            return H.Modules[name] == true
        end,
    }
end

local function loadLib()
    for _, file in ipairs({ 'shared/init.lua', 'shared/utils.lua', 'shared/string.lua', 'shared/table.lua' }) do
        run(H.LibPath .. '/' .. file)
    end
end

-- Client mocks.

---@type { hit: boolean, coords?: vector3, entity?: integer } what the next camera raycast answers
H.Ray = {
    hit = false,
}
---@type vector3 the local ped's position
H.PedPosition = vector3(0.0, 0.0, 0.0)
---@type table<integer, boolean> controls that read as just pressed once
H.Pressed = {}
---@type table<integer, boolean> controls held down
H.Held = {}
---@type table[] ug-lib keybinds registered
H.Keybinds = {}
---@type table<string, fun(...): table> server answers by full callback name
H.Respond = {}
---@type { name: string, args: any[] }[] callbacks the client awaited
H.Requests = {}
---@type table<string, fun(body: any, cb: fun(reply: any))> NUI callbacks the client registered
H.NuiCallbacks = {}

function PlayerPedId()
    return 1
end

function IsDisabledControlJustPressed(_, control)
    if H.Pressed[control] then
        H.Pressed[control] = nil

        return true
    end

    return false
end

function IsDisabledControlPressed(_, control)
    return H.Held[control] == true
end

function IsPedInAnyVehicle()
    return false
end

function GetScreenCoordFromWorldCoord()
    return true, 0.5, 0.4
end

function GetOffsetFromEntityGivenWorldCoords()
    return vector3(0.0, 0.0, 1.0)
end

function GetOffsetFromEntityInWorldCoords(entity)
    return GetEntityCoords(entity)
end

function GetGameplayCamCoord()
    return vector3(0.0, 0.0, 0.0)
end

function GetGameplayCamRot()
    return vector3(0.0, 0.0, 0.0)
end

function RegisterNUICallback(name, handler)
    H.NuiCallbacks[name] = handler
end

---Posts to a NUI callback like the page does. Returns the reply.
---@param name string
---@param body any
---@return any
function H.PostNui(name, body)
    local reply = nil

    assert(H.NuiCallbacks[name], 'NUI callback not registered: ' .. name)(body, function(value)
        reply = value
    end)

    return reply
end

---Messages sent to the page, in order.
---@return { action: string, payload: any }[]
function H.PageMessages()
    local list = {}

    for _, call in ipairs(H.CallsOf('SendNUIMessage')) do
        list[#list + 1] = call.args[1]
    end

    return list
end

---The payload of the last page message with this action.
---@param action string
---@return any
function H.LastPage(action)
    local found = nil

    for _, message in ipairs(H.PageMessages()) do
        if message.action == action then
            found = message
        end
    end

    return found and found.payload
end

local function installClient()
    LocalPlayer = {
        state = {
            [UgCore.Enums.StateBags.Loaded] = true,
        },
    }
    UgCore.Callback = {
        Await = function(name, ...)
            H.Requests[#H.Requests + 1] = {
                name = name,
                args = { ... },
            }

            local respond = H.Respond[name]

            if not respond then
                return false, nil, UgCore.Enums.Errors.Timeout
            end

            return true, respond(...), nil
        end,
    }
    UgLib.Raycast = {
        FromCamera = function()
            Wait(0)

            return H.Ray
        end,
    }
    UgLib.Math = {
        RotationToDirection = function()
            return vector3(0.0, 1.0, 0.0)
        end,
    }
    UgLib.Enums = UgLib.Enums or {}
    UgLib.Enums.GlobalState = {
        Config = 'ug-lib:Config',
    }
    UgLib.Locale = {
        Create = function()
            return function(key)
                return 'label:' .. key
            end
        end,
        GetCode = function()
            return 'en'
        end,
    }
    UgLib.Keybind = {
        Register = function(options)
            H.Keybinds[#H.Keybinds + 1] = options

            return '+ug-target-' .. options.name
        end,
    }
end

---Reads script lists from fxmanifest.lua.
---@return table<string, string[]>
local function readManifest()
    local lists = {
        shared = {},
        server = {},
        client = {},
    }
    local groups = {
        shared_script = 'shared', shared_scripts = 'shared',
        server_script = 'server', server_scripts = 'server',
        client_script = 'client', client_scripts = 'client',
    }
    local env = setmetatable({}, {
        __index = function(_, directive)
            return function(value)
                local group = groups[directive]

                if group then
                    for _, entry in ipairs(rawType(value) == 'table' and value or { value }) do
                        table.insert(lists[group], entry)
                    end
                end
            end
        end,
    })

    assert(loadfile('fxmanifest.lua', 't', env))()

    return lists
end

---Fresh mocks. Tests change them before H.Load. `config.lua` starts missing, whatever is on disk.
function H.Reset()
    H.Files, H.Saved = {
        ['config.lua'] = false,
    }, {}
    H.Callbacks, H.Commands, H.Handlers = {}, {}, {}
    H.Events, H.ServerEvents, H.Executed, H.Flags = {}, {}, {}, {}
    H.Entities, H.NetEntities, H.PedCoords, H.DeathStates = {}, {}, {}, {}
    H.Jobs, H.Gangs, H.Items, H.Modules = {}, {}, {}, {
        jobs = true,
        gangs = true,
        inventory = true,
    }
    H.Exports, H.Remote, H.Invoking = {}, {}, nil
    H.Now, H.CoreReady = 1000, true
    H.Natives, H.NativeReturns = {}, {}
    H.Ray, H.PedPosition, H.Pressed, H.Held = {
        hit = false,
    }, vector3(0.0, 0.0, 0.0), {}, {}
    H.Keybinds, H.Respond, H.Requests, H.NuiCallbacks = {}, {}, {}, {}
    GlobalState = setmetatable({}, {
        __index = {
            set = function(self, key, value)
                rawset(self, key, value)
            end,
        },
    })
    sleeping = {}
    UgCore, UgLib, UgTarget, LocalPlayer = nil, nil, nil, nil
end

---Calls a registered server callback like ug-core does: the schema first, then the handler.
---@param name string
---@param target integer
---@param ... any
---@return table? result
---@return string? errorCode when ug-core rejects before the handler
function H.Call(name, target, ...)
    local entry = assert(H.Callbacks[name], 'callback not registered: ' .. name)
    local ok, args = UgCore.Schema.Validate(entry.options.schema, ...)

    if not ok or not args then
        return nil, UgCore.Enums.Errors.InvalidArgs
    end

    return entry.handler(target, table.unpack(args, 1, args.n))
end

---Runs every handler of a FiveM event with `source` set, like the runtime.
---@param name string
---@param target? integer
function H.TriggerEvent(name, target, ...)
    for _, handler in ipairs(H.Handlers[name] or {}) do
        source = target
        handler(...)
    end

    source = nil
end

---@param name string
---@param target integer
---@param args? string[]
---@return string[] printed lines
function H.RunCommand(name, target, args)
    local command = assert(H.Commands[name], 'command not registered: ' .. name)

    return H.Capture(function()
        command.handler(target, args or {})
    end)
end

---Loads ug-core and ug-lib, then this resource's shared and side scripts in manifest order.
---@param side 'server'|'client'
---@return string[] printed lines
function H.Load(side)
    return H.Capture(function()
        loadCore()
        loadLib()

        if side == 'client' then
            installClient()
        end

        local manifest = readManifest()

        for _, group in ipairs({ 'shared', side }) do
            for _, path in ipairs(manifest[group]) do
                if path:sub(1, 1) ~= '@' then
                    run(path)
                end
            end
        end
    end)
end

---Loads the client with the server's config replicated, and runs boot until the key is bound.
---@param overrides? table config values that replace the defaults
---@return string[] printed lines
function H.LoadClient(overrides)
    local lines = H.Capture(function()
        loadCore()
        loadLib()
    end)

    -- The defaults come from the server file, so the client sees what a real server sends.
    UgTarget = {
        Internal = {},
    }
    run('shared/enums.lua')
    local values = H.Defaults()

    values.actionMargin = nil

    for key, value in pairs(overrides or {}) do
        values[key] = value
    end

    UgCore, UgLib, UgTarget = nil, nil, nil
    GlobalState['ug-target:Config'] = values

    for _, line in ipairs(H.Load('client')) do
        lines[#lines + 1] = line
    end

    H.PostNui('ready', {})

    return lines
end

---Runs `fn` and returns every printed line, without color codes.
---@param fn fun()
---@return string[]
function H.Capture(fn)
    local lines = {}
    local original = print

    print = function(...)
        local parts = {}

        for index = 1, select('#', ...) do
            parts[#parts + 1] = tostring((select(index, ...)))
        end

        lines[#lines + 1] = (table.concat(parts, ' '):gsub('%^%d', ''))
    end

    local ok, err = pcall(fn)

    print = original

    if not ok then
        error(err, 0)
    end

    return lines
end

---@param a any
---@param b any
---@return boolean
local function same(a, b)
    if rawType(a) ~= 'table' or rawType(b) ~= 'table' then
        return a == b
    end

    if vectorKinds[a] ~= vectorKinds[b] then
        return false
    end

    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

---@param value any
---@param depth? integer
---@return string
local function show(value, depth)
    depth = depth or 0

    if rawType(value) ~= 'table' then
        return rawType(value) == 'string' and ('%q'):format(value) or tostring(value)
    end

    if depth > 3 then
        return '{...}'
    end

    local parts = {}

    for key, item in pairs(value) do
        parts[#parts + 1] = ('%s = %s'):format(tostring(key), show(item, depth + 1))
    end

    table.sort(parts)

    return (vectorKinds[value] or '') .. '{ ' .. table.concat(parts, ', ') .. ' }'
end

function H.Equal(actual, expected, message)
    if not same(actual, expected) then
        error(('%s\n  expected: %s\n  actual:   %s'):format(message or 'not equal', show(expected), show(actual)), 2)
    end
end

function H.Assert(condition, message)
    if not condition then
        error(message or 'assertion failed', 2)
    end
end

---Runs `fn` and expects it to raise an error containing `text`.
---@param fn fun()
---@param text string
function H.Raises(fn, text)
    local ok, err = pcall(fn)

    if ok then
        error(('expected an error containing "%s"'):format(text), 2)
    end

    if not tostring(err):find(text, 1, true) then
        error(('expected an error containing "%s", got: %s'):format(text, tostring(err)), 2)
    end
end

---@param lines string[]
---@param text string
---@return boolean
function H.Contains(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then
            return true
        end
    end

    return false
end

---@param lines string[]
---@param text string
function H.ExpectLine(lines, text)
    if not H.Contains(lines, text) then
        error(('no line contains "%s":\n  %s'):format(text, table.concat(lines, '\n  ')), 2)
    end
end

---Wrong-type values for tests. LuaLS ignores casts on literals.
---@param value any
---@return any
function H.Any(value)
    return value
end

---@param name string
---@param fn fun()
function H.Test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)

    if ok then
        passed = passed + 1
        print('  ok    ' .. name)
    else
        failed = failed + 1
        print('  FAIL  ' .. name .. '\n        ' .. tostring(err):gsub('\n', '\n        '))
    end
end

function H.Done()
    print(('\n%d passed, %d failed'):format(passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

---The defaults, read from server/config.default.lua like the server reads them.
---@return table
function H.Defaults()
    local content = assert(LoadResourceFile('ug-target', 'server/config.default.lua'))
    local env = setmetatable({}, {
        __index = _G,
    })

    return assert(load(content, '@server/config.default.lua', 't', env))()
end

return H
