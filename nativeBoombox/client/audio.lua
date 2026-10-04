local boxes
local currentId
local currentStation
local currentMode
local currentRevision
local currentAudioId
local musicOnlyStation
local debugBusOverride
local sceneActive = false
local dirty = true

local function ensureScene()
    if sceneActive then return end
    StartAudioScene(Config.Audio.scene)
    sceneActive = true
end

local function clearMusicOnly()
    if musicOnlyStation then
        SetRadioStationMusicOnly(musicOnlyStation, false)
        musicOnlyStation = nil
    end
end

local function setMusicOnly(station)
    if musicOnlyStation == station then return end

    clearMusicOnly()
    SetRadioStationMusicOnly(station, true)
    musicOnlyStation = station
end

local function clearCurrent()
    currentId = nil
    currentStation = nil
    currentMode = nil
    currentRevision = nil
    currentAudioId = nil
end

local function stopPortableEmitter()
    SetStaticEmitterEnabled(Config.Audio.emitter, false)
    clearMusicOnly()
    if sceneActive then
        StopAudioScene(Config.Audio.scene)
        sceneActive = false
    end
    clearCurrent()
end

local function applyWorldEmitter(box)
    if not box.emitter or box.emitter == '' then return end
    SetEmitterRadioStation(box.emitter, box.station)
    SetStaticEmitterEnabled(box.emitter, box.powered)
end

local function resolvePortableEntity(id, netId)
    if type(netId) ~= 'number' or netId <= 0 then return end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 or not DoesEntityExist(entity) then return end
    if Entity(entity).state.nativeBoomboxId ~= id then return end

    return entity
end

local function nearestPortable()
    local playerPosition = GetEntityCoords(cache.ped)
    local maxDistanceSquared = Config.Audio.distance * Config.Audio.distance
    local bestId, bestEntity, bestDistanceSquared

    for id, box in pairs(boxes) do
        if box.kind == 'placed' and box.powered and box.netId then
            local dx = playerPosition.x - box.x
            local dy = playerPosition.y - box.y
            local dz = playerPosition.z - box.z
            local distanceSquared = dx * dx + dy * dy + dz * dz

            if distanceSquared <= maxDistanceSquared
                and (not bestDistanceSquared or distanceSquared < bestDistanceSquared) then
                local entity = resolvePortableEntity(id, box.netId)
                if entity then
                    bestId = id
                    bestEntity = entity
                    bestDistanceSquared = distanceSquared
                end
            end
        end
    end

    return bestId, bestEntity
end

local function linkEmitter(entity, station)
    ensureScene()
    Citizen.InvokeNative(0x651D3228960D08AF, Config.Audio.emitter, entity)
    SetEmitterRadioStation(Config.Audio.emitter, station)
end

local function applyRadio(id, entity, box)
    clearMusicOnly()

    if dirty or currentId ~= id or currentMode ~= 'radio' or currentStation ~= box.station then
        linkEmitter(entity, box.station)
        SetStaticEmitterEnabled(Config.Audio.emitter, true)

        currentId = id
        currentStation = box.station
        currentMode = 'radio'
        currentRevision = nil
        currentAudioId = nil
        dirty = false
    end
end

local function calculatedMixtapeOffset(state)
    local offset = (tonumber(state.trackStartOffsetMs) or 0) + (tonumber(state.positionMs) or 0)

    if not state.paused and tonumber(state.syncUnix) then
        local cloudTime = GetCloudTimeAsInt()
        if cloudTime and cloudTime > 0 then
            local elapsedSeconds = math.max(0, cloudTime - state.syncUnix)
            offset = offset + elapsedSeconds * 1000
        end
    end

    local startOffset = tonumber(state.trackStartOffsetMs) or 0
    local duration = tonumber(state.trackDurationMs) or 0
    if duration > 0 then
        offset = math.min(offset, startOffset + math.max(0, duration - 100))
    end

    return math.max(startOffset, math.floor(offset))
end

local function applyMixtape(id, entity, box)
    local state = Entity(entity).state.nativeBoomboxPlayback

    if type(state) ~= 'table' or state.mode ~= 'mixtape'
        or state.finished or state.waiting or not state.station or not state.audioId then
        clearMusicOnly()
        if dirty or currentId ~= id or currentMode ~= 'mixtape_silent' then
            SetStaticEmitterEnabled(Config.Audio.emitter, false)
            currentId = id
            currentStation = nil
            currentMode = 'mixtape_silent'
            currentRevision = type(state) == 'table' and state.revision or nil
            currentAudioId = nil
            dirty = false
        end
        return
    end

    local revision = tonumber(state.revision) or 0
    if dirty or currentId ~= id or currentMode ~= 'mixtape'
        or currentRevision ~= revision or currentAudioId ~= state.audioId then
        setMusicOnly(state.station)
        linkEmitter(entity, state.station)
        SetStaticEmitterEnabled(Config.Audio.emitter, true)

        FreezeRadioStation(state.station)
        SetRadioAutoUnfreeze(false)
        Citizen.InvokeNative(
            0x2CB0075110BE1E56,
            state.station,
            state.audioId,
            calculatedMixtapeOffset(state)
        )
        UnfreezeRadioStation(state.station)
        SetRadioAutoUnfreeze(true)
        SetRadioStationMusicOnly(state.station, true)

        currentId = id
        currentStation = state.station
        currentMode = 'mixtape'
        currentRevision = revision
        currentAudioId = state.audioId
        dirty = false

        if Config.Debug then
            local actualHash = GetCurrentTrackSoundName(state.station)
            local expectedHash = GetHashKey(state.audioId)
            if actualHash ~= 0 and actualHash ~= expectedHash then
                print(('[nativeBoombox] Mixtape track verification mismatch for box %s (%s).')
                    :format(id, state.audioId))
            end
        end
    end
end

local function audioLoop()
    while true do
        if not debugBusOverride then
            local id, entity = nearestPortable()
            if not id then
                stopPortableEmitter()
            else
                local box = boxes[id]
                if box.mode == 'mixtape' then
                    applyMixtape(id, entity, box)
                else
                    applyRadio(id, entity, box)
                end
            end
        end
        Wait(Config.Audio.scanInterval)
    end
end

if Config.Debug then
    local TEST_TRACK_LIST = 'radio_02_pop_music'
    local TEST_TRACK_OFFSET_MS = 887798 -- Gimme More: list offset 887561 + song marker 237.
    local TEST_AUDIO_ID = 'radio_02_pop_gimme_more'
    local MEDIA_PLAYER_BUS = 'RADIO_36_AUDIOPLAYER'
    local HIDDEN_TEST_BUS = 'HIDDEN_RADIO_ASTU_SILENCE'

    local function startBusTest(bus)
        local id, entity = nearestPortable()
        if not id or not entity then
            return print('^1[nativeBoombox bus test]^7 No streamed powered boombox is in audio range.')
        end

        debugBusOverride = {
            id = id,
            entity = entity,
            bus = bus,
            trackList = TEST_TRACK_LIST
        }

        SetStaticEmitterEnabled(Config.Audio.emitter, false)
        clearMusicOnly()
        ensureScene()

        UnlockRadioStationTrackList(bus, TEST_TRACK_LIST)
        SetRadioStationMusicOnly(bus, true)
        Citizen.InvokeNative(0x4E0AF9114608257C, bus, TEST_TRACK_LIST, TEST_TRACK_OFFSET_MS)

        Citizen.InvokeNative(0x651D3228960D08AF, Config.Audio.emitter, entity)
        SetEmitterRadioStation(Config.Audio.emitter, bus)
        SetStaticEmitterEnabled(Config.Audio.emitter, true)

        print(('^2[nativeBoombox bus test]^7 Playing Gimme More through %s on boombox %s.'):format(bus, id))
        print('^3[nativeBoombox bus test]^7 Verify Non-Stop-Pop FM elsewhere remains on its normal live program.')
    end

    RegisterCommand('nbmixbus', function(_, args)
        local action = args[1] and args[1]:lower() or 'help'

        if action == 'media' then
            startBusTest(MEDIA_PLAYER_BUS)
            return
        end

        if action == 'hidden' then
            startBusTest(HIDDEN_TEST_BUS)
            return
        end

        if action == 'status' then
            if not debugBusOverride then
                return print('^3[nativeBoombox bus test]^7 No isolated bus test is active.')
            end

            local bus = debugBusOverride.bus
            print(('^5[nativeBoombox bus test]^7 bus=%s playback=%s actualHash=%s expectedHash=%s match=%s')
                :format(
                    bus,
                    tostring(GetCurrentRadioTrackPlaybackTime(bus)),
                    tostring(GetCurrentTrackSoundName(bus)),
                    tostring(GetHashKey(TEST_AUDIO_ID)),
                    tostring(GetCurrentTrackSoundName(bus) == GetHashKey(TEST_AUDIO_ID))
                ))
            return
        end

        if action == 'stop' then
            if debugBusOverride then
                local bus = debugBusOverride.bus
                SetStaticEmitterEnabled(Config.Audio.emitter, false)
                SetRadioStationMusicOnly(bus, false)
                LockRadioStationTrackList(bus, TEST_TRACK_LIST)
                debugBusOverride = nil
                dirty = true
                clearCurrent()
                print('^2[nativeBoombox bus test]^7 Isolated bus test stopped; normal boombox audio will resume.')
            end
            return
        end

        print('^5[nativeBoombox bus test]^7 Commands:')
        print('  /nbmixbus media  - test Rockstar Media Player as an isolated backend')
        print('  /nbmixbus hidden - test a non-wheel hidden station as an isolated backend')
        print('  /nbmixbus status - inspect current backend track state')
        print('  /nbmixbus stop   - restore normal boombox audio')
    end, false)
end

function InitialiseBoomboxAudio(sharedBoxes)
    boxes = sharedBoxes
    for _, box in pairs(boxes) do
        if box.kind == 'world' then applyWorldEmitter(box) end
    end

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
            if box.kind == 'world' and box.emitter then
                SetStaticEmitterEnabled(box.emitter, false)
            end
        end
    end
end
