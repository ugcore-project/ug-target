--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Option checks. Options come from other resources: every mistake raises at registration, with the export name,
-- so the developer sees it at once instead of a menu that silently misbehaves.

---@class UgTarget.Internal.Options
local Options = {}
UgTarget.Internal.Options = Options

local Conditions = UgTarget.Internal.Conditions

local MAX_OPTIONS = 64
local MAX_HOLD = 10000
local MAX_COOLDOWN = 3600000
local MAX_DISTANCE = 20.0
local NAME_PATTERN = '^[%w_%-%.:]+$'
local ACTION_PATTERN = '^[%w_%-]+:[%w_%-]+$'
local EXPORT_PATTERN = '^[%w_%-]+%.[%w_]+$'

local STRINGS = {
    label = 64, icon = 64, iconColor = 32, description = 128, badge = 16, event = 128, serverEvent = 128,
    command = 128, menu = 48, openMenu = 48,
}
local FUNCTIONS = {
    canInteract = true,
    onSelect = true,
    onResult = true,
}
local KNOWN = {
    name = true, label = true, icon = true, iconColor = true, description = true, badge = true, distance = true,
    bones = true, conditions = true, canInteract = true, onSelect = true, onResult = true, event = true,
    serverEvent = true, command = true, export = true, serverAction = true, hold = true, cooldown = true, menu = true,
    openMenu = true, order = true, keepOpen = true, data = true,
}
local KNOWN_NAMES = {}

for name in pairs(KNOWN) do
    KNOWN_NAMES[#KNOWN_NAMES + 1] = name
end

table.sort(KNOWN_NAMES)

-- What an option does when picked. One of them is required.
local EFFECTS = { 'onSelect', 'event', 'serverEvent', 'command', 'export', 'serverAction', 'openMenu' }

---@class UgTargetOption
---@field id integer unique per registration
---@field resource string the resource that registered it
---@field name string
---@field label string
---@field icon? string
---@field iconColor? string
---@field description? string
---@field badge? string
---@field distance? number
---@field bones? string[]
---@field conditions? UgTargetConditions
---@field canInteract? fun(context: UgTargetContext): boolean?
---@field onSelect? fun(context: UgTargetContext)
---@field onResult? fun(ok: boolean, value: any, errorCode: string?)
---@field event? string
---@field serverEvent? string
---@field command? string
---@field export? string `resource.function`
---@field serverAction? string `resource:Name`, registered with RegisterAction on the server
---@field hold integer
---@field cooldown integer
---@field menu? string the submenu this option belongs to
---@field openMenu? string the submenu this option opens
---@field order integer
---@field keepOpen boolean
---@field data? table developer data passed back in the context
---@field compat? boolean registered through the ox_target exports

---@class UgTargetSettings client config from GlobalState['ug-target:Config'], see server/config.default.lua
---@field trigger UgTargetTrigger
---@field key string
---@field layout UgTargetLayout
---@field maxDistance number
---@field defaultDistance number
---@field showDisabled boolean
---@field outline boolean
---@field outlineColor integer[]
---@field sounds boolean
---@field allowWhileDowned boolean
---@field allowInVehicle boolean
---@field debug boolean
---@field cursor boolean
---@field numberKeys boolean
---@field soundEffects table<UgTargetSound, { name: string, set: string }>
---@field theme table
---@field optionColors string[]
---@field look table

---@class UgTargetContext
---@field kind UgTargetKind
---@field coords vector3 where the aim hit
---@field distance number from the player's ped to `coords`
---@field entity? integer
---@field model? integer
---@field netId? integer
---@field bone? integer
---@field zone? string|integer
---@field name string the option name
---@field data? table

local nextId = 0

---@param level integer
---@param message string
---@param ... any
local function raise(level, message, ...)
    error('[ug-target] ' .. message:format(...), level + 1)
end

---Functions from other resources arrive as callable tables.
---@param value any
---@return boolean
function Options.IsCallable(value)
    if type(value) == 'function' then
        return true
    end

    local meta = type(value) == 'table' and getmetatable(value)

    return type(meta) == 'table' and meta.__call ~= nil
end

---@param where string
---@param resource string
---@param input table
---@param index integer
---@return UgTargetOption
local function normalize(where, resource, input, index)
    local at = ('%s option %d'):format(where, index)

    if type(input) ~= 'table' then
        raise(5, '%s MUST be a table', at)
    end

    for key in pairs(input) do
        if not KNOWN[key] then
            local suggestion = type(key) == 'string' and UgLib.String.Suggest(key, KNOWN_NAMES) or nil

            raise(5, '%s: unknown field "%s".%s', at, tostring(key), suggestion and (' Did you mean "%s"?'):format(suggestion) or '')
        end
    end

    for key, max in pairs(STRINGS) do
        local value = input[key]

        if value ~= nil and (type(value) ~= 'string' or value == '' or #value > max) then
            raise(5, '%s: %s MUST be a string of 1 to %d characters', at, key, max)
        end
    end

    if input.label == nil then
        raise(5, '%s: label is required', at)
    end

    local name = input.name

    if name == nil then
        name = ('%s_%d'):format(resource, index)
    elseif type(name) ~= 'string' or #name > 64 or not name:find(NAME_PATTERN) then
        raise(5, '%s: name MUST be 1 to 64 letters, digits or _ - . :', at)
    end

    for key in pairs(FUNCTIONS) do
        if input[key] ~= nil and not Options.IsCallable(input[key]) then
            raise(5, '%s: %s MUST be a function', at, key)
        end
    end

    if input.distance ~= nil and (type(input.distance) ~= 'number' or input.distance <= 0 or input.distance > MAX_DISTANCE) then
        raise(5, '%s: distance MUST be a number above 0 and at most %d', at, MAX_DISTANCE)
    end

    local bones = nil

    if input.bones ~= nil then
        bones = type(input.bones) == 'string' and { input.bones } or input.bones

        if type(bones) ~= 'table' or #bones == 0 or #bones > 32 then
            raise(5, '%s: bones MUST be a bone name or 1 to 32 of them', at)
        end

        for _, bone in ipairs(bones) do
            if type(bone) ~= 'string' or bone == '' or #bone > 64 then
                raise(5, '%s: bones MUST be bone names such as "door_dside_f"', at)
            end
        end
    end

    if input.serverAction ~= nil and (type(input.serverAction) ~= 'string' or #input.serverAction > 96 or not input.serverAction:find(ACTION_PATTERN)) then
        raise(5, '%s: serverAction MUST be "<resource>:<name>"', at)
    end

    if input.export ~= nil and (type(input.export) ~= 'string' or #input.export > 128 or not input.export:find(EXPORT_PATTERN)) then
        raise(5, '%s: export MUST be "<resource>.<function>"', at)
    end

    if input.serverAction and input.serverEvent then
        raise(5, '%s: use serverAction or serverEvent, not both', at)
    end

    for _, key in ipairs({ 'hold', 'cooldown', 'order' }) do
        local value = input[key]
        local max = key == 'hold' and MAX_HOLD or key == 'cooldown' and MAX_COOLDOWN or 1000

        if value ~= nil and (math.type(value) ~= 'integer' or value < (key == 'order' and -1000 or 0) or value > max) then
            raise(5, '%s: %s MUST be an integer of at most %d', at, key, max)
        end
    end

    if input.keepOpen ~= nil and type(input.keepOpen) ~= 'boolean' then
        raise(5, '%s: keepOpen MUST be a boolean', at)
    end

    if input.data ~= nil and type(input.data) ~= 'table' then
        raise(5, '%s: data MUST be a table', at)
    end

    if input.openMenu ~= nil and input.openMenu == input.menu then
        raise(5, '%s: an option MUST NOT open its own menu', at)
    end

    local hasEffect = false

    for _, key in ipairs(EFFECTS) do
        if input[key] ~= nil then
            hasEffect = true
        end
    end

    if not hasEffect then
        raise(5, '%s: set onSelect, event, command, export, serverAction or openMenu', at)
    end

    nextId = nextId + 1

    ---@type UgTargetOption
    return {
        id = nextId,
        resource = resource,
        name = name,
        label = input.label,
        icon = input.icon,
        iconColor = input.iconColor,
        description = input.description,
        badge = input.badge,
        distance = input.distance,
        bones = bones,
        conditions = Conditions.Normalize(at, input.conditions),
        canInteract = input.canInteract,
        onSelect = input.onSelect,
        onResult = input.onResult,
        event = input.event,
        serverEvent = input.serverEvent,
        command = input.command,
        export = input.export,
        serverAction = input.serverAction,
        hold = input.hold or 0,
        cooldown = input.cooldown or 0,
        menu = input.menu,
        openMenu = input.openMenu,
        order = input.order or 0,
        keepOpen = input.keepOpen == true,
        data = input.data,
    }
end

---Checks one option or a list of options. Raises on mistakes.
---@param where string the export name, for errors
---@param resource string
---@param input table one option or a list
---@return UgTargetOption[]
function Options.Normalize(where, resource, input)
    if type(input) ~= 'table' then
        raise(3, '%s: options MUST be a table or a list of tables', where)
    end

    local list = input[1] ~= nil and input or { input }

    if #list > MAX_OPTIONS then
        raise(3, '%s: at most %d options per call', where, MAX_OPTIONS)
    end

    local result = {}

    for index, option in ipairs(list) do
        result[index] = normalize(where, resource, option, index)
    end

    return result
end

---Names to remove: nil for every option, a name or a list of names.
---@param where string
---@param names any
---@return table<string, boolean>?
function Options.NameSet(where, names)
    if names == nil then
        return nil
    end

    local list = type(names) == 'string' and { names } or names

    if type(list) ~= 'table' then
        raise(3, '%s: names MUST be a name or a list of names', where)
    end

    local set = {}

    for _, name in ipairs(list) do
        if type(name) ~= 'string' then
            raise(3, '%s: names MUST be strings', where)
        end

        set[name] = true
    end

    return set
end
