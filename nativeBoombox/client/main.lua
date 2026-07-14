local boxes = {}
local worldZones = {}
local initialised = false

local function entityBoxId(entity)
    if entity == 0 or not DoesEntityExist(entity) then return end
    return Entity(entity).state.nativeBoomboxId
end

local function openRadio(id)
    local box = boxes[id]
    if not box then return end
    local options = {
        {
            title = box.powered and 'Turn Off' or 'Turn On',
            icon = 'power-off',
            onSelect = function()
                TriggerServerEvent('nativeBoombox:server:setState', id, 'power', not box.powered)
            end
        }
    }
    for i = 1, #Stations do
        local station = Stations[i]
        options[#options + 1] = {
            title = station.label,
            icon = box.station == station.value and 'circle-check' or 'radio',
            disabled = box.station == station.value,
            onSelect = function()
                TriggerServerEvent('nativeBoombox:server:setState', id, 'station', station.value)
            end
        }
    end
    lib.registerContext({
        id = ('nativeBoombox_radio_%s'):format(id),
        title = box.label or 'Native Boombox',
        options = options
    })
    lib.showContext(('nativeBoombox_radio_%s'):format(id))
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
            if id then openRadio(id) end
        end
    },
    {
        name = 'nativeBoombox_pickup',
        icon = 'fas fa-hand',
        label = 'Pick Up Boombox',
        distance = Config.InteractDistance,
        canInteract = function(entity) return entityBoxId(entity) ~= nil end,
        onSelect = function(data)
            local id = entityBoxId(data.entity)
            if id then TriggerServerEvent('nativeBoombox:server:pickup', id) end
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
    local state = lib.callback.await('nativeBoombox:server:getState', false)
    for i = 1, #state do
        if not boxes[state[i].id] then boxes[state[i].id] = state[i] end
        if state[i].kind == 'world' then addWorldZone(state[i]) end
    end
    InitialiseBoomboxAudio(boxes)
    initialised = true
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    StopBoomboxAudio()
    exports.ox_target:removeModel(Config.PropModel, { 'nativeBoombox_control', 'nativeBoombox_pickup' })
    for _, zone in pairs(worldZones) do exports.ox_target:removeZone(zone) end
end)
