-- cl_vat_menu.lua
--========================================================--
-- VAT MENU UI (CLIENT) - FIXED
--========================================================--
lib.locale()

local function money(x)
    return ("$%.2f"):format(tonumber(x) or 0)
end

local function notify(title, msg, ntype, ms)
    if lib and lib.notify then
        lib.notify({ title = title or 'VAT', description = msg or '', type = ntype or 'inform', duration = ms or 6000 })
    else
        print(('[rsg-economy] %s: %s'):format(title or 'VAT', msg or ''))
    end
end

RegisterNetEvent('rsg-economy:openVatMenu', function(data)
    data = data or {}

    local bizName   = data.business_name or (locale('business_label') or "Business")
    local region    = data.region or (locale('unknown') or "unknown")
    local s         = data.summary or {}
    local citizenid = data.citizenid

    if not lib or not lib.registerContext then
        print('[rsg-economy] ERROR: ox_lib context not available on client.')
        return
    end

    local due = tonumber(s.net_due or 0) or 0
    local settleDesc
    if due > 0 then
        settleDesc = (locale('pay_to_government') or "Pay %s to government"):format(money(due))
    elseif due < 0 then
        settleDesc = (locale('refund_due') or "Refund %s due to you"):format(money(-due))
    else
        settleDesc = locale('nothing_to_settle') or "Nothing to settle"
    end

    lib.registerContext({
        id = "vat_menu",
        title = (locale("vat_ledger_title") or "VAT — %s (%s)"):format(bizName, region),
        canClose = true,
        options = {
            { title = locale('output_label_vat') or "Output VAT", description = money(s.output),  disabled = true, icon = "arrow-up" },
            { title = locale('input_label_vat') or "Input VAT",  description = money(s.input),   disabled = true, icon = "arrow-down" },
            { title = locale('settled_label') or "Settled",    description = money(s.settled), disabled = true, icon = "briefcase" },
            { title = locale('net_vat_due_label') or "Net VAT Due",description = money(s.net_due), disabled = true, icon = "scale-balanced" },

            {
                title = locale("settle_vat") or "Settle VAT",
                icon = "circle-check",
                description = settleDesc,
                disabled = (due == 0),
                onSelect = function()
                    -- IMPORTANT: server listens to RegisterNetEvent("vat:clientSettle")
                    -- so we must TriggerServerEvent from client.
                    if not citizenid or not region then
                        return notify(locale("vat") or "VAT", locale("missing_vat_data") or "Missing VAT data; cannot settle.", "error", 7000)
                    end

                    TriggerServerEvent("vat:clientSettle", { citizenid = citizenid, region = region })
                end
            }
        }
    })

    lib.showContext("vat_menu")
end)
