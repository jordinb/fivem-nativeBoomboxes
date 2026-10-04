local recorder

local function formatDuration(ms)
    ms = math.max(0, math.floor(tonumber(ms) or 0))
    local totalSeconds = math.floor(ms / 1000)
    return ('%02d:%02d'):format(math.floor(totalSeconds / 60), totalSeconds % 60)
end

local function resolveSlotId(data, slot)
    if type(slot) == 'table' then return tonumber(slot.slot) end
    if type(slot) == 'number' then return slot end
    if type(data) == 'table' then return tonumber(data.slot) end
end

local function availableTracks(station)
    local result = {}
    local source = MixtapeTracksByStation[station] or {}
    local build = recorder and recorder.gameBuild or 999999

    for i = 1, #source do
        local track = source[i]
        if (tonumber(track.minBuild) or 1) <= build then
            result[#result + 1] = track
        end
    end

    return result
end

local function currentDuration()
    local total = 0
    if not recorder then return total end

    for i = 1, #recorder.trackIds do
        local track = MixtapeTrackLookup[recorder.trackIds[i]]
        if track then total = total + track.durationMs end
    end

    return total
end

local showBuilder

local function showPlaylist()
    if not recorder then return end
    local options = {}

    for i = 1, #recorder.trackIds do
        local index = i
        local track = MixtapeTrackLookup[recorder.trackIds[i]]
        options[#options + 1] = {
            title = ('%02d. %s'):format(i, track and track.title or 'Unknown Track'),
            description = track and (('%s • %s'):format(track.artist, formatDuration(track.durationMs))) or nil,
            icon = 'music',
            onSelect = function()
                table.remove(recorder.trackIds, index)
                lib.notify({ type = 'success', description = 'Track removed from the mixtape.' })
                showPlaylist()
            end
        }
    end

    if #options == 0 then
        options[1] = {
            title = 'No Tracks Added',
            description = 'Add songs from the radio catalog first.',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'nativeBoombox_mixtape_playlist',
        title = ('%s — %s used'):format(recorder.title, formatDuration(currentDuration())),
        menu = 'nativeBoombox_mixtape_builder',
        options = options
    })
    lib.showContext('nativeBoombox_mixtape_playlist')
end

local function chooseTrack(station)
    if not recorder then return end
    local tracks = availableTracks(station)
    if #tracks == 0 then
        return lib.notify({ type = 'error', description = 'No compatible tracks are available for that station.' })
    end

    local selectOptions = {}
    for i = 1, #tracks do
        local track = tracks[i]
        selectOptions[#selectOptions + 1] = {
            value = track.id,
            label = ('%s — %s [%s]'):format(track.artist, track.title, formatDuration(track.durationMs))
        }
    end

    local input = lib.inputDialog(StationLookup[station] or 'Select Track', {
        {
            type = 'select',
            label = 'Track',
            required = true,
            searchable = true,
            options = selectOptions
        }
    })
    if not input or not input[1] then return showBuilder() end

    local track = MixtapeTrackLookup[input[1]]
    if not track then return showBuilder() end
    if #recorder.trackIds >= recorder.maximumTracks then
        lib.notify({ type = 'error', description = 'This mixtape has reached its track limit.' })
        return showBuilder()
    end

    local newDuration = currentDuration() + track.durationMs
    if newDuration > recorder.capacityMs then
        lib.notify({
            type = 'error',
            description = ('That track would exceed the cassette capacity by %s.'):format(
                formatDuration(newDuration - recorder.capacityMs)
            )
        })
        return showBuilder()
    end

    recorder.trackIds[#recorder.trackIds + 1] = track.id
    lib.notify({
        type = 'success',
        description = ('Added %s — %s'):format(track.artist, track.title)
    })
    showBuilder()
end

local function chooseStation()
    if not recorder then return end
    local options = {}

    for i = 1, #Stations do
        local station = Stations[i]
        local stationValue = station.value
        local count = #availableTracks(stationValue)
        if count > 0 then
            options[#options + 1] = {
                title = station.label,
                description = ('%s available tracks'):format(count),
                icon = 'radio',
                onSelect = function() chooseTrack(stationValue) end
            }
        end
    end

    lib.registerContext({
        id = 'nativeBoombox_mixtape_stations',
        title = 'Add Track',
        menu = 'nativeBoombox_mixtape_builder',
        options = options
    })
    lib.showContext('nativeBoombox_mixtape_stations')
end

local function recordTape()
    if not recorder or #recorder.trackIds == 0 then
        return lib.notify({ type = 'error', description = 'Add at least one track first.' })
    end

    local answer = lib.alertDialog({
        header = 'Record Mixtape',
        content = ('Record **%s** with %s tracks (%s)?\n\nThis will permanently record the blank cassette.'):format(
            recorder.title,
            #recorder.trackIds,
            formatDuration(currentDuration())
        ),
        centered = true,
        cancel = true
    })
    if answer ~= 'confirm' then return showBuilder() end

    local ok, success, result = pcall(
        lib.callback.await,
        'nativeBoombox:server:recordMixtape',
        false,
        recorder.slotId,
        recorder.title,
        recorder.trackIds
    )

    if not ok or not success then
        lib.notify({
            type = 'error',
            description = type(result) == 'string' and result or 'The mixtape could not be recorded.'
        })
        return showBuilder()
    end

    lib.notify({
        type = 'success',
        description = ('Recorded "%s" — %s tracks, %s.'):format(
            result.title,
            result.trackCount,
            formatDuration(result.durationMs)
        )
    })
    recorder = nil
end

showBuilder = function()
    if not recorder then return end

    local used = currentDuration()
    local remaining = math.max(0, recorder.capacityMs - used)

    lib.registerContext({
        id = 'nativeBoombox_mixtape_builder',
        title = recorder.title,
        options = {
            {
                title = 'Add Track',
                description = ('%s remaining • %s/%s tracks'):format(
                    formatDuration(remaining),
                    #recorder.trackIds,
                    recorder.maximumTracks
                ),
                icon = 'plus',
                disabled = remaining <= 0 or #recorder.trackIds >= recorder.maximumTracks,
                onSelect = chooseStation
            },
            {
                title = 'Edit Playlist',
                description = ('%s tracks • %s used'):format(#recorder.trackIds, formatDuration(used)),
                icon = 'list-ol',
                disabled = #recorder.trackIds == 0,
                onSelect = showPlaylist
            },
            {
                title = 'Record Mixtape',
                description = 'Finalize this playlist onto the cassette.',
                icon = 'compact-disc',
                disabled = #recorder.trackIds == 0,
                onSelect = recordTape
            },
            {
                title = 'Cancel',
                description = 'Discard this draft. The cassette remains blank.',
                icon = 'xmark',
                onSelect = function() recorder = nil end
            }
        }
    })
    lib.showContext('nativeBoombox_mixtape_builder')
end

function OpenMixtapeRecorder(slotId)
    slotId = tonumber(slotId)
    if not slotId then
        return lib.notify({ type = 'error', description = 'The cassette inventory slot could not be resolved.' })
    end

    local ok, settings = pcall(lib.callback.await, 'nativeBoombox:server:getMixtapeConfig', false)
    if not ok or type(settings) ~= 'table' then
        return lib.notify({ type = 'error', description = 'Mixtape configuration could not be loaded.' })
    end

    local input = lib.inputDialog('Record Mixtape', {
        {
            type = 'input',
            label = 'Mixtape Title',
            required = true,
            minLength = 1,
            maxLength = Config.Mixtapes.titleMaximumLength
        }
    })
    if not input or not input[1] then return end

    recorder = {
        slotId = slotId,
        title = input[1],
        trackIds = {},
        capacityMs = settings.capacityMs or Config.Mixtapes.capacityMs,
        maximumTracks = settings.maximumTracks or Config.Mixtapes.maximumTracks,
        gameBuild = settings.gameBuild or 999999
    }
    showBuilder()
end

function OpenBoomboxCassetteBay(id)
    exports.ox_inventory:openInventory('stash', ('nativeBoombox_cassette_%s'):format(id))
end

exports('useCassette', function(data, slot)
    local slotId = resolveSlotId(data, slot)
    local metadata = type(slot) == 'table' and slot.metadata
        or type(data) == 'table' and data.metadata
        or {}

    if metadata and metadata.recorded == true then
        return lib.notify({
            type = 'inform',
            description = ('"%s" is already recorded. Insert it into a boombox cassette bay.'):format(
                metadata.mixtapeTitle or metadata.label or 'Mixtape'
            )
        })
    end

    OpenMixtapeRecorder(slotId)
end)
