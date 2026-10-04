Mixtapes = {}

local context
local playlistCache = {}
local activePlayback = {}
local hookId
local stashPrefix = 'nativeBoombox_cassette_'
local revision = 0

local function nextRevision()
    revision = revision + 1
    if revision > 2147483000 then revision = 1 end
    return revision
end

local function stashId(id)
    return ('%s%s'):format(stashPrefix, id)
end

local function parseStashId(value)
    if type(value) ~= 'string' then return end
    local id = value:match('^' .. stashPrefix .. '(%d+)$')
    return id and tonumber(id) or nil
end

local function effectiveBuild()
    local configured = tonumber(Config.Mixtapes.gameBuild) or 0
    if configured > 0 then return configured end

    local enforced = tonumber(GetConvar('sv_enforceGameBuild', '0')) or 0
    return enforced > 0 and enforced or 999999
end

local function validTrack(track)
    return track
        and StationLookup[track.station]
        and (tonumber(track.minBuild) or 1) <= effectiveBuild()
end

local function sanitizeTitle(value)
    if type(value) ~= 'string' then return end
    value = value:gsub('[%z\1-\31\127]', ''):match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if not length or length < 1 or length > Config.Mixtapes.titleMaximumLength then return end
    return value
end

local function loadPlaylist(id)
    id = tonumber(id)
    if not id then return end
    if playlistCache[id] then return playlistCache[id] end

    local mixtape = Database.loadMixtape(id)
    if not mixtape then return end

    local tracks = {}
    for i = 1, #mixtape.tracks do
        local track = MixtapeTrackLookup[mixtape.tracks[i].track_id]
        if validTrack(track) then
            tracks[#tracks + 1] = track
        end
    end

    if #tracks == 0 then return end

    mixtape.tracks = tracks
    playlistCache[id] = mixtape
    return mixtape
end

local function currentPosition(playback)
    if not playback then return 0 end
    if playback.paused or not playback.startedAtGame then
        return playback.offsetMs or 0
    end

    return math.max(0, (playback.offsetMs or 0) + (GetGameTimer() - playback.startedAtGame))
end

local function playbackPayload(box)
    if box.mode ~= 'mixtape' then return false end

    local playback = box.playback
    if not playback then
        return {
            mode = 'mixtape',
            finished = false,
            waiting = true,
            revision = nextRevision(),
            label = box.mixtapeLabel
        }
    end

    if playback.finished then
        return {
            mode = 'mixtape',
            finished = true,
            revision = playback.revision,
            index = playback.index,
            count = playback.count,
            label = box.mixtapeLabel
        }
    end

    local playlist = loadPlaylist(playback.mixtapeId)
    local track = playlist and playlist.tracks[playback.index]
    if not track then return false end

    local position = math.min(currentPosition(playback), track.durationMs)
    return {
        mode = 'mixtape',
        finished = false,
        paused = playback.paused == true,
        revision = playback.revision,
        index = playback.index,
        count = playback.count,
        trackId = track.id,
        station = track.station,
        audioId = track.audioId,
        trackStartOffsetMs = track.startOffsetMs or 0,
        trackDurationMs = track.durationMs,
        positionMs = position,
        syncUnix = os.time(),
        title = track.title,
        artist = track.artist,
        label = box.mixtapeLabel
    }
end

function Mixtapes.syncBoxEntity(box)
    if not context or not box or box.kind ~= 'placed' then return end
    local entity = context.entities[box.id]
    if not entity or not DoesEntityExist(entity) then return end
    Entity(entity).state:set('nativeBoomboxPlayback', playbackPayload(box), true)
end

local function setFinished(box)
    local playback = box.playback or {}
    playback.finished = true
    playback.paused = false
    playback.startedAtGame = nil
    playback.offsetMs = 0
    playback.revision = nextRevision()
    box.playback = playback
    activePlayback[box.id] = nil
    Mixtapes.syncBoxEntity(box)
end

local function startTrack(box, index, positionMs)
    local playlist = loadPlaylist(box.mixtapeId)
    if not playlist or not playlist.tracks[index] then
        return setFinished(box)
    end

    box.playback = {
        mixtapeId = box.mixtapeId,
        index = index,
        count = #playlist.tracks,
        offsetMs = math.max(0, tonumber(positionMs) or 0),
        startedAtGame = GetGameTimer(),
        startedAtUnix = os.time(),
        paused = not box.powered,
        finished = false,
        revision = nextRevision()
    }

    if box.playback.paused then
        box.playback.startedAtGame = nil
        activePlayback[box.id] = nil
    else
        activePlayback[box.id] = box
    end

    Mixtapes.syncBoxEntity(box)
end

function Mixtapes.onPowerChanged(box, powered)
    if not box or box.mode ~= 'mixtape' then return end

    local playback = box.playback
    if not playback then
        if powered then startTrack(box, 1, 0) end
        return
    end

    if playback.finished then
        activePlayback[box.id] = nil
        Mixtapes.syncBoxEntity(box)
        return
    end

    if powered and playback.paused then
        playback.paused = false
        playback.startedAtGame = GetGameTimer()
        playback.startedAtUnix = os.time()
        playback.revision = nextRevision()
        activePlayback[box.id] = box
    elseif not powered and not playback.paused then
        playback.offsetMs = currentPosition(playback)
        playback.paused = true
        playback.startedAtGame = nil
        playback.revision = nextRevision()
        activePlayback[box.id] = nil
    end

    Mixtapes.syncBoxEntity(box)
end

function Mixtapes.hasCassette(box)
    return box and box.mode == 'mixtape' and box.mixtapeId ~= nil
end

function Mixtapes.registerBox(box)
    if not Config.Mixtapes.enabled or not box or box.kind ~= 'placed' then return end

    exports.ox_inventory:RegisterStash(
        stashId(box.id),
        ('%s — Cassette Bay'):format(box.label or 'Boombox'),
        1,
        Config.Mixtapes.cassetteBayMaxWeight,
        false,
        nil,
        vec3(box.x, box.y, box.z)
    )
end

function Mixtapes.refreshBox(box, silent)
    if not Config.Mixtapes.enabled or not box or box.kind ~= 'placed' then return end

    local items = exports.ox_inventory:GetInventoryItems(stashId(box.id)) or {}
    local cassette

    for _, item in pairs(items) do
        if item.name == Config.Mixtapes.itemName and item.metadata
            and item.metadata.recorded == true and tonumber(item.metadata.mixtapeId) then
            cassette = item
            break
        end
    end

    local oldMode = box.mode
    local oldMixtapeId = box.mixtapeId

    if cassette then
        box.mode = 'mixtape'
        box.mixtapeId = tonumber(cassette.metadata.mixtapeId)
        box.mixtapeLabel = cassette.metadata.mixtapeTitle or cassette.metadata.label or 'Mixtape'

        if oldMixtapeId ~= box.mixtapeId then
            box.playback = nil
            if box.powered then startTrack(box, 1, 0) end
        elseif box.powered and not box.playback then
            startTrack(box, 1, 0)
        end
    else
        box.mode = 'radio'
        box.mixtapeId = nil
        box.mixtapeLabel = nil
        box.playback = nil
        activePlayback[box.id] = nil
        Mixtapes.syncBoxEntity(box)
    end

    if not silent and (oldMode ~= box.mode or oldMixtapeId ~= box.mixtapeId) then
        context.broadcast(box)
        context.audit(cassette and 'cassette_inserted' or 'cassette_ejected', nil, box, {
            mixtapeId = box.mixtapeId
        })
    end
end

local function validateCassetteMove(payload)
    local fromId = parseStashId(payload.fromInventory)
    local toId = parseStashId(payload.toInventory)
    local boxId = toId or fromId
    if not boxId then return end

    local box = context.boxes[boxId]
    if not box or not context.isNear(payload.source, box, Config.InteractDistance + 1.0)
        or not context.canPerform(payload.source, 'control', box) then
        return false
    end

    if toId then
        local item = payload.fromSlot
        local metadata = item and item.metadata
        if not item or item.name ~= Config.Mixtapes.itemName
            or not metadata or metadata.recorded ~= true
            or not tonumber(metadata.mixtapeId)
            or not loadPlaylist(metadata.mixtapeId) then
            TriggerClientEvent('ox_lib:notify', payload.source, {
                type = 'error',
                description = 'Only a recorded mixtape can be inserted into the cassette bay.'
            })
            return false
        end
    end
end

local function registerInventoryHook()
    hookId = exports.ox_inventory:registerHook('swapItems', validateCassetteMove, {
        inventoryFilter = { '^' .. stashPrefix }
    })

    AddEventHandler(hookId, function(success, payload)
        if not success then return end
        local id = parseStashId(payload.toInventory) or parseStashId(payload.fromInventory)
        if not id then return end

        SetTimeout(100, function()
            local box = context.boxes[id]
            if box then Mixtapes.refreshBox(box, false) end
        end)
    end)
end

local function registerCallbacks()
    lib.callback.register('nativeBoombox:server:getMixtapeConfig', function()
        return {
            capacityMs = Config.Mixtapes.capacityMs,
            maximumTracks = Config.Mixtapes.maximumTracks,
            gameBuild = effectiveBuild()
        }
    end)

    lib.callback.register('nativeBoombox:server:recordMixtape', function(source, slotId, title, trackIds)
        if not Config.Mixtapes.enabled or not context.ready() then return false, 'Mixtapes are unavailable.' end
        if context.rateLimited(source, 'record_mixtape', 1500) then return false, 'Please wait a moment.' end

        slotId = tonumber(slotId)
        title = sanitizeTitle(title)
        if not slotId or not title or type(trackIds) ~= 'table'
            or #trackIds < 1 or #trackIds > Config.Mixtapes.maximumTracks then
            return false, 'Invalid mixtape.'
        end

        local slot = exports.ox_inventory:GetSlot(source, slotId)
        if not slot or slot.name ~= Config.Mixtapes.itemName then
            return false, 'The cassette tape could not be found.'
        end

        local metadata = slot.metadata or {}
        if metadata.recorded == true then
            return false, 'That cassette has already been recorded.'
        end

        local capacityMs = Config.Mixtapes.capacityMs
        local validated = {}
        local durationMs = 0

        for i = 1, #trackIds do
            local trackId = trackIds[i]
            if type(trackId) ~= 'string' then return false, 'Invalid track selection.' end

            local track = MixtapeTrackLookup[trackId]
            if not validTrack(track) then
                return false, ('Track %s is unavailable on this server build.'):format(trackId)
            end

            durationMs = durationMs + track.durationMs
            if durationMs > capacityMs then
                return false, 'The selected tracks exceed the cassette capacity.'
            end
            validated[#validated + 1] = trackId
        end

        local creatorIdentifier = GetPlayerIdentifierByType(source, 'license')
            or GetPlayerIdentifierByType(source, 'license2')
        if not creatorIdentifier then return false, 'Your player identifier could not be resolved.' end

        local mixtapeId
        local ok, err = xpcall(function()
            mixtapeId = Database.createMixtape(
                creatorIdentifier,
                GetPlayerName(source) or 'Unknown',
                title,
                capacityMs,
                durationMs,
                validated
            )
            if not mixtapeId then error('mixtape database insert failed', 0) end

            metadata.recorded = true
            metadata.mixtapeId = mixtapeId
            metadata.mixtapeTitle = title
            metadata.trackCount = #validated
            metadata.runtimeMs = durationMs
            metadata.capacityMs = capacityMs
            metadata.label = title
            metadata.description = ('Recorded mixtape • %s tracks • %02d:%02d'):format(
                #validated,
                math.floor(durationMs / 60000),
                math.floor((durationMs % 60000) / 1000)
            )

            exports.ox_inventory:SetMetadata(source, slotId, metadata)
        end, debug.traceback)

        if not ok then
            if mixtapeId then Database.deleteMixtape(mixtapeId) end
            context.reportError('record mixtape', err)
            return false, 'The mixtape could not be recorded.'
        end

        playlistCache[mixtapeId] = nil
        return true, {
            id = mixtapeId,
            title = title,
            trackCount = #validated,
            durationMs = durationMs
        }
    end)
end

local function registerControls()
    RegisterNetEvent('nativeBoombox:server:mixtapeControl', function(id, action)
        local source = source
        if not Config.Mixtapes.enabled or not context.ready()
            or context.rateLimited(source, 'mixtape_control', 300) then return end

        id = tonumber(id)
        local box = id and context.boxes[id]
        if not box or box.mode ~= 'mixtape'
            or not context.isNear(source, box, Config.InteractDistance + 1.0)
            or not context.canPerform(source, 'control', box) then return end

        local playlist = loadPlaylist(box.mixtapeId)
        if not playlist then return end

        if action == 'restart' then
            startTrack(box, 1, 0)
        elseif action == 'next' then
            local index = box.playback and box.playback.index or 0
            if index >= #playlist.tracks then
                setFinished(box)
            else
                startTrack(box, index + 1, 0)
            end
        elseif action == 'previous' then
            local index = box.playback and box.playback.index or 1
            local position = box.playback and currentPosition(box.playback) or 0
            if position > 5000 or index <= 1 then
                startTrack(box, index, 0)
            else
                startTrack(box, index - 1, 0)
            end
        else
            return
        end

        context.audit('mixtape_control', source, box, { action = action })
    end)
end

local function playbackWorker()
    local lastSync = 0

    while true do
        local hasActive = next(activePlayback) ~= nil
        Wait(hasActive and Config.Mixtapes.advanceInterval or 1000)

        if context and context.ready() and hasActive then
            local now = GetGameTimer()
            local shouldSync = now - lastSync >= Config.Mixtapes.syncInterval

            for id, box in pairs(activePlayback) do
                local playback = box.playback

                if context.boxes[id] ~= box or box.mode ~= 'mixtape' or not box.powered
                    or not playback or playback.paused or playback.finished then
                    activePlayback[id] = nil
                else
                    local playlist = loadPlaylist(playback.mixtapeId)
                    local track = playlist and playlist.tracks[playback.index]

                    if not track then
                        setFinished(box)
                    else
                        local position = currentPosition(playback)

                        while track and position >= track.durationMs do
                            position = position - track.durationMs
                            local nextIndex = playback.index + 1

                            if nextIndex > #playlist.tracks then
                                setFinished(box)
                                track = nil
                                break
                            end

                            startTrack(box, nextIndex, position)
                            playback = box.playback
                            track = playlist.tracks[nextIndex]
                            position = currentPosition(playback)
                        end

                        if track and shouldSync then
                            Mixtapes.syncBoxEntity(box)
                        end
                    end
                end
            end

            if shouldSync then lastSync = now end
        end
    end
end

function Mixtapes.configure(value)
    context = value
    if not Config.Mixtapes.enabled then return end
    registerInventoryHook()
    registerCallbacks()
    registerControls()
    CreateThread(playbackWorker)
end

function Mixtapes.getStashId(id)
    return stashId(id)
end
