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
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_native_boombox_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

