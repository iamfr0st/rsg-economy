--======================================================================
-- rsg-economy / server/_auth.lua
-- Region authorization + region alias helpers
--
-- Exports:
--   CanActOnRegion(src, targetRegion, perm)
--   GetPlayerRegionAlias(src) -> "new_hanover", etc.
--======================================================================

local RSGCore   = exports['rsg-core']:GetCoreObject()
local GOV_TABLE = Config.TableName or 'governors'

-- Basic admin override:
--  - Console
--  - Specific ACE perm (command.*)
--  - Global ACE (Config.AcePermission)
--  - group.admin
local function isAdminOverride(src, perm)
    if src == 0 then return true end

    if perm and IsPlayerAceAllowed(src, perm) then
        return true
    end

    if Config and Config.AcePermission and IsPlayerAceAllowed(src, Config.AcePermission) then
        return true
    end

    return IsPlayerAceAllowed(src, 'group.admin')
end

-- Try to use rsg-governor as source-of-truth for governor status
local function isRegionGovernorSourceOfTruth(src, region_name)
    region_name = string.lower(region_name or 'unknown')

    -- Preferred: delegate to rsg-governor if it exposes IsRegionGovernor
    local ok, res = pcall(function()
        if exports['rsg-governor'] and exports['rsg-governor'].IsRegionGovernor then
            return exports['rsg-governor']:IsRegionGovernor(src, region_name)
        end
    end)
    if ok and res ~= nil then
        return res == true
    end

    -- Optional ACE fallback per region (e.g. add_ace group.governor role.governor.new_hanover allow)
    if IsPlayerAceAllowed(src, ('role.governor.%s'):format(region_name)) then
        return true
    end

    return false
end

-- Public guard: call this before changing taxes, registering businesses, VAT, etc.
-- perm is an ACE override string, e.g. 'command.settax' / 'command.vataudit'
local function CanActOnRegion(src, targetRegion, perm)
    if not targetRegion or targetRegion == '' then return false end
    targetRegion = string.lower(targetRegion)
    if isAdminOverride(src, perm) then return true end
    return isRegionGovernorSourceOfTruth(src, targetRegion)
end
exports('CanActOnRegion', CanActOnRegion)

-- Region alias helper for VAT, HUD, etc.
-- Uses rsg-governor:getRegionHash callback: expected to return (hash, alias).
local function GetPlayerRegionAlias(src)
    local ok, hash, alias = pcall(function()
        return lib.callback.await('rsg-governor:getRegionHash', src)
    end)

    if ok and alias and alias ~= '' then
        return string.lower(alias)
    end

    return nil
end
exports('GetPlayerRegionAlias', GetPlayerRegionAlias)
