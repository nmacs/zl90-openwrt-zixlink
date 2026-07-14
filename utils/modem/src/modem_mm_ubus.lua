#!/usr/bin/lua

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

local nixio          = require("nixio")
local posix          = require("posix")
local uci            = require("uci")
local json           = require("cjson")

local uloop          = require("uloop")
local ubus           = require("ubus")

local modem_gpio     = require("modem_gpio")

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

local ucicursor = uci.cursor()

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

local system_ifname = "broadband"
local modem_device = ucicursor:get("network", system_ifname, "device") or "/dev/ttyUSB0"

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

local function system_execute(cmd)
	local handle = io.popen(cmd)
	
	if not handle then
		return nil, "command_error"
	end

	local result = handle:read("*a")
	handle:close()
	
	if (result) then
		result = result:gsub("%s+$", "")
	end
	
	return result
end

local function get_modem_state(dev)
	local cmd = string.format("mmcli -J --modem %s", dev)
	
	local result = system_execute(cmd)
	if (not result) then
		return nil
	end
	
	local ok, data = pcall(json.decode, result)
	if (not ok) then
		return nil
	end
	
	return data
end

local function modem_ubus_status(msg)
	local result = {}
	
	print("Ubus modem status request")
	
	local modem_state = get_modem_state(modem_device)
	if (modem_state) then
		result = modem_state
	end
	
	if (not result.modem) then
		result.modem = {}
	end
	
	if (not result.modem.sim) then
		result.modem.sim = {}
	end
	
	result.modem.sim.selected = modem_gpio.sim_selected_read()
	result.modem.sim.sim1 = modem_gpio.sim_detect(1)
	result.modem.sim.sim2 = modem_gpio.sim_detect(2)
	
	return result
end

local ubus_modem = {
	modem = {
		get_status = {
			function(req, msg)
				local result = modem_ubus_status(msg)
				uconn:reply(req, result)
			end, {}
		},
	}
}

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

modem_gpio.init(ucicursor)

uloop.init()

uconn = ubus.connect()
uconn:add(ubus_modem)

uloop.run()
