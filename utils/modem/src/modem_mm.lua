#!/usr/bin/luajit

-----------------------------------------------------------------------------------------------
local socket         = require("socket")
local nixio          = require("nixio")
local posix          = require("posix")
local uci            = require("uci")
local json           = require("cjson")

local uloop          = require("uloop")
local ubus           = require("ubus")

local modem_gpio     = require("modem_gpio")

-----------------------------------------------------------------------------------------------
-- ##### Global variables
-----------------------------------------------------------------------------------------------

local ucicursor = uci.cursor()

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

local sim_settings = {}

local modem_system_ifname = "broadband"
local modem_ifname = ucicursor:get("network", modem_system_ifname, "_modem_ifname") or "ppp0"
local modem_device = ucicursor:get("network", modem_system_ifname, "_modem_device") or "/dev/ttyUSB0"

local sim_priority = tonumber(ucicursor:get("network", modem_system_ifname, "sim_priority")) or 1
local sim_switch_timeout = tonumber(ucicursor:get("network", modem_system_ifname, "sim_switch_timeout")) or 600
local sim_switch_retries = tonumber(ucicursor:get("network", modem_system_ifname, "sim_switch_retries")) or 3

local startup_delay = tonumber(ucicursor:get("network", modem_system_ifname, "startup_delay")) or 30

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

local sim_switches_remaining = sim_switch_retries
local sim_current_id = -1
local sim_connected = false
local sim_online_ts = 0

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

local function monotonic_seconds()
	return posix.clock_gettime(1).tv_sec
end

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

local function sim_get_settings(id)
	local out = {}
	local prefix = "sim" .. tostring(id) .. "_"
	local section = modem_system_ifname
	local config = "network"
	
	out.apn = ucicursor:get(config, section, prefix .. "apn") or "internet"
	out.auth = ucicursor:get(config, section, prefix .. "auth") or "none"
	out.user = ucicursor:get(config, section, prefix .. "user") or ""
	out.password = ucicursor:get(config, section, prefix .. "password") or ""
	out.pin = ucicursor:get(config, section, prefix .. "pin") or ""
	
	out.ping_monitoring = tonumber(ucicursor:get(config, section, prefix .. "ping_monitoring")) or 1
	out.ping_interval = tonumber(ucicursor:get(config, section, prefix .. "ping_interval")) or 10
	out.ping_timeout = tonumber(ucicursor:get(config, section, prefix .. "ping_timeout")) or 10
	out.ping_packet_size = tonumber(ucicursor:get(config, section, prefix .. "ping_packet_size")) or 0
	out.ping_packets_count = tonumber(ucicursor:get(config, section, prefix .. "ping_packets_count")) or 5
	out.ping_hosts = ucicursor:get(config, section, prefix .. "ping_hosts") or "8.8.8.8"
	
	out.ping_tcp_port_monitoring = tonumber(ucicursor:get(config, section, prefix .. "ping_tcp_port_monitoring") or "0") or 0
	out.ping_tcp_port_hosts = ucicursor:get(config, section, prefix .. "ping_tcp_port_hosts") or 0
	
	return out
end

local function get_sim_settings()
	if (sim_current_id <= 0) then
		return nil
	end
	
	return sim_settings[sim_current_id]
end

local function sim_select_next()
	local detected = nil
	local _sim_current_id = sim_current_id
	
	print("Select next sim, priority: " .. sim_priority .. ". Current sim: " .. tostring(_sim_current_id))
	
	if (_sim_current_id <= 0) then
		if (sim_priority == 1) then
			_sim_current_id = 1
		elseif (sim_priority == 2) then
			_sim_current_id = 2
		else
			_sim_current_id = 1
		end
	else
		_sim_current_id = _sim_current_id + 1
		if (_sim_current_id > 2) then
			_sim_current_id = 1
		end
	end
	
	for simid=1,2 do
		detected = modem_gpio.sim_detect(_sim_current_id)
		if (detected == 1) then
			modem_gpio.sim_select(_sim_current_id)
			sim_current_id = _sim_current_id
			
			print("Next sim: " .. tostring(sim_current_id))
			return true
		else
			_sim_current_id = _sim_current_id + 1
			if (_sim_current_id > 2) then
				_sim_current_id = 1
			end
		end
	end
	
	print("Next sim not selected.")
	
	sim_current_id = -1
	return false
end

local function sim_selected_reset()
	sim_current_id = -1
	sim_switches_remaining = sim_switch_retries
end

local function sim_selected()
	return sim_current_id
end

local function sim_inserted()
	if (sim_current_id > 0) then
		return modem_gpio.sim_detect(sim_current_id) == 1
	end
	
	return false
end

local function one_sim_inserted()
	if (modem_gpio.sim_detect(1) == 1) then return true end
	if (modem_gpio.sim_detect(2) == 1) then return true end
	return false
end

local function get_sys_interface_ip(iface)
	local cmd = string.format("ip addr show %s 2>&1", iface)
	local handle = io.popen(cmd)
	local output = handle:read("*a")
	handle:close()
	
	if output:find("does not exist") then
		return false, "not_found"
	end

	local ip = output:match("inet%s+(%d+%.%d+%.%d+%.%d+)")

	if ip then
		return true, ip
	else
		return true, nil
	end
end

local function is_device_detected(dev)
	local ret = posix.stat(dev)
	return ret ~= nil
end

local function wait_for_device(dev, timeout)
	for i = 1, timeout do
		if is_device_detected(dev) == true then
			return true
		end
		socket.sleep(1)
	end
	return false
end

local function wait_for_modem_attached(dev, timeout)
	print("Wait for modem attached")
	
	local cmd = string.format("mmcli --modem %s", dev)
	for i = 1, timeout do
		local res = os.execute(cmd)
		if (res == 0) then
			print("Modem attaching ok")
			return true
		end
		socket.sleep(1)
	end
	
	print("Modem attaching failed")
	return false
end

local function modem_simple_connect(dev, timeout, args)
	local cmd = string.format("mmcli --modem %s --timeout %d --simple-connect=%s", dev, timeout, args)
	local res = os.execute(cmd)
	if (res == 0) then
		print("Modem simple connect - ok")
		return true
	end
	
	return false
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

local function check_online_ping()
	local online = false
	local retry = false
	local hosts = {}
	
	local settings = get_sim_settings()
	if not settings then
		return false
	end

	if settings.ping_monitoring <= 0 then
		return true
	end
	
	if type(settings.ping_hosts) == "table" and next(settings.ping_hosts) ~= nil then
		hosts = settings.ping_hosts
	else
		table.insert(hosts, settings.ping_hosts)
	end

	for idx, onehost in ipairs(hosts) do
		local cmd = string.format("ping -I %s -c 1 -W %d -s %d %s 2>/dev/null", modem_ifname, settings.ping_timeout, settings.ping_packet_size, onehost)
		print(cmd)
		
		for try=1,settings.ping_packets_count do
			retry = false

			local res = io.popen(cmd)
			if res then
				while true do
					local ln = res:read("*l")
					if not ln then break end
					if string.match(ln, "1 packets transmitted, 1 packets received") then
						online = true
					elseif string.match(ln, "1 packets transmitted, 0 packets received") then
						nixio.syslog("debug", "Ping packet timeout")
						retry = true
					end
				end
				res:close()
			end

			if (not retry) then
				return online
			end
			
			if (online) then
				return online
			end
		end
	end

	return online
end

local function check_online_port()
	local online = false
	local retry = false
	local hosts = {}
	
	local settings = get_sim_settings()
	if not settings then
		return false
	end

	if settings.ping_tcp_port_monitoring <= 0 then
		return true
	end
	
	if type(settings.ping_tcp_port_hosts) == "table" and next(settings.ping_tcp_port_hosts) ~= nil then
		hosts = settings.ping_tcp_port_hosts
	else
		table.insert(hosts, settings.ping_tcp_port_hosts)
	end
	
	for idx, onehost in ipairs(hosts) do
		local tcp = socket.tcp()
		tcp:settimeout(10)
		
		local host, port = onehost:match("([^:]+):(%d+)")
		if (host and port) then
			print("Try to connect to " .. tostring(host) .. ":" .. tostring(port))
			
			local success, err = tcp:connect(host, port)
			if success then
				tcp:close()
				online = true
				
				print("Connected to " .. tostring(host) .. ":" .. tostring(port))
			end
		end
		
		if (online) then
			return online
		end
	end
	
	return online
end

local function delete_modem_pdp_contexts(device)
	print("Delete current PDP context")
	local res = true
	for cid = 15, 1, -1 do -- Max cid count 15pcs
		local cmd = string.format("modemat -p %s -b 115200 -c 'AT+CGDCONT=%d' -r 'OK;ERROR'", device, cid)
		print(cmd)
		local ret = os.execute(cmd)
		if (ret ~= 0) then
			print("Command failed")
			ret = false
		end
	end
	print("PDP deleting done")
	
	print("PDP context deactivate")
	local cmd = string.format("modemat -p %s -b 115200 -c 'AT+CGATT=0' -r 'OK;ERROR' -t 12000", device)
	print(cmd)
	local ret = os.execute(cmd)
	if (ret ~= 0) then
		print("Command failed")
		ret = false
	end
	
	return res
end

local function get_modem_tty_device(sysfsDevice)
	local res = {}
	
	local f = io.popen('ls /dev/ttyUSB*')
	if (f) then
		for name in f:lines() do
			print(name)
			local cmd = string.format("modemat -p %s -b 115200 -c 'AT' -r 'OK;AT'", name)
			local ret = os.execute(cmd)
			if (ret == 0) then
				print("AT device was found: " .. name)
				return name
			end
		end
		f:close()
	end
	
	f = io.popen('ls /dev/ttyACM*')
	if (f) then
		for name in f:lines() do
			print(name)
			local cmd = string.format("modemat -p %s -b 115200 -c 'AT' -r 'OK;AT'", name)
			local ret = os.execute(cmd)
			if (ret == 0) then
				print("AT device was found: " .. name)
				return name
			end
		end
		f:close()
	end
	
	return nil
end


local function if_up(simid, interface)
	nixio.syslog("info", "Interface up")
	local cmd = ""
	
	cmd = string.format("echo '%d' > /var/run/active_sim_slot", simid)
	os.execute(cmd)
	
	cmd = string.format("ifup %s", interface)
	os.execute(cmd)
end

local function if_down(interface)
	nixio.syslog("info", "Interface down")
	local cmd = string.format("ifdown %s", simid, interface)
	print(cmd)
	os.execute(cmd)
end

local function sys_action_modem(action)
	nixio.syslog("warning", "Modem " .. action)
	os.execute("/lib/functions/modem.sh " .. action)
end

local function sys_action_modem_manager(action)
	nixio.syslog("warning", "Modem Manager " .. action)
	os.execute("/etc/init.d/modemmanager " .. action)
end

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

function state_online()
	print("State online!")
	
	local settings = get_sim_settings()
	if not settings then
		return state_reset
	end
	
	while (true) do
		if (get_modem_state(modem_device) == nil) then
			print("Modem not found, reset all")
			return state_reset
		end
		
		local ping_ok = check_online_ping()
		if (not ping_ok) then
			print("Modem offline (ICMP), reset all")
			return state_reset
		end
		
		local ports_ok = check_online_port()
		if (not ports_ok) then
			print("Modem offline (TCP ports), reset all")
			return state_reset
		end
		
		print("Modem online")
		
		if (sim_connected == false) then
			sim_connected = true
			sim_online_ts = monotonic_seconds()
			
			print("Modem connected since: " .. tostring(sim_online_ts))
		end
		
		if (monotonic_seconds() - sim_online_ts > sim_switch_timeout) then
			if (sim_priority > 0) then
				if (sim_selected() ~= sim_priority) then
					sim_selected_reset()
					return state_reset
				end
			end
		end
		
		socket.sleep(settings.ping_interval * 60)
	end
end

function state_connected()
	print("State connected!")
	
	local settings = get_sim_settings()
	if not settings then
		return state_reset
	end
	
	local start_time = monotonic_seconds()
	while (true) do
		local now_time = monotonic_seconds()
		if (now_time - start_time > 120) then
			print("Interface awaiting timeout timeout....")
			return state_reset
		end
		
		local ok, ipaddress = get_sys_interface_ip("ppp0")
		print("ppp0 interface: " .. tostring(ok) .. " " .. tostring(ipaddress))
		if (ok and ipaddress) then
			return state_online
		end
		
		socket.sleep(1)
	end
	
	print("PPPD connecting error")
	return state_reset
end

function state_detected()
	print("State detected!")
	
	local settings = get_sim_settings()
	if not settings then
		return state_reset
	end
	
	local start_time = monotonic_seconds()
	
	while (true) do
		local state = get_modem_state(modem_device)
		if (not state) then
			print("Modem get state error, reset it")
			return state_reset
		end
		
		local now_time = monotonic_seconds()
		if (now_time - start_time > 120) then
			print("Connecting timeout....")
			return state_reset
		end
		
		if (state.modem and state.modem.generic) then
			if (state.modem.generic.state == "connected") then
				return state_connected
			elseif (state.modem.generic.state == "connecting" or state.modem.generic.state == "enabling") then
				socket.sleep(1)
			elseif (state.modem.generic.state == "disabled") then
				if_up(sim_selected(), modem_system_ifname)
				socket.sleep(5)
			else
				if_up(sim_selected(), modem_system_ifname)
				socket.sleep(5)
			end
		end
		
	end
	
	if (state.modem and state.modem.generic and state.modem.generic.state == "connected") then
		return state_connected
	end
	
	return state_reset
end

function state_reset()
	local sim_changed = false
	
	print("State reset!")
	print("SIM was online: " .. tostring(sim_connected) .. ". SIM switch counter: " .. tostring(sim_switches_remaining))
	
	nixio.syslog("warning", "Modem reset")
	
	if_down(modem_system_ifname)
	sys_action_modem_manager("stop")
	sys_action_modem("stop")
	
	socket.sleep(1)

	if (not sim_connected) then
		sim_switches_remaining = sim_switches_remaining - 1
		print("modem: not connected, decrement sim switch counter: " .. tostring(sim_switches_remaining))
	else
		sim_switches_remaining = sim_switch_retries
	end
	
	if ((sim_switches_remaining == 0) or (sim_selected() <= 0) or (not sim_inserted())) then
		while (sim_select_next() == false) do
			print("SIM not found... SIM waiting...")
			socket.sleep(5)
		end
		
		sim_changed = true
		sim_switches_remaining = sim_switch_retries
	end
	
	sim_connected = false
	sim_online_ts = 0
	
	if (sim_changed) then
		print("SIM changed, delete old pdp context")
		
		sys_action_modem("start")
		socket.sleep(20)
		
		local modem_tty_dev = get_modem_tty_device()
		if (modem_tty_dev) then
			print("Modem was started. TTY dev: " .. modem_tty_dev)
			delete_modem_pdp_contexts(modem_tty_dev)
		end
		
		sys_action_modem("stop")
		socket.sleep(5)
	end
	
	sys_action_modem_manager("start")
	socket.sleep(5)
	sys_action_modem("start")

	if wait_for_device(modem_device, 15) == true then
		socket.sleep(10)
		
		local modem_detected = wait_for_modem_attached(modem_device, 60)
		if (not modem_detected) then
			return state_reset
		end
		
		return state_detected
	end

	return state_reset
end

-----------------------------------------------------------------------------------------------
-- ##### 
-----------------------------------------------------------------------------------------------

table.insert(sim_settings, sim_get_settings(1))
table.insert(sim_settings, sim_get_settings(2))

modem_gpio.init(ucicursor)

nixio.openlog("modem", "cons", "perror")

if (startup_delay > 0) then
	nixio.syslog("debug", "Sleeping for " .. startup_delay .. "sec")
	socket.sleep(startup_delay)
end

local state = state_reset
while true do
	state = state()
end
