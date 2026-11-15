--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Zone math, pure Lua so the server checks the same shapes the client aims at.

---@class UgTarget.Internal.Shapes
local Shapes = {}
UgTarget.Internal.Shapes = Shapes

local Shape = UgTarget.Enums.Shape

---@class UgTargetZoneShape
---@field shape UgTargetShape
---@field coords vector3 center
---@field radius? number sphere
---@field size? vector3 box: width, length, height
---@field rotation? number box heading in degrees
---@field points? vector2[] poly corners
---@field minZ? number poly floor
---@field maxZ? number poly ceiling

---@param point vector3
---@param polygon vector2[]
---@return boolean
local function insidePolygon(point, polygon)
    local inside = false
    local count = #polygon
    local j = count

    for i = 1, count do
        local a, b = polygon[i], polygon[j]

        if (a.y > point.y) ~= (b.y > point.y) and point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x then
            inside = not inside
        end

        j = i
    end

    return inside
end

---True when `point` is inside the zone.
---@param zone UgTargetZoneShape
---@param point vector3
---@return boolean
function Shapes.Contains(zone, point)
    local center = zone.coords

    if zone.shape == Shape.Sphere then
        local dx, dy, dz = point.x - center.x, point.y - center.y, point.z - center.z
        local radius = zone.radius or 0

        return dx * dx + dy * dy + dz * dz <= radius * radius
    end

    if zone.shape == Shape.Box then
        local size = zone.size or vector3(1.0, 1.0, 1.0)
        local angle = -math.rad(zone.rotation or 0)
        local dx, dy = point.x - center.x, point.y - center.y
        local localX = dx * math.cos(angle) - dy * math.sin(angle)
        local localY = dx * math.sin(angle) + dy * math.cos(angle)

        return math.abs(localX) <= size.x / 2 and math.abs(localY) <= size.y / 2 and math.abs(point.z - center.z) <= size.z / 2
    end

    if zone.shape == Shape.Poly then
        if (zone.minZ and point.z < zone.minZ) or (zone.maxZ and point.z > zone.maxZ) then
            return false
        end

        return insidePolygon(point, zone.points or {})
    end

    return false
end

---The middle of a poly's corners, at the middle height.
---@param points vector2[]|vector3[]
---@param minZ number
---@param maxZ number
---@return vector3
function Shapes.PolyCenter(points, minZ, maxZ)
    local x, y = 0.0, 0.0

    for _, point in ipairs(points) do
        x, y = x + point.x, y + point.y
    end

    return vector3(x / #points, y / #points, (minZ + maxZ) / 2)
end
