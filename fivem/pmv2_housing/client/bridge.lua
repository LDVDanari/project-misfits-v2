-- ─────────────────────────────────────────────────────────────
--  CLIENT BRIDGE - wardrobe + notifications. Edit here for other scripts.
-- ─────────────────────────────────────────────────────────────
Bridge = {}

function Bridge.Notify(description, ntype, title)
    lib.notify({ title = title or 'Housing', description = description, type = ntype or 'inform' })
end

function Bridge.OpenWardrobe()
    local w = Config.Wardrobe
    if w == 'illenium' then
        TriggerEvent('illenium-appearance:client:openOutfitMenu')
    elseif w == 'qb-clothing' then
        TriggerEvent('qb-clothing:client:openOutfitMenu')
    else
        -- 'custom' / anything else: put your clothing script's outfit menu call here.
        Bridge.Notify('Wardrobe is not set up (Config.Wardrobe).', 'error')
    end
end

function Bridge.OpenStash(stashId)
    exports.ox_inventory:openInventory('stash', stashId)
end
