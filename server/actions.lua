--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Server actions: options whose effect runs on the server. The client only names the action and the entity it aims
-- at. The server finds the entity itself, checks its kind and model, the distance from the player's ped, the
-- conditions, the hold time and the cooldown, then runs the handler.

---@class UgTarget.Internal.Actions
local Actions = {}
UgTarget.Internal.Actions = Actions

local Conditions = UgTarget.Internal.Conditions
local Kind = UgTarget.Enums.Kind
local Errors = UgCore.Enums.Errors
local Violations = UgCore.Enums.Violations

local NAME_PATTERN = '^[%w_%-]+$'
local MAX_DISTANCE = 20.0
local MAX_HOLD = 30000
local MAX_COOLDOWN = 3600000
-- The client waits the full hold before it asks. Only clock rounding is forgiven.
local HOLD_TOLERANCE = 150
local ENTITY_KINDS = {
    [Kind.Ped] = true,
    [Kind.Vehicle] = true,
    [Kind.Object] = true,
    [Kind.Player] = true,
}
local OPTIONS = {
    distance = true, kinds = true, models = true, coords = true, conditions = true, hold = true, cooldown = true,
    allowDowned = true,
}

---@class UgTargetAction
---@field name string `<resource>:<name>`
---@field resource string
---@field distance number
---@field kinds? table<UgTargetKind, boolean>
---@field models? table<integer, boolean>
---@field coords? vector3[]
---@field conditions? UgTargetConditions
---@field hold integer
---@field cooldown integer
---@field allowDowned boolean
---@field handler fun(source: integer, context: UgTargetActionContext): any

---@class UgTargetActionContext
---@field action string
---@field kind UgTargetKind
---@field coords vector3 the entity's or the zone's position, read on the server
---@field entity? integer
---@field netId? integer
---@field model? integer
---@field player? integer server id, when the target is another player

---@type table<string, UgTargetAction>
local actions = {}
---@type table<integer, { action: string, netId: integer?, at: integer }>
local holding = {}
---@type table<integer, table<string, integer>> source to action to the time it MAY run again
local cooldowns = {}

---@param level integer
---@param message string
---@param ... any
local function raise(level, message, ...)
    error('[ug-target] ' .. message:format(...), level + 1)
end

---@param code UgErrorCode
---@return table
local function fail(code)
    return {
        ok = false,
        error = code,
    }
end

---@param where string
---@param value any
---@return table<integer, boolean>?
local function modelSet(where, value)
    if value == nil then
        return nil
    end

    local list = type(value) == 'table' and value or { value }
    local set = {}

    if #list == 0 or #list > 200 then
        raise(4, '%s: models MUST list 1 to 200 models', where)
    end

    for _, model in ipairs(list) do
        if type(model) == 'string' then
            set[joaat(model)] = true
        elseif math.type(model) == 'integer' then
            set[model] = true
        else
            raise(4, '%s: models MUST be names or hashes', where)
        end
    end

    return set
end

---Registers a server action. `name` is prefixed with the calling resource, as `<resource>:<name>`.
---@param resource string
---@param name string
---@param options { distance: number, kinds?: UgTargetKind[], models?: (string|integer)[], coords?: vector3|vector3[], conditions?: table, hold?: integer, cooldown?: integer, allowDowned?: boolean }
---@param handler fun(source: integer, context: UgTargetActionContext): any
---@return string fullName
function Actions.Register(resource, name, options, handler)
    local where = 'RegisterAction'

    if type(name) ~= 'string' or #name > 48 or not name:find(NAME_PATTERN) then
        raise(3, '%s: name MUST be 1 to 48 letters, digits, _ or -', where)
    end

    if type(options) ~= 'table' then
        raise(3, '%s: options MUST be a table', where)
    end

    if type(handler) ~= 'function' and type(handler) ~= 'table' then
        raise(3, '%s: handler MUST be a function', where)
    end

    for key in pairs(options) do
        if not OPTIONS[key] then
            raise(3, '%s: unknown option "%s"', where, tostring(key))
        end
    end

    local distance = options.distance

    if type(distance) ~= 'number' or distance <= 0 or distance > MAX_DISTANCE then
        raise(3, '%s: distance MUST be a number above 0 and at most %d', where, MAX_DISTANCE)
    end

    local kinds = nil

    if options.kinds ~= nil then
        kinds = {}

        for _, kind in ipairs(type(options.kinds) == 'table' and options.kinds or {}) do
            if not ENTITY_KINDS[kind] then
                raise(3, '%s: kinds MUST be ped, vehicle, object or player', where)
            end

            kinds[kind] = true
        end

        if not next(kinds) then
            raise(3, '%s: kinds MUST list at least one kind', where)
        end
    end

    local coords = nil

    if options.coords ~= nil then
        local list = type(options.coords) == 'vector3' and { options.coords } or options.coords

        if type(list) ~= 'table' or #list == 0 or #list > 500 then
            raise(3, '%s: coords MUST be a vector3 or 1 to 500 of them', where)
        end

        ---@cast list vector3[]
        coords = list

        for _, point in ipairs(list) do
            if type(point) ~= 'vector3' then
                raise(3, '%s: coords MUST be vector3 values', where)
            end
        end
    end

    local models = modelSet(where, options.models)

    if not kinds and not models and not coords then
        raise(3, '%s: set kinds, models or coords, so the server knows where the action MAY run', where)
    end

    if (kinds or models) and coords then
        raise(3, '%s: an action is for entities (kinds, models) or for places (coords), not both', where)
    end

    for _, key in ipairs({ 'hold', 'cooldown' }) do
        local value = options[key]
        local max = key == 'hold' and MAX_HOLD or MAX_COOLDOWN

        if value ~= nil and (math.type(value) ~= 'integer' or value < 0 or value > max) then
            raise(3, '%s: %s MUST be an integer from 0 to %d ms', where, key, max)
        end
    end

    if options.allowDowned ~= nil and type(options.allowDowned) ~= 'boolean' then
        raise(3, '%s: allowDowned MUST be a boolean', where)
    end

    local fullName = resource .. ':' .. name

    actions[fullName] = {
        name = fullName,
        resource = resource,
        distance = distance,
        kinds = kinds,
        models = models,
        coords = coords,
        conditions = Conditions.Normalize(where, options.conditions),
        hold = options.hold or 0,
        cooldown = options.cooldown or 0,
        allowDowned = options.allowDowned == true,
        handler = handler,
    }

    return fullName
end

---@param fullName string
---@return boolean removed
function Actions.Remove(fullName)
    if not actions[fullName] then
        return false
    end

    actions[fullName] = nil

    return true
end

---Removes every action of a resource.
---@param resource string
---@return integer count
function Actions.RemoveResource(resource)
    local count = 0

    for name, action in pairs(actions) do
        if action.resource == resource then
            actions[name] = nil
            count = count + 1
        end
    end

    return count
end

---@return table<string, UgTargetAction>
function Actions.GetAll()
    return actions
end

---@param entity integer
---@return UgTargetKind?
local function kindOf(entity)
    local entityType = GetEntityType(entity)

    if entityType == 1 then
        return IsPedAPlayer(entity) and Kind.Player or Kind.Ped
    elseif entityType == 2 then
        return Kind.Vehicle
    elseif entityType == 3 then
        return Kind.Object
    end

    return nil
end

---@param source integer
---@return UgTargetFacts
local function factsOf(source)
    local Modules = UgCore.Modules
    local ped = GetPlayerPed(source)

    return {
        job = Modules.IsEnabled('jobs') and UgCore.Jobs.Get(source) or nil,
        gang = Modules.IsEnabled('gangs') and UgCore.Gangs.Get(source) or nil,
        inVehicle = GetVehiclePedIsIn(ped, false) ~= 0,
        count = function(item)
            return Modules.IsEnabled('inventory') and UgCore.Inventory.Count(source, item) or 0
        end,
    }
end

---@param from vector3
---@param points vector3[]
---@return vector3
local function nearest(from, points)
    local best, bestDistance = points[1], math.huge

    for _, point in ipairs(points) do
        local dx, dy, dz = point.x - from.x, point.y - from.y, point.z - from.z
        local distance = dx * dx + dy * dy + dz * dz

        if distance < bestDistance then
            best, bestDistance = point, distance
        end
    end

    return best
end

---Finds the action's target on the server and checks everything but the hold and the cooldown.
---@param source integer
---@param name string
---@param target { netId?: integer }
---@return UgTargetAction? action
---@return UgTargetActionContext? context
---@return UgErrorCode? errorCode
local function resolve(source, name, target)
    local action = actions[name]

    if not action then
        return nil, nil, Errors.NotFound
    end

    ---@type UgTargetActionContext
    local context

    if action.coords then
        local ped = GetPlayerPed(source)

        context = {
            action = name,
            kind = Kind.Zone,
            coords = nearest(GetEntityCoords(ped), action.coords),
        }
    else
        local netId = target.netId
        local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0

        if entity == 0 or not DoesEntityExist(entity) then
            return nil, nil, Errors.NotFound
        end

        local kind = kindOf(entity)
        local model = GetEntityModel(entity)

        if not kind or (action.kinds and not action.kinds[kind]) or (action.models and not action.models[model]) then
            UgCore.Guard.Flag(source, Violations.InvalidPayload, ('ug-target %s on a wrong entity'):format(name))

            return nil, nil, Errors.InvalidArgs
        end

        context = {
            action = name,
            kind = kind,
            coords = GetEntityCoords(entity),
            entity = entity,
            netId = netId,
            model = model,
        }

        if kind == Kind.Player then
            context.player = NetworkGetEntityOwner(entity)

            if context.player == source then
                return nil, nil, Errors.InvalidArgs
            end
        end
    end

    local margin = UgTarget.Internal.Config.Get().actionMargin

    if not UgCore.Guard.IsNear(source, context.coords, action.distance + margin) then
        UgCore.Guard.Flag(source, Violations.OutOfRange, ('ug-target %s'):format(name))

        return nil, nil, Errors.NoPermission
    end

    if not action.allowDowned and UgCore.Players.GetDeathState(source) ~= UgCore.Enums.DeathState.Alive then
        return nil, nil, Errors.NoPermission
    end

    if not Conditions.Check(action.conditions, factsOf(source)) then
        return nil, nil, Errors.NoPermission
    end

    return action, context, nil
end

---@param source integer
---@param action UgTargetAction
---@return boolean
local function coolingDown(source, action)
    local until_ = cooldowns[source] and cooldowns[source][action.name]

    return until_ ~= nil and GetGameTimer() < until_
end

---Starts the hold of an action. The client calls it when the player starts holding.
---@param source integer
---@param name string
---@param target { netId?: integer }
---@return table
function Actions.Begin(source, name, target)
    local action, _, errorCode = resolve(source, name, target)

    if not action then
        return fail(errorCode or Errors.InternalError)
    end

    if coolingDown(source, action) then
        return fail(Errors.RateLimited)
    end

    holding[source] = {
        action = name,
        netId = target.netId,
        at = GetGameTimer(),
    }

    return {
        ok = true,
    }
end

---Runs an action. Actions with a hold need a Begin for the same target at least `hold` ms before.
---@param source integer
---@param name string
---@param target { netId?: integer }
---@return table
function Actions.Run(source, name, target)
    local action, context, errorCode = resolve(source, name, target)

    if not action or not context then
        holding[source] = nil

        return fail(errorCode or Errors.InternalError)
    end

    if coolingDown(source, action) then
        return fail(Errors.RateLimited)
    end

    if action.hold > 0 then
        local started = holding[source]

        holding[source] = nil

        if not started or started.action ~= name or started.netId ~= target.netId
            or GetGameTimer() - started.at < action.hold - HOLD_TOLERANCE then
            UgCore.Guard.Flag(source, Violations.InvalidPayload, ('ug-target %s without its hold'):format(name))

            return fail(Errors.NoPermission)
        end
    end

    if action.cooldown > 0 then
        cooldowns[source] = cooldowns[source] or {}
        cooldowns[source][name] = GetGameTimer() + action.cooldown
    end

    local ok, value = pcall(action.handler, source, context)

    if not ok then
        UgCore.Logger.Error('Action %s failed: %s', name, tostring(value))

        return fail(Errors.InternalError)
    end

    return {
        ok = true,
        value = value,
    }
end

---Forgets a player's holds and cooldowns.
---@param source integer
function Actions.Forget(source)
    holding[source], cooldowns[source] = nil, nil
end

---Registers the callbacks and the cleanup handlers. Runs once after a clean boot.
function Actions.Listen()
    local Schema = UgCore.Schema
    local schema = Schema.Define({
        Schema.String({
            min = 3,
            max = 96,
            pattern = '^[%w_%-]+:[%w_%-]+$',
        }),
        Schema.Object({
            netId = Schema.Optional(Schema.Integer({
                min = 1,
                max = 2147483647,
            })),
        }),
    })
    local rate = {
        max = 10,
        per = 5000,
    }

    UgCore.Callback.Register('Begin', {
        schema = schema,
        rate = rate,
        requirePlayer = true,
    }, Actions.Begin)
    UgCore.Callback.Register('Run', {
        schema = schema,
        rate = rate,
        requirePlayer = true,
    }, Actions.Run)

    AddEventHandler('playerDropped', function()
        local player = math.tointeger(tonumber(source))

        if player then
            Actions.Forget(player)
        end
    end)

    AddEventHandler('onResourceStop', function(resource)
        local count = Actions.RemoveResource(resource)

        if count > 0 then
            UgCore.Logger.Debug('Removed %d action(s) of %s.', count, resource)
        end
    end)
end

---@param name string
---@param options table
---@param handler function
---@return string
local function registerExport(name, options, handler)
    return Actions.Register(GetInvokingResource() or GetCurrentResourceName(), name, options, handler)
end

---@param name string full name, or a name of the calling resource
---@return boolean
local function removeExport(name)
    if type(name) ~= 'string' then
        return false
    end

    if not name:find(':', 1, true) then
        name = (GetInvokingResource() or GetCurrentResourceName()) .. ':' .. name
    end

    return Actions.Remove(name)
end

exports('RegisterAction', registerExport)
exports('RemoveAction', removeExport)
