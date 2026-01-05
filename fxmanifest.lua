fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'rsg-economy'
author 'fr0st'
description 'Regional taxes, treasury, VAT & revenue for RedM'
version '1.5.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',

    -- Authoritative district→state resolver (exports getState/debugDump)
    'shared/sh_state_region_helper.lua',

    -- OPTIONAL:
    -- If you want the shared ApplyAndRecordTax() export to exist (shared-side),
    -- uncomment this. If you only use server exports, leave it off.
    -- 'shared/sh_tax_helper.lua',
}

client_scripts {
    'client/cl_main.lua',
    'client/cl_vat_menu.lua',
    'client/cl_vat_audit.lua',
    'client/cl_auto_vat.lua',
    'client/cl_economy_menu.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',

    'server/_auth.lua',
    'server/sv_tax.lua',
    'server/sv_treasury.lua',
    'server/sv_revenue.lua',
    'server/sv_vat.lua',

    -- Canonical server-side export for ApplyAndRecordTax()
    'server/sv_tax_helper.lua',

    'server/sv_residency.lua',
}

files{
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'rsg-core'
}
