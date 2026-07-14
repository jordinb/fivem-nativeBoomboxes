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
