local placing = false
local activePreview
local activeEditId
local placementAlertOpen = false

local function showPlacementAlert(options)
    placementAlertOpen = true
    local result = lib.alertDialog(options)
    placementAlertOpen = false
    return result
end

local function deletePreview(entity)
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    if activePreview == entity then activePreview = nil end
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
    activePreview = preview

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

    local answer = showPlacementAlert({
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

function BeginBoomboxReposition(id, originalEntity)
    if placing then return end
    placing = true

    local callbackOk, box = pcall(lib.callback.await, 'nativeBoombox:server:beginReposition', false, id)
    if not callbackOk or not box then
        TriggerServerEvent('nativeBoombox:server:cancelReposition', id)
        placing = false
        return lib.notify({ type = 'error', description = 'This boombox cannot be repositioned right now.' })
    end
    activeEditId = id
    CreateThread(function()
        local interval = math.max(5000, math.floor(Config.Reposition.lockTimeout / 3))
        while activeEditId == id do
            Wait(interval)
            if activeEditId == id then
                TriggerServerEvent('nativeBoombox:server:refreshReposition', id)
            end
        end
    end)

    if not lib.requestModel(Config.PropModel, 5000) then
        TriggerServerEvent('nativeBoombox:server:cancelReposition', id)
        activeEditId = nil
        placing = false
        return lib.notify({ type = 'error', description = 'The boombox model could not be loaded.' })
    end

    if not originalEntity or not DoesEntityExist(originalEntity) then
        originalEntity = box.netId and NetworkGetEntityFromNetworkId(box.netId) or 0
    end

    local preview = CreateObjectNoOffset(Config.PropModel, box.x, box.y, box.z, false, false, false)
    if preview == 0 then
        TriggerServerEvent('nativeBoombox:server:cancelReposition', id)
        activeEditId = nil
        deletePreview(preview)
        return lib.notify({ type = 'error', description = 'The reposition preview could not be created.' })
    end
    activePreview = preview

    SetEntityRotation(preview, box.rot_x or 0.0, box.rot_y or 0.0, box.rot_z or 0.0, 2, true)
    SetEntityCollision(preview, false, false)
    SetEntityAlpha(preview, 210, false)
    FreezeEntityPosition(preview, true)

    local ok, result = pcall(UseBoomboxPlacementEditor, preview, originalEntity)
    if not ok or not result or not DoesEntityExist(preview) then
        TriggerServerEvent('nativeBoombox:server:cancelReposition', id)
        activeEditId = nil
        deletePreview(preview)
        return lib.notify({ type = 'error', description = 'The reposition editor could not complete.' })
    end

    if result.cancelled then
        TriggerServerEvent('nativeBoombox:server:cancelReposition', id)
        activeEditId = nil
        deletePreview(preview)
        return
    end

    local position = GetEntityCoords(preview)
    local rotation = GetEntityRotation(preview, 2)
    local answer = showPlacementAlert({
        header = 'Reposition Boombox',
        content = 'Save this new position?',
        centered = true,
        cancel = true
    })
    deletePreview(preview)
    activeEditId = nil

    if answer ~= 'confirm' then
        TriggerServerEvent('nativeBoombox:server:cancelReposition', id)
        return
    end

    placing = true
    local saveCallbackOk, saved = pcall(lib.callback.await,
        'nativeBoombox:server:finishReposition', false, id, {
        x = position.x, y = position.y, z = position.z
    }, {
        x = rotation.x, y = rotation.y, z = rotation.z
    })
    placing = false
    if saveCallbackOk and saved then
        lib.notify({ type = 'success', description = 'Boombox position saved.' })
    else
        TriggerServerEvent('nativeBoombox:server:cancelReposition', id)
        lib.notify({ type = 'error', description = 'The new boombox position was rejected.' })
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if placementAlertOpen then lib.closeAlertDialog() end
    if activePreview and DoesEntityExist(activePreview) then DeleteEntity(activePreview) end
    if activeEditId then TriggerServerEvent('nativeBoombox:server:cancelReposition', activeEditId) end
end)
