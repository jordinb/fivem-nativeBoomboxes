local boxes
local currentId
local currentStation
local sceneActive = false
local dirty = true

local function stopPortableEmitter()
    if currentId then SetStaticEmitterEnabled(Config.Audio.emitter, false) end
    if sceneActive then
        StopAudioScene(Config.Audio.scene)
        sceneActive = false
    end
    currentId = nil
    currentStation = nil
end

local function applyWorldEmitter(box)
    if not box.emitter or box.emitter == '' then return end
    SetEmitterRadioStation(box.emitter, box.station)
    SetStaticEmitterEnabled(box.emitter, box.powered)
end

local function nearestPortable()
    local playerPosition = GetEntityCoords(cache.ped)
    local bestId, bestEntity, bestDistance
    for id, box in pairs(boxes) do
        if box.kind == 'placed' and box.powered and box.netId then
            local entity = NetworkGetEntityFromNetworkId(box.netId)
            if entity ~= 0 and DoesEntityExist(entity) then
                local distance = #(playerPosition - GetEntityCoords(entity))
                if distance <= Config.Audio.distance and (not bestDistance or distance < bestDistance) then
                    bestId, bestEntity, bestDistance = id, entity, distance
                end
            end
        end
    end
    return bestId, bestEntity
end

local function audioLoop()
    while true do
        local id, entity = nearestPortable()
        if not id then
            stopPortableEmitter()
        else
            local box = boxes[id]
            if dirty or currentId ~= id or currentStation ~= box.station then
                if not sceneActive then
                    StartAudioScene(Config.Audio.scene)
                    sceneActive = true
                end
                Citizen.InvokeNative(0x651D3228960D08AF, Config.Audio.emitter, entity)
                SetEmitterRadioStation(Config.Audio.emitter, box.station)
                SetStaticEmitterEnabled(Config.Audio.emitter, true)
                currentId = id
                currentStation = box.station
                dirty = false
            end
        end
        Wait(Config.Audio.scanInterval)
    end
end

function InitialiseBoomboxAudio(sharedBoxes)
    boxes = sharedBoxes
    for _, box in pairs(boxes) do if box.kind == 'world' then applyWorldEmitter(box) end end
    CreateThread(function()
        local ok, err = xpcall(audioLoop, debug.traceback)
        if not ok then
            stopPortableEmitter()
            print(('[nativeBoombox] Audio worker stopped: %s'):format(err))
        end
    end)
end

function RefreshBoomboxAudio(box)
    dirty = true
    if box.kind == 'world' then applyWorldEmitter(box) end
end

function StopBoomboxAudio()
    stopPortableEmitter()
    if boxes then
        for _, box in pairs(boxes) do
            if box.kind == 'world' and box.emitter then SetStaticEmitterEnabled(box.emitter, false) end
        end
    end
end

