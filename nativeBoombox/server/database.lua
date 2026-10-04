Database = {}

function Database.init()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `native_boomboxes` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(80) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `rot_x` FLOAT NOT NULL DEFAULT 0,
            `rot_y` FLOAT NOT NULL DEFAULT 0,
            `rot_z` FLOAT NOT NULL DEFAULT 0,
            `station` VARCHAR(64) NOT NULL,
            `powered` TINYINT(1) NOT NULL DEFAULT 0,
            `label` VARCHAR(48) NULL DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_native_boombox_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `native_boombox_mixtapes` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `creator_identifier` VARCHAR(80) NOT NULL,
            `creator_name` VARCHAR(80) NOT NULL,
            `title` VARCHAR(48) NOT NULL,
            `capacity_ms` INT UNSIGNED NOT NULL,
            `duration_ms` INT UNSIGNED NOT NULL,
            `track_count` SMALLINT UNSIGNED NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_native_boombox_mixtapes_creator` (`creator_identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `native_boombox_mixtape_tracks` (
            `mixtape_id` BIGINT UNSIGNED NOT NULL,
            `position` SMALLINT UNSIGNED NOT NULL,
            `track_id` VARCHAR(160) NOT NULL,
            PRIMARY KEY (`mixtape_id`, `position`),
            KEY `idx_native_boombox_mixtape_track_id` (`track_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    local columns = MySQL.query.await('SHOW COLUMNS FROM `native_boomboxes`')
    local found = {}
    for i = 1, #columns do found[columns[i].Field] = true end
    if not found.rot_x then MySQL.query.await('ALTER TABLE `native_boomboxes` ADD COLUMN `rot_x` FLOAT NOT NULL DEFAULT 0 AFTER `z`') end
    if not found.rot_y then MySQL.query.await('ALTER TABLE `native_boomboxes` ADD COLUMN `rot_y` FLOAT NOT NULL DEFAULT 0 AFTER `rot_x`') end
    if not found.rot_z then
        MySQL.query.await('ALTER TABLE `native_boomboxes` ADD COLUMN `rot_z` FLOAT NOT NULL DEFAULT 0 AFTER `rot_y`')
        if found.heading then MySQL.query.await('UPDATE `native_boomboxes` SET `rot_z` = `heading`') end
    end
    if not found.label then
        MySQL.query.await('ALTER TABLE `native_boomboxes` ADD COLUMN `label` VARCHAR(48) NULL DEFAULT NULL AFTER `powered`')
    end
end

function Database.load()
    return MySQL.query.await('SELECT `id`, `owner`, `x`, `y`, `z`, `rot_x`, `rot_y`, `rot_z`, `station`, `powered`, `label` FROM `native_boomboxes`')
end

function Database.insert(owner, position, rotation, label)
    return MySQL.insert.await([[
        INSERT INTO `native_boomboxes`
            (`owner`, `x`, `y`, `z`, `rot_x`, `rot_y`, `rot_z`, `station`, `powered`, `label`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
    ]], {
        owner, position.x, position.y, position.z,
        rotation.x, rotation.y, rotation.z,
        Config.DefaultStation, label
    })
end

function Database.updateState(box)
    MySQL.update.await('UPDATE `native_boomboxes` SET `station` = ?, `powered` = ? WHERE `id` = ?', {
        box.station, box.powered and 1 or 0, box.id
    })
end

function Database.restore(box)
    return MySQL.update.await([[
        INSERT INTO `native_boomboxes`
            (`id`, `owner`, `x`, `y`, `z`, `rot_x`, `rot_y`, `rot_z`, `station`, `powered`, `label`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `owner` = VALUES(`owner`),
            `x` = VALUES(`x`),
            `y` = VALUES(`y`),
            `z` = VALUES(`z`),
            `rot_x` = VALUES(`rot_x`),
            `rot_y` = VALUES(`rot_y`),
            `rot_z` = VALUES(`rot_z`),
            `station` = VALUES(`station`),
            `powered` = VALUES(`powered`),
            `label` = VALUES(`label`)
    ]], {
        box.id, box.owner, box.x, box.y, box.z,
        box.rot_x, box.rot_y, box.rot_z,
        box.station, box.powered and 1 or 0, box.label
    }) > 0
end

function Database.updateTransform(box)
    MySQL.update.await([[
        UPDATE `native_boomboxes`
        SET `x` = ?, `y` = ?, `z` = ?, `rot_x` = ?, `rot_y` = ?, `rot_z` = ?
        WHERE `id` = ?
    ]], { box.x, box.y, box.z, box.rot_x, box.rot_y, box.rot_z, box.id })
end

function Database.updateLabel(box)
    MySQL.update.await('UPDATE `native_boomboxes` SET `label` = ? WHERE `id` = ?', {
        box.label, box.id
    })
end

function Database.delete(id)
    return MySQL.update.await('DELETE FROM `native_boomboxes` WHERE `id` = ?', { id }) > 0
end


function Database.createMixtape(creatorIdentifier, creatorName, title, capacityMs, durationMs, trackIds)
    local id = MySQL.insert.await([[
        INSERT INTO `native_boombox_mixtapes`
            (`creator_identifier`, `creator_name`, `title`, `capacity_ms`, `duration_ms`, `track_count`)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        creatorIdentifier, creatorName, title, capacityMs, durationMs, #trackIds
    })
    if not id then return end

    local ok, err = xpcall(function()
        for i = 1, #trackIds do
            MySQL.insert.await([[
                INSERT INTO `native_boombox_mixtape_tracks` (`mixtape_id`, `position`, `track_id`)
                VALUES (?, ?, ?)
            ]], { id, i, trackIds[i] })
        end
    end, debug.traceback)

    if not ok then
        MySQL.update.await('DELETE FROM `native_boombox_mixtape_tracks` WHERE `mixtape_id` = ?', { id })
        MySQL.update.await('DELETE FROM `native_boombox_mixtapes` WHERE `id` = ?', { id })
        error(err, 0)
    end

    return id
end

function Database.loadMixtape(id)
    local header = MySQL.single.await([[
        SELECT `id`, `creator_identifier`, `creator_name`, `title`, `capacity_ms`,
               `duration_ms`, `track_count`, `created_at`
        FROM `native_boombox_mixtapes`
        WHERE `id` = ?
    ]], { id })
    if not header then return end

    header.tracks = MySQL.query.await([[
        SELECT `position`, `track_id`
        FROM `native_boombox_mixtape_tracks`
        WHERE `mixtape_id` = ?
        ORDER BY `position` ASC
    ]], { id }) or {}

    return header
end

function Database.deleteMixtape(id)
    MySQL.update.await('DELETE FROM `native_boombox_mixtape_tracks` WHERE `mixtape_id` = ?', { id })
    return MySQL.update.await('DELETE FROM `native_boombox_mixtapes` WHERE `id` = ?', { id }) > 0
end
