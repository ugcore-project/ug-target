--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@type TestHelpers
local H = dofile('tests/helpers.lua')

---@param path string
---@return string
local function read(path)
    local handle = assert(io.open(path, 'rb'))
    local source = handle:read('a')

    handle:close()

    return source
end

---Decodes the JSON subset the locale files use: objects and strings. The json global is a mock in tests.
---@param source string
---@return table
local function decodeLocale(source)
    local position = 1

    local function skip()
        position = source:find('[^%s]', position) or #source + 1
    end

    local function expect(char)
        skip()
        assert(source:sub(position, position) == char, ('expected %s at %d'):format(char, position))
        position = position + 1
    end

    local function str()
        expect('"')

        local parts = {}

        while true do
            local char = source:sub(position, position)

            assert(char ~= '', 'unterminated string')

            if char == '"' then
                position = position + 1

                return table.concat(parts)
            elseif char == '\\' then
                parts[#parts + 1] = source:sub(position + 1, position + 1)
                position = position + 2
            else
                parts[#parts + 1] = char
                position = position + 1
            end
        end
    end

    local object

    local function value()
        skip()

        return source:sub(position, position) == '{' and object() or str()
    end

    function object()
        expect('{')

        local result = {}

        skip()

        if source:sub(position, position) == '}' then
            position = position + 1

            return result
        end

        while true do
            local key = str()

            expect(':')
            assert(result[key] == nil, 'duplicate key ' .. key)
            result[key] = value()
            skip()

            local char = source:sub(position, position)

            position = position + 1

            if char == '}' then
                return result
            end

            assert(char == ',', 'expected , or }')
        end
    end

    return object()
end

---Dotted keys of a decoded locale group, sorted.
---@param group table
---@param prefix? string
---@param keys? string[]
---@return string[]
local function flatKeys(group, prefix, keys)
    keys = keys or {}

    for key, value in pairs(group) do
        if type(value) == 'table' then
            flatKeys(value, (prefix or '') .. key .. '.', keys)
        else
            keys[#keys + 1] = (prefix or '') .. key
        end
    end

    if not prefix then
        table.sort(keys)
    end

    return keys
end

---Reads `export const <name> = { ... }` of protocol.ts.
---@param source string
---@param name string
---@return table<string, string>
local function tsEnum(source, name)
    local block = assert(source:match('export const ' .. name .. ' = (%b{})'), name .. ' missing in protocol.ts')
    local values = {}

    for key, value in block:gmatch('(%w+): "([^"]+)"') do
        values[key] = value
    end

    return values
end

print('nui')

H.Test('Lua and the page agree on every enum they share', function()
    H.Reset()
    H.Load('server')

    local source = read('web/src/types/protocol.ts')

    for _, name in ipairs({ 'NuiAction', 'NuiCallback', 'Layout', 'Reason', 'Kind', 'Reticle', 'Side' }) do
        H.Equal(tsEnum(source, name), UgTarget.Enums[name], name)
    end
end)

H.Test('every locale has exactly the labels the page uses', function()
    H.Reset()
    H.LoadClient()

    local expected = { table.unpack(UgTarget.Internal.Nui.LabelKeys) }

    table.sort(expected)

    for _, code in ipairs({ 'en', 'pt' }) do
        local locale = decodeLocale(read(('locales/%s.json'):format(code)))
        local keys = flatKeys(locale.page, '', {})

        table.sort(keys)
        H.Equal(keys, expected, code)
        H.Assert(type(locale.keybind) == 'string', code .. ': keybind label')
    end
end)

H.Test('page callbacks drop malformed bodies and floods', function()
    H.Reset()
    H.LoadClient()

    H.Equal(H.PostNui('hover', 'x'), {
        ok = false,
    })
    H.Equal(H.PostNui('hover', {
        index = 0,
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('hover', {
        index = 1.5,
    }), {
        ok = false,
    })
    H.Equal(H.PostNui('hover', {
        index = 3,
    }), {
        ok = true,
    })

    for _ = 1, 40 do
        H.PostNui('back', {})
    end

    H.Equal(H.PostNui('back', {}), {
        ok = false,
    }, 'over 30 per second')

    H.Now = H.Now + 1000

    H.Equal(H.PostNui('back', {}), {
        ok = true,
    })
end)

H.Test('messages wait for the page, then config goes first', function()
    H.Reset()
    H.Load('client')
    UgTarget.Internal.Nui.Send('close')

    H.Equal(#H.PageMessages(), 0)

    H.PostNui('ready', {})

    local messages = H.PageMessages()

    H.Equal(messages[1].action, 'config')
    H.Equal(messages[2].action, 'close')
end)

H.Done()
