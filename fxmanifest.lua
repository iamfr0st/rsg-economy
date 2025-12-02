fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'rsg-economy'
author 'fr0st'
description 'Regional taxes, treasury, VAT & revenue for RedM'

lua54 'yes'

-- Main economy config (VAT, state mapping, owner IDs)
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/sh_region_helper.lua',    
    'shared/sh_state_region_helper.lua',
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
    'server/sv_tax_helper.lua',
    'server/sv_residency.lua',
}