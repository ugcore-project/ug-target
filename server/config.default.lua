--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- ug-target config. Copied to config.lua in the resource folder on the first start: edit that file, never this one.
-- Updates never overwrite config.lua.
-- Values left out use the defaults. Every value is checked on start: errors are logged and ug-target stays idle.

return {
    -- 'hold': hold the key to aim, release to close. 'toggle': press to open, press again to close.
    trigger = 'hold',

    -- Default key, from the FiveM key names. Players MAY rebind it in the game's key bindings.
    key = 'LMENU',

    -- 'anchored': options float next to what you aim at. 'list': options sit beside the crosshair.
    layout = 'anchored',

    -- Meters the aim reaches. Options set their own distance, at most this.
    maxDistance = 7.0,

    -- Meters for options that set no distance.
    defaultDistance = 2.5,

    -- Options whose conditions fail show greyed out with the reason, instead of hiding.
    showDisabled = true,

    -- Outlines the vehicle or object you aim at, in { red, green, blue, alpha }. Peds are never outlined.
    outline = true,
    outlineColor = { 59, 130, 246, 255 },

    -- Frontend sounds on hover and select.
    sounds = true,

    -- Downed and dead players MAY aim. Options still MAY refuse them.
    allowWhileDowned = false,

    -- Players in a vehicle MAY aim.
    allowInVehicle = true,

    -- Meters the server adds to an option's distance before refusing a server action, for movement and latency.
    actionMargin = 1.5,

    -- Draws the aim point and zone outlines.
    debug = false,

    -- Left click frees the cursor to pick with the mouse. false: keyboard, scroll and number keys only.
    cursor = true,

    -- Number keys 1 to 9 pick a row, and rows show their number.
    numberKeys = true,

    -- Sounds per event, as { name, set } from the game's frontend sounds. Leave one out to silence it.
    -- 'sounds = false' above silences all.
    soundEffects = {
        hover = {
            name = 'NAV_UP_DOWN',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
        select = {
            name = 'SELECT',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
        back = {
            name = 'BACK',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
        error = {
            name = 'ERROR',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
    },

    -- ug-lib theme overrides for ug-target only: mode, colors (HSL strings such as '262 83% 58%'), radius, font,
    -- scale. colors take ug-lib's tokens plus brandTo (where gradients end) and reticle (the idle crosshair).
    theme = {},

    -- Row colors (hex), one per row in turn. Options MAY set their own. { } colors every row with the theme's primary.
    optionColors = { '#a78bfa', '#38bdf8', '#34d399', '#fbbf24', '#fb7185', '#e879f9', '#2dd4bf', '#818cf8' },

    -- How the options look. Leave a field out to keep its default.
    -- cardWidth: pixels, 200 to 480. cardOpacity: background, 0 to 1. blur: frosted background.
    -- side: 'auto', 'left' or 'right' of the anchor or crosshair. connector: the dashed line to what you aim at.
    -- pulse: the ring around the anchor. reticle: 'brackets', 'dot' or 'none'. hints: the bottom line with keys.
    -- animations: false keeps everything still. resultDuration: ms a done or failed mark stays.
    look = {
        cardWidth = 288,
        cardOpacity = 0.7,
        blur = true,
        side = 'auto',
        connector = true,
        pulse = true,
        reticle = 'brackets',
        hints = true,
        animations = true,
        resultDuration = 1400,
    },
}
