CREATE TABLE IF NOT EXISTS `qbbusinesses` (
    `id` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NOT NULL,
    `job` VARCHAR(64) NOT NULL,
    `modules` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `qbbusinesses_job` (`job`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Prices an employee set for an item that no shop-item list fixes a price for.
-- Stock itself lives in qbinventory's own durable shop inventory; this table
-- only remembers the price policy, so restocking an item does not re-prompt.
CREATE TABLE IF NOT EXISTS `qbbusinesses_prices` (
    `shop` VARCHAR(64) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `price` INT UNSIGNED NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`shop`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `qbbusinesses_logs` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `business` VARCHAR(64) NOT NULL,
    `category` VARCHAR(32) NOT NULL,
    `message` VARCHAR(512) NOT NULL,
    `citizenid` VARCHAR(64) DEFAULT NULL,
    `amount` INT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `qbbusinesses_logs_business` (`business`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
