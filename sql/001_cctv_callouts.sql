CREATE TABLE IF NOT EXISTS `qbbusinesses_cctv_callouts` (
    `id` varchar(40) NOT NULL,
    `business` varchar(50) NOT NULL,
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

CREATE TABLE IF NOT EXISTS `qbbusinesses_cctv_systems` (
    `id` varchar(80) NOT NULL,
    `installer_business` varchar(50) NOT NULL,
    `business` varchar(50) NOT NULL,
    `business_label` varchar(100) DEFAULT NULL,
    `camera_count` int NOT NULL DEFAULT 0,
    `status` varchar(20) NOT NULL DEFAULT 'online',
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    KEY `qbbusinesses_cctv_systems_installer` (`installer_business`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
