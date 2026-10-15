DB = {}

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `pmv2_properties` (
      `id` INT NOT NULL AUTO_INCREMENT, `label` VARCHAR(100) NOT NULL, `type` VARCHAR(16) NOT NULL,
      `parent_id` INT NULL, `data` LONGTEXT NOT NULL, `price` INT NOT NULL DEFAULT 0,
      `rent_price` INT NOT NULL DEFAULT 0, `for_sale` TINYINT(1) NOT NULL DEFAULT 0,
      `for_rent` TINYINT(1) NOT NULL DEFAULT 0, `owner` VARCHAR(64) NULL, `owner_name` VARCHAR(100) NULL,
      `renter` VARCHAR(64) NULL, `renter_name` VARCHAR(100) NULL, `rent_due` INT NULL,
      `rent_missed` INT NOT NULL DEFAULT 0, `state` LONGTEXT NULL, `created_by` VARCHAR(64) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`),
      KEY `owner` (`owner`), KEY `renter` (`renter`), KEY `parent_id` (`parent_id`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `pmv2_property_access` (
      `property_id` INT NOT NULL, `citizenid` VARCHAR(64) NOT NULL, `name` VARCHAR(100) NULL,
      `level` VARCHAR(16) NOT NULL, `rent` INT NOT NULL DEFAULT 0, `rent_due` INT NULL,
      `rent_missed` INT NOT NULL DEFAULT 0, PRIMARY KEY (`property_id`, `citizenid`), KEY `citizenid` (`citizenid`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `pmv2_property_payouts` (
      `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL, `amount` INT NOT NULL,
      `reason` VARCHAR(150) NULL, PRIMARY KEY (`id`), KEY `citizenid` (`citizenid`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `pmv2_property_inside` (
      `citizenid` VARCHAR(64) NOT NULL, `property_id` INT NOT NULL, PRIMARY KEY (`citizenid`))]])
    DB.ready = true
end)

function DB.WaitReady()
    while not DB.ready do Wait(50) end
end

function DB.LoadAll()
    DB.WaitReady()
    local props = MySQL.query.await('SELECT * FROM pmv2_properties') or {}
    local access = MySQL.query.await('SELECT * FROM pmv2_property_access') or {}
    return props, access
end

function DB.Insert(p)
    return MySQL.insert.await(
        'INSERT INTO pmv2_properties (label, type, parent_id, data, price, rent_price, for_sale, for_rent, state, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { p.label, p.type, p.parent_id, json.encode(p.data), p.price, p.rent_price, p.for_sale and 1 or 0, p.for_rent and 1 or 0, json.encode(p.state), p.created_by })
end

--- Saves every column of a property from the in-memory copy.
function DB.Save(p)
    MySQL.update(
        [[UPDATE pmv2_properties SET label = ?, type = ?, parent_id = ?, data = ?, price = ?, rent_price = ?,
          for_sale = ?, for_rent = ?, owner = ?, owner_name = ?, renter = ?, renter_name = ?, rent_due = ?,
          rent_missed = ?, state = ? WHERE id = ?]],
        { p.label, p.type, p.parent_id, json.encode(p.data), p.price, p.rent_price, p.for_sale and 1 or 0,
          p.for_rent and 1 or 0, p.owner, p.owner_name, p.renter, p.renter_name, p.rent_due, p.rent_missed,
          json.encode(p.state), p.id })
end

function DB.Delete(id)
    MySQL.query('DELETE FROM pmv2_properties WHERE id = ?', { id })
    MySQL.query('DELETE FROM pmv2_property_access WHERE property_id = ?', { id })
end

function DB.SetAccess(id, a)
    MySQL.query(
        [[INSERT INTO pmv2_property_access (property_id, citizenid, name, level, rent, rent_due, rent_missed) VALUES (?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE name = VALUES(name), level = VALUES(level), rent = VALUES(rent), rent_due = VALUES(rent_due), rent_missed = VALUES(rent_missed)]],
        { id, a.citizenid, a.name, a.level, a.rent or 0, a.rent_due, a.rent_missed or 0 })
end

function DB.RemoveAccess(id, citizenid)
    MySQL.query('DELETE FROM pmv2_property_access WHERE property_id = ? AND citizenid = ?', { id, citizenid })
end

function DB.ClearAccess(id)
    MySQL.query('DELETE FROM pmv2_property_access WHERE property_id = ?', { id })
end

function DB.AddPayout(citizenid, amount, reason)
    MySQL.insert('INSERT INTO pmv2_property_payouts (citizenid, amount, reason) VALUES (?, ?, ?)', { citizenid, amount, reason })
end

function DB.TakePayouts(citizenid)
    local rows = MySQL.query.await('SELECT id, amount, reason FROM pmv2_property_payouts WHERE citizenid = ?', { citizenid }) or {}
    if #rows > 0 then MySQL.query.await('DELETE FROM pmv2_property_payouts WHERE citizenid = ?', { citizenid }) end
    return rows
end

function DB.SetInside(citizenid, id)
    if id then
        MySQL.query('INSERT INTO pmv2_property_inside (citizenid, property_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE property_id = VALUES(property_id)', { citizenid, id })
    else
        MySQL.query('DELETE FROM pmv2_property_inside WHERE citizenid = ?', { citizenid })
    end
end

function DB.GetInside(citizenid)
    return MySQL.scalar.await('SELECT property_id FROM pmv2_property_inside WHERE citizenid = ?', { citizenid })
end
