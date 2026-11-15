--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The page bridge. The page is untrusted: every callback body is checked here before the target sees it.

---@class UgTarget.Internal.Nui
local Nui = {}
UgTarget.Internal.Nui = Nui

local Enums = UgTarget.Enums
local Action = Enums.NuiAction
local Callback = Enums.NuiCallback
local Errors = UgCore.Enums.Errors
local Schema = UgCore.Schema

-- Callbacks per second the page MAY send. Hover sends at most one per pointer move over a new row.
local EVENTS_PER_SECOND = 30
local MAX_INDEX = 64

---@param enum table<string, any>
---@return string[]
local function valuesOf(enum)
    local values = {}

    for _, value in pairs(enum) do
        values[#values + 1] = value
    end

    table.sort(values)

    return values
end

---Labels the page shows, from locales/<code>.json under `page`. tests/nui.lua checks the file has exactly these.
---@return string[]
local function labelKeys()
    local keys = { 'back', 'hold', 'cursor', 'select', 'done', 'failed', 'empty' }

    for _, value in ipairs(valuesOf(Enums.Reason)) do
        keys[#keys + 1] = 'reason.' .. value
    end

    for _, code in ipairs({
        Errors.InvalidArgs,
        Errors.NotFound,
        Errors.NoPermission,
        Errors.RateLimited,
        Errors.Timeout,
        Errors.InternalError,
    }) do
        keys[#keys + 1] = 'error.' .. code
    end

    return keys
end

Nui.LabelKeys = labelKeys()

local ready = false
---@type table[] messages sent before the page was ready
local queue = {}
local budget = {
    second = -1,
    count = 0,
}
---@type table<UgTargetNuiCallback, fun(value: any)>
local handlers = {}
---@type UgTargetSettings?
local settings = nil
local translate = nil

---A label in the configured language.
---@param key string such as `page.back`
---@param vars? table<string, any> values for `{name}` placeholders
---@return string
function Nui.Label(key, vars)
    translate = translate or UgLib.Locale.Create()

    return translate(key, vars)
end

---Sends a message, or queues it until the page is ready.
---@param action UgTargetNuiAction
---@param payload? table
function Nui.Send(action, payload)
    local message = {
        action = action,
        payload = payload,
    }

    if ready then
        SendNUIMessage(message)
    else
        queue[#queue + 1] = message
    end
end

---ug-lib's theme with the owner's ug-target overrides on top. Colors merge token by token.
---@param base table? ug-lib's theme
---@param own table? the ug-target theme
---@return table
function Nui.Theme(base, own)
    base = type(base) == 'table' and base or {}
    own = type(own) == 'table' and own or {}

    local colors = {}

    -- Not ipairs over both: it stops at a missing ug-lib table and drops the owner colors.
    for index = 1, 2 do
        local source = index == 1 and base.colors or own.colors

        if type(source) == 'table' then
            for token, color in pairs(source) do
                colors[token] = color
            end
        end
    end

    return {
        mode = own.mode or base.mode,
        colors = colors,
        radius = own.radius or base.radius,
        font = own.font or base.font,
        scale = own.scale or base.scale,
    }
end

---The page config: the theme, the layout, the look, labels in the configured language.
---@return table
local function config()
    local libConfig = GlobalState[UgLib.Enums.GlobalState.Config]
    local labels = {}

    for _, key in ipairs(Nui.LabelKeys) do
        labels[key] = Nui.Label('page.' .. key)
    end

    return {
        theme = Nui.Theme(type(libConfig) == 'table' and libConfig.theme or nil, settings and settings.theme),
        labels = labels,
        locale = UgLib.Locale.GetCode(),
        layout = settings and settings.layout or Enums.Layout.Anchored,
        look = settings and settings.look or nil,
        optionColors = settings and settings.optionColors or nil,
        cursor = not settings or settings.cursor,
        numberKeys = not settings or settings.numberKeys,
    }
end

---Stores the client settings the page config needs. Sends the config again when the page is up.
---@param values UgTargetSettings
function Nui.Configure(values)
    settings = values

    if ready then
        SendNUIMessage({
            action = Action.Config,
            payload = config(),
        })
    end
end

---Sets who receives a page intent.
---@param callback UgTargetNuiCallback
---@param handler fun(value: any)
function Nui.On(callback, handler)
    handlers[callback] = handler
end

---@return boolean
local function withinBudget()
    local second = GetGameTimer() // 1000

    if budget.second ~= second then
        budget.second, budget.count = second, 0
    end

    budget.count = budget.count + 1

    return budget.count <= EVENTS_PER_SECOND
end

local INDEX = Schema.Integer({
    min = 1,
    max = MAX_INDEX,
})

---@param body any
---@return integer?
local function readIndex(body)
    if type(body) ~= 'table' then
        return nil
    end

    local ok, value = Schema.Check(INDEX, body.index)

    return ok and value or nil
end

---@return boolean
local function always()
    return true
end

local READERS = {
    [Callback.Hover] = readIndex,
    [Callback.Pick] = readIndex,
    [Callback.Release] = always,
    [Callback.Back] = always,
}

for name, read in pairs(READERS) do
    RegisterNUICallback(name, function(body, cb)
        local value = nil

        if withinBudget() then
            value = read(body)
        end

        if value ~= nil and handlers[name] then
            handlers[name](value)
        end

        cb({
            ok = value ~= nil,
        })
    end)
end

RegisterNUICallback(Callback.Ready, function(_, cb)
    ready = true
    SendNUIMessage({
        action = Action.Config,
        payload = config(),
    })

    for _, message in ipairs(queue) do
        SendNUIMessage(message)
    end

    queue = {}
    cb({
        ok = true,
    })
end)
