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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `native_boombox_mixtape_tracks` (
    `mixtape_id` BIGINT UNSIGNED NOT NULL,
    `position` SMALLINT UNSIGNED NOT NULL,
    `track_id` VARCHAR(160) NOT NULL,
    PRIMARY KEY (`mixtape_id`, `position`),
    KEY `idx_native_boombox_mixtape_track_id` (`track_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
