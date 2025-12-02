-- rsg-economy/server/sv_residency.lua
-- Simple helpers to check if a player/citizen is a resident of a region

local RSGCore      = exports['rsg-core']:GetCoreObject()
local RES_TABLE    = 'rsg_residency'

local function normRegion(s)
    s = tostring(s or ''):lower()
    s = s:gsub('[%s%-]+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    return s
end

local function isCitizenResidentOfRegion(citizenid, region_alias)
    if not citizenid or citizenid == '' or not region_alias or region_alias == '' then
        return false
    end

    local reg = normRegion(region_alias)

    local rows = MySQL.query.await(([[ 
        SELECT region_alias 
          FROM %s 
         WHERE citizenid = ? 
         ORDER BY id DESC 
         LIMIT 1
    ]]):format(RES_TABLE), { citizenid })

    if not rows or not rows[1] then
        return false
    end

    local rowAlias = normRegion(rows[1].region_alias or '')
    return rowAlias == reg
end

-- MAIN: check by src
local function isPlayerResidentOfRegion(src, region_alias)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end
    return isCitizenResidentOfRegion(Player.PlayerData.citizenid, region_alias)
end

exports('IsPlayerResidentOfRegion', isPlayerResidentOfRegion)
exports('IsCitizenResidentOfRegion', isCitizenResidentOfRegion)
