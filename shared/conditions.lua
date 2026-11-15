--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Declarative conditions: job, gang, duty, items, vehicle. The client checks them to show options, the server checks
-- them again before a server action runs. Both use this code with their own facts.

---@class UgTarget.Internal.Conditions
local Conditions = {}
UgTarget.Internal.Conditions = Conditions

local Reason = UgTarget.Enums.Reason

local MAX_NAMES = 32
local MAX_GRADE = 1000
local MAX_COUNT = 1000000

---@class UgTargetConditions
---@field jobs? table<string, integer> job name to minimum grade
---@field gangs? table<string, integer> gang name to minimum grade
---@field groups? table<string, integer> job or gang name to minimum grade
---@field onDuty? boolean
---@field items? table<string, integer> item name to count
---@field anyItem? boolean one of the items is enough
---@field inVehicle? boolean

---@class UgTargetFacts
---@field job? { name: string, grade: integer, onDuty?: boolean }
---@field gang? { name: string, grade: integer }
---@field inVehicle boolean
---@field count fun(item: string): integer

---@param level integer
---@param message string
---@param ... any
local function raise(level, message, ...)
    error('[ug-target] ' .. message:format(...), level + 1)
end

---`'police'`, `{ 'police', 'ems' }` or `{ police = 2 }` to a map of name to minimum.
---@param where string
---@param field string
---@param value any
---@param minimum integer value for names given without one
---@param maximum integer
---@return table<string, integer>?
local function nameMap(where, field, value, minimum, maximum)
    if value == nil then
        return nil
    end

    local map, count = {}, 0

    local function add(name, amount)
        if type(name) ~= 'string' or name == '' or #name > 64 then
            raise(4, '%s: %s names MUST be non-empty strings of at most 64 characters', where, field)
        end

        if math.type(amount) ~= 'integer' or amount < minimum or amount > maximum then
            raise(4, '%s: %s.%s MUST be an integer from %d to %d', where, field, name, minimum, maximum)
        end

        count = count + 1

        if count > MAX_NAMES then
            raise(4, '%s: %s MUST list at most %d names', where, field, MAX_NAMES)
        end

        map[name] = amount
    end

    if type(value) == 'string' then
        add(value, minimum)
    elseif type(value) == 'table' then
        if value[1] ~= nil then
            for _, name in ipairs(value) do
                add(name, minimum)
            end
        else
            for name, amount in pairs(value) do
                add(name, amount)
            end
        end
    else
        raise(4, '%s: %s MUST be a name, a list of names or a map of names', where, field)
    end

    return next(map) and map or nil
end

local KNOWN = {
    job = true,
    gang = true,
    groups = true,
    onDuty = true,
    items = true,
    anyItem = true,
    inVehicle = true,
}

---Checks and normalizes conditions written by a developer. Raises on mistakes.
---@param where string such as `AddModel`, for errors
---@param input? table `{ job?, gang?, groups?, onDuty?, items?, anyItem?, inVehicle? }`
---@return UgTargetConditions?
function Conditions.Normalize(where, input)
    if input == nil then
        return nil
    end

    if type(input) ~= 'table' then
        raise(3, '%s: conditions MUST be a table', where)
    end

    for key in pairs(input) do
        if not KNOWN[key] then
            raise(3, '%s: unknown condition "%s"', where, tostring(key))
        end
    end

    for _, key in ipairs({ 'onDuty', 'anyItem', 'inVehicle' }) do
        if input[key] ~= nil and type(input[key]) ~= 'boolean' then
            raise(3, '%s: conditions.%s MUST be a boolean', where, key)
        end
    end

    ---@type UgTargetConditions
    local result = {
        jobs = nameMap(where, 'job', input.job, 0, MAX_GRADE),
        gangs = nameMap(where, 'gang', input.gang, 0, MAX_GRADE),
        groups = nameMap(where, 'groups', input.groups, 0, MAX_GRADE),
        onDuty = input.onDuty,
        items = nameMap(where, 'items', input.items, 1, MAX_COUNT),
        anyItem = input.anyItem,
        inVehicle = input.inVehicle,
    }

    return next(result) and result or nil
end

---@param map table<string, integer>
---@param role? { name: string, grade: integer }
---@return boolean
local function matches(map, role)
    if not role then
        return false
    end

    local minimum = map[role.name]

    return minimum ~= nil and (role.grade or 0) >= minimum
end

---Checks conditions against the player's facts.
---@param conditions? UgTargetConditions
---@param facts UgTargetFacts
---@return boolean ok
---@return UgTargetReason? reason the first condition that failed
function Conditions.Check(conditions, facts)
    if not conditions then
        return true, nil
    end

    if conditions.jobs and not matches(conditions.jobs, facts.job) then
        return false, Reason.Job
    end

    if conditions.gangs and not matches(conditions.gangs, facts.gang) then
        return false, Reason.Gang
    end

    if conditions.groups and not matches(conditions.groups, facts.job) and not matches(conditions.groups, facts.gang) then
        return false, Reason.Job
    end

    if conditions.onDuty ~= nil then
        local onDuty = facts.job ~= nil and facts.job.onDuty == true

        if onDuty ~= conditions.onDuty then
            return false, Reason.Duty
        end
    end

    if conditions.inVehicle ~= nil and facts.inVehicle ~= conditions.inVehicle then
        return false, Reason.Vehicle
    end

    if conditions.items then
        local any, all = false, true

        for name, count in pairs(conditions.items) do
            if facts.count(name) >= count then
                any = true
            else
                all = false
            end
        end

        local passed = all

        if conditions.anyItem then
            passed = any
        end

        if not passed then
            return false, Reason.Items
        end
    end

    return true, nil
end
