--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Owner config: config.lua, copied from server/config.default.lua on the first start and never overwritten.
-- Owner values replace the defaults key by key. Clients get every value but actionMargin through GlobalState.

---@class UgTarget.Internal.Config
local Config = {}
UgTarget.Internal.Config = Config

local Schema = UgCore.Schema
local Enums = UgTarget.Enums

local RESOURCE = GetCurrentResourceName()
local OWNER_FILE = 'config.lua'
local DEFAULT_FILE = 'server/config.default.lua'
local STATE_KEY = 'ug-target:Config'
-- Server-only values, never replicated.
local SERVER_ONLY = {
    actionMargin = true,
}

---@param enum table<string, string>
---@return string[]
local function valuesOf(enum)
    local values = {}

    for _, value in pairs(enum) do
        values[#values + 1] = value
    end

    table.sort(values)

    return values
end

local BYTE = Schema.Integer({
    min = 0,
    max = 255,
})
local HEX = Schema.String({
    min = 7,
    max = 7,
    pattern = '^#%x%x%x%x%x%x$',
})
local HSL = Schema.String({
    min = 5,
    max = 24,
    pattern = '^%d+%.?%d* %d+%.?%d*%% %d+%.?%d*%%$',
})
local GAME_NAME = Schema.String({
    min = 1,
    max = 64,
    pattern = '^[%w_%-]+$',
})

-- ug-lib's theme tokens, then this page's own.
local THEME_TOKENS = {
    'background', 'foreground', 'card', 'cardForeground', 'popover', 'popoverForeground',
    'primary', 'primaryForeground', 'secondary', 'secondaryForeground', 'muted', 'mutedForeground',
    'accent', 'accentForeground', 'destructive', 'destructiveForeground', 'success', 'successForeground',
    'warning', 'warningForeground', 'border', 'input', 'ring',
    'brandTo', 'reticle',
}

---@param value string
---@return boolean ok
---@return string? message
local function size(value)
    if value:find('^%d*%.?%d+rem$') or value:find('^%d*%.?%d+px$') then
        return true, nil
    end

    return false, 'MUST be a size such as "0.75rem" or "12px"'
end

---@type { key: string, rule: UgSchemaRule }[]
local RULES = {
    {
        key = 'trigger',
        rule = Schema.Enum(valuesOf(Enums.Trigger)),
    },
    {
        key = 'key',
        rule = Schema.String({
            min = 1,
            max = 16,
            pattern = '^[%w_]+$',
        }),
    },
    {
        key = 'layout',
        rule = Schema.Enum(valuesOf(Enums.Layout)),
    },
    {
        key = 'maxDistance',
        rule = Schema.Number({
            min = 1,
            max = 20,
        }),
    },
    {
        key = 'defaultDistance',
        rule = Schema.Number({
            min = 0.5,
            max = 20,
        }),
    },
    {
        key = 'showDisabled',
        rule = Schema.Boolean(),
    },
    {
        key = 'outline',
        rule = Schema.Boolean(),
    },
    {
        key = 'outlineColor',
        rule = Schema.Array(BYTE, {
            min = 4,
            max = 4,
        }),
    },
    {
        key = 'sounds',
        rule = Schema.Boolean(),
    },
    {
        key = 'allowWhileDowned',
        rule = Schema.Boolean(),
    },
    {
        key = 'allowInVehicle',
        rule = Schema.Boolean(),
    },
    {
        key = 'actionMargin',
        rule = Schema.Number({
            min = 0,
            max = 10,
        }),
    },
    {
        key = 'debug',
        rule = Schema.Boolean(),
    },
    {
        key = 'cursor',
        rule = Schema.Boolean(),
    },
    {
        key = 'numberKeys',
        rule = Schema.Boolean(),
    },
    {
        key = 'soundEffects',
        rule = Schema.Map(Schema.Enum(valuesOf(Enums.Sound)), Schema.Object({
            name = GAME_NAME,
            set = GAME_NAME,
        }), {
            max = 8,
        }),
    },
    {
        key = 'theme',
        rule = Schema.Object({
            mode = Schema.Optional(Schema.Enum({ 'dark', 'light' })),
            colors = Schema.Optional(Schema.Map(Schema.Enum(THEME_TOKENS), HSL, {
                max = #THEME_TOKENS,
            })),
            radius = Schema.Optional(Schema.String({
                min = 3,
                max = 16,
                validate = size,
            })),
            font = Schema.Optional(Schema.Enum({ 'Inter' })),
            scale = Schema.Optional(Schema.Number({
                min = 0.75,
                max = 1.5,
            })),
        }),
    },
    {
        key = 'optionColors',
        rule = Schema.Array(HEX, {
            max = 16,
        }),
    },
    {
        key = 'look',
        rule = Schema.Object({
            cardWidth = Schema.Integer({
                min = 200,
                max = 480,
            }),
            cardOpacity = Schema.Number({
                min = 0,
                max = 1,
            }),
            blur = Schema.Boolean(),
            side = Schema.Enum(valuesOf(Enums.Side)),
            connector = Schema.Boolean(),
            pulse = Schema.Boolean(),
            reticle = Schema.Enum(valuesOf(Enums.Reticle)),
            hints = Schema.Boolean(),
            animations = Schema.Boolean(),
            resultDuration = Schema.Integer({
                min = 300,
                max = 5000,
            }),
        }),
    },
}

-- Tables that merge onto the defaults field by field.
local MERGED = {
    look = true,
}

---Runs owner code in a sandbox with only what a config needs.
---@param content string
---@param name? string file name in errors, config.lua by default
---@return boolean ok
---@return table? values
---@return string? message
local function run(content, name)
    local env = {
        vector2 = vector2, vector3 = vector3, vector4 = vector4,
        vec2 = vec2, vec3 = vec3, vec4 = vec4,
        tonumber = tonumber, tostring = tostring, type = type, pairs = pairs, ipairs = ipairs,
        math = setmetatable({}, {
            __index = math,
        }),
        string = setmetatable({}, {
            __index = string,
        }),
        table = setmetatable({}, {
            __index = table,
        }),
    }

    local chunk, syntaxError = load(content, '@' .. (name or OWNER_FILE), 't', env)

    if not chunk then
        return false, nil, tostring(syntaxError)
    end

    local ok, result = pcall(chunk)

    if not ok then
        return false, nil, tostring(result)
    end

    if type(result) ~= 'table' then
        return false, nil, 'MUST return a table'
    end

    return true, result, nil
end

---A fresh copy of the defaults, read from server/config.default.lua: the only place they live.
---@return table
function UgTarget.Internal.Defaults()
    local ok, values, message = run(LoadResourceFile(RESOURCE, DEFAULT_FILE) or '', DEFAULT_FILE)

    if not ok or not values then
        error(('[ug-target] %s: %s'):format(DEFAULT_FILE, tostring(message)), 2)
    end

    return values
end

---Checks merged values. Returns clean copies of every valid key.
---@param values table
---@return table clean
---@return string[] errors
function Config.Validate(values)
    local errors, clean, known, names = {}, {}, {}, {}

    for _, entry in ipairs(RULES) do
        known[entry.key] = true
        names[#names + 1] = entry.key

        local ok, checked, detail = Schema.Check(entry.rule, values[entry.key])

        if ok then
            clean[entry.key] = checked
        else
            local text = (detail or 'is invalid'):gsub('^value:? ?', '')

            errors[#errors + 1] = ('%s: %s'):format(entry.key, text)
        end
    end

    for key in pairs(values) do
        if not known[key] then
            local suggestion = type(key) == 'string' and UgLib.String.Suggest(key, names) or nil

            errors[#errors + 1] = ('unknown key "%s".%s'):format(tostring(key), suggestion and (' Did you mean "%s"?'):format(suggestion) or '')
        end
    end

    if clean.defaultDistance and clean.maxDistance and clean.defaultDistance > clean.maxDistance then
        errors[#errors + 1] = 'defaultDistance MUST NOT be greater than maxDistance'
    end

    table.sort(errors)

    return clean, errors
end

---@type table?
local current = nil

---Reads, merges and checks config.lua, generating it from the example when missing. Publishes the client values.
---@return boolean ok
---@return string[] errors
function Config.Load()
    local content = LoadResourceFile(RESOURCE, OWNER_FILE)

    if content == nil then
        local example = LoadResourceFile(RESOURCE, DEFAULT_FILE)

        if example and SaveResourceFile(RESOURCE, OWNER_FILE, example, -1) then
            UgCore.Logger.Info('Generated %s.', OWNER_FILE)
        end

        content = example
    end

    local values = UgTarget.Internal.Defaults()

    if content then
        local ok, owner, message = run(content)

        if not ok or not owner then
            current = nil

            return false, { ('%s: %s'):format(OWNER_FILE, tostring(message)) }
        end

        for key, value in pairs(owner) do
            if MERGED[key] and type(value) == 'table' and type(values[key]) == 'table' then
                for field, fieldValue in pairs(value) do
                    values[key][field] = fieldValue
                end
            else
                values[key] = value
            end
        end
    end

    local clean, errors = Config.Validate(values)

    for index, message in ipairs(errors) do
        errors[index] = ('%s: %s'):format(OWNER_FILE, message)
    end

    current = #errors == 0 and clean or nil

    if current then
        local shared = {}

        for key, value in pairs(current) do
            if not SERVER_ONLY[key] then
                shared[key] = value
            end
        end

        GlobalState:set(STATE_KEY, shared, true)
    end

    return current ~= nil, errors
end

---The loaded config. Raises before a successful Load.
---@return table
function Config.Get()
    if not current then
        error('[ug-target] Config.Get before a successful Config.Load', 2)
    end

    return current
end

Config.StateKey = STATE_KEY

---Runs owner code like Load does, for tests that compare server/config.default.lua with the defaults.
Config.Run = run
