-- cl_vat_menu.lua
--========================================================--
-- VAT MENU UI (CLIENT) - FIXED
--========================================================--

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

    local bizName   = data.business_name or "Business"
    local region    = data.region or "unknown"
    local s         = data.summary or {}
    local citizenid = data.citizenid

    if not lib or not lib.registerContext then
        print('[rsg-economy] ERROR: ox_lib context not available on client.')
        return
    end

    local due = tonumber(s.net_due or 0) or 0
    local settleDesc
    if due > 0 then
        settleDesc = ("Pay %s to government"):format(money(due))
    elseif due < 0 then
        settleDesc = ("Refund %s due to you"):format(money(-due))
    else
        settleDesc = "Nothing to settle"
    end

    lib.registerContext({
        id = "vat_menu",
        title = ("VAT — %s (%s)"):format(bizName, region),
        canClose = true,
        options = {
            { title = "Output VAT", description = money(s.output),  disabled = true, icon = "arrow-up" },
            { title = "Input VAT",  description = money(s.input),   disabled = true, icon = "arrow-down" },
            { title = "Settled",    description = money(s.settled), disabled = true, icon = "briefcase" },
            { title = "Net VAT Due",description = money(s.net_due), disabled = true, icon = "scale-balanced" },

            {
                title = "Settle VAT",
                icon = "circle-check",
                description = settleDesc,
                disabled = (due == 0),
                onSelect = function()
                    -- IMPORTANT: server listens to RegisterNetEvent("vat:clientSettle")
                    -- so we must TriggerServerEvent from client.
                    if not citizenid or not region then
                        return notify("VAT", "Missing VAT data; cannot settle.", "error", 7000)
                    end

                    TriggerServerEvent("vat:clientSettle", { citizenid = citizenid, region = region })
                end
            }
        }
    })

    lib.showContext("vat_menu")
end)
