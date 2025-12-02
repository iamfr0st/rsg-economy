--======================================================================
-- rsg-economy / server/sv_business.lua
-- Business registration + VAT-aware helper exports
--======================================================================

local RSGCore = exports['rsg-core']:GetCoreObject()

local function normRegion(s)
    s = tostring(s or ''):lower()
    s = s:gsub('[%s%-]+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    return s
end

-- internal helpers
local function getBusinessRow(citizenid, region_name)
    region_name = normRegion(region_name)
    local row = MySQL.single.await(
        'SELECT * FROM economy_businesses WHERE citizenid = ? AND region_name = ? LIMIT 1',
        { citizenid, region_name }
    )
    return row
end

local function upsertBusiness(citizenid, region_name, name, license_type, vat)
    region_name  = normRegion(region_name)
    license_type = tostring(license_type or 'general')
    vat          = vat and 1 or 0

    MySQL.insert.await([[
        INSERT INTO economy_businesses (citizenid, region_name, business_name, license_type, vat_registered)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            business_name = VALUES(business_name),
            license_type  = VALUES(license_type),
            vat_registered = VALUES(vat_registered),
            updated_at    = CURRENT_TIMESTAMP
    ]], { citizenid, region_name, name, license_type, vat })
end

local function clearBusiness(citizenid, region_name)
    region_name = normRegion(region_name)
    MySQL.update.await(
        'DELETE FROM economy_businesses WHERE citizenid = ? AND region_name = ?',
        { citizenid, region_name }
    )
end

--======================================================================
-- COMMANDS
--======================================================================

-- /registerbiz [region|here] [licenseType] [business name...]
RSGCore.Commands.Add('registerbiz', 'Register / update a business in this region', {
    { name = 'region',      help = 'region name or "here"' },
    { name = 'licenseType', help = 'type (e.g. shop, market, etc)' },
    { name = 'name',        help = 'business name (rest of args)' },
}, true, function(source, args)
    local src         = source
    local regionArg   = args[1]
    local licenseType = tostring(args[2] or 'general')
    local businessName

    if #args >= 3 then
        businessName = table.concat(args, ' ', 3)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Economy',
            description = 'Usage: /registerbiz [region|here] [licenseType] [business name]',
            type = 'error'
        })
        return
    end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Resolve region
    local regionName = regionArg
    if regionArg == 'here' or not regionArg or regionArg == '' then
        local ok, _, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Economy',
                description = 'Unable to determine your current region.',
                type = 'error'
            })
            return
        end
        regionName = alias
    end

    -- Permission via economy _auth
    local okAuth = false
    local ok, res = pcall(function()
        return exports['rsg-economy']:CanActOnRegion(src, regionName, 'command.registerbiz')
    end)
    if ok and res then okAuth = true end

    if not okAuth then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Economy',
            description = 'You are not allowed to manage businesses for this region.',
            type = 'error'
        })
        return
    end

    upsertBusiness(
        Player.PlayerData.citizenid,
        regionName,
        businessName,
        licenseType,
        true   -- mark VAT-registered by default, you can toggle later
    )

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Economy',
        description = ('Registered business "%s" in %s.'):format(businessName, normRegion(regionName)),
        type = 'success'
    })
end, 'user')

-- /unregisterbiz [region|here]
RSGCore.Commands.Add('unregisterbiz', 'Clear your business registration in this region', {
    { name = 'region', help = 'region name or "here"' },
}, false, function(source, args)
    local src       = source
    local regionArg = args[1]
    local Player    = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local regionName = regionArg
    if regionArg == 'here' or not regionArg or regionArg == '' then
        local ok, _, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Economy',
                description = 'Unable to determine your current region.',
                type = 'error'
            })
            return
        end
        regionName = alias
    end

    -- You can restrict this further via CanActOnRegion if you want governors only.
    clearBusiness(Player.PlayerData.citizenid, regionName)

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Economy',
        description = ('Cleared your business registration in %s.'):format(normRegion(regionName)),
        type = 'success'
    })
end, 'user')

-- /bizinfo [region|here]
RSGCore.Commands.Add('bizinfo', 'Show your business info in this region', {
    { name = 'region', help = 'region name or "here"' },
}, false, function(source, args)
    local src       = source
    local regionArg = args[1]
    local Player    = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local regionName = regionArg
    if regionArg == 'here' or not regionArg or regionArg == '' then
        local ok, _, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Economy',
                description = 'Unable to determine your current region.',
                type = 'error'
            })
            return
        end
        regionName = alias
    end

    local row = getBusinessRow(Player.PlayerData.citizenid, regionName)
    if not row then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Economy',
            description = 'No business registered in this region.',
            type = 'inform'
        })
        return
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Business Info',
        description = ('Name: %s\nType: %s\nVAT: %s'):format(
            row.business_name,
            row.license_type,
            row.vat_registered == 1 and 'Registered' or 'No'
        ),
        type = 'inform',
        duration = 8000
    })
end, 'user')

--======================================================================
-- EXPORTS (for VAT or other resources)
--======================================================================

exports('GetBusinessForCitizen', function(citizenid, region_name)
    return getBusinessRow(citizenid, region_name)
end)

exports('IsVATRegistered', function(citizenid, region_name)
    local row = getBusinessRow(citizenid, region_name)
    return row and row.vat_registered == 1 or false
end)
