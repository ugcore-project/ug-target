--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Where options live: per entity kind, model, networked entity, local entity, and zone.

---@class UgTarget.Internal.Registry
local Registry = {}
UgTarget.Internal.Registry = Registry

local Shapes = UgTarget.Internal.Shapes
local Kind = UgTarget.Enums.Kind
local Shape = UgTarget.Enums.Shape

local MAX_ZONES = 4096

---@alias UgTargetBucket 'global'|'model'|'entity'|'local'

---@class UgTargetZone : UgTargetZoneShape
---@field id integer
---@field name? string
---@field resource string
---@field options UgTargetOption[]
---@field debug boolean
---@field center vector3

---@type table<UgTargetBucket, table<any, UgTargetOption[]>>
local buckets = {
    global = {},
    model = {},
    entity = {},
    ['local'] = {},
}
---@type table<integer, UgTargetZone>
local zones = {}
local zoneCount = 0
local nextZone = 0
-- Bumped on every change, so the scanner knows when to rebuild the menu.
local revision = 0

---@return integer
function Registry.Revision()
    return revision
end

---@param level integer
---@param message string
---@param ... any
local function raise(level, message, ...)
    error('[ug-target] ' .. message:format(...), level + 1)
end

---Adds options under a key. Options with the name of an existing option of the same resource replace it.
---@param bucket UgTargetBucket
---@param key any
---@param options UgTargetOption[]
function Registry.Add(bucket, key, options)
    local list = buckets[bucket][key] or {}

    for _, option in ipairs(options) do
        local replaced = false

        for index, existing in ipairs(list) do
            if existing.name == option.name and existing.resource == option.resource then
                list[index], replaced = option, true

                break
            end
        end

        if not replaced then
            list[#list + 1] = option
        end
    end

    buckets[bucket][key] = list
    revision = revision + 1
end

---@param list UgTargetOption[]
---@param keep fun(option: UgTargetOption): boolean
---@return UgTargetOption[]? rest nil when nothing is left
---@return integer removed
local function filter(list, keep)
    local rest, removed = {}, 0

    for _, option in ipairs(list) do
        if keep(option) then
            rest[#rest + 1] = option
        else
            removed = removed + 1
        end
    end

    return #rest > 0 and rest or nil, removed
end

---Removes options of a resource under a key: the named ones, or all of them.
---@param bucket UgTargetBucket
---@param key any
---@param resource string
---@param names? table<string, boolean>
---@return integer removed
function Registry.Remove(bucket, key, resource, names)
    local list = buckets[bucket][key]

    if not list then
        return 0
    end

    local rest, removed = filter(list, function(option)
        return option.resource ~= resource or (names ~= nil and not names[option.name])
    end)

    buckets[bucket][key] = rest

    if removed > 0 then
        revision = revision + 1
    end

    return removed
end

---@param bucket UgTargetBucket
---@param key any
---@return UgTargetOption[]?
function Registry.Get(bucket, key)
    return buckets[bucket][key]
end

---@param where string
---@param field string
---@param point any
---@return vector3
local function checkPoint(where, field, point)
    if type(point) ~= 'vector3' then
        raise(4, '%s: %s MUST be a vector3', where, field)
    end

    return point
end

---@param where string
---@param resource string
---@param shape UgTargetShape
---@param input table
---@param options UgTargetOption[]
---@return integer id
function Registry.AddZone(where, resource, shape, input, options)
    if zoneCount >= MAX_ZONES then
        raise(3, '%s: at most %d zones', where, MAX_ZONES)
    end

    if input.name ~= nil and (type(input.name) ~= 'string' or input.name == '' or #input.name > 64) then
        raise(3, '%s: name MUST be a string of 1 to 64 characters', where)
    end

    ---@type UgTargetZone
    local zone = {
        id = 0, name = input.name, resource = resource, options = options, debug = input.debug == true,
        shape = shape, coords = vector3(0, 0, 0), center = vector3(0, 0, 0),
    }

    if shape == Shape.Sphere then
        zone.coords = checkPoint(where, 'coords', input.coords)

        if type(input.radius) ~= 'number' or input.radius <= 0 or input.radius > 100 then
            raise(3, '%s: radius MUST be a number above 0 and at most 100', where)
        end

        zone.radius = input.radius
        zone.center = zone.coords
    elseif shape == Shape.Box then
        zone.coords = checkPoint(where, 'coords', input.coords)

        local size = input.size or vector3(2.0, 2.0, 2.0)

        if type(size) ~= 'vector3' or size.x <= 0 or size.y <= 0 or size.z <= 0 or size.x > 200 or size.y > 200 or size.z > 200 then
            raise(3, '%s: size MUST be a vector3 with sides above 0 and at most 200', where)
        end

        if input.rotation ~= nil and type(input.rotation) ~= 'number' then
            raise(3, '%s: rotation MUST be a number of degrees', where)
        end

        zone.size, zone.rotation = size, input.rotation or 0.0
        zone.center = zone.coords
    elseif shape == Shape.Poly then
        local points = input.points

        if type(points) ~= 'table' or #points < 3 or #points > 64 then
            raise(3, '%s: points MUST list 3 to 64 vector3 or vector2 values', where)
        end

        local copy, lowest = {}, math.huge

        for index, point in ipairs(points) do
            if type(point) ~= 'vector3' and type(point) ~= 'vector2' then
                raise(3, '%s: points MUST be vector3 or vector2 values', where)
            end

            copy[index] = point
            lowest = math.min(lowest, type(point) == 'vector3' and point.z or math.huge)
        end

        local thickness = input.thickness or 4.0

        if type(thickness) ~= 'number' or thickness <= 0 or thickness > 200 then
            raise(3, '%s: thickness MUST be a number above 0 and at most 200', where)
        end

        zone.points = copy
        zone.minZ = input.minZ or (lowest ~= math.huge and lowest - thickness / 2 or nil)
        zone.maxZ = input.maxZ or (lowest ~= math.huge and lowest + thickness / 2 or nil)
        zone.center = Shapes.PolyCenter(copy, zone.minZ or zone.maxZ or 0.0, zone.maxZ or zone.minZ or 0.0)
        zone.coords = zone.center
    end

    nextZone = nextZone + 1
    zoneCount = zoneCount + 1
    zone.id = nextZone
    zones[zone.id] = zone
    revision = revision + 1

    return zone.id
end

---Removes a zone of the resource by id, or every zone of the resource with that name.
---@param resource string
---@param key integer|string
---@return boolean removed
function Registry.RemoveZone(resource, key)
    local removed = false

    for id, zone in pairs(zones) do
        if zone.resource == resource and (id == key or zone.name == key) then
            zones[id] = nil
            zoneCount = zoneCount - 1
            removed = true
        end
    end

    if removed then
        revision = revision + 1
    end

    return removed
end

---@param key integer|string
---@return boolean
function Registry.ZoneExists(key)
    for id, zone in pairs(zones) do
        if id == key or zone.name == key then
            return true
        end
    end

    return false
end

---@param a vector3
---@param b vector3
---@return number
local function distanceSquared(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z

    return dx * dx + dy * dy + dz * dz
end

---Zones that contain a point, nearest first.
---@param point vector3
---@return UgTargetZone[]
function Registry.ZonesAt(point)
    local found = {}

    for _, zone in pairs(zones) do
        if Shapes.Contains(zone, point) then
            found[#found + 1] = zone
        end
    end

    if #found > 1 then
        table.sort(found, function(a, b)
            local da, db = distanceSquared(a.center, point), distanceSquared(b.center, point)

            return da < db or (da == db and a.id < b.id)
        end)
    end

    return found
end

---@return table<integer, UgTargetZone>
function Registry.Zones()
    return zones
end

---Every option list that applies to an entity: its kind, its model, its network id and its handle.
---@param kind UgTargetKind
---@param model? integer
---@param netId? integer
---@param entity? integer
---@return UgTargetOption[][]
function Registry.ForEntity(kind, model, netId, entity)
    local lists = {}

    lists[#lists + 1] = buckets.global[kind]

    if model then
        lists[#lists + 1] = buckets.model[model]
    end

    if netId then
        lists[#lists + 1] = buckets.entity[netId]
    end

    if entity then
        lists[#lists + 1] = buckets['local'][entity]
    end

    return lists
end

---Removes everything a resource registered.
---@param resource string
---@return integer removed options and zones
function Registry.RemoveResource(resource)
    local count = 0

    for bucket in pairs(buckets) do
        for key in pairs(buckets[bucket]) do
            count = count + Registry.Remove(bucket, key, resource, nil)
        end
    end

    for id, zone in pairs(zones) do
        if zone.resource == resource then
            zones[id] = nil
            zoneCount = zoneCount - 1
            count = count + 1
        end
    end

    revision = revision + 1

    return count
end

Registry.EntityKinds = { Kind.Ped, Kind.Vehicle, Kind.Object, Kind.Player }
