local axes = { 'X', 'Y', 'Z' }
local axisIndex = 1
local axisByMode = { move = 1, rotate = 3 }
local mode = 'move'
local localSpace = false
local editorActive = false
local outlinedEntity
local disabledControls = { 21, 36, 44, 47, 74, 172, 173, 174, 175, 177, 182, 191 }
local editorConfig = Config.Placement.editor

local function axisDirection(entity, axis)
    if not localSpace or mode == 'rotate' then
        if axis == 'X' then return vec3(1.0, 0.0, 0.0) end
        if axis == 'Y' then return vec3(0.0, 1.0, 0.0) end
        return vec3(0.0, 0.0, 1.0)
    end

    local forward, right, up = GetEntityMatrix(entity)
    if axis == 'X' then return right end
    if axis == 'Y' then return forward end
    return up
end

local function currentModifier()
    if IsDisabledControlPressed(0, 21) then return 'precision' end -- Left Shift
    if IsDisabledControlPressed(0, 36) then return 'fast' end -- Left Ctrl
    return 'normal'
end

local function nudgeAmount()
    local modifier = currentModifier()
    if mode == 'move' then return editorConfig.moveNudge[modifier] end
    return editorConfig.rotateNudge[modifier]
end

local function holdSpeed()
    local modifier = currentModifier()
    if mode == 'move' then return editorConfig.moveSpeed[modifier] end
    return editorConfig.rotateSpeed[modifier]
end

local function updateHelp()
    local axis = axes[axisIndex]
    local space = mode == 'move' and (localSpace and 'Local' or 'World') or 'Euler'
    local nudge = mode == 'move' and ('%.2f m'):format(nudgeAmount()) or ('%.0f°'):format(nudgeAmount())
    local spaceHint = mode == 'move' and '[L] Local/World' or 'Euler X/Y/Z rotation'
    lib.showTextUI((
        '%s | %s axis | %s | Nudge %s  \n' ..
        '[H] Move/Rotate  [←/→] Axis  [↑/↓] Nudge or hold  \n' ..
        '%s  [Shift] Precision  [Ctrl] Fast  \n' ..
        '[G] Ground  [Enter] Confirm  [Backspace] Cancel'
    ):format(mode == 'move' and 'MOVE' or 'ROTATE', axis, space, nudge, spaceHint))
end

local function drawAxes(entity)
    local origin = GetEntityCoords(entity)
    local selected = axes[axisIndex]
    local definitions = {
        { axis = 'X', colour = { 255, 70, 70 } },
        { axis = 'Y', colour = { 70, 255, 70 } },
        { axis = 'Z', colour = { 70, 140, 255 } }
    }

    for i = 1, #definitions do
        local entry = definitions[i]
        local isSelected = entry.axis == selected
        local length = isSelected and 0.90 or 0.42
        local direction = axisDirection(entity, entry.axis)
        local endpoint = origin + direction * length
        local startpoint = isSelected and origin - direction * 0.32 or origin
        DrawLine(origin.x, origin.y, origin.z, endpoint.x, endpoint.y, endpoint.z,
            entry.colour[1], entry.colour[2], entry.colour[3], isSelected and 255 or 105)
        if isSelected then
            DrawLine(startpoint.x, startpoint.y, startpoint.z, origin.x, origin.y, origin.z,
                entry.colour[1], entry.colour[2], entry.colour[3], 210)
        end
    end
end

local function adjust(entity, amount)
    local axis = axes[axisIndex]
    if mode == 'move' then
        local position = GetEntityCoords(entity)
        local direction = axisDirection(entity, axis)
        local target = position + direction * amount
        SetEntityCoordsNoOffset(entity, target.x, target.y, target.z, false, false, false)
        return
    end

    local rotation = GetEntityRotation(entity, 2)
    if axis == 'X' then
        SetEntityRotation(entity, rotation.x + amount, rotation.y, rotation.z, 2, true)
    elseif axis == 'Y' then
        SetEntityRotation(entity, rotation.x, rotation.y + amount, rotation.z, 2, true)
    else
        SetEntityRotation(entity, rotation.x, rotation.y, rotation.z + amount, 2, true)
    end
end

local function cleanupEditor()
    lib.hideTextUI()
    if outlinedEntity and DoesEntityExist(outlinedEntity) then
        SetEntityDrawOutline(outlinedEntity, false)
    end
    outlinedEntity = nil
    editorActive = false
end

function UseBoomboxPlacementEditor(entity)
    if editorActive or not DoesEntityExist(entity) then return nil end
    editorActive = true
    outlinedEntity = entity
    axisIndex = 1
    axisByMode.move = 1
    axisByMode.rotate = 3
    mode = 'move'
    localSpace = false
    local cancelled = false
    local heldDirection = 0
    local holdStartedAt = 0
    local lastModifier = 'normal'

    SetEntityDrawOutline(entity, true)
    updateHelp()

    local ok, err = xpcall(function()
        while DoesEntityExist(entity) do
            Wait(0)
            DisablePlayerFiring(cache.playerId, true)
            for i = 1, #disabledControls do
                local control = disabledControls[i]
                DisableControlAction(0, control, true)
            end

            drawAxes(entity)

            if IsDisabledControlJustPressed(0, 74) then -- H
                mode = mode == 'move' and 'rotate' or 'move'
                axisIndex = axisByMode[mode]
                heldDirection = 0
                updateHelp()
            elseif IsDisabledControlJustPressed(0, 174) then -- Left Arrow
                axisIndex = axisIndex == 1 and #axes or axisIndex - 1
                axisByMode[mode] = axisIndex
                heldDirection = 0
                updateHelp()
            elseif IsDisabledControlJustPressed(0, 175) then -- Right Arrow
                axisIndex = axisIndex == #axes and 1 or axisIndex + 1
                axisByMode[mode] = axisIndex
                heldDirection = 0
                updateHelp()
            elseif mode == 'move' and IsDisabledControlJustPressed(0, 182) then -- L
                localSpace = not localSpace
                heldDirection = 0
                updateHelp()
            elseif IsDisabledControlJustPressed(0, 47) then -- G
                FreezeEntityPosition(entity, false)
                PlaceObjectOnGroundProperly_2(entity)
                FreezeEntityPosition(entity, true)
            elseif IsDisabledControlJustPressed(0, 177) then -- Backspace
                cancelled = true
                break
            elseif IsDisabledControlJustPressed(0, 191) then -- Enter
                break
            end

            local upPressed = IsDisabledControlPressed(0, 172)
            local downPressed = IsDisabledControlPressed(0, 173)
            local direction = upPressed ~= downPressed and (upPressed and 1 or -1) or 0
            local now = GetGameTimer()

            if direction == 0 then
                heldDirection = 0
            elseif direction ~= heldDirection then
                heldDirection = direction
                holdStartedAt = now
                adjust(entity, nudgeAmount() * direction)
            elseif now - holdStartedAt >= editorConfig.holdDelay then
                local frameTime = math.min(GetFrameTime(), 0.05)
                adjust(entity, holdSpeed() * frameTime * direction)
            end

            local modifier = currentModifier()
            if modifier ~= lastModifier then
                lastModifier = modifier
                updateHelp()
            end
        end
    end, debug.traceback)

    cleanupEditor()
    if not ok then
        if Config.Debug then print(('[nativeBoombox] Placement editor stopped: %s'):format(err)) end
        return nil
    end
    return { cancelled = cancelled }
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and editorActive then cleanupEditor() end
end)
