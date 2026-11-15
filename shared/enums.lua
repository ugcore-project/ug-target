--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@class UgTarget.Enums
UgTarget.Enums = {}

---What an option is attached to.
---@enum UgTargetKind
UgTarget.Enums.Kind = {
    Ped = 'ped',
    Vehicle = 'vehicle',
    Object = 'object',
    Player = 'player',
    Zone = 'zone',
}

---Zone shapes.
---@enum UgTargetShape
UgTarget.Enums.Shape = {
    Sphere = 'sphere',
    Box = 'box',
    Poly = 'poly',
}

---How the target key works.
---@enum UgTargetTrigger
UgTarget.Enums.Trigger = {
    Hold = 'hold',
    Toggle = 'toggle',
}

---Where options show. MUST match web/src/types/protocol.ts.
---@enum UgTargetLayout
UgTarget.Enums.Layout = {
    Anchored = 'anchored',
    List = 'list',
}

---Crosshair looks. MUST match web/src/types/protocol.ts.
---@enum UgTargetReticle
UgTarget.Enums.Reticle = {
    -- A ring that snaps brackets around what you aim at.
    Brackets = 'brackets',
    Dot = 'dot',
    None = 'none',
}

---Which side of the anchor or crosshair the options card takes. MUST match web/src/types/protocol.ts.
---@enum UgTargetSide
UgTarget.Enums.Side = {
    -- Right, and left near the right edge.
    Auto = 'auto',
    Left = 'left',
    Right = 'right',
}

---Frontend sounds. Each owner entry is { name, set }.
---@enum UgTargetSound
UgTarget.Enums.Sound = {
    Hover = 'hover',
    Select = 'select',
    Back = 'back',
    Error = 'error',
}

---Why an option is shown disabled. Labels: `reason.<value>` in the locale file. MUST match web/src/types/protocol.ts.
---@enum UgTargetReason
UgTarget.Enums.Reason = {
    Job = 'job',
    Gang = 'gang',
    Duty = 'duty',
    Items = 'items',
    Vehicle = 'vehicle',
    Cooldown = 'cooldown',
    Busy = 'busy',
}

---Messages Lua sends to the page. MUST match web/src/types/protocol.ts.
---@enum UgTargetNuiAction
UgTarget.Enums.NuiAction = {
    Config = 'config',
    Aim = 'aim',
    Options = 'options',
    Anchor = 'anchor',
    Select = 'select',
    Hold = 'hold',
    Result = 'result',
    Cursor = 'cursor',
    Close = 'close',
}

---Callbacks the page posts. MUST match web/src/types/protocol.ts.
---@enum UgTargetNuiCallback
UgTarget.Enums.NuiCallback = {
    Ready = 'ready',
    Hover = 'hover',
    Pick = 'pick',
    Release = 'release',
    Back = 'back',
}
