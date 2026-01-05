-- sv_business.lua

--======================================================================
-- rsg-economy / server/sv_business.lua
-- Business registration + VAT-aware helper exports
--======================================================================

local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local function normRegion(s)
    s = tostring(s or ''):lower()
    s = s:gsub('[%s%-]+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    return s
end

-- HARDENED: use economy auth helper (which itself falls back)
local function getHereRegionAlias(src)
    local ok, alias = pcall(function()
        return exports['rsg-economy']:GetPlayerRegionAlias(src)
    end)
    if ok and alias and alias ~= '' then
        return alias
    end
    return nil
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
RSGCore.Commands.Add('registerbiz', locale('registerbiz_command_description') or 'Register / update a business in this region', {
    { name = locale('region') or 'region',      help = locale('region_label') or 'region name or "here"' },
    { name = locale('license_label') or 'licenseType', help = locale('license_desc') or 'type (e.g. shop, market, etc)' },
    { name = locale('name') or 'name',        help = locale('name_desc') or 'business name (rest of args)' },
}, true, function(source, args)
    local src         = source
    local regionArg   = args[1]
    local licenseType = tostring(args[2] or 'general')
    local businessName

    if #args >= 3 then
        businessName = table.concat(args, ' ', 3)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('economy') or 'Economy',
            description = locale('registerbiz_command_usage') or 'Usage: /registerbiz [region|here] [licenseType] [business name]',
            type = 'error'
        })
        return
    end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Resolve region
    local regionName = regionArg
    if regionArg == 'here' or not regionArg or regionArg == '' then
        regionName = getHereRegionAlias(src)
        if not regionName then
            TriggerClientEvent('ox_lib:notify', src, {
                title = locale('economy') or 'Economy',
                description = locale('unable_to_detect_region') or 'Unable to determine your current region.',
                type = 'error'
            })
            return
        end
    end

    -- Permission via economy _auth
    local okAuth = false
    local ok, res = pcall(function()
        return exports['rsg-economy']:CanActOnRegion(src, regionName, 'command.registerbiz')
    end)
    if ok and res then okAuth = true end

    if not okAuth then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('economy') or 'Economy',
            description = locale('not_allowed_manage_businesses') or 'You are not allowed to manage businesses for this region.',
            type = 'error'
        })
        return
    end

    upsertBusiness(
        Player.PlayerData.citizenid,
        regionName,
        businessName,
        licenseType,
        true
    )

    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('economy') or 'Economy',
        description = (locale('registered_business') or 'Registered business "%s" in %s.'):format(businessName, normRegion(regionName)),
        type = 'success'
    })
end, 'user')

-- /unregisterbiz [region|here]
RSGCore.Commands.Add('unregisterbiz', locale('unregisterbiz_command_description') or 'Clear your business registration in this region', {
    { name = locale('region') or 'region', help = locale('region_label') or 'region name or "here"' },
}, false, function(source, args)
    local src       = source
    local regionArg = args[1]
    local Player    = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local regionName = regionArg
    if regionArg == 'here' or not regionArg or regionArg == '' then
        regionName = getHereRegionAlias(src)
        if not regionName then
            TriggerClientEvent('ox_lib:notify', src, {
                title = locale('economy') or 'Economy',
                description = locale('unable_to_detect_region') or 'Unable to determine your current region.',
                type = 'error'
            })
            return
        end
    end

    clearBusiness(Player.PlayerData.citizenid, regionName)

    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('economy') or 'Economy',
        description = (locale('cleared_business_registration') or 'Cleared your business registration in %s.'):format(normRegion(regionName)),
        type = 'success'
    })
end, 'user')

-- /bizinfo [region|here]
RSGCore.Commands.Add('bizinfo', locale('bizinfo_command_description') or 'Show your business info in this region', {
    { name = locale('region') or 'region', help = locale('region_label') or 'region name or "here"' },
}, false, function(source, args)
    local src       = source
    local regionArg = args[1]
    local Player    = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local regionName = regionArg
    if regionArg == 'here' or not regionArg or regionArg == '' then
        regionName = getHereRegionAlias(src)
        if not regionName then
            TriggerClientEvent('ox_lib:notify', src, {
                title = locale('economy') or 'Economy',
                description = locale('unable_to_detect_region') or 'Unable to determine your current region.',
                type = 'error'
            })
            return
        end
    end

    local row = getBusinessRow(Player.PlayerData.citizenid, regionName)
    if not row then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale('economy') or 'Economy',
            description = locale('no_business_registered') or 'No business registered in this region.',
            type = 'inform'
        })
        return
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('business_info') or 'Business Info',
        description = (locale('info_description') or 'Name: %s\nType: %s\nVAT: %s'):format(
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
