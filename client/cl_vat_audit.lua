-- cl_vat_audit.lua
--========================================================--
-- Client VAT Audit Panel (ox_lib) - HARDENED
--========================================================--
lib.locale()

local function fmtMoney(val)
    return ("$%.2f"):format(tonumber(val) or 0)
end

local function safeStr(s, maxLen)
    s = tostring(s or '')
    maxLen = maxLen or 180
    if #s > maxLen then
        return s:sub(1, maxLen - 3) .. '...'
    end
    return s
end

RegisterNetEvent('rsg-economy:vatAuditOpen', function(data)
    data = data or {}
    local region      = data.region or 'unknown'
    local businesses  = data.businesses or {}

    if not lib or not lib.registerContext then
        print('[rsg-economy] ox_lib context not available on client.')
        return
    end

    local opts = {}

    for _, biz in ipairs(businesses) do
        local net = tonumber(biz.net or 0) or 0

        local state
        if net > 0.01 then
            state = (locale('owes_label') or 'OWES %s'):format(fmtMoney(net))
        elseif net < -0.01 then
            state = (locale('refund_label') or 'REFUND %s'):format(fmtMoney(-net))
        else
            state = locale('settled_label') or 'Settled'
        end

        local desc = (locale('output_label') or 'Output: %s') .. ' | ' .. (locale('input_label') or 'Input: %s') .. ' | ' .. (locale('settled_label_porc') or 'Settled: %s') .. ' | %s'):format(
            fmtMoney(biz.output),
            fmtMoney(biz.input),
            fmtMoney(biz.settled),
            state
        )

        opts[#opts+1] = {
            title       = biz.business_name or (locale('business_label') or 'Business #' .. tostring(biz.business_id)),
            description = safeStr(desc, 200),
            icon        = (net > 0.01 and 'triangle-exclamation')
                       or (net < -0.01 and 'circle-arrow-left')
                       or 'circle-check',
            arrow       = true,
            event       = 'rsg-economy:vatAuditDetail',
            args        = {
                business_id   = biz.business_id,
                business_name = biz.business_name,
                region        = region
            }
        }
    end

    lib.registerContext({
        id = 'vat_audit_main',
        title = (locale('vat_audit_title') or 'VAT Audit — %s'):format(region),
        canClose = true,
        options = opts
    })

    lib.showContext('vat_audit_main')
end)

RegisterNetEvent('rsg-economy:vatAuditDetail', function(args)
    args = args or {}
    local business_id   = tonumber(args.business_id or 0) or 0
    local business_name = args.business_name or (locale('business_label') or 'Business #' .. tostring(business_id))
    local region        = args.region or locale('unknown') or 'unknown'

    if business_id <= 0 then
        return print('[rsg-economy] vatAuditDetail: invalid business_id')
    end

    local ledger = {}
    if lib and lib.callback and lib.callback.await then
        ledger = lib.callback.await('rsg-economy:getVatLedger', false, business_id, region) or {}
    else
        print('[rsg-economy] ox_lib callback not available on client.')
        ledger = {}
    end

    local opts = {}

    if #ledger == 0 then
        opts[#opts+1] = {
            title = locale('no_vat_ledger_entries') or 'No VAT ledger entries.',
            description = locale('no_vat_ledger_entries_description') or 'This business has no recorded INPUT/OUTPUT/SETTLEMENT entries yet.',
            disabled = true
        }
    else
        for _, row in ipairs(ledger) do
            local dir = tostring(row.direction or '?')
            local tag = (dir == (locale('output_label_upper') or 'OUTPUT') and (locale('sale_label') or 'Sale'))
                     or (dir == (locale('input_label_upper') or 'INPUT') and (locale('expense_label') or 'Expense'))
                     or (dir == (locale('settled_label_upper') or 'SETTLEMENT') and (locale('settle_label') or 'Settle'))
                     or dir

            local title = ('[%s] %s'):format(tag, fmtMoney(row.tax_amount or 0))

            local created = safeStr(row.created_at or '', 32)
            local desc = ('Base: %s | Rate: %.2f%%\n%s\n%s'):format(
                fmtMoney(row.base_amount or 0),
                tonumber(row.tax_rate or 0) or 0,
                safeStr(row.ref_text or '', 90),
                created
            )

            opts[#opts+1] = { title = title, description = desc, disabled = true }
        end
    end

    local id = 'vat_audit_detail_' .. tostring(business_id)

    lib.registerContext({
        id = id,
        title = (locale('vat_ledger_title') or 'VAT Ledger — %s (%s)'):format(business_name, region),
        menu  = 'vat_audit_main',
        canClose = true,
        options = opts
    })

    lib.showContext(id)
end)
