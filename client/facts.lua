--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- What the local player is, for conditions. Read from ug-core statebags, so no export call per option.
-- These only decide what the menu shows: server actions check again on the server.

---@class UgTarget.Internal.Facts
local Facts = {}
UgTarget.Internal.Facts = Facts

local StateBags = UgCore.Enums.StateBags

---@param role any
---@return { name: string, grade: integer, onDuty?: boolean }?
local function roleOf(role)
    if type(role) ~= 'table' or type(role.name) ~= 'string' then
        return nil
    end

    return {
        name = role.name,
        grade = math.tointeger(role.grade) or 0,
        onDuty = role.onDuty == true,
    }
end

---Fresh facts. Item counts are read once per scan, on first use.
---@return UgTargetFacts
function Facts.Get()
    local state = LocalPlayer.state
    local counts = {}
    local inventory = UgCore.Modules.IsEnabled('inventory')

    return {
        job = roleOf(state[StateBags.Job]),
        gang = roleOf(state[StateBags.Gang]),
        inVehicle = IsPedInAnyVehicle(PlayerPedId(), false),
        count = function(item)
            if not inventory then
                return 0
            end

            if counts[item] == nil then
                local ok, count = pcall(UgCore.Inventory.Count, item)

                counts[item] = ok and math.tointeger(count) or 0
            end

            return counts[item]
        end,
    }
end

---True when the local player is downed or dead.
---@return boolean
function Facts.IsIncapacitated()
    local state = LocalPlayer.state[StateBags.DeathState]

    return state ~= nil and state ~= UgCore.Enums.DeathState.Alive
end
