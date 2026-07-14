local boxes = {}
local entities = {}
local world = {}
local ready = false
local cooldowns = {}
local operationLocks = {}
local placementLocks = {}
local recoveryFailures = {}
local errorReports = {}

local function license(source)
    return GetPlayerIdentifierByType(source, 'license') or GetPlayerIdentifierByType(source, 'license2')
end

local function finiteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return end
    return value
end

local function normalizeAngle(value)
    return (value + 180.0) % 360.0 - 180.0
end

local function reportError(scope, err)
    local now = GetGameTimer()
    if errorReports[scope] and now - errorReports[scope] < 60000 then return end
    errorReports[scope] = now
    print(('[nativeBoombox] %s failed: %s'):format(scope, err))
end

local function acquireLock(id)
    if operationLocks[id] then return false end
    operationLocks[id] = true
    return true
end

local function releaseLock(id)
    operationLocks[id] = nil
end

local function validateConfig()
    local problems = {}
    local coordinateLimit = finiteNumber(Config.Validation and Config.Validation.worldCoordinateLimit)
    local function requireNumber(value, label, minimum)
        local number = finiteNumber(value)
        if not number or number < minimum then
            problems[#problems + 1] = ('%s must be a finite number greater than or equal to %s'):format(label, minimum)
        end
    end

    if type(Config.ItemName) ~= 'string' or Config.ItemName == '' then
        problems[#problems + 1] = 'Config.ItemName must be a non-empty string'
    end
    if type(Config.PropModel) ~= 'number' then
        problems[#problems + 1] = 'Config.PropModel must be a model hash'
    end
    if type(Config.EntityRecovery and Config.EntityRecovery.enabled) ~= 'boolean' then
        problems[#problems + 1] = 'Config.EntityRecovery.enabled must be a boolean'
    end
    if type(Config.Audio and Config.Audio.emitter) ~= 'string' or Config.Audio.emitter == '' then
        problems[#problems + 1] = 'Config.Audio.emitter must be a non-empty string'
    end
    if type(Config.Audio and Config.Audio.scene) ~= 'string' or Config.Audio.scene == '' then
        problems[#problems + 1] = 'Config.Audio.scene must be a non-empty string'
    end
    if not StationLookup[Config.DefaultStation] then
        problems[#problems + 1] = 'Config.DefaultStation is not present in Stations'
    end
    if type(Config.AllowAnyoneToControl) ~= 'boolean' then
        problems[#problems + 1] = 'Config.AllowAnyoneToControl must be a boolean'
    end
    if type(Config.AllowAnyoneToPickup) ~= 'boolean' then
        problems[#problems + 1] = 'Config.AllowAnyoneToPickup must be a boolean'
    end
    requireNumber(Config.InteractDistance, 'Config.InteractDistance', 0.1)
    requireNumber(Config.Placement and Config.Placement.initialDistance, 'Config.Placement.initialDistance', 0.1)
    requireNumber(Config.Placement and Config.Placement.maximumDistance, 'Config.Placement.maximumDistance', 0.1)
    requireNumber(Config.MaximumOwned, 'Config.MaximumOwned', 1)
    requireNumber(Config.Audio and Config.Audio.distance, 'Config.Audio.distance', 1)
    requireNumber(Config.Audio and Config.Audio.scanInterval, 'Config.Audio.scanInterval', 50)
    requireNumber(Config.EntityRecovery and Config.EntityRecovery.interval, 'Config.EntityRecovery.interval', 1000)
    requireNumber(Config.Validation and Config.Validation.worldCoordinateLimit,
        'Config.Validation.worldCoordinateLimit', 1000)

    local editor = Config.Placement and Config.Placement.editor
    requireNumber(editor and editor.holdDelay, 'Config.Placement.editor.holdDelay', 0)
    for _, modifier in ipairs({ 'precision', 'normal', 'fast' }) do
        requireNumber(editor and editor.moveNudge and editor.moveNudge[modifier],
            ('Config.Placement.editor.moveNudge.%s'):format(modifier), 0.001)
        requireNumber(editor and editor.moveSpeed and editor.moveSpeed[modifier],
            ('Config.Placement.editor.moveSpeed.%s'):format(modifier), 0.001)
        requireNumber(editor and editor.rotateNudge and editor.rotateNudge[modifier],
            ('Config.Placement.editor.rotateNudge.%s'):format(modifier), 0.1)
        requireNumber(editor and editor.rotateSpeed and editor.rotateSpeed[modifier],
            ('Config.Placement.editor.rotateSpeed.%s'):format(modifier), 0.1)
    end

    if type(Config.WorldRadios) ~= 'table' then
        problems[#problems + 1] = 'Config.WorldRadios must be a table'
    else
        local emitters = {}
        for i = 1, #Config.WorldRadios do
            local radio = Config.WorldRadios[i]
            local prefix = ('Config.WorldRadios[%s]'):format(i)
            if type(radio) ~= 'table' then
                problems[#problems + 1] = prefix .. ' must be a table'
                radio = {}
            end
            if not radio.coords or not finiteNumber(radio.coords.x) or not finiteNumber(radio.coords.y)
                or not finiteNumber(radio.coords.z) then
                problems[#problems + 1] = prefix .. '.coords must contain finite x, y, and z values'
            elseif coordinateLimit and (math.abs(radio.coords.x) > coordinateLimit
                or math.abs(radio.coords.y) > coordinateLimit
                or math.abs(radio.coords.z) > coordinateLimit) then
                problems[#problems + 1] = prefix .. '.coords exceeds the configured world coordinate limit'
            end
            if type(radio.emitter) ~= 'string' or radio.emitter == '' then
                problems[#problems + 1] = prefix .. '.emitter must be a non-empty string'
            elseif emitters[radio.emitter] then
                problems[#problems + 1] = prefix .. '.emitter duplicates another world radio emitter'
            else
                emitters[radio.emitter] = true
            end
            if radio.defaultStation and not StationLookup[radio.defaultStation] then
                problems[#problems + 1] = prefix .. '.defaultStation is not present in Stations'
            end
            if radio.controllable ~= nil and type(radio.controllable) ~= 'boolean' then
                problems[#problems + 1] = prefix .. '.controllable must be a boolean when provided'
            end
        end
    end

    if #problems > 0 then
        error(('Invalid configuration:\n- %s'):format(table.concat(problems, '\n- ')), 0)
    end
end

local function serialize(box)
    return {
        id = box.id,
        kind = box.kind,
        netId = box.netId,
        x = box.x, y = box.y, z = box.z,
        station = box.station,
        powered = box.powered == true or box.powered == 1,
        emitter = box.emitter,
        label = box.label,
        controllable = box.controllable
    }
end

local function isNear(source, box, distance)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    local p = GetEntityCoords(ped)
    local dx, dy, dz = p.x - box.x, p.y - box.y, p.z - box.z
    return dx * dx + dy * dy + dz * dz <= distance * distance
end

local function rateLimited(source, action, milliseconds)
    local now = GetGameTimer()
    local key = ('%s:%s'):format(source, action)
    if cooldowns[key] and now - cooldowns[key] < milliseconds then return true end
    cooldowns[key] = now
    return false
end

local function spawn(box)
    local entity = CreateObjectNoOffset(Config.PropModel, box.x, box.y, box.z, true, true, false)
    if entity == 0 then return false end
    SetEntityRotation(entity, box.rot_x, box.rot_y, box.rot_z, 2, true)
    FreezeEntityPosition(entity, true)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if netId == 0 then
        DeleteEntity(entity)
        return false
    end
    box.netId = netId
    entities[box.id] = entity
    SetEntityOrphanMode(entity, 2)
    Entity(entity).state:set('nativeBoomboxId', box.id, true)
    return true
end

local function despawn(id)
    local entity = entities[id]
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    entities[id] = nil
end

local function broadcast(box)
    TriggerClientEvent('nativeBoombox:client:upsert', -1, serialize(box))
end

validateConfig()

local function initialise()
    Database.init()
    local rows = Database.load()
    for i = 1, #rows do
        local box = rows[i]
        box.kind = 'placed'
        box.powered = box.powered == true or tonumber(box.powered) == 1
        boxes[box.id] = box
        spawn(box)
    end

    for i = 1, #Config.WorldRadios do
        local cfg = Config.WorldRadios[i]
        local id = -i
        world[id] = {
            id = id, kind = 'world', owner = 'world',
            x = cfg.coords.x, y = cfg.coords.y, z = cfg.coords.z,
            station = cfg.defaultStation or Config.DefaultStation,
            powered = cfg.powered ~= false,
            emitter = cfg.emitter,
            label = cfg.label or ('World Radio %s'):format(i),
            controllable = cfg.controllable ~= false
        }
    end
    ready = true
end

MySQL.ready(function()
    local ok, err = xpcall(initialise, debug.traceback)
    if not ok then
        reportError('database initialization', err)
        StopResource(GetCurrentResourceName())
    end
end)

lib.callback.register('nativeBoombox:server:getState', function()
    while not ready do Wait(50) end
    local result = {}
    for _, box in pairs(boxes) do result[#result + 1] = serialize(box) end
    for _, box in pairs(world) do result[#result + 1] = serialize(box) end
    return result
end)

RegisterNetEvent('nativeBoombox:server:place', function(position, rotation, slotId)
    local source = source
    if not ready then return end
    if rateLimited(source, 'place', 1500) then return end
    if type(position) ~= 'table' or type(rotation) ~= 'table' or type(slotId) ~= 'number' then return end
    if placementLocks[source] then return end
    local owner = license(source)
    if not owner then return end

    local x, y, z = finiteNumber(position.x), finiteNumber(position.y), finiteNumber(position.z)
    local rx, ry, rz = finiteNumber(rotation.x), finiteNumber(rotation.y), finiteNumber(rotation.z)
    if not x or not y or not z or not rx or not ry or not rz then return end
    local coordinateLimit = Config.Validation.worldCoordinateLimit
    if math.abs(x) > coordinateLimit or math.abs(y) > coordinateLimit or math.abs(z) > coordinateLimit then return end

    local p = vector3(x, y, z)
    local r = vector3(normalizeAngle(rx), normalizeAngle(ry), normalizeAngle(rz))
    if not isNear(source, { x = p.x, y = p.y, z = p.z }, Config.Placement.maximumDistance) then return end

    local owned = 0
    for _, box in pairs(boxes) do
        if box.owner == owner then owned = owned + 1 end
    end
    if owned >= Config.MaximumOwned then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'You have reached the boombox placement limit.' })
        return
    end

    placementLocks[source] = true
    if not exports.ox_inventory:RemoveItem(source, Config.ItemName, 1, nil, slotId) then
        placementLocks[source] = nil
        return
    end

    local persisted = false
    local box
    local ok, err = xpcall(function()
        local id = Database.insert(owner, p, r)
        if not id then error('database insert returned no id', 0) end
        persisted = true

        box = {
            id = id, kind = 'placed', owner = owner,
            x = p.x, y = p.y, z = p.z,
            rot_x = r.x, rot_y = r.y, rot_z = r.z,
            station = Config.DefaultStation, powered = false
        }
        boxes[id] = box
        local spawned = spawn(box)
        broadcast(box)
        if not spawned then
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'inform',
                description = 'The boombox was saved and will appear as soon as its entity can be created.'
            })
        end
    end, debug.traceback)

    if not ok then
        if not persisted then
            local refunded = exports.ox_inventory:AddItem(source, Config.ItemName, 1, nil, slotId)
            if not refunded then
                reportError('placement refund', 'the removed inventory item could not be returned')
            end
        elseif box then
            boxes[box.id] = box
        end
        reportError('placement', err)
    end
    placementLocks[source] = nil
end)

RegisterNetEvent('nativeBoombox:server:setState', function(id, action, value)
    local source = source
    if not ready then return end
    if rateLimited(source, 'state', 250) then return end
    id = tonumber(id)
    if not id or not acquireLock(id) then return end

    local changedBox
    local previousStation
    local previousPower
    local ok, err = xpcall(function()
        local box = boxes[id] or world[id]
        if not box or not isNear(source, box, Config.InteractDistance + 1.0) then return end
        if box.kind == 'world' then
            if not box.controllable then return end
        elseif not Config.AllowAnyoneToControl and box.owner ~= license(source) then
            return
        end

        previousStation = box.station
        previousPower = box.powered
        if action == 'power' and type(value) == 'boolean' then
            box.powered = value
        elseif action == 'station' and type(value) == 'string' and StationLookup[value] then
            box.station = value
        else
            return
        end

        changedBox = box
        if box.kind == 'placed' then Database.updateState(box) end
    end, debug.traceback)

    if not ok and changedBox then
        changedBox.station = previousStation
        changedBox.powered = previousPower
    end
    releaseLock(id)
    if not ok then
        reportError('state update', err)
    elseif changedBox then
        broadcast(changedBox)
    end
end)

RegisterNetEvent('nativeBoombox:server:pickup', function(id)
    local source = source
    if not ready then return end
    if rateLimited(source, 'pickup', 1000) then return end
    id = tonumber(id)
    if not id or not acquireLock(id) then return end

    local deletedBox
    local databaseDeleted = false
    local itemAdded = false
    local ok, err = xpcall(function()
        local box = boxes[id]
        if not box or not isNear(source, box, Config.InteractDistance + 1.0) then return end
        if not Config.AllowAnyoneToPickup and box.owner ~= license(source) then
            TriggerClientEvent('ox_lib:notify', source,
                { type = 'error', description = 'You do not own this boombox.' })
            return
        end
        if not exports.ox_inventory:CanCarryItem(source, Config.ItemName, 1) then
            TriggerClientEvent('ox_lib:notify', source,
                { type = 'error', description = 'You cannot carry the boombox.' })
            return
        end
        if not Database.delete(id) then return end
        deletedBox = box
        databaseDeleted = true

        local added = exports.ox_inventory:AddItem(source, Config.ItemName, 1)
        if not added then
            if not Database.restore(box) then
                error(('critical rollback failure for boombox %s'):format(id), 0)
            end
            databaseDeleted = false
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                description = 'The boombox could not be added to your inventory. It was left in place.'
            })
            return
        end
        itemAdded = true

        boxes[id] = nil
        despawn(id)
        TriggerClientEvent('nativeBoombox:client:remove', -1, id)
    end, debug.traceback)

    if not ok and databaseDeleted and not itemAdded and deletedBox then
        local restored, restoreResult = pcall(Database.restore, deletedBox)
        if restored and restoreResult then
            databaseDeleted = false
        else
            reportError('pickup rollback', restoreResult or 'the original database row could not be restored')
        end
    elseif not ok and itemAdded then
        boxes[id] = nil
        despawn(id)
        TriggerClientEvent('nativeBoombox:client:remove', -1, id)
    end

    releaseLock(id)
    if not ok then reportError('pickup', err) end
end)

if Config.EntityRecovery.enabled then
    CreateThread(function()
        while true do
            Wait(Config.EntityRecovery.interval)
            if ready then
                for id, box in pairs(boxes) do
                    local entity = entities[id]
                    if (not entity or not DoesEntityExist(entity)) and acquireLock(id) then
                        local recovered, recoveryError = xpcall(function()
                            local currentBox = boxes[id]
                            local currentEntity = entities[id]
                            if currentBox and (not currentEntity or not DoesEntityExist(currentEntity)) then
                                entities[id] = nil
                                currentBox.netId = nil
                                if spawn(currentBox) then
                                    recoveryFailures[id] = nil
                                    broadcast(currentBox)
                                    if Config.Debug then
                                        print(('[nativeBoombox] Recovered missing entity for boombox %s.'):format(id))
                                    end
                                elseif not recoveryFailures[id] then
                                    recoveryFailures[id] = true
                                    reportError(('entity recovery %s'):format(id),
                                        'the server could not create the object')
                                end
                            end
                        end, debug.traceback)
                        releaseLock(id)
                        if not recovered then
                            reportError(('entity recovery %s'):format(id), recoveryError)
                        end
                    else
                        recoveryFailures[id] = nil
                    end
                end
            end
        end
    end)
end

AddEventHandler('playerDropped', function()
    local prefix = ('%s:'):format(source)
    for key in pairs(cooldowns) do if key:sub(1, #prefix) == prefix then cooldowns[key] = nil end end
    placementLocks[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(entities) do despawn(id) end
end)
