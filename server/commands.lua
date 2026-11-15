--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- `ugtarget`, the console inspector.

---@class UgTarget.Internal.Commands
local Commands = {}
UgTarget.Internal.Commands = Commands

local Actions = UgTarget.Internal.Actions

---@return string[] lines
function Commands.Status()
    local lines = {}

    for name, action in pairs(Actions.GetAll()) do
        local extras = {}

        if action.hold > 0 then
            extras[#extras + 1] = ('hold %d ms'):format(action.hold)
        end

        if action.cooldown > 0 then
            extras[#extras + 1] = ('cooldown %d ms'):format(action.cooldown)
        end

        if action.conditions then
            extras[#extras + 1] = 'conditions'
        end

        lines[#lines + 1] = ('  %s  %.1f m%s'):format(name, action.distance, #extras > 0 and ('  ' .. table.concat(extras, ', ')) or '')
    end

    table.sort(lines)
    table.insert(lines, 1, ('ug-target: %d server action(s).'):format(#lines))

    return lines
end

---Registers the command. Runs once after a clean boot.
function Commands.Register()
    RegisterCommand('ugtarget', function(caller, args)
        if caller ~= 0 then
            return
        end

        if args[1] == 'status' then
            for _, line in ipairs(Commands.Status()) do
                print(line)
            end
        else
            print('Usage: ugtarget status')
        end
    end, true)
end
