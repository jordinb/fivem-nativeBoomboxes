local placing = false

local function deletePreview(entity)
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    SetModelAsNoLongerNeeded(Config.PropModel)
    placing = false
end

function BeginBoomboxPlacement(slotId)
    if placing then return end
    if type(slotId) ~= 'number' then
        return lib.notify({ type = 'error', description = 'The inventory slot could not be resolved.' })
    end
    placing = true

    if not lib.requestModel(Config.PropModel, 5000) then
        placing = false
        return lib.notify({ type = 'error', description = 'The boombox model could not be loaded.' })
    end

    local ped = cache.ped
    local start = GetEntityCoords(ped) + GetEntityForwardVector(ped) * Config.Placement.initialDistance
    local preview = CreateObjectNoOffset(Config.PropModel, start.x, start.y, start.z, false, false, false)
    if preview == 0 then
        deletePreview(preview)
        return lib.notify({ type = 'error', description = 'The placement preview could not be created.' })
    end

    SetEntityHeading(preview, GetEntityHeading(ped))
    PlaceObjectOnGroundProperly_2(preview)
    SetEntityCollision(preview, false, false)
    SetEntityAlpha(preview, 210, false)
    FreezeEntityPosition(preview, true)

    local ok, result = pcall(UseBoomboxPlacementEditor, preview)
    if not ok or not result or not DoesEntityExist(preview) then
        deletePreview(preview)
        return lib.notify({ type = 'error', description = 'The placement editor could not complete.' })
    end

    if result.cancelled then
        deletePreview(preview)
        return
    end

    local position = GetEntityCoords(preview)
    local rotation = GetEntityRotation(preview, 2)
    local distance = #(GetEntityCoords(ped) - position)
    if distance > Config.Placement.maximumDistance then
        deletePreview(preview)
        return lib.notify({
            type = 'error',
            description = ('Keep the boombox within %.1f metres.'):format(Config.Placement.maximumDistance)
        })
    end

    local answer = lib.alertDialog({
        header = 'Place Boombox',
        content = 'Confirm this position?',
        centered = true,
        cancel = true
    })
    deletePreview(preview)
    if answer ~= 'confirm' then return end

    TriggerServerEvent('nativeBoombox:server:place', {
        x = position.x, y = position.y, z = position.z
    }, {
        x = rotation.x, y = rotation.y, z = rotation.z
    }, slotId)
end
