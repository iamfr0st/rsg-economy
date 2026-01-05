-- sv_vat.lua

--========================================================--
-- rsg-economy / server/sv_vat.lua
-- Hybrid VAT v2.0 (Full Ledger Mode)
--========================================================--

local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

------------------------------------------------------------
-- Region VAT enable check
------------------------------------------------------------
local function isRegionVATEnabled(region_name)
    if not Config or not Config.VAT then return false end
    if Config.VAT.EnabledGlobal then return true end
    region_name = string.lower(region_name or "unknown")
    if type(Config.VAT.RegionsEnabled) == "table" then
        return Config.VAT.RegionsEnabled[region_name] == true
    end
    return false
end

------------------------------------------------------------
-- SQL Helpers: ensure business + vat accounts
------------------------------------------------------------
local function ensureBusinessRow(citizenid, region_name)
    region_name = string.lower(region_name)
    local rows = MySQL.single.await(
        "SELECT id FROM economy_businesses WHERE citizenid = ? AND region_name = ? LIMIT 1",
        { citizenid, region_name }
    )
    if rows and rows.id then
        return rows.id
    end

    MySQL.insert.await(
        "INSERT INTO economy_businesses (citizenid, region_name, name, vat_registered) VALUES (?, ?, ?, 1)",
        { citizenid, region_name, ("Business %s"):format(citizenid) }
    )

    local created = MySQL.single.await(
        "SELECT id FROM economy_businesses WHERE citizenid = ? AND region_name = ? LIMIT 1",
        { citizenid, region_name }
    )
    return created and created.id
end

local function ensureVATAccount(business_id, region_name)
    region_name = string.lower(region_name)
    local acc = MySQL.single.await(
        "SELECT * FROM economy_vat_accounts WHERE business_id = ? AND region_name = ? LIMIT 1",
        { business_id, region_name }
    )
    if acc then return acc end

    MySQL.insert.await(
        "INSERT INTO economy_vat_accounts (business_id, region_name, vat_input_cents, vat_output_cents, vat_settled_cents) VALUES (?, ?, 0, 0, 0)",
        { business_id, region_name }
    )

    return {
        business_id = business_id,
        region_name = region_name,
        vat_input_cents = 0,
        vat_output_cents = 0,
        vat_settled_cents = 0,
    }
end

------------------------------------------------------------
-- VAT PUBLIC API
------------------------------------------------------------
local function VAT_RecordOutput(citizenid, region_name, base_amount, tax_amount, tax_rate, ref)
    region_name = string.lower(region_name)
    local bid = ensureBusinessRow(citizenid, region_name)
    if not bid then return false end

    MySQL.insert.await(
        "INSERT INTO economy_vat_ledger (business_id, region_name, direction, base_amount, tax_amount, tax_rate, ref_text) VALUES (?, ?, 'OUTPUT', ?, ?, ?, ?)",
        { bid, region_name, base_amount, tax_amount, tax_rate, ref or "sale" }
    )

    MySQL.update.await(
        "UPDATE economy_vat_accounts SET vat_output_cents = vat_output_cents + ? WHERE business_id = ? AND region_name = ?",
        { math.floor((tax_amount or 0) * 100 + 0.5), bid, region_name }
    )

    return true
end
exports("VAT_RecordOutput", VAT_RecordOutput)

local function VAT_RecordInput(citizenid, region_name, base_amount, tax_amount, tax_rate, ref)
    region_name = string.lower(region_name)
    local bid = ensureBusinessRow(citizenid, region_name)
    if not bid then return false end

    MySQL.insert.await(
        "INSERT INTO economy_vat_ledger (business_id, region_name, direction, base_amount, tax_amount, tax_rate, ref_text) VALUES (?, ?, 'INPUT', ?, ?, ?, ?)",
        { bid, region_name, base_amount, tax_amount, tax_rate, ref or "expense" }
    )

    MySQL.update.await(
        "UPDATE economy_vat_accounts SET vat_input_cents = vat_input_cents + ? WHERE business_id = ? AND region_name = ?",
        { math.floor((tax_amount or 0) * 100 + 0.5), bid, region_name }
    )

    return true
end
exports("VAT_RecordInput", VAT_RecordInput)

local function VAT_GetSummary(citizenid, region_name)
    region_name = string.lower(region_name)
    local rowBiz = MySQL.single.await(
        "SELECT id FROM economy_businesses WHERE citizenid = ? AND region_name = ? LIMIT 1",
        { citizenid, region_name }
    )
    if not rowBiz or not rowBiz.id then
        return { output = 0, input = 0, settled = 0, net_due = 0 }
    end

    local acc = ensureVATAccount(rowBiz.id, region_name)

    local output  = tonumber(acc.vat_output_cents or 0) / 100
    local input   = tonumber(acc.vat_input_cents or 0) / 100
    local settled = tonumber(acc.vat_settled_cents or 0) / 100
    local net_due = output - input - settled

    return {
        output = output,
        input = input,
        settled = settled,
        net_due = net_due
    }
end
exports("VAT_GetSummary", VAT_GetSummary)

local function VAT_Settle(citizenid, region_name, ref)
    region_name = string.lower(region_name)
    local s = VAT_GetSummary(citizenid, region_name)
    local due = s.net_due
    if due == 0 then return 0 end

    local bid = ensureBusinessRow(citizenid, region_name)
    local due_cents = math.floor(due * 100 + 0.5)

    MySQL.insert.await(
        "INSERT INTO economy_vat_ledger (business_id, region_name, direction, base_amount, tax_amount, tax_rate, ref_text) VALUES (?, ?, 'SETTLEMENT', 0, ?, 0, ?)",
        { bid, region_name, due, ref or "VAT settlement" }
    )

    MySQL.update.await(
        "UPDATE economy_vat_accounts SET vat_settled_cents = vat_settled_cents + ? WHERE business_id = ? AND region_name = ?",
        { due_cents, bid, region_name }
    )

    exports['rsg-economy']:RecordCollectedTax(
        region_name,
        "vat_settlement",
        due,
        0,
        nil,
        citizenid,
        ref or "VAT settlement"
    )

    return due
end
exports("VAT_Settle", VAT_Settle)

------------------------------------------------------------
-- Notifications
------------------------------------------------------------
local function notify(src, title, msg, ntype, ms)
    TriggerClientEvent("ox_lib:notify", src, {
        title = title,
        description = msg,
        type = ntype,
        duration = ms or 6000
    })
end

------------------------------------------------------------
-- Region detection helper (via rsg-economy/_auth)
------------------------------------------------------------
local function getCallerRegionName(src)
    local ok, alias = pcall(function()
        return exports['rsg-economy']:GetPlayerRegionAlias(src)
    end)
    if ok and alias then
        return string.lower(alias)
    end
    return nil
end

------------------------------------------------------------
-- OWNER COMMAND: /vatmenu
------------------------------------------------------------
RSGCore.Commands.Add("vatmenu", "Open your VAT dashboard", {}, false, function(src, args)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local region    = getCallerRegionName(src)
    if not region then
        return notify(src, locale('vat') or "VAT", locale('unable_to_detect_region') or "Could not determine your region.", "error")
    end

    local biz = MySQL.single.await(
        "SELECT * FROM economy_businesses WHERE citizenid = ? AND region_name = ? LIMIT 1",
        { citizenid, region }
    )
    if not biz then
        return notify(src, locale('vat') or "VAT", locale('no_own_business_registered') or "You do not own a business in this region.", "error")
    end

    local summary = VAT_GetSummary(citizenid, region)

    TriggerClientEvent('rsg-economy:openVatMenu', src, {
        business_name = biz.name,
        region        = region,
        summary       = summary,
        citizenid     = citizenid
    })
end, "user")

------------------------------------------------------------
-- UI → Server Settlement Event
------------------------------------------------------------
RegisterNetEvent("vat:clientSettle", function(data)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = data.citizenid
    local region    = data.region

    if Player.PlayerData.citizenid ~= citizenid then
        return notify(src, locale('vat') or "VAT", locale('not_your_business') or "This is not your business.", "error")
    end

    local summary = VAT_GetSummary(citizenid, region)
    local net     = summary.net_due

    if net == 0 then
        return notify(src, locale('vat') or "VAT", locale('nothing_to_settle') or "Nothing to settle.", "inform")
    end

    -- IMPORTANT: keep money operations deterministic (whole dollars)
    if net > 0 then
        local pay = math.floor(net + 0.5)
        if pay <= 0 then
            return notify(src, locale('vat') or "VAT", locale('nothing_to_settle') or "Nothing to settle.", "inform")
        end

        if not Player.Functions.RemoveMoney("cash", pay, "vat-settlement") then
            return notify(src, locale('vat') or "VAT", locale('insufficient_funds_cash') or "Insufficient cash to settle VAT.", "error")
        end

        VAT_Settle(citizenid, region, "Owner VAT Settlement")
        notify(src, locale('vat') or "VAT", (locale('you_paid_vat') or "You paid $%d in VAT."):format(pay), "success")
    else
        local refund = math.floor((-net) + 0.5)
        if refund <= 0 then
            return notify(src, locale('vat') or "VAT", locale('nothing_to_settle') or "Nothing to settle.", "inform")
        end

        Player.Functions.AddMoney("cash", refund, "vat-refund")
        VAT_Settle(citizenid, region, "VAT Refund")
        notify(src, locale('vat') or "VAT", (locale('you_received_refund') or "You received a refund of $%d."):format(refund), "success")
    end
end)

------------------------------------------------------------
-- GOVERNOR COMMANDS
------------------------------------------------------------
RSGCore.Commands.Add("vatreport", locale("vat_report_command") or "VAT summary for business", {
    { name = "citizenid", help = locale("citizenid_label") or "business owner's citizenid" },
    { name = "region_name", help = locale("region_label_optional") or "optional region name (default: your region)" }
}, false, function(src, args)
    local citizenid = args[1]
    local region    = args[2] or getCallerRegionName(src)
    if not citizenid or not region then
        return notify(src, locale("vat") or "VAT", locale("vat_report_usage") or "Usage: /vatreport <citizenid> [region]", "inform")
    end

    local summary = VAT_GetSummary(citizenid, region)
    local text = (locale("vat_report_vsd") or "Region: %s\nOutput VAT: $%.2f\nInput VAT: $%.2f\nSettled: $%.2f\nNet Due: $%.2f")
        :format(region, summary.output, summary.input, summary.settled, summary.net_due)

    notify(src, "VAT Report", text, "success", 12000)
end)

RSGCore.Commands.Add("settlevat", locale("settle_vat_command") or "Manually settle VAT for a business", {
    { name = "citizenid", help = locale("citizenid_label") or "business owner's citizenid" },
    { name = "region_name", help = locale("region_label_optional") or "optional region name (default: your region)" }
}, false, function(src, args)
    local citizenid = args[1]
    local region    = args[2] or getCallerRegionName(src)

    local amt = VAT_Settle(citizenid, region, "Manual settlement")
    if amt > 0 then
        notify(src, locale("vat") or "VAT", (locale("settled_vat_for") or "Settled $%.2f VAT for %s."):format(amt, citizenid), "success")
    else
        notify(src, locale("vat") or "VAT", locale("nothing_to_settle") or "Nothing to settle.", "inform")
    end
end)

-- /registerbusiness
RSGCore.Commands.Add('registerbusiness',  locale("registerbiz_command_description") or 'Register a business in your current region', {
    { name = 'name', help = locale("business_name_label") or "Business Name (e.g. Sundance Trading Co.)" }
}, false, function(src, args)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local region    = getCallerRegionName(src)

    if not region then
        return notify(src, locale("business") or "Business", locale("unable_to_detect_region") or "Unable to determine your region.", "error", 7000)
    end

    if not isRegionVATEnabled(region) then
        return notify(src, locale("business") or "Business", (locale("business_registration_not_available") or "Business registration is not available in %s."):format(region), "error", 7000)
    end

    local name = table.concat(args or {}, ' ')
    name = (name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then
        return notify(src, locale("business") or "Business", locale("registerbiz_command_usage") or "Usage: /registerbusiness <Business Name>", "inform", 8000)
    end

    if #name < 3 or #name > 64 then
        return notify(src, locale("business") or "Business", locale("business_name_length_error") or "Business name must be between 3 and 64 characters.", "error", 8000)
    end

    local res = MySQL.single.await([[
        SELECT id FROM election_residents
        WHERE citizenid = ? AND LOWER(region_alias) = ?
        LIMIT 1
    ]], { citizenid, region })

    if not res then
        return notify(src, locale("business") or "Business", locale("error_resident") or "You must be a registered resident of this region to open a business.", "error", 8000)
    end

    local existing = MySQL.single.await([[
        SELECT id, name FROM economy_businesses
        WHERE citizenid = ? AND region_name = ?
        LIMIT 1
    ]], { citizenid, region })

    if existing then
        return notify(src, locale("business") or "Business",
            (locale("already_own_business") or 'You already own a business ("%s") in this region.'):format(existing.name),
            "error", 9000
        )
    end

    local fee = 0
    if Config and Config.VAT and Config.VAT.RegistrationFee then
        fee = tonumber(Config.VAT.RegistrationFee) or 0
    end

    if fee > 0 then
        if not Player.Functions.RemoveMoney('cash', fee, 'business-registration') then
            return notify(src, locale("business") or "Business",
                (locale("need_cash_to_register_business") or 'You need $%d in cash to register a business.'):format(fee),
                "error", 9000
            )
        end
    end

    MySQL.insert.await(
        'INSERT INTO economy_businesses (citizenid, region_name, name, vat_registered) VALUES (?, ?, ?, 1)',
        { citizenid, region, name }
    )

    local biz = MySQL.single.await([[
        SELECT id FROM economy_businesses
        WHERE citizenid = ? AND region_name = ?
        ORDER BY id DESC LIMIT 1
    ]], { citizenid, region })

    if biz and biz.id then
        ensureVATAccount(biz.id, region)
    end

    notify(src, locale("business") or "Business",
        (locale("registered_business_sv") or 'You registered "%s" as a business in %s%s.'):format(
            name, region,
            fee > 0 and (' (paid $' .. fee .. ' fee)') or ''
        ),
        'success', 9000
    )
end, 'user')

-- /vataudit
RSGCore.Commands.Add('vataudit', locale("vataudit_command_description") or 'Open VAT audit panel for this region', {
    { name = 'region', help = locale("region_alias_optional") or 'Optional region alias (new_hanover, lemoyne, etc.)' }
}, false, function(source, args)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local region = args[1] and string.lower(args[1]) or getCallerRegionName(src)
    if not region then
        return notify(src, locale("vat_audit") or 'VAT Audit', locale("unable_to_detect_region") or 'Unable to determine region.', 'error', 8000)
    end

    local okPerm = false
    local ok, res = pcall(function()
        if exports['rsg-economy'] and exports['rsg-economy'].CanActOnRegion then
            return exports['rsg-economy']:CanActOnRegion(src, region, 'command.vataudit')
        end
    end)

    if ok and res then
        okPerm = true
    else
        if RSGCore.Functions.HasPermission(src, 'god') or RSGCore.Functions.HasPermission(src, 'admin') then
            okPerm = true
        end
    end

    if not okPerm then
        return notify(src, locale("vat_audit") or 'VAT Audit', locale("not_allowed_audit_vat") or 'You are not allowed to audit VAT in this region.', 'error', 8000)
    end

    local rows = MySQL.query.await([[
        SELECT
            b.id             AS business_id,
            b.name           AS business_name,
            b.citizenid      AS citizenid,
            COALESCE(a.vat_input_cents,   0) AS vat_input_cents,
            COALESCE(a.vat_output_cents,  0) AS vat_output_cents,
            COALESCE(a.vat_settled_cents, 0) AS vat_settled_cents
        FROM economy_businesses b
        LEFT JOIN economy_vat_accounts a
          ON a.business_id = b.id AND a.region_name = b.region_name
        WHERE b.region_name = ?
        ORDER BY b.name ASC
    ]], { region }) or {}

    if #rows == 0 then
        return notify(src, locale("vat_audit") or 'VAT Audit', (locale("no_registered_businesses") or 'No registered businesses found in %s.'):format(region), 'inform', 8000)
    end

    local businesses = {}
    for _, r in ipairs(rows) do
        local output  = (tonumber(r.vat_output_cents or 0) or 0) / 100
        local input   = (tonumber(r.vat_input_cents or 0) or 0) / 100
        local settled = (tonumber(r.vat_settled_cents or 0) or 0) / 100
        local net     = output - input - settled

        businesses[#businesses+1] = {
            business_id   = r.business_id,
            business_name = r.business_name,
            citizenid     = r.citizenid,
            region        = region,
            output        = output,
            input         = input,
            settled       = settled,
            net           = net
        }
    end

    TriggerClientEvent('rsg-economy:vatAuditOpen', src, {
        region     = region,
        businesses = businesses
    })
end, 'user')

------------------------------------------------------------
-- Server callback: fetch detailed VAT ledger for a business
------------------------------------------------------------
lib.callback.register('rsg-economy:getVatLedger', function(source, business_id, region)
    local src = source
    business_id = tonumber(business_id or 0) or 0
    if business_id <= 0 or not region then
        return {}
    end

    region = string.lower(region)

    local okPerm = false
    local ok, res = pcall(function()
        if exports['rsg-economy'] and exports['rsg-economy'].CanActOnRegion then
            return exports['rsg-economy']:CanActOnRegion(src, region, 'command.vataudit')
        end
    end)

    if ok and res then
        okPerm = true
    else
        if RSGCore.Functions.HasPermission(src, 'god') or RSGCore.Functions.HasPermission(src, 'admin') then
            okPerm = true
        end
    end

    if not okPerm then
        return {}
    end

    local ledger = MySQL.query.await([[
        SELECT direction, base_amount, tax_amount, tax_rate, ref_text, created_at
        FROM economy_vat_ledger
        WHERE business_id = ? AND region_name = ?
        ORDER BY created_at DESC
        LIMIT 25
    ]], { business_id, region }) or {}

    return ledger
end)

--========================================================--
-- AUTO VAT SETTLEMENT (triggered by cl_auto_vat.lua)
--========================================================--

RegisterNetEvent('rsg-economy:autoVatCollect', function()
    if not Config or not Config.VAT or not Config.VAT.AutoSettle then
        return
    end

    print('[rsg-economy] Auto VAT collect triggered.')

    -- For each VAT-enabled region, settle VAT for all businesses
    local enabledRegions
    if Config.VAT.EnabledGlobal then
        -- settle for ALL regions found in economy_businesses
        enabledRegions = nil
    else
        enabledRegions = {}
        for region, enabled in pairs(Config.VAT.RegionsEnabled or {}) do
            if enabled then
                enabledRegions[#enabledRegions+1] = region
            end
        end
    end

    local function makePlaceholders(n)
        local t = {}
        for i = 1, n do
            t[i] = "?"
        end
        return table.concat(t, ",")
    end

    local rows
    if enabledRegions == nil then
        rows = MySQL.query.await("SELECT DISTINCT citizenid, region_name FROM economy_businesses") or {}
    else
        if #enabledRegions == 0 then return end
        local placeholders = makePlaceholders(#enabledRegions)
        rows = MySQL.query.await(
            ("SELECT DISTINCT citizenid, region_name FROM economy_businesses WHERE region_name IN ("..placeholders..")"),
            enabledRegions
        ) or {}
    end

    for _, r in ipairs(rows) do
        local cid    = r.citizenid
        local region = r.region_name
        local amt    = VAT_Settle(cid, region, "Auto VAT settlement")
        if amt ~= 0 then
            print(('[rsg-economy] Auto VAT: settled %.2f for %s in %s'):format(amt, cid, region))
        end
    end
end)
