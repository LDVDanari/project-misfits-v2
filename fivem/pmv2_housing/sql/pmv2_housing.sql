-- Tables are also created automatically on first start.
CREATE TABLE IF NOT EXISTS `pmv2_properties` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `label` VARCHAR(100) NOT NULL,
  `type` VARCHAR(16) NOT NULL,
  `parent_id` INT NULL,
  `data` LONGTEXT NOT NULL,
  `price` INT NOT NULL DEFAULT 0,
  `rent_price` INT NOT NULL DEFAULT 0,
  `for_sale` TINYINT(1) NOT NULL DEFAULT 0,
  `for_rent` TINYINT(1) NOT NULL DEFAULT 0,
  `owner` VARCHAR(64) NULL,
  `owner_name` VARCHAR(100) NULL,
  `renter` VARCHAR(64) NULL,
  `renter_name` VARCHAR(100) NULL,
  `rent_due` INT NULL,
  `rent_missed` INT NOT NULL DEFAULT 0,
  `state` LONGTEXT NULL,
  `created_by` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `owner` (`owner`),
  KEY `renter` (`renter`),
  KEY `parent_id` (`parent_id`)
);

CREATE TABLE IF NOT EXISTS `pmv2_property_access` (
  `property_id` INT NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `name` VARCHAR(100) NULL,
  `level` VARCHAR(16) NOT NULL,
  `rent` INT NOT NULL DEFAULT 0,
  `rent_due` INT NULL,
  `rent_missed` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`property_id`, `citizenid`),
  KEY `citizenid` (`citizenid`)
);

CREATE TABLE IF NOT EXISTS `pmv2_property_payouts` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(64) NOT NULL,
  `amount` INT NOT NULL,
  `reason` VARCHAR(150) NULL,
  PRIMARY KEY (`id`),
  KEY `citizenid` (`citizenid`)
);

CREATE TABLE IF NOT EXISTS `pmv2_property_inside` (
  `citizenid` VARCHAR(64) NOT NULL,
  `property_id` INT NOT NULL,
  PRIMARY KEY (`citizenid`)
);
