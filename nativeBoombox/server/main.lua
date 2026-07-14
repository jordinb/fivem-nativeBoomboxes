local boxes = {}
local entities = {}
local world = {}
local ready = false
local cooldowns = {}

local function license(source)
    return GetPlayerIdentifierByType(source, 'license') or GetPlayerIdentifier(source, 0)
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
        label = box.label
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

MySQL.ready(function()
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
            label = cfg.label or ('World Radio %s'):format(i)
        }
    end
    ready = true
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
    local owner = license(source)
    if not owner then return end

    local p = vector3(tonumber(position.x) or 0, tonumber(position.y) or 0, tonumber(position.z) or 0)
    local r = vector3(tonumber(rotation.x) or 0, tonumber(rotation.y) or 0, tonumber(rotation.z) or 0)
    if not isNear(source, { x = p.x, y = p.y, z = p.z }, Config.Placement.maximumDistance) then return end

    local owned = 0
    for _, box in pairs(boxes) do
        if box.owner == owner then owned = owned + 1 end
    end
    if owned >= Config.MaximumOwned then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'You have reached the boombox placement limit.' })
        return
    end

    if not exports.ox_inventory:RemoveItem(source, Config.ItemName, 1, nil, slotId) then return end
    local id = Database.insert(owner, p, r)
    if not id then
        exports.ox_inventory:AddItem(source, Config.ItemName, 1)
        return
    end

    local box = {
        id = id, kind = 'placed', owner = owner,
        x = p.x, y = p.y, z = p.z,
        rot_x = r.x, rot_y = r.y, rot_z = r.z,
        station = Config.DefaultStation, powered = false
    }
    boxes[id] = box
    if not spawn(box) then
        boxes[id] = nil
        Database.delete(id)
        exports.ox_inventory:AddItem(source, Config.ItemName, 1)
        return
    end
    broadcast(box)
end)

RegisterNetEvent('nativeBoombox:server:setState', function(id, action, value)
    local source = source
    if not ready then return end
    if rateLimited(source, 'state', 250) then return end
    id = tonumber(id)
    local box = id and (boxes[id] or world[id])
    if not box or not isNear(source, box, Config.InteractDistance + 1.0) then return end
    if not Config.AllowAnyoneToControl and box.owner ~= license(source) then return end

    if action == 'power' and type(value) == 'boolean' then
        box.powered = value
    elseif action == 'station' and type(value) == 'string' and StationLookup[value] then
        box.station = value
    else
        return
    end

    if box.kind == 'placed' then Database.updateState(box) end
    broadcast(box)
end)

RegisterNetEvent('nativeBoombox:server:pickup', function(id)
    local source = source
    if not ready then return end
    if rateLimited(source, 'pickup', 1000) then return end
    id = tonumber(id)
    local box = id and boxes[id]
    if not box or not isNear(source, box, Config.InteractDistance + 1.0) then return end
    if not Config.AllowAnyoneToPickup and box.owner ~= license(source) then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'You do not own this boombox.' })
        return
    end
    if not exports.ox_inventory:CanCarryItem(source, Config.ItemName, 1) then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'You cannot carry the boombox.' })
        return
    end
    if not Database.delete(id) then return end

    boxes[id] = nil
    despawn(id)
    if not exports.ox_inventory:AddItem(source, Config.ItemName, 1) then
        local restoredId = Database.insert(box.owner, vector3(box.x, box.y, box.z), vector3(box.rot_x, box.rot_y, box.rot_z))
        if restoredId then
            box.id = restoredId
            boxes[restoredId] = box
            Database.updateState(box)
            spawn(box)
            broadcast(box)
        end
        return
    end
    TriggerClientEvent('nativeBoombox:client:remove', -1, id)
end)

AddEventHandler('playerDropped', function()
    local prefix = ('%s:'):format(source)
    for key in pairs(cooldowns) do if key:sub(1, #prefix) == prefix then cooldowns[key] = nil end end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(entities) do despawn(id) end
end)
