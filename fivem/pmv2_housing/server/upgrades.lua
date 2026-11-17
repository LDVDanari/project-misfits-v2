-- ─────────────────────────────────────────────────────────────
--  UPGRADES - stash size, furniture limit, motion sensor, robot vacuum
--  Prices and amounts: Config.Upgrades. Upgrades belong to the property.
-- ─────────────────────────────────────────────────────────────
Upgrades = {}
local U = Config.Upgrades

function Upgrades.Of(p)
    p.data.upgrades = p.data.upgrades or {}
    local up = p.data.upgrades
    up.stash = tonumber(up.stash) or 0
    up.furniture = tonumber(up.furniture) or 0
    up.motion = up.motion == true
    up.vacuum = up.vacuum == true
    return up
end

function Upgrades.FurnitureLimit(p)
    local up = Upgrades.Of(p)
    return math.min(U.furniture.max, U.furniture.base + up.furniture * U.furniture.perLevel)
end

local function furnitureMaxLevel()
    return math.ceil((U.furniture.max - U.furniture.base) / U.furniture.perLevel)
end

--- Everything the menu shows: current level, next price (nil = maxed / owned).
function Upgrades.List(p)
    local up = Upgrades.Of(p)
    local stashNext = up.stash < U.stash.maxLevel and (U.stash.basePrice + up.stash * U.stash.priceStep) or nil
    local furnLimit = Upgrades.FurnitureLimit(p)
    return {
        stash = {
            label = U.stash.label, level = up.stash, maxLevel = U.stash.maxLevel, price = stashNext,
            text = ('+%d kg storage (level %d/%d)'):format(up.stash * U.stash.weightPerLevel / 1000, up.stash, U.stash.maxLevel),
            nextText = stashNext and ('+%d kg more'):format(U.stash.weightPerLevel / 1000) or 'Maxed out',
        },
        furniture = {
            label = U.furniture.label, level = up.furniture, maxLevel = furnitureMaxLevel(),
            price = furnLimit < U.furniture.max and U.furniture.price or nil,
            text = ('%d / %d items'):format(furnLimit, U.furniture.max),
            nextText = furnLimit < U.furniture.max and ('Raise to %d'):format(math.min(U.furniture.max, furnLimit + U.furniture.perLevel)) or 'Maxed out',
        },
        motion = {
            label = U.motion.label, owned = up.motion, price = not up.motion and U.motion.price or nil,
            text = up.motion and 'Installed: alerts you when anyone enters' or 'Get alerted when anyone enters',
        },
        vacuum = {
            label = U.vacuum.label, owned = up.vacuum, price = not up.vacuum and U.vacuum.price or nil,
            text = up.vacuum and ('Installed: cleans %.1f%% per hour while powered'):format(U.vacuum.cleanPerHour) or 'Cleans the place by itself',
        },
    }
end

local function canBuy(p, cid)
    local level = Housing.Level(p, cid)
    return level and U.buyers[level] == true
end

lib.callback.register('pmv2_housing:upgrades', function(src, id)
    local p = Housing.Get(id)
    if not p or not Housing.Level(p, Bridge.GetCitizenId(src)) then return nil end
    return { list = Upgrades.List(p), canBuy = canBuy(p, Bridge.GetCitizenId(src)) }
end)

lib.callback.register('pmv2_housing:buyUpgrade', function(src, id, key)
    local p = Housing.Get(id)
    local cid = Bridge.GetCitizenId(src)
    if not p or not cid then return false end
    if not canBuy(p, cid) then return false, 'Only the owner can buy upgrades.' end
    if not Housing.IsAtProperty(src, p) then return false, 'You need to be at the property.' end
    local info = Upgrades.List(p)[key]
    if not info then return false end
    if not info.price then return false, 'Already maxed out.' end
    if Bridge.GetBank(src) < info.price then return false, ("You need %s in the bank."):format(Shared.Money(info.price)) end
    if not Bridge.RemoveBank(src, info.price, ('%s upgrade: %s'):format(info.label, p.label)) then return false, 'Payment failed.' end
    Bridge.AddSociety(U.society, info.price, info.label .. ' upgrade ' .. p.label)

    local up = Upgrades.Of(p)
    if key == 'stash' then up.stash = up.stash + 1
    elseif key == 'furniture' then up.furniture = up.furniture + 1
    elseif key == 'motion' then up.motion = true
    elseif key == 'vacuum' then up.vacuum = true end

    Housing.Commit(p, { stash = key == 'stash', doors = false, garage = false })
    Bridge.Log('⬆️ Property upgrade', ('**%s** bought **%s** for **#%d %s** (%s)'):format(
        Bridge.GetName(src), info.label, p.id, p.label, Shared.Money(info.price)))
    return true, info.label
end)

-- Owner/renter turns security alerts on/off for a keyholder or tenant.
lib.callback.register('pmv2_housing:setSecurity', function(src, id, tcid, enabled)
    local p = Housing.Get(id)
    if not p then return false end
    local level = Housing.Level(p, Bridge.GetCitizenId(src))
    if level ~= 'owner' and level ~= 'renter' then return false, "You can't change that." end
    local a = p.access[tcid]
    if not a then return false end
    a.perms = a.perms or {}
    a.perms.security = enabled == true
    DB.SetAccess(p.id, a)
    return true
end)

-- ── Motion sensor ────────────────────────────────────────────
local lastAlert = {}   -- ["propertyId:src"] = os.time()

function Upgrades.Motion(p, src)
    local up = p.data.upgrades
    if not (up and up.motion) then return end
    if U.motion.needsElectricity and not p.state.util.electricity.on then return end
    local intruderCid = Bridge.GetCitizenId(src)
    if U.motion.ignoreAccessHolders and Housing.Level(p, intruderCid) then return end

    local key = p.id .. ':' .. src
    local now = os.time()
    if (lastAlert[key] or 0) + U.motion.cooldownSeconds > now then return end
    lastAlert[key] = now

    local recipients = {}
    if p.owner then recipients[#recipients + 1] = p.owner end
    if p.renter then recipients[#recipients + 1] = p.renter end
    for cid in pairs(p.access) do
        if Housing.Can(p, cid, 'security') then recipients[#recipients + 1] = cid end
    end

    for _, cid in ipairs(recipients) do
        if cid ~= intruderCid then
            local s = Bridge.GetSource(cid)
            if s then
                Bridge.Notify(s, ('Motion detected at %s.'):format(p.label), 'warning', 'Security')
                TriggerClientEvent('pmv2_housing:securityAlert', s, p.id)
            end
        end
    end
end

-- MLO properties: the client reports walking into the property area; we double-check the distance.
RegisterNetEvent('pmv2_housing:motion', function(id)
    local src = source
    local p = Housing.Get(id)
    if not p or p.type ~= 'mlo' or not p.data.zone then return end
    local z = p.data.zone
    if #(Housing.Coords(src) - vector3(z.x, z.y, z.z)) > (z.r or 20.0) + 5.0 then return end
    Upgrades.Motion(p, src)
end)

AddEventHandler('playerDropped', function()
    local src = tostring(source)
    for k in pairs(lastAlert) do
        if k:sub(-#src - 1) == ':' .. src then lastAlert[k] = nil end
    end
end)

exports('GetFurnitureLimit', function(id)
    local p = Housing.Get(id)
    return p and Upgrades.FurnitureLimit(p) or U.furniture.base
end)
exports('GetUpgrades', function(id)
    local p = Housing.Get(id)
    return p and Upgrades.Of(p) or nil
end)
