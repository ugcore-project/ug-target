--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The targeting session: aim, menu, input, holds, cooldowns, outline and the anchor on screen.
-- Input is read in Lua, so keyboard and controller work without NUI focus. Left click locks the menu and frees the cursor.
-- Number keys are key mappings: GTA does not report the weapon slot controls while Alt is held.

---@class UgTarget.Internal.Target
local Target = {}
UgTarget.Internal.Target = Target

local Api = UgTarget.Internal.Api
local Facts = UgTarget.Internal.Facts
local Nui = UgTarget.Internal.Nui
local Registry = UgTarget.Internal.Registry
local Scanner = UgTarget.Internal.Scanner
local Enums = UgTarget.Enums
local Action = Enums.NuiAction
local Callback = Enums.NuiCallback
local Errors = UgCore.Enums.Errors

-- Options are rebuilt at least this often, so conditions and canInteract follow the world.
local REBUILD_MS = 250
-- The anchor is sent again only when it moves more than this, in screen fractions.
local ANCHOR_EPSILON = 0.0015

-- Control indices from the Cfx controls reference.
local CONTROL = {
    Attack = 24, Aim = 25, WeaponWheel = 37, Pickup = 38, Pause = 200,
    ScrollUp = 241, ScrollDown = 242, NextWeapon = 14, PrevWeapon = 15,
    CellphoneUp = 172, CellphoneDown = 173, CellphoneCancel = 177, FrontendAccept = 201,
}
-- Not 176, cellphone select: it fires on left click too, which frees the cursor.
local CONFIRM = { CONTROL.Pickup, CONTROL.FrontendAccept }
local BACK = { CONTROL.Aim, CONTROL.CellphoneCancel }
local UP = { CONTROL.ScrollUp, CONTROL.CellphoneUp }
local DOWN = { CONTROL.ScrollDown, CONTROL.CellphoneDown }
local DISABLED = {
    24, 25, 37, 38, 140, 141, 142, 257, 263, 264, 14, 15, 16, 17, 99, 100, 115, 116, 172, 173, 176, 177, 200, 201, 241, 242,
    157, 158, 159, 160, 161, 162, 163, 164, 165,
}
local CURSOR = 'cursor'
-- A hold started by a number key mapping. Its release cancels the hold.
local NUMBER = 'number'
---@type UgTargetSettings
local DEFAULTS = {
    trigger = Enums.Trigger.Hold, key = 'LMENU', layout = Enums.Layout.Anchored, maxDistance = 7.0, defaultDistance = 2.5,
    showDisabled = true, outline = false, outlineColor = {
        255,
        255,
        255,
        255,
    }, sounds = false, allowWhileDowned = false,
    allowInVehicle = true, debug = false, cursor = true, numberKeys = true, soundEffects = {}, theme = {}, optionColors = {},
    look = {},
}
local Sound = Enums.Sound

---@class UgTargetHold
---@field index integer
---@field entry UgTargetEntry
---@field startedAt integer
---@field control integer|'cursor'|'number'
---@field denied boolean the server refused the Begin

---@class UgTargetState
---@field open boolean
---@field locked boolean
---@field generation integer
---@field target? UgTargetTarget
---@field entries UgTargetEntry[]
---@field selected integer
---@field menus string[]
---@field signature string
---@field lastBuild integer
---@field revision integer
---@field hold? UgTargetHold
---@field outlined? integer
---@field anchorOffset? vector3
---@field anchor { x: number, y: number, visible: boolean }

---@type UgTargetState
local state = {
    open = false, locked = false, generation = 0, entries = {}, selected = 1, menus = {}, signature = '',
    lastBuild = 0, revision = -1, anchor = {
        x = -1,
        y = -1,
        visible = false,
    },
}
---@type table<integer, integer> option id to the time it MAY run again
local cooldowns = {}

---Only called while targeting MAY run, after boot stored the settings.
---@return UgTargetSettings
local function settings()
    return UgTarget.Internal.Settings or DEFAULTS
end

---@param name UgTargetSound
local function sound(name)
    local values = settings()
    local entry = values.sounds and values.soundEffects[name]

    if entry then
        PlaySoundFrontend(-1, entry.name, entry.set, true)
    end
end

---@param option UgTargetOption
---@return integer
local function cooldownLeft(option)
    local until_ = cooldowns[option.id]

    return until_ and math.max(until_ - GetGameTimer(), 0) or 0
end

---@param option UgTargetOption
---@return boolean
local function coolingDown(option)
    return cooldownLeft(option) > 0
end

---@return boolean
function Target.IsOpen()
    return state.open
end

---Whether targeting MAY run right now.
---@return boolean
function Target.CanRun()
    local values = UgTarget.Internal.Settings

    if not values or Api.IsDisabled() or IsPauseMenuActive() then
        return false
    end

    if not LocalPlayer.state[UgCore.Enums.StateBags.Loaded] then
        return false
    end

    if not values.allowWhileDowned and Facts.IsIncapacitated() then
        return false
    end

    if not values.allowInVehicle and IsPedInAnyVehicle(PlayerPedId(), false) then
        return false
    end

    -- Another resource holds the cursor.
    if not state.locked and IsNuiFocused() then
        return false
    end

    return true
end

local function clearOutline()
    if state.outlined then
        SetEntityDrawOutline(state.outlined, false)
        state.outlined = nil
    end
end

---@param entity? integer
local function outline(entity)
    if entity == state.outlined then
        return
    end

    clearOutline()

    local values = settings()

    if entity and values.outline then
        local color = values.outlineColor

        SetEntityDrawOutlineColor(color[1], color[2], color[3], color[4])
        SetEntityDrawOutline(entity, true)
        state.outlined = entity
    end
end

---@param silent? boolean
local function cancelHold(silent)
    if state.hold then
        state.hold = nil

        if not silent then
            Nui.Send(Action.Hold, {})
        end
    end
end

local function sendSelection()
    Nui.Send(Action.Select, {
        index = state.selected,
    })
end

---Rebuilds the options for the current target and sends them when they changed.
local function build()
    local target = state.target

    state.lastBuild = GetGameTimer()
    state.revision = Registry.Revision()

    if not target then
        return
    end

    local menu = state.menus[#state.menus]
    local entries = Scanner.Build(target, Facts.Get(), menu, coolingDown, settings())

    -- A submenu that emptied falls back to its parent.
    if #entries == 0 and menu then
        state.menus[#state.menus] = nil

        return build()
    end

    state.entries = entries
    state.selected = math.max(math.min(state.selected, #entries), 1)

    if state.hold and entries[state.hold.index] ~= state.hold.entry then
        local still = false

        for index, entry in ipairs(entries) do
            if entry.option == state.hold.entry.option then
                state.hold.index, state.hold.entry, still = index, entry, true
            end
        end

        if not still then
            cancelHold()
        end
    end

    local signature = Scanner.Signature(entries, menu)

    if signature ~= state.signature then
        state.signature = signature
        Nui.Send(Action.Options, {
            options = Scanner.Present(entries, cooldownLeft),
            selected = state.selected,
            depth = #state.menus,
            kind = target.kind,
        })
    end

    -- Vehicles and objects only: outlining peds can crash the game, which is why other target resources skip them.
    local outlined = target.kind == Enums.Kind.Vehicle or target.kind == Enums.Kind.Object

    outline(#entries > 0 and outlined and target.entity or nil)
end

---@param target UgTargetTarget
local function setTarget(target)
    state.target = target
    state.menus = {}
    state.selected = 1
    state.signature = ''
    state.anchor.visible = false
    cancelHold()

    if target.entity then
        state.anchorOffset = GetOffsetFromEntityGivenWorldCoords(target.entity, target.coords.x, target.coords.y, target.coords.z)
    else
        state.anchorOffset = nil
    end

    build()
end

---The world point the menu hangs from.
---@return vector3?
local function anchorPoint()
    local target = state.target

    if not target then
        return nil
    end

    local offset = state.anchorOffset

    if target.entity and offset and DoesEntityExist(target.entity) then
        return GetOffsetFromEntityInWorldCoords(target.entity, offset.x, offset.y, offset.z)
    end

    return target.coords
end

local function updateAnchor()
    if settings().layout ~= Enums.Layout.Anchored then
        return
    end

    local point = #state.entries > 0 and anchorPoint() or nil
    local visible, x, y = false, -1.0, -1.0

    if point then
        visible, x, y = GetScreenCoordFromWorldCoord(point.x, point.y, point.z)
        visible = visible == true or visible == 1
    end

    local anchor = state.anchor

    if visible ~= anchor.visible or (visible and (math.abs(x - anchor.x) > ANCHOR_EPSILON or math.abs(y - anchor.y) > ANCHOR_EPSILON)) then
        anchor.visible, anchor.x, anchor.y = visible, x, y
        Nui.Send(Action.Anchor, {
            visible = visible,
            x = x,
            y = y,
        })
    end
end

---Runs an option's effects. Server actions wait for the server in this thread.
---@param entry UgTargetEntry
---@param index integer
---@param keepOpen boolean
local function runEffects(entry, index, keepOpen)
    local option, context = entry.option, entry.context

    if option.onSelect then
        local ok, err = pcall(option.onSelect, context)

        if not ok then
            UgCore.Logger.Error('onSelect of %s (%s) failed: %s', option.name, option.resource, tostring(err))
        end
    end

    if option.event then
        TriggerEvent(option.event, context)
    end

    if option.serverEvent then
        TriggerServerEvent(option.serverEvent, {
            entity = context.netId or 0, coords = context.coords, distance = context.distance, zone = context.zone,
            name = context.name, data = context.data,
        })
    end

    if option.command then
        ExecuteCommand(option.command)
    end

    if option.export then
        local resource, method = option.export:match('^(.-)%.(.+)$')
        local ok, err = pcall(function()
            exports[resource][method](nil, context)
        end)

        if not ok then
            UgCore.Logger.Error('export %s failed: %s', option.export, tostring(err))
        end
    end

    if option.serverAction then
        local ok, value, errorCode = UgCore.Callback.Await('ug-target:Run', option.serverAction, {
            netId = context.netId,
        })
        local success = ok and type(value) == 'table' and value.ok == true
        local code = nil

        if not success then
            code = (not ok and errorCode) or (type(value) == 'table' and value.error) or Errors.InternalError
        end

        if keepOpen and state.open then
            Nui.Send(Action.Result, {
                index = index,
                ok = success,
                error = code,
            })
        end

        if not success then
            sound(Sound.Error)
        end

        if option.onResult then
            pcall(option.onResult, success, success and value.value or nil, code)
        end
    end
end

---Runs an entry now: holds are done, conditions passed.
---@param entry UgTargetEntry
---@param index integer
local function execute(entry, index)
    local option = entry.option

    if option.cooldown > 0 then
        cooldowns[option.id] = GetGameTimer() + option.cooldown
    end

    sound(Sound.Select)

    if option.keepOpen then
        Nui.Send(Action.Result, {
            index = index,
            ok = true,
        })
        state.signature = ''
        build()
    else
        Target.Close()
    end

    CreateThread(function()
        runEffects(entry, index, option.keepOpen)
    end)
end

---Starts a hold. Server actions open it on the server too, which times it.
---@param entry UgTargetEntry
---@param index integer
---@param control integer|'cursor'|'number'
local function startHold(entry, index, control)
    local hold = {
        index = index,
        entry = entry,
        startedAt = GetGameTimer(),
        control = control,
        denied = false,
    }

    state.hold = hold
    Nui.Send(Action.Hold, {
        index = index,
        duration = entry.option.hold,
    })

    local action = entry.option.serverAction

    if action then
        CreateThread(function()
            local ok, value = UgCore.Callback.Await('ug-target:Begin', action, {
                netId = entry.context.netId,
            })

            if not (ok and type(value) == 'table' and value.ok == true) and state.hold == hold then
                hold.denied = true
                cancelHold()
                sound(Sound.Error)
                Nui.Send(Action.Result, {
                    index = index,
                    ok = false,
                    error = type(value) == 'table' and value.error or Errors.InternalError,
                })
            end
        end)
    end
end

---Picks the entry at `index`: opens its submenu, starts its hold or runs it.
---@param index integer
---@param control integer|'cursor'|'number'
function Target.Pick(index, control)
    local entry = state.entries[index]

    if not entry or state.hold then
        return
    end

    state.selected = index

    if not entry.enabled then
        sound(Sound.Error)
        Nui.Send(Action.Result, {
            index = index,
            ok = false,
            reason = entry.reason,
        })

        return
    end

    local option = entry.option

    if option.openMenu then
        sound(Sound.Select)
        state.menus[#state.menus + 1] = option.openMenu
        state.selected = 1
        state.signature = ''
        build()

        return
    end

    if option.hold > 0 then
        startHold(entry, index, control)

        return
    end

    execute(entry, index)
end

---Goes back: cancels a hold, leaves a submenu, frees the cursor, or closes in toggle mode.
function Target.Back()
    if state.hold then
        cancelHold()
    elseif #state.menus > 0 then
        sound(Sound.Back)
        state.menus[#state.menus] = nil
        state.selected = 1
        state.signature = ''
        build()
    elseif state.locked then
        Target.Lock(false)
    elseif settings().trigger == Enums.Trigger.Toggle then
        Target.Close()
    end
end

---Locks the menu and frees the cursor, or the opposite. Unlocking in hold mode closes: the key MAY be up by now.
---@param locked boolean
function Target.Lock(locked)
    if locked == state.locked or (locked and (#state.entries == 0 or not settings().cursor)) then
        return
    end

    state.locked = locked
    SetNuiFocus(locked, locked)
    Nui.Send(Action.Cursor, {
        active = locked,
    })

    if not locked and settings().trigger == Enums.Trigger.Hold then
        Target.Close()
    end
end

---@param controls integer[]
---@return integer? control the one just pressed
local function justPressed(controls)
    for _, control in ipairs(controls) do
        if IsDisabledControlJustPressed(0, control) then
            return control
        end
    end

    return nil
end

---@param step integer
local function move(step)
    local count = #state.entries

    if count < 2 or state.hold then
        return
    end

    state.selected = (state.selected - 1 + step) % count + 1
    sound(Sound.Hover)
    sendSelection()
end

local function handleInput()
    for _, control in ipairs(DISABLED) do
        DisableControlAction(0, control, true)
    end

    if state.locked then
        return
    end

    if justPressed(BACK) then
        Target.Back()

        return
    end

    if #state.entries == 0 then
        return
    end

    if justPressed(UP) then
        move(-1)
    elseif justPressed(DOWN) then
        move(1)
    end

    local confirm = justPressed(CONFIRM)

    if confirm then
        Target.Pick(state.selected, confirm)
    elseif IsDisabledControlJustPressed(0, CONTROL.Attack) then
        Target.Lock(true)
    end
end

local function updateHold()
    local hold = state.hold

    if not hold then
        return
    end

    local control = hold.control

    if type(control) == 'number' and not IsDisabledControlPressed(0, control) then
        cancelHold()

        return
    end

    if GetGameTimer() - hold.startedAt >= hold.entry.option.hold then
        state.hold = nil

        if not hold.denied then
            execute(hold.entry, hold.index)
        end
    end
end

---@param generation integer
local function scanLoop(generation)
    while state.open and state.generation == generation do
        if not Target.CanRun() then
            Target.Close()

            break
        end

        local ped = PlayerPedId()

        if state.locked then
            Wait(REBUILD_MS)

            if state.open and state.generation == generation and state.target then
                local pedCoords = GetEntityCoords(ped)
                local coords = state.target.coords
                local dx, dy, dz = coords.x - pedCoords.x, coords.y - pedCoords.y, coords.z - pedCoords.z

                state.target.distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                build()

                if #state.entries == 0 then
                    Target.Lock(false)
                end
            end
        else
            local result, endPoint = Scanner.Cast(settings().maxDistance)

            if state.open and state.generation == generation and not state.locked then
                local target = Scanner.Resolve(result, endPoint, GetEntityCoords(ped))

                -- Holding keeps the target: looking away a little MUST NOT reset the menu mid-hold.
                if not state.target or (target.key ~= state.target.key and not state.hold) then
                    setTarget(target)
                else
                    state.target.distance, state.target.coords = target.distance, target.coords

                    if GetGameTimer() - state.lastBuild >= REBUILD_MS or Registry.Revision() ~= state.revision then
                        build()
                    end
                end
            end
        end
    end
end

---Draws the aim point and nearby zones for config.debug, or only zones created with debug.
---@param all boolean
local function drawDebug(all)
    local target = state.target

    if all and target then
        local c = target.coords

        DrawMarker(28, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.05, 0.05, 255, 255, 255, 200, false, false, 2, false, nil, nil, false)
    end

    local ped = GetEntityCoords(PlayerPedId())

    for _, zone in pairs(Registry.Zones()) do
        local c = zone.center
        local dx, dy = c.x - ped.x, c.y - ped.y

        if (all or zone.debug) and dx * dx + dy * dy < 2500 then
            if zone.radius then
                DrawMarker(28, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, zone.radius, zone.radius, zone.radius, 59, 130, 246, 60, false, false, 2, false, nil, nil, false)
            elseif zone.size then
                DrawMarker(43, c.x, c.y, c.z - zone.size.z / 2, 0.0, 0.0, 0.0, 0.0, 0.0, zone.rotation or 0.0, zone.size.x, zone.size.y, zone.size.z, 59, 130, 246, 60, false, false, 2, false, nil, nil, false)
            elseif zone.points then
                local points, low, high = zone.points or {}, zone.minZ or c.z, zone.maxZ or c.z

                for index, a in ipairs(points) do
                    local b = points[index % #points + 1]

                    DrawLine(a.x, a.y, low, b.x, b.y, low, 59, 130, 246, 200)
                    DrawLine(a.x, a.y, high, b.x, b.y, high, 59, 130, 246, 200)
                    DrawLine(a.x, a.y, low, a.x, a.y, high, 59, 130, 246, 200)
                end
            end
        end
    end
end

---@param generation integer
local function frameLoop(generation)
    while state.open and state.generation == generation do
        handleInput()

        if state.open and state.generation == generation then
            updateHold()
        end

        if state.open and state.generation == generation then
            updateAnchor()
        end

        if state.open then
            drawDebug(settings().debug)
        end

        Wait(0)
    end
end

---Opens targeting.
function Target.Open()
    if state.open or not Target.CanRun() then
        return
    end

    state.open = true
    state.generation = state.generation + 1
    state.target, state.entries, state.selected, state.menus, state.signature = nil, {}, 1, {}, ''
    state.anchor = {
        x = -1,
        y = -1,
        visible = false,
    }
    Nui.Send(Action.Aim, {
        active = true,
        layout = settings().layout,
    })
    TriggerEvent('ug-target:Toggled', true)

    local generation = state.generation

    CreateThread(function()
        scanLoop(generation)
    end)

    CreateThread(function()
        frameLoop(generation)
    end)
end

---Closes targeting.
function Target.Close()
    if not state.open then
        return
    end

    state.open = false
    state.generation = state.generation + 1
    cancelHold(true)
    clearOutline()

    if state.locked then
        state.locked = false
        SetNuiFocus(false, false)
    end

    state.target, state.entries, state.menus = nil, {}, {}
    Nui.Send(Action.Close)
    TriggerEvent('ug-target:Toggled', false)
end

---The target key went down.
function Target.Pressed()
    if settings().trigger == Enums.Trigger.Toggle and state.open then
        if not state.locked then
            Target.Close()
        end
    else
        Target.Open()
    end
end

---The target key went up. Ignored while the menu is locked.
function Target.Released()
    if settings().trigger == Enums.Trigger.Hold and not state.locked then
        Target.Close()
    end
end

---A number key went down: picks that row, unless the cursor is free.
---@param number integer
function Target.NumberPressed(number)
    if settings().numberKeys and state.open and not state.locked and state.entries[number] then
        Target.Pick(number, NUMBER)
    end
end

---A number key went up: ends a hold it started.
function Target.NumberReleased()
    if state.hold and state.hold.control == NUMBER then
        cancelHold()
    end
end

---Selected index and entries, for tests and the ugtarget command.
---@return UgTargetState
function Target.State()
    return state
end

Nui.On(Callback.Hover, function(index)
    if state.locked and state.entries[index] and not state.hold then
        state.selected = index
    end
end)

Nui.On(Callback.Pick, function(index)
    if state.locked then
        Target.Pick(index, CURSOR)
    end
end)

Nui.On(Callback.Release, function()
    if state.hold and state.hold.control == CURSOR then
        cancelHold()
    end
end)

Nui.On(Callback.Back, function()
    if state.locked then
        Target.Back()
    end
end)
