CREATE TABLE IF NOT EXISTS `qbbusinesses_cctv_callouts` (
    `id` varchar(40) NOT NULL,
    `business` varchar(50) DEFAULT NULL,
    `customer_type` varchar(20) NOT NULL DEFAULT 'business',
    `citizenid` varchar(50) DEFAULT NULL,
    `issue` enum('camera','nvr') NOT NULL,
    `camera_id` varchar(80) DEFAULT NULL,
    `nvr_id` varchar(80) DEFAULT NULL,
    `requester` int NOT NULL,
    `engineer` int DEFAULT NULL,
    `charge` int NOT NULL DEFAULT 0,
    `repair_price` int DEFAULT NULL,
    `status` varchar(20) NOT NULL,
    `coords` text DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    `completed_at` timestamp NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `qbbusinesses_cctv_callouts_business` (`business`),
    KEY `qbbusinesses_cctv_callouts_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `qbbusinesses_cctv_callouts`
    MODIFY COLUMN `business` varchar(50) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `customer_type` varchar(20) NOT NULL DEFAULT 'business',
    ADD COLUMN IF NOT EXISTS `citizenid` varchar(50) DEFAULT NULL;

CREATE TABLE IF NOT EXISTS `qbbusinesses_cctv_systems` (
    `id` varchar(80) NOT NULL,
    `installer_business` varchar(50) NOT NULL,
    `business` varchar(50) NOT NULL,
    `business_label` varchar(100) DEFAULT NULL,
    `camera_count` int NOT NULL DEFAULT 0,
    `status` varchar(20) NOT NULL DEFAULT 'online',
    `security_level` int NOT NULL DEFAULT 1,
    `intrusion_level` int NOT NULL DEFAULT 0,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    KEY `qbbusinesses_cctv_systems_installer` (`installer_business`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `qbbusinesses_cctv_systems`
    ADD COLUMN IF NOT EXISTS `security_level` int NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS `intrusion_level` int NOT NULL DEFAULT 0;
