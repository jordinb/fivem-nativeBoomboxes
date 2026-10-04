-- Debug-only proof of concept for native GTA radio-track playback.
-- This file is intentionally isolated from production mixtape logic.
-- Commands are registered only when Config.Debug is enabled.

if not Config.Debug then return end

local TEST_TRACKS = {
    fortunate_son = {
        station = 'RADIO_01_CLASS_ROCK',
        audioId = 'radio_01_class_rock_fortunate_son',
        durationMs = 129216,
        label = 'Creedence Clearwater Revival - Fortunate Son'
    },
    radio_ga_ga = {
        station = 'RADIO_01_CLASS_ROCK',
        audioId = 'radio_01_class_rock_radio_ga_ga',
        durationMs = 278613,
        label = 'Queen - Radio Ga Ga'
    },
    gimme_more = {
        station = 'RADIO_02_POP',
        audioId = 'radio_02_pop_gimme_more',
        durationMs = 205898,
        label = 'Britney Spears - Gimme More'
    },
    adhd = {
        station = 'RADIO_03_HIPHOP_NEW',
        audioId = 'radio_03_hiphop_new_adhd',
        durationMs = 198784,
        label = 'Kendrick Lamar - A.D.H.D'
    },
    the_box = {
        station = 'RADIO_03_HIPHOP_NEW',
        audioId = 'dlc_security_music_radio_03_hiphop_new_the_box',
        durationMs = 196652,
        label = 'Roddy Ricch - The Box'
    },
    california_love = {
        station = 'RADIO_09_HIPHOP_OLD',
        audioId = 'dlc_security_music_radio_09_hiphop_old_california_love_single',
        durationMs = 240568,
        label = '2Pac feat. Roger Troutman & Dr. Dre - California Love'
    }
}

local activeTest

local function nearestLocalBoombox()
    local playerCoords = GetEntityCoords(cache.ped)
    local bestEntity, bestDistance

    for _, entity in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(entity) and GetEntityModel(entity) == Config.PropModel then
            local state = Entity(entity).state
            if state.nativeBoomboxId then
                local distance = #(playerCoords - GetEntityCoords(entity))
                if distance <= Config.Audio.distance and (not bestDistance or distance < bestDistance) then
                    bestEntity = entity
                    bestDistance = distance
                end
            end
        end
    end

    return bestEntity, bestDistance
end

local function printTrackList()
    print('^5[nativeBoombox POC]^7 Available test tracks:')
    local keys = {}
    for key in pairs(TEST_TRACKS) do keys[#keys + 1] = key end
    table.sort(keys)

    for i = 1, #keys do
        local key = keys[i]
        local track = TEST_TRACKS[key]
        print(('  ^3%s^7 -> %s [%s]'):format(key, track.label, track.station))
    end
end

local function forceTrack(track, offsetMs)
    local entity, distance = nearestLocalBoombox()
    if not entity then
        return print('^1[nativeBoombox POC]^7 No streamed nativeBoombox is within audio range.')
    end

    offsetMs = math.max(0, math.floor(tonumber(offsetMs) or 0))
    if offsetMs >= track.durationMs then
        return print(('^1[nativeBoombox POC]^7 Offset must be below %d ms.'):format(track.durationMs))
    end

    Citizen.InvokeNative(0x651D3228960D08AF, Config.Audio.emitter, entity) -- LINK_STATIC_EMITTER_TO_ENTITY
    SetEmitterRadioStation(Config.Audio.emitter, track.station)
    SetStaticEmitterEnabled(Config.Audio.emitter, true)

    FreezeRadioStation(track.station)
    SetRadioAutoUnfreeze(false)

    if offsetMs > 0 then
        Citizen.InvokeNative(0x2CB0075110BE1E56, track.station, track.audioId, offsetMs)
    else
        SetRadioTrack(track.station, track.audioId)
    end

    UnfreezeRadioStation(track.station)
    SetRadioAutoUnfreeze(true)

    activeTest = {
        key = nil,
        station = track.station,
        audioId = track.audioId,
        expectedHash = GetHashKey(track.audioId),
        durationMs = track.durationMs,
        requestedOffsetMs = offsetMs,
        entity = entity,
        startedAt = GetGameTimer()
    }

    print(('^2[nativeBoombox POC]^7 Requested "%s" at %d ms on boombox entity %d (%.2fm away).')
        :format(track.label, offsetMs, entity, distance or 0.0))
end

local function printStatus()
    if not activeTest then
        return print('^3[nativeBoombox POC]^7 No track has been requested this session.')
    end

    local playbackMs = GetCurrentRadioTrackPlaybackTime(activeTest.station)
    local actualHash = GetCurrentTrackSoundName(activeTest.station)
    local hashMatches = actualHash == activeTest.expectedHash
    local entityValid = activeTest.entity ~= 0 and DoesEntityExist(activeTest.entity)

    print(('^5[nativeBoombox POC]^7 station=%s playback=%sms expectedHash=%s actualHash=%s match=%s entityValid=%s')
        :format(
            activeTest.station,
            tostring(playbackMs),
            tostring(activeTest.expectedHash),
            tostring(actualHash),
            tostring(hashMatches),
            tostring(entityValid)
        ))
end

RegisterCommand('nbmixpoc', function(_, args)
    local action = args[1] and args[1]:lower() or 'help'

    if action == 'list' then
        printTrackList()
        return
    end

    if action == 'status' then
        printStatus()
        return
    end

    if action == 'play' then
        local key = args[2] and args[2]:lower()
        local track = key and TEST_TRACKS[key]
        if not track then
            print('^1[nativeBoombox POC]^7 Unknown track. Use /nbmixpoc list.')
            return
        end

        activeTest = nil
        forceTrack(track, args[3])
        if activeTest then activeTest.key = key end
        return
    end

    print('^5[nativeBoombox POC]^7 Commands:')
    print('  /nbmixpoc list')
    print('  /nbmixpoc play <track_key> [offset_ms]')
    print('  /nbmixpoc status')
end, false)
