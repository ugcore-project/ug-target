--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@diagnostic disable: undefined-global

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ug-target'
author 'UgCore Framework & Contributors'
version '1.0.0' -- x-release-please-version
description 'Third-eye targeting for UgCore: world-anchored options, secure server actions and conditions'
repository 'https://github.com/ugcore-project/ug-target'

ugcore_version '1.0.0'
uglib_version '1.0.0'

dependencies {
    '/onesync',
    'ug-core',
    'ug-lib',
}

-- Scripts written for ox_target keep working: its export names map onto ug-target.
provide 'ox_target'

shared_scripts {
    '@ug-core/import.lua',
    '@ug-lib/import.lua',
    'shared/init.lua',
    'shared/enums.lua',
    'shared/shapes.lua',
    'shared/conditions.lua',
}

server_scripts {
    'server/config.lua',
    'server/actions.lua',
    'server/commands.lua',
    'server/boot.lua',
}

client_scripts {
    'client/options.lua',
    'client/registry.lua',
    'client/api.lua',
    'client/compat.lua',
    'client/facts.lua',
    'client/scanner.lua',
    'client/nui.lua',
    'client/target.lua',
    'client/boot.lua',
}

ui_page 'web/dist/index.html'

files {
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/assets/*',
}
