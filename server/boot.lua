--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Last server script: loads config, waits for ug-core and registers the callbacks.

local Config = UgTarget.Internal.Config
local Logger = UgCore.Logger

local RESOURCE = GetCurrentResourceName()
local READY_TIMEOUT = 60000

---Set once config and ug-core are usable. Nothing registers before.
---@type boolean
UgTarget.Internal.Ready = false

CreateThread(function()
    local ok, errors = Config.Load()

    if not ok then
        for _, message in ipairs(errors) do
            Logger.Error(message)
        end

        Logger.Error('Config invalid: %d error(s). ug-target stays idle.', #errors)

        return
    end

    if not UgCore.Lifecycle.Await(UgCore.Enums.Lifecycle.Ready, READY_TIMEOUT) then
        Logger.Error('ug-core did not become ready. Check its console output.')
        Logger.Error('ug-target stays idle.')

        return
    end

    UgTarget.Internal.Actions.Listen()
    UgTarget.Internal.Commands.Register()
    UgTarget.Internal.Ready = true

    print(('[ug-target] v%s ready.'):format(GetResourceMetadata(RESOURCE, 'version', 0) or '?'))
end)
