local boxes = {}
local worldZones = {}
local initialised = false
local renameDialogOpen = false
local interactionAlertOpen = false

local function showInteractionAlert(options)
    interactionAlertOpen = true
    local result = lib.alertDialog(options)
    interactionAlertOpen = false
    return result
end

local function showRenameDialog(box)
    renameDialogOpen = true
    local result = lib.inputDialog('Rename Boombox', {
        {
            type = 'input',
            label = 'Name',
            default = box.label,
            required = true,
            minLength = 1,
            maxLength = Config.Labels.maximumLength
        }
    })
    renameDialogOpen = false
    return result
end

local function entityBoxId(entity)
    if entity == 0 or not DoesEntityExist(entity) then return end
    return Entity(entity).state.nativeBoomboxId
end

local function openRadio(id, entity)
    local box = boxes[id]
    if not box then return end

    local callbackOk, access = pcall(lib.callback.await, 'nativeBoombox:server:getAccess', false, id)
    if not callbackOk or not access then
        return lib.notify({ type = 'error', description = 'Boombox access could not be checked.' })
    end
    if access.busy then
        return lib.notify({ type = 'inform', description = 'This boombox is currently being edited.' })
    end

    local contextId = ('nativeBoombox_radio_%s'):format(id)
    local stationContextId = ('nativeBoombox_stations_%s'):format(id)
    local options = {}

    if access.control then
        options[#options + 1] = {
            title = box.powered and 'Turn Off' or 'Turn On',
            icon = 'power-off',
            description = box.powered and 'Stop native radio playback' or 'Start native radio playback',
            onSelect = function()
                local current = boxes[id]
                if current then
                    TriggerServerEvent('nativeBoombox:server:setState', id, 'power', not current.powered)
                end
            end
        }
        options[#options + 1] = {
            title = 'Select Station',
            icon = 'radio',
            description = StationLookup[box.station] or box.station,
            menu = stationContextId
        }
        local stationOptions = {}
        for i = 1, #Stations do
            local station = Stations[i]
            local stationValue = station.value
            stationOptions[#stationOptions + 1] = {
                title = station.label,
                icon = box.station == stationValue and 'circle-check' or 'radio',
                disabled = box.station == stationValue,
                onSelect = function()
                    TriggerServerEvent('nativeBoombox:server:setState', id, 'station', stationValue)
                end
            }
        end
        lib.registerContext({
            id = stationContextId,
            title = 'Select Station',
            menu = contextId,
            options = stationOptions
        })
    end

    if access.reposition then
        options[#options + 1] = {
            title = 'Reposition',
            icon = 'up-down-left-right',
            description = 'Move or rotate this boombox',
            onSelect = function() BeginBoomboxReposition(id, entity) end
        }
    end

    if access.rename then
        options[#options + 1] = {
            title = 'Rename',
            icon = 'pen',
            description = box.label,
            onSelect = function()
                local input = showRenameDialog(box)
                if input and input[1] then
                    TriggerServerEvent('nativeBoombox:server:rename', id, input[1])
                end
            end
        }
    end

    if access.pickup then
        options[#options + 1] = {
            title = 'Pick Up',
            icon = 'hand',
            description = 'Return this boombox to your inventory',
            onSelect = function()
                local answer = showInteractionAlert({
                    header = 'Pick Up Boombox',
                    content = 'Return this boombox to your inventory?',
                    centered = true,
                    cancel = true
                })
                if answer == 'confirm' then TriggerServerEvent('nativeBoombox:server:pickup', id) end
            end
        }
    end

    if access.admin and access.details then
        local details = access.details
        options[#options + 1] = {
            title = 'Administrative Details',
            icon = 'shield-halved',
            description = ('ID %s | Owner %s'):format(details.id, details.owner or 'world'),
            onSelect = function()
                showInteractionAlert({
                    header = 'Boombox Details',
                    content = ('ID: `%s`  \nKind: `%s`  \nOwner: `%s`  \nNetwork ID: `%s`  \n' ..
                        'Position: `%.3f, %.3f, %.3f`  \nRotation: `%.2f, %.2f, %.2f`  \n' ..
                        'Station: `%s`  \nPowered: `%s`'):format(
                        details.id, details.kind, details.owner or 'world', details.netId or 'none',
                        details.x, details.y, details.z,
                        details.rot_x or 0.0, details.rot_y or 0.0, details.rot_z or 0.0,
                        details.station, details.powered and 'yes' or 'no'),
                    centered = true
                })
            end
        }
        if box.kind == 'placed' then
            options[#options + 1] = {
                title = 'Administrative Delete',
                icon = 'trash',
                description = 'Permanently remove without returning an item',
                onSelect = function()
                    local answer = showInteractionAlert({
                        header = 'Delete Boombox',
                        content = 'Permanently delete this boombox? The owner will not receive an item.',
                        centered = true,
                        cancel = true
                    })
                    if answer == 'confirm' then
                        TriggerServerEvent('nativeBoombox:server:adminDelete', id)
                    end
                end
            }
        end
    end

    if #options == 0 then
        return lib.notify({ type = 'error', description = 'You do not have access to this boombox.' })
    end

    lib.registerContext({
        id = contextId,
        title = box.label or 'Native Boombox',
        options = options
    })
    lib.showContext(contextId)
end

local targetOptions = {
    {
        name = 'nativeBoombox_control',
        icon = 'fas fa-radio',
        label = 'Use Boombox',
        distance = Config.InteractDistance,
        canInteract = function(entity) return entityBoxId(entity) ~= nil end,
        onSelect = function(data)
            local id = entityBoxId(data.entity)
            if id then openRadio(id, data.entity) end
        end
    }
}

local function addWorldZone(box)
    if worldZones[box.id] or box.controllable == false then return end
    worldZones[box.id] = exports.ox_target:addSphereZone({
        coords = vec3(box.x, box.y, box.z),
        radius = 0.8,
        debug = Config.Debug,
        drawSprite = Config.Debug,
        options = {
            {
                name = ('nativeBoombox_world_%s'):format(box.id),
                icon = 'fas fa-radio',
                label = 'Use Radio',
                distance = Config.InteractDistance,
                onSelect = function() openRadio(box.id) end
            }
        }
    })
end

RegisterNetEvent('nativeBoombox:client:upsert', function(box)
    boxes[box.id] = box
    if box.kind == 'world' then addWorldZone(box) end
    if initialised then RefreshBoomboxAudio(box) end
end)

RegisterNetEvent('nativeBoombox:client:remove', function(id)
    boxes[id] = nil
    if worldZones[id] then exports.ox_target:removeZone(worldZones[id]) worldZones[id] = nil end
end)

exports('useBoombox', function(data, slot)
    local slotId = type(slot) == 'table' and slot.slot or slot
    BeginBoomboxPlacement(slotId)
end)

CreateThread(function()
    exports.ox_target:addModel(Config.PropModel, targetOptions)
    local stateOk, state = pcall(lib.callback.await, 'nativeBoombox:server:getState', false)
    if not stateOk or type(state) ~= 'table' then
        return lib.notify({ type = 'error', description = 'Boombox state could not be loaded.' })
    end
    for i = 1, #state do
        if not boxes[state[i].id] then boxes[state[i].id] = state[i] end
        if state[i].kind == 'world' then addWorldZone(state[i]) end
    end
    InitialiseBoomboxAudio(boxes)
    initialised = true
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local openContext = lib.getOpenContextMenu()
    if openContext and openContext:find('^nativeBoombox_') then lib.hideContext(false) end
    if renameDialogOpen then lib.closeInputDialog() end
    if interactionAlertOpen then lib.closeAlertDialog() end
    StopBoomboxAudio()
    exports.ox_target:removeModel(Config.PropModel, { 'nativeBoombox_control' })
    for _, zone in pairs(worldZones) do exports.ox_target:removeZone(zone) end
end)
