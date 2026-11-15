--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- ox_target exports. The manifest provides ox_target, so scripts written for it run unchanged. Their options are
-- translated to ug-target options: groups and items become conditions, callbacks get ox_target's arguments.

---@class UgTarget.Internal.Compat
local Compat = {}
UgTarget.Internal.Compat = Compat

local Api = UgTarget.Internal.Api
local Registry = UgTarget.Internal.Registry
local Kind = UgTarget.Enums.Kind
local Shape = UgTarget.Enums.Shape

local RESOURCE = GetCurrentResourceName()

-- ox_target fields with a ug-target equivalent. Everything else is developer data, passed back to callbacks.
local MAPPED = {
    name = true, label = true, icon = true, iconColor = true, distance = true, bones = true, groups = true,
    items = true, anyItem = true, canInteract = true, onSelect = true, export = true, event = true,
    serverEvent = true, command = true, menuName = true, openMenu = true,
}
-- ox_target fields ug-target ignores.
local IGNORED = {
    offset = true,
    offsetAbsolute = true,
    offsetSize = true,
    resource = true,
}

---@return string
local function caller()
    return GetInvokingResource() or RESOURCE
end

---The table ox_target passes to onSelect, events and exports: the context plus the option's own fields.
---@param context UgTargetContext
---@param extra table
---@return table
local function oxData(context, extra)
    local data = {}

    for key, value in pairs(extra) do
        data[key] = value
    end

    data.entity = context.entity or 0
    data.coords = context.coords
    data.distance = context.distance
    data.zone = context.zone
    data.name = context.name

    return data
end

---@param input table
---@return table
local function translate(input)
    if type(input) ~= 'table' then
        return input
    end

    local extra = {}

    for key, value in pairs(input) do
        if not MAPPED[key] and not IGNORED[key] then
            extra[key] = value
        end
    end

    local conditions = nil

    if input.groups ~= nil or input.items ~= nil then
        conditions = {
            groups = input.groups,
            items = input.items,
            anyItem = input.anyItem,
        }
    end

    local canInteract = input.canInteract
    local onSelect, event, serverEvent, command, export = input.onSelect, input.event, input.serverEvent, input.command, input.export
    local select = nil

    if onSelect or event or serverEvent or command or export then
        select = function(context)
            local data = oxData(context, extra)

            if onSelect then
                onSelect(data)
            elseif export then
                local resource, method = export:match('^(.-)%.(.+)$')

                exports[resource][method](nil, data)
            elseif event then
                TriggerEvent(event, data)
            elseif serverEvent then
                data.entity = context.netId or 0
                TriggerServerEvent(serverEvent, data)
            elseif command then
                ExecuteCommand(command)
            end
        end
    end

    return {
        name = input.name,
        label = input.label or input.name or '?',
        icon = input.icon,
        iconColor = input.iconColor,
        distance = input.distance,
        bones = input.bones,
        conditions = conditions,
        canInteract = canInteract and function(context)
            return canInteract(context.entity or 0, context.distance, context.coords, context.name, context.bone)
        end or nil,
        onSelect = select,
        menu = input.menuName,
        openMenu = input.openMenu,
        data = next(extra) and extra or nil,
    }
end

---One option or a list, translated.
---@param options any
---@return any
function Compat.Translate(options)
    if type(options) ~= 'table' then
        return options
    end

    if options[1] == nil then
        return translate(options)
    end

    local list = {}

    for index, option in ipairs(options) do
        list[index] = translate(option)
    end

    return list
end

local Translate = Compat.Translate

---@param shape UgTargetShape
---@param input any
---@return integer
local function addZone(shape, input)
    if type(input) ~= 'table' then
        return Api.AddZone(caller(), shape, input)
    end

    return Api.AddZone(caller(), shape, {
        name = input.name,
        coords = input.coords,
        radius = input.radius,
        size = input.size,
        rotation = input.rotation,
        points = input.points,
        thickness = input.thickness,
        debug = input.debug,
        options = Translate(input.options),
    })
end

local GLOBALS = {
    Ped = Kind.Ped,
    Vehicle = Kind.Vehicle,
    Object = Kind.Object,
    Player = Kind.Player,
}

for suffix, kind in pairs(GLOBALS) do
    exports('addGlobal' .. suffix, function(options)
        Api.AddGlobal(caller(), kind, Translate(options))
    end)

    exports('removeGlobal' .. suffix, function(names)
        Api.RemoveGlobal(caller(), kind, names)
    end)
end

-- ox_target's global options show on every entity.
exports('addGlobalOption', function(options)
    local resource = caller()

    for _, kind in pairs(GLOBALS) do
        Api.AddGlobal(resource, kind, Translate(options))
    end
end)

exports('removeGlobalOption', function(names)
    local resource = caller()

    for _, kind in pairs(GLOBALS) do
        Api.RemoveGlobal(resource, kind, names)
    end
end)

exports('addModel', function(models, options)
    Api.AddKeyed(caller(), 'model', 'addModel', models, Translate(options))
end)

exports('removeModel', function(models, names)
    Api.RemoveKeyed(caller(), 'model', 'removeModel', models, names)
end)

exports('addEntity', function(netIds, options)
    Api.AddKeyed(caller(), 'entity', 'addEntity', netIds, Translate(options))
end)

exports('removeEntity', function(netIds, names)
    Api.RemoveKeyed(caller(), 'entity', 'removeEntity', netIds, names)
end)

exports('addLocalEntity', function(entities, options)
    Api.AddKeyed(caller(), 'local', 'addLocalEntity', entities, Translate(options))
end)

exports('removeLocalEntity', function(entities, names)
    Api.RemoveKeyed(caller(), 'local', 'removeLocalEntity', entities, names)
end)

exports('addSphereZone', function(input)
    return addZone(Shape.Sphere, input)
end)

exports('addBoxZone', function(input)
    return addZone(Shape.Box, input)
end)

exports('addPolyZone', function(input)
    return addZone(Shape.Poly, input)
end)

exports('removeZone', function(key)
    Registry.RemoveZone(caller(), key)
end)

exports('zoneExists', function(key)
    return Registry.ZoneExists(key)
end)

exports('disableTargeting', function(state)
    Api.Disable(caller(), state)
end)

exports('isActive', function()
    return UgTarget.Internal.Target ~= nil and UgTarget.Internal.Target.IsOpen()
end)
