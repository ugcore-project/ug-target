--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Turns the aim into a target, and a target into the options the menu shows.

---@class UgTarget.Internal.Scanner
local Scanner = {}
UgTarget.Internal.Scanner = Scanner

local Registry = UgTarget.Internal.Registry
local Conditions = UgTarget.Internal.Conditions
local Kind = UgTarget.Enums.Kind
local Reason = UgTarget.Enums.Reason

-- The camera sits behind the ped: the ray reaches this much further than maxDistance.
local CAMERA_REACH = 10.0
-- A bone counts when the aim hits within this many meters of it.
local BONE_RADIUS = 1.0

---@class UgTargetTarget
---@field key string identity: changes when the entity or the zones change
---@field kind UgTargetKind
---@field coords vector3 where the aim hit
---@field distance number from the ped to `coords`
---@field entity? integer
---@field model? integer
---@field netId? integer
---@field zones UgTargetZone[]

---@class UgTargetEntry
---@field option UgTargetOption
---@field enabled boolean
---@field reason? UgTargetReason
---@field context UgTargetContext

---@param a vector3
---@param b vector3
---@return number
local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@param entity integer
---@return UgTargetKind?
function Scanner.KindOf(entity)
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

---Casts from the camera. MUST run in a thread.
---@param maxDistance number
---@return UgRaycastResult result
---@return vector3 endPoint where the ray ends without a hit
function Scanner.Cast(maxDistance)
    local reach = maxDistance + CAMERA_REACH
    local from = GetGameplayCamCoord()
    local direction = UgLib.Math.RotationToDirection(GetGameplayCamRot(2))
    local endPoint = vector3(from.x + direction.x * reach, from.y + direction.y * reach, from.z + direction.z * reach)

    return UgLib.Raycast.FromCamera(reach), endPoint
end

---@param result UgRaycastResult
---@param endPoint vector3
---@param pedCoords vector3
---@return UgTargetTarget
function Scanner.Resolve(result, endPoint, pedCoords)
    local coords = result.hit and result.coords or endPoint
    local zones = Registry.ZonesAt(coords)
    ---@type UgTargetTarget
    local target = {
        key = '',
        kind = Kind.Zone,
        coords = coords,
        distance = distance(pedCoords, coords),
        zones = zones,
    }
    local entity = result.entity

    if entity and DoesEntityExist(entity) then
        local kind = Scanner.KindOf(entity)

        if kind then
            target.kind, target.entity, target.model = kind, entity, GetEntityModel(entity)

            if NetworkGetEntityIsNetworked(entity) then
                target.netId = NetworkGetNetworkIdFromEntity(entity)
            end
        end
    end

    local parts = { tostring(target.entity or 0) }

    for _, zone in ipairs(zones) do
        parts[#parts + 1] = tostring(zone.id)
    end

    target.key = table.concat(parts, ':')

    return target
end

---The nearest listed bone the aim hit, as a bone index.
---@param entity integer
---@param bones string[]
---@param coords vector3
---@return integer?
local function boneAt(entity, bones, coords)
    local best, bestDistance = nil, BONE_RADIUS

    for _, name in ipairs(bones) do
        local index = GetEntityBoneIndexByName(entity, name)

        if index and index ~= -1 then
            local position = GetEntityBonePosition_2(entity, index)
            local gap = distance(position, coords)

            if gap <= bestDistance then
                best, bestDistance = index, gap
            end
        end
    end

    return best
end

---Options to show for a target in a menu, sorted by `order`.
---@param target UgTargetTarget
---@param facts UgTargetFacts
---@param menu? string the open submenu, nil for the root
---@param coolingDown fun(option: UgTargetOption): boolean
---@param settings UgTargetSettings
---@return UgTargetEntry[]
function Scanner.Build(target, facts, menu, coolingDown, settings)
    ---@type UgTargetEntry[]
    local entries = {}

    ---@param option UgTargetOption
    ---@param zone? UgTargetZone
    local function consider(option, zone)
        if option.menu ~= menu then
            return
        end

        local reach = math.min(option.distance or settings.defaultDistance, settings.maxDistance)

        if target.distance > reach then
            return
        end

        local bone = nil

        if option.bones then
            bone = target.entity and boneAt(target.entity, option.bones, target.coords)

            if not bone then
                return
            end
        end

        ---@type UgTargetContext
        local context = {
            kind = zone and not target.entity and Kind.Zone or target.kind,
            coords = target.coords,
            distance = target.distance,
            entity = target.entity,
            model = target.model,
            netId = target.netId,
            bone = bone,
            zone = zone and (zone.name or zone.id) or nil,
            name = option.name,
            data = option.data,
        }

        local enabled, reason = Conditions.Check(option.conditions, facts)

        if enabled and option.canInteract then
            local ok, allowed = pcall(option.canInteract, context)

            if not ok then
                UgCore.Logger.Debug('canInteract of %s (%s) failed: %s', option.name, option.resource, tostring(allowed))

                return
            end

            -- canInteract hides: it answers whether the option makes sense here at all.
            if not allowed then
                return
            end
        end

        if enabled and coolingDown(option) then
            enabled, reason = false, Reason.Cooldown
        end

        if not enabled and not settings.showDisabled then
            return
        end

        entries[#entries + 1] = {
            option = option,
            enabled = enabled,
            reason = reason,
            context = context,
        }
    end

    if target.entity then
        for _, list in ipairs(Registry.ForEntity(target.kind, target.model, target.netId, target.entity)) do
            for _, option in ipairs(list) do
                consider(option, nil)
            end
        end
    end

    for _, zone in ipairs(target.zones) do
        for _, option in ipairs(zone.options) do
            consider(option, zone)
        end
    end

    table.sort(entries, function(a, b)
        if a.option.order ~= b.option.order then
            return a.option.order < b.option.order
        end

        return a.option.id < b.option.id
    end)

    return entries
end

---Identity of what the page shows, to skip sending the same menu again. Never empty: an empty signature means
---nothing was sent, so an empty menu is sent too.
---@param entries UgTargetEntry[]
---@param menu? string
---@return string
function Scanner.Signature(entries, menu)
    local parts = { 'menu:' .. (menu or '') }

    for _, entry in ipairs(entries) do
        parts[#parts + 1] = ('%d%s%s'):format(entry.option.id, entry.enabled and '+' or '-', entry.reason or '')
    end

    return table.concat(parts, '|')
end

---What the page gets for each entry. Functions and developer data stay in Lua.
---@param entries UgTargetEntry[]
---@param cooldownLeft fun(option: UgTargetOption): integer
---@return table[]
function Scanner.Present(entries, cooldownLeft)
    local list = {}

    for index, entry in ipairs(entries) do
        local option = entry.option

        list[index] = {
            label = option.label,
            icon = option.icon,
            iconColor = option.iconColor,
            description = option.description,
            badge = option.badge,
            enabled = entry.enabled,
            reason = entry.reason,
            hold = option.hold,
            submenu = option.openMenu ~= nil,
            cooldown = entry.reason == Reason.Cooldown and cooldownLeft(option) or 0,
        }
    end

    return list
end
