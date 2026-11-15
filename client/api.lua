--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The client API, as exports. Options belong to the resource that added them and leave with it.

---@class UgTarget.Internal.Api
local Api = {}
UgTarget.Internal.Api = Api

local Options = UgTarget.Internal.Options
local Registry = UgTarget.Internal.Registry
local Kind = UgTarget.Enums.Kind
local Shape = UgTarget.Enums.Shape

local RESOURCE = GetCurrentResourceName()

local ZONE_EXPORTS = {
    [Shape.Sphere] = 'AddSphereZone',
    [Shape.Box] = 'AddBoxZone',
    [Shape.Poly] = 'AddPolyZone',
}

---@type table<string, boolean> resources that disabled targeting
local disabledBy = {}

---@param level integer
---@param message string
---@param ... any
local function raise(level, message, ...)
    error('[ug-target] ' .. message:format(...), level + 1)
end

---@return string
local function caller()
    return GetInvokingResource() or RESOURCE
end

---@param where string
---@param value any
---@param check fun(item: any): any converts one key, nil when invalid
---@param what string
---@return any[]
local function keysOf(where, value, check, what)
    local list = type(value) == 'table' and value or { value }
    local keys = {}

    if #list == 0 or #list > 512 then
        raise(4, '%s: pass one %s or a list of 1 to 512', where, what)
    end

    for index, item in ipairs(list) do
        local key = check(item)

        if key == nil then
            raise(4, '%s: %s %d is invalid', where, what, index)
        end

        keys[index] = key
    end

    return keys
end

---@param item any
---@return integer?
local function modelKey(item)
    if type(item) == 'string' and item ~= '' then
        return joaat(item)
    end

    return math.type(item) == 'integer' and item or nil
end

---@param item any
---@return integer?
local function handleKey(item)
    return math.type(item) == 'integer' and item > 0 and item or nil
end

---@param resource string
---@param kind UgTargetKind
---@param options table
function Api.AddGlobal(resource, kind, options)
    Registry.Add('global', kind, Options.Normalize('AddGlobal' .. kind, resource, options))
end

---@param resource string
---@param kind UgTargetKind
---@param names any
---@return integer removed
function Api.RemoveGlobal(resource, kind, names)
    return Registry.Remove('global', kind, resource, Options.NameSet('RemoveGlobal', names))
end

---@param resource string
---@param bucket UgTargetBucket
---@param where string
---@param keys any
---@param options table
function Api.AddKeyed(resource, bucket, where, keys, options)
    local check = bucket == 'model' and modelKey or handleKey
    local list = keysOf(where, keys, check, bucket == 'model' and 'model' or 'entity')
    local normalized = Options.Normalize(where, resource, options)

    for _, key in ipairs(list) do
        Registry.Add(bucket, key, normalized)
    end
end

---@param resource string
---@param bucket UgTargetBucket
---@param where string
---@param keys any
---@param names any
---@return integer removed
function Api.RemoveKeyed(resource, bucket, where, keys, names)
    local check = bucket == 'model' and modelKey or handleKey
    local set = Options.NameSet(where, names)
    local removed = 0

    for _, key in ipairs(keysOf(where, keys, check, bucket == 'model' and 'model' or 'entity')) do
        removed = removed + Registry.Remove(bucket, key, resource, set)
    end

    return removed
end

---@param resource string
---@param shape UgTargetShape
---@param input table
---@return integer id
function Api.AddZone(resource, shape, input)
    local where = ZONE_EXPORTS[shape]

    if type(input) ~= 'table' then
        raise(3, '%s: MUST receive a table', where)
    end

    return Registry.AddZone(where, resource, shape, input, Options.Normalize(where, resource, input.options))
end

---Turns targeting off while any resource asks it to.
---@param resource string
---@param state boolean
function Api.Disable(resource, state)
    disabledBy[resource] = state == true or nil
end

---@return boolean
function Api.IsDisabled()
    return next(disabledBy) ~= nil
end

---@param resource string
function Api.ForgetResource(resource)
    disabledBy[resource] = nil
end

local GLOBALS = {
    Ped = Kind.Ped, Vehicle = Kind.Vehicle, Object = Kind.Object, Player = Kind.Player,
}

for suffix, kind in pairs(GLOBALS) do
    exports('AddGlobal' .. suffix, function(options)
        Api.AddGlobal(caller(), kind, options)
    end)

    exports('RemoveGlobal' .. suffix, function(names)
        return Api.RemoveGlobal(caller(), kind, names)
    end)
end

exports('AddModel', function(models, options)
    Api.AddKeyed(caller(), 'model', 'AddModel', models, options)
end)

exports('RemoveModel', function(models, names)
    return Api.RemoveKeyed(caller(), 'model', 'RemoveModel', models, names)
end)

exports('AddEntity', function(netIds, options)
    Api.AddKeyed(caller(), 'entity', 'AddEntity', netIds, options)
end)

exports('RemoveEntity', function(netIds, names)
    return Api.RemoveKeyed(caller(), 'entity', 'RemoveEntity', netIds, names)
end)

exports('AddLocalEntity', function(entities, options)
    Api.AddKeyed(caller(), 'local', 'AddLocalEntity', entities, options)
end)

exports('RemoveLocalEntity', function(entities, names)
    return Api.RemoveKeyed(caller(), 'local', 'RemoveLocalEntity', entities, names)
end)

exports('AddSphereZone', function(input)
    return Api.AddZone(caller(), Shape.Sphere, input)
end)

exports('AddBoxZone', function(input)
    return Api.AddZone(caller(), Shape.Box, input)
end)

exports('AddPolyZone', function(input)
    return Api.AddZone(caller(), Shape.Poly, input)
end)

exports('RemoveZone', function(key)
    return Registry.RemoveZone(caller(), key)
end)

exports('ZoneExists', function(key)
    return Registry.ZoneExists(key)
end)

exports('Disable', function(state)
    Api.Disable(caller(), state)
end)

exports('IsActive', function()
    return UgTarget.Internal.Target ~= nil and UgTarget.Internal.Target.IsOpen()
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= RESOURCE then
        Registry.RemoveResource(resource)
        Api.ForgetResource(resource)
    end
end)
