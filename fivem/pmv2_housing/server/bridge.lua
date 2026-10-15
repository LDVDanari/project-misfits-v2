-- ─────────────────────────────────────────────────────────────
--  FRAMEWORK BRIDGE (server) - Qbox. Everything framework-specific lives here.
-- ─────────────────────────────────────────────────────────────
Bridge = {}

function Bridge.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

function Bridge.GetCitizenId(src)
    local p = Bridge.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

function Bridge.GetName(src)
    local p = Bridge.GetPlayer(src)
    if not p then return 'Unknown' end
    local ci = p.PlayerData.charinfo or {}
    return ('%s %s'):format(ci.firstname or '?', ci.lastname or '?')
end

function Bridge.GetSource(citizenid)
    local p = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    return p and p.PlayerData.source or nil
end

function Bridge.IsRealtor(src)
    if IsPlayerAceAllowed(src, Config.Realtor.adminAce) then return true end
    local p = Bridge.GetPlayer(src)
    local job = p and p.PlayerData.job
    if not job then return false end
    local minGrade = Config.Realtor.jobs[job.name]
    return minGrade ~= nil and (job.grade and (job.grade.level or job.grade) or 0) >= minGrade
end

function Bridge.IsAdmin(src)
    return IsPlayerAceAllowed(src, Config.Realtor.adminAce)
end

function Bridge.Notify(src, description, ntype, title)
    if not src then return end
    lib.notify(src, { title = title or 'Housing', description = description, type = ntype or 'inform' })
end

-- ── Money ────────────────────────────────────────────────────
function Bridge.GetBank(src)
    local p = Bridge.GetPlayer(src)
    return p and (p.PlayerData.money.bank or 0) or 0
end

function Bridge.RemoveBank(src, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local ok, res = pcall(exports.qbx_core.RemoveMoney, exports.qbx_core, src, 'bank', amount, reason or 'housing')
    return ok and res ~= false
end

function Bridge.AddBank(src, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local ok, res = pcall(exports.qbx_core.AddMoney, exports.qbx_core, src, 'bank', amount, reason or 'housing')
    return ok and res ~= false
end

--- Pays a character whether they're online or not (offline = paid on next login).
function Bridge.Pay(citizenid, amount, reason)
    amount = math.floor(amount or 0)
    if not citizenid or amount <= 0 then return end
    local src = Bridge.GetSource(citizenid)
    if src and Bridge.AddBank(src, amount, reason) then
        Bridge.Notify(src, ('%s received: %s'):format(Shared.Money(amount), reason or 'Housing'), 'success')
        return
    end
    DB.AddPayout(citizenid, amount, reason)
end

--- Money into a job's society account. Edit this for your banking script.
function Bridge.AddSociety(job, amount, reason)
    amount = math.floor(amount or 0)
    if not job or amount <= 0 then return end
    if GetResourceState('Renewed-Banking') == 'started' then
        local ok = pcall(function() exports['Renewed-Banking']:addAccountMoney(job, amount) end)
        if ok then return end
    end
    if GetResourceState('qbx_management') == 'started' then
        local ok = pcall(function() exports.qbx_management:AddMoney(job, amount) end)
        if ok then return end
    end
    print(('[pmv2_housing] No society banking found - %s for %s was not deposited (%s)'):format(Shared.Money(amount), job, reason or ''))
end

-- ── Discord logs ─────────────────────────────────────────────
-- set pmv2_housing_webhook "https://discord.com/api/webhooks/..." in server.cfg
local webhook = GetConvar('pmv2_housing_webhook', '')

function Bridge.Log(title, description, color)
    if webhook == '' then return end
    PerformHttpRequest(webhook, function() end, 'POST', json.encode({
        username = 'PMv2 Housing',
        embeds = { {
            title = title,
            description = description,
            color = color or 0x9b59ff,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            footer = { text = 'Project Misfits v2 • Housing' },
        } },
    }), { ['Content-Type'] = 'application/json' })
end
