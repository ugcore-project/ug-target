--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Last client script: waits for the server config and ug-core, then binds the target key.

local Target = UgTarget.Internal.Target
local Nui = UgTarget.Internal.Nui

local STATE_KEY = 'ug-target:Config'
local READY_TIMEOUT = 60000
local PICK_KEYS = 9

---Client settings from the server, nil until they replicate.
---@type UgTargetSettings?
UgTarget.Internal.Settings = nil

CreateThread(function()
    local deadline = GetGameTimer() + READY_TIMEOUT

    while type(GlobalState[STATE_KEY]) ~= 'table' do
        if GetGameTimer() >= deadline then
            print('^1[ug-target] No config from the server. Check the server console.^7')

            return
        end

        Wait(250)
    end

    if not UgCore.Lifecycle.Await(UgCore.Enums.Lifecycle.Ready, READY_TIMEOUT) then
        print('^1[ug-target] ug-core did not become ready.^7')

        return
    end

    local settings = GlobalState[STATE_KEY] --[[@as UgTargetSettings]]

    UgTarget.Internal.Settings = settings
    Nui.Configure(settings)

    UgLib.Keybind.Register({
        name = 'target',
        label = Nui.Label('keybind'),
        defaultKey = settings.key,
        onPressed = Target.Pressed,
        onReleased = Target.Released,
    })

    for number = 1, settings.numberKeys and PICK_KEYS or 0 do
        UgLib.Keybind.Register({
            name = 'pick_' .. number,
            label = Nui.Label('keybindPick', {
                number = number,
            }),
            defaultKey = tostring(number),
            onPressed = function()
                Target.NumberPressed(number)
            end,
            onReleased = Target.NumberReleased,
        })
    end

    print(('[ug-target] Ready: %s, %s.'):format(settings.trigger, settings.layout))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        Target.Close()
    end
end)
