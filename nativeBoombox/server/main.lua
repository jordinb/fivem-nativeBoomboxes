local boxes = {}
local entities = {}
local world = {}
local ready = false
local cooldowns = {}
local operationLocks = {}
local placementLocks = {}
local editLocks = {}
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
    if type(Config.Labels and Config.Labels.default) ~= 'string' or Config.Labels.default == '' then
        problems[#problems + 1] = 'Config.Labels.default must be a non-empty string'
    end
    requireNumber(Config.Labels and Config.Labels.maximumLength, 'Config.Labels.maximumLength', 1)
    local maximumLabelLength = finiteNumber(Config.Labels and Config.Labels.maximumLength)
    local defaultLabelLength = type(Config.Labels and Config.Labels.default) == 'string'
        and utf8.len(Config.Labels.default) or nil
    if type(Config.Labels and Config.Labels.default) == 'string' and not defaultLabelLength then
        problems[#problems + 1] = 'Config.Labels.default must contain valid UTF-8 text'
    end
    if type(Config.Labels and Config.Labels.default) == 'string'
        and Config.Labels.default:find('[%z\1-\31\127]') then
        problems[#problems + 1] = 'Config.Labels.default cannot contain control characters'
    end
    if maximumLabelLength and maximumLabelLength % 1 ~= 0 then
        problems[#problems + 1] = 'Config.Labels.maximumLength must be an integer'
    elseif maximumLabelLength and maximumLabelLength > 48 then
        problems[#problems + 1] = 'Config.Labels.maximumLength cannot exceed the database limit of 48'
    elseif defaultLabelLength and maximumLabelLength and defaultLabelLength > maximumLabelLength then
        problems[#problems + 1] = 'Config.Labels.default exceeds Config.Labels.maximumLength'
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
    requireNumber(Config.Reposition and Config.Reposition.lockTimeout, 'Config.Reposition.lockTimeout', 10000)
    requireNumber(Config.Reposition and Config.Reposition.maximumDistanceFromPlayer,
        'Config.Reposition.maximumDistanceFromPlayer', 0.1)
    requireNumber(Config.Reposition and Config.Reposition.maximumDistanceFromOrigin,
        'Config.Reposition.maximumDistanceFromOrigin', 0.1)

    local validModes = { everyone = true, owner = true, ace = true, owner_or_ace = true, disabled = true }
    if type(Config.Permissions) ~= 'table' or type(Config.Permissions.actions) ~= 'table' then
        problems[#problems + 1] = 'Config.Permissions.actions must be a table'
    else
        if type(Config.Permissions.adminAce) ~= 'string' or Config.Permissions.adminAce == '' then
            problems[#problems + 1] = 'Config.Permissions.adminAce must be a non-empty string'
        end
        if type(Config.Permissions.adminBypass) ~= 'boolean' then
            problems[#problems + 1] = 'Config.Permissions.adminBypass must be a boolean'
        end
        for _, action in ipairs({ 'control', 'pickup', 'reposition', 'rename', 'worldControl' }) do
            local policy = Config.Permissions.actions[action]
            local prefix = ('Config.Permissions.actions.%s'):format(action)
            if type(policy) ~= 'table' or not validModes[policy.mode] then
                problems[#problems + 1] = prefix .. '.mode is invalid'
            elseif (policy.mode == 'ace' or policy.mode == 'owner_or_ace')
                and (type(policy.ace) ~= 'string' or policy.ace == '') then
                problems[#problems + 1] = prefix .. '.ace must be a non-empty string for this mode'
            end
        end
    end

    local function validateHook(hook, label)
        if type(hook) ~= 'table' then
            problems[#problems + 1] = label .. ' must be a table'
            return
        end
        if type(hook.resource) ~= 'string' or type(hook.export) ~= 'string' then
            problems[#problems + 1] = label .. '.resource and .export must be strings'
        elseif (hook.resource == '') ~= (hook.export == '') then
            problems[#problems + 1] = label .. '.resource and .export must both be configured or both be empty'
        end
    end
    validateHook(Config.Permissions and Config.Permissions.hook, 'Config.Permissions.hook')
    validateHook(Config.Audit and Config.Audit.hook, 'Config.Audit.hook')
    if type(Config.Audit and Config.Audit.print) ~= 'boolean' then
        problems[#problems + 1] = 'Config.Audit.print must be a boolean'
    end

    if type(Config.StationFilter) ~= 'table' or type(Config.StationFilter.allow) ~= 'table'
        or type(Config.StationFilter.block) ~= 'table' then
        problems[#problems + 1] = 'Config.StationFilter.allow and .block must be tables'
    else
        for listName, list in pairs({ allow = Config.StationFilter.allow, block = Config.StationFilter.block }) do
            for i = 1, #list do
                if not AllStationLookup[list[i]] then
                    problems[#problems + 1] = ('Config.StationFilter.%s[%s] is not a known station'):format(listName, i)
                end
            end
        end
    end

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
        rot_x = box.rot_x, rot_y = box.rot_y, rot_z = box.rot_z,
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

local function isAdmin(source)
    return IsPlayerAceAllowed(source, Config.Permissions.adminAce)
end

local function callConfiguredExport(hook, ...)
    if hook.resource == '' or GetResourceState(hook.resource) ~= 'started' then return nil end
    local ok, result = pcall(function(...)
        return exports[hook.resource][hook.export](...)
    end, ...)
    if not ok then
        reportError(('export %s:%s'):format(hook.resource, hook.export), result)
        return nil
    end
    return result
end

local function canPerform(source, action, box)
    local policyAction = box and box.kind == 'world' and action == 'control' and 'worldControl' or action
    local policy = Config.Permissions.actions[policyAction]
    if not policy then return false end

    local owner = box and box.kind == 'placed' and box.owner == license(source)
    local ace = policy.ace and IsPlayerAceAllowed(source, policy.ace) or false
    local allowed = policy.mode == 'everyone'
        or policy.mode == 'owner' and owner
        or policy.mode == 'ace' and ace
        or policy.mode == 'owner_or_ace' and (owner or ace)

    if Config.Permissions.adminBypass and isAdmin(source) then allowed = true end

    local override = callConfiguredExport(Config.Permissions.hook, source, policyAction, box, allowed)
    if type(override) == 'boolean' then return override end
    return allowed == true
end

local function audit(action, source, box, details)
    local payload = {
        action = action,
        source = source,
        identifier = source and license(source) or nil,
        boomboxId = box and box.id or nil,
        kind = box and box.kind or nil,
        owner = box and box.owner or nil,
        station = box and box.station or nil,
        powered = box and box.powered or nil,
        x = box and box.x or nil,
        y = box and box.y or nil,
        z = box and box.z or nil,
        details = details or {}
    }
    if Config.Audit.print then
        print(('[nativeBoombox] AUDIT action=%s source=%s id=%s'):format(
            action, source or 'system', box and box.id or 'none'))
    end
    TriggerEvent('nativeBoombox:server:audit', payload)
    callConfiguredExport(Config.Audit.hook, payload)
end

local function activeEdit(id)
    local lock = editLocks[id]
    if lock and GetGameTimer() >= lock.expires then
        editLocks[id] = nil
        lock = nil
    end
    return lock
end

local function clearEditsForSource(source)
    for id, lock in pairs(editLocks) do
        if lock.source == source then editLocks[id] = nil end
    end
end

local function sanitizeLabel(value)
    if type(value) ~= 'string' then return end
    value = value:gsub('[%z\1-\31\127]', ''):match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if not length or length < 1 or length > Config.Labels.maximumLength then return end
    return value
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
        local storedLabel = box.label
        box.label = sanitizeLabel(box.label) or Config.Labels.default
        if storedLabel ~= box.label then Database.updateLabel(box) end
        if not StationLookup[box.station] then
            box.station = Config.DefaultStation
            Database.updateState(box)
        end
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

lib.callback.register('nativeBoombox:server:getAccess', function(source, id)
    if not ready or rateLimited(source, 'access', 150) then return end
    id = tonumber(id)
    local box = id and (boxes[id] or world[id])
    if not box or not isNear(source, box, Config.InteractDistance + 1.0) then return end

    local placed = box.kind == 'placed'
    local admin = isAdmin(source)
    local editing = activeEdit(id) ~= nil
    local result = {
        control = not editing and box.controllable ~= false and canPerform(source, 'control', box),
        pickup = not editing and placed and canPerform(source, 'pickup', box),
        reposition = not editing and placed and canPerform(source, 'reposition', box),
        rename = not editing and placed and canPerform(source, 'rename', box),
        admin = admin,
        busy = editing
    }
    if admin then
        result.details = {
            id = box.id,
            kind = box.kind,
            owner = box.owner,
            x = box.x, y = box.y, z = box.z,
            rot_x = box.rot_x, rot_y = box.rot_y, rot_z = box.rot_z,
            station = box.station,
            powered = box.powered,
            netId = box.netId
        }
    end
    return result
end)

lib.callback.register('nativeBoombox:server:beginReposition', function(source, id)
    if not ready or rateLimited(source, 'begin_reposition', 500) then return end
    id = tonumber(id)
    if not id or not acquireLock(id) then return end

    local result
    local ok, err = xpcall(function()
        local box = boxes[id]
        if not box or activeEdit(id) or not isNear(source, box, Config.InteractDistance + 1.0) then return end
        if not canPerform(source, 'reposition', box) then return end

        clearEditsForSource(source)
        editLocks[id] = {
            source = source,
            expires = GetGameTimer() + Config.Reposition.lockTimeout,
            origin = { x = box.x, y = box.y, z = box.z }
        }
        result = serialize(box)
    end, debug.traceback)

    releaseLock(id)
    if not ok then reportError('begin reposition', err) end
    return result
end)

RegisterNetEvent('nativeBoombox:server:cancelReposition', function(id)
    local source = source
    id = tonumber(id)
    local lock = id and activeEdit(id)
    if lock and lock.source == source then editLocks[id] = nil end
end)

RegisterNetEvent('nativeBoombox:server:refreshReposition', function(id)
    local source = source
    if rateLimited(source, 'refresh_reposition', 1000) then return end
    id = tonumber(id)
    local lock = id and activeEdit(id)
    local box = id and boxes[id]
    if lock and lock.source == source and box
        and isNear(source, box, Config.Reposition.maximumDistanceFromPlayer + 1.0) then
        lock.expires = GetGameTimer() + Config.Reposition.lockTimeout
    elseif lock and lock.source == source then
        editLocks[id] = nil
    end
end)

lib.callback.register('nativeBoombox:server:finishReposition', function(source, id, position, rotation)
    if not ready or rateLimited(source, 'finish_reposition', 750) then return false end
    if type(position) ~= 'table' or type(rotation) ~= 'table' then return false end
    id = tonumber(id)
    if not id or not acquireLock(id) then return false end

    local changedBox
    local previous
    local ok, err = xpcall(function()
        local box = boxes[id]
        local edit = activeEdit(id)
        if not box or not edit or edit.source ~= source then return end
        if not canPerform(source, 'reposition', box) then return end

        local x, y, z = finiteNumber(position.x), finiteNumber(position.y), finiteNumber(position.z)
        local rx, ry, rz = finiteNumber(rotation.x), finiteNumber(rotation.y), finiteNumber(rotation.z)
        if not x or not y or not z or not rx or not ry or not rz then return end
        local limit = Config.Validation.worldCoordinateLimit
        if math.abs(x) > limit or math.abs(y) > limit or math.abs(z) > limit then return end

        local target = { x = x, y = y, z = z }
        if not isNear(source, target, Config.Reposition.maximumDistanceFromPlayer) then return end
        local dx, dy, dz = x - edit.origin.x, y - edit.origin.y, z - edit.origin.z
        if dx * dx + dy * dy + dz * dz > Config.Reposition.maximumDistanceFromOrigin ^ 2 then return end

        previous = {
            x = box.x, y = box.y, z = box.z,
            rot_x = box.rot_x, rot_y = box.rot_y, rot_z = box.rot_z
        }
        box.x, box.y, box.z = x, y, z
        box.rot_x, box.rot_y, box.rot_z = normalizeAngle(rx), normalizeAngle(ry), normalizeAngle(rz)
        changedBox = box
        Database.updateTransform(box)

        local entity = entities[id]
        if entity and DoesEntityExist(entity) then
            SetEntityCoords(entity, box.x, box.y, box.z, false, false, false, false)
            SetEntityRotation(entity, box.rot_x, box.rot_y, box.rot_z, 2, true)
            FreezeEntityPosition(entity, true)
        end
    end, debug.traceback)

    editLocks[id] = nil
    if not ok and changedBox and previous then
        changedBox.x, changedBox.y, changedBox.z = previous.x, previous.y, previous.z
        changedBox.rot_x, changedBox.rot_y, changedBox.rot_z = previous.rot_x, previous.rot_y, previous.rot_z
    end
    releaseLock(id)

    if not ok then
        reportError('finish reposition', err)
        return false
    elseif changedBox then
        broadcast(changedBox)
        audit('repositioned', source, changedBox, { previous = previous })
        return true
    end
    return false
end)

RegisterNetEvent('nativeBoombox:server:rename', function(id, value)
    local source = source
    if not ready or rateLimited(source, 'rename', 750) then return end
    id = tonumber(id)
    local label = sanitizeLabel(value)
    if not id or not label then
        return TriggerClientEvent('ox_lib:notify', source, {
            type = 'error', description = 'Enter a valid boombox name.'
        })
    end
    if not acquireLock(id) then return end

    local changedBox
    local previousLabel
    local ok, err = xpcall(function()
        local box = boxes[id]
        if not box or activeEdit(id) or not isNear(source, box, Config.InteractDistance + 1.0) then return end
        if not canPerform(source, 'rename', box) then return end
        previousLabel = box.label
        box.label = label
        changedBox = box
        Database.updateLabel(box)
    end, debug.traceback)

    if not ok and changedBox then changedBox.label = previousLabel end
    releaseLock(id)
    if not ok then
        reportError('rename', err)
    elseif changedBox then
        broadcast(changedBox)
        audit('renamed', source, changedBox, { previousLabel = previousLabel })
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'success', description = 'Boombox renamed.'
        })
    end
end)

RegisterNetEvent('nativeBoombox:server:adminDelete', function(id)
    local source = source
    if not ready or not isAdmin(source) or rateLimited(source, 'admin_delete', 1000) then return end
    id = tonumber(id)
    if not id or not acquireLock(id) then return end

    local deletedBox
    local ok, err = xpcall(function()
        local box = boxes[id]
        if not box or not isNear(source, box, Config.InteractDistance + 1.0) then return end
        if not Database.delete(id) then return end
        deletedBox = box
        editLocks[id] = nil
        boxes[id] = nil
        despawn(id)
        TriggerClientEvent('nativeBoombox:client:remove', -1, id)
    end, debug.traceback)

    releaseLock(id)
    if not ok then
        reportError('admin delete', err)
    elseif deletedBox then
        audit('admin_deleted', source, deletedBox)
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'success', description = 'Boombox permanently deleted.'
        })
    end
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
        local id = Database.insert(owner, p, r, Config.Labels.default)
        if not id then error('database insert returned no id', 0) end
        persisted = true

        box = {
            id = id, kind = 'placed', owner = owner,
            x = p.x, y = p.y, z = p.z,
            rot_x = r.x, rot_y = r.y, rot_z = r.z,
            station = Config.DefaultStation, powered = false,
            label = Config.Labels.default
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
        audit('placed', source, box)
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
        if activeEdit(id) then return end
        if box.kind == 'world' and not box.controllable then return end
        if not canPerform(source, 'control', box) then return end

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
        audit(action == 'power' and 'power_changed' or 'station_changed', source, changedBox, {
            value = value
        })
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
        if activeEdit(id) then return end
        if not canPerform(source, 'pickup', box) then
            TriggerClientEvent('ox_lib:notify', source,
                { type = 'error', description = 'You are not allowed to pick up this boombox.' })
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
        audit('picked_up', source, box)
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
                                    audit('entity_recovered', nil, currentBox)
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
    clearEditsForSource(source)
end)

exports('getBoombox', function(id)
    id = tonumber(id)
    local box = id and (boxes[id] or world[id])
    return box and serialize(box) or nil
end)

exports('canAccess', function(source, action, id)
    id = tonumber(id)
    local box = id and (boxes[id] or world[id])
    if not box or type(action) ~= 'string' then return false end
    return canPerform(source, action, box)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(entities) do despawn(id) end
end)
