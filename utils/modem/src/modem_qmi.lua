#!/usr/bin/lua

local socket = require("socket")
local nixio  = require("nixio")
local posix = require("posix")
local uci = require("uci")

local MaxNetUpDownRetries = 3
local MaxModemResetRetries = 10

local PING_SIZE = 0

local offlineTimeout = 300

local cursor = uci.cursor()

--local initialDelay = tonumber(cursor:get("modem", "general", "startdelay")) or 30
local ping = tonumber(cursor:get("modem", "general", "ping")) or 0
local pingInterval = tonumber(cursor:get("modem", "general", "pinginterval")) or 10
local pingTimeout = tonumber(cursor:get("modem", "general", "pingtimeout")) or 10
local pingPacketSize = tonumber(cursor:get("modem", "general", "pingsize")) or 0
local pingPacketsCount = tonumber(cursor:get("modem", "general", "pingcount")) or 5
local pingAddress = cursor:get("modem", "general", "pingaddr") or "8.8.8.8"
local modemIfName = cursor:get("modem", "general", "ifname") or "qmi"
local modemDevice = cursor:get("network", modemIfName, "device") or "/dev/unknown"

--print("initialDelay", initialDelay)
--print("pingInterval", pingInterval)
--print("pingAddress", pingAddress)
--print("modemIfName", modemIfName)
--print("modemDevice", modemDevice)
--print("pingTimeout", pingTimeout)

local function isDetected(dev)
	local ret = posix.stat(dev)
	return ret ~= nil
end

local function waitForDevice(dev, timeout)
	for i = 1, timeout do
		if isDetected(dev) == true then
			return true
		end

		socket.sleep(1)
	end

	return false
end

local function isOnline(pingAddr)
  local online = false
  local retry = false

  if ping <= 0 then
	return true
  end

  local cmd = string.format("ping -I wwan0 -c 1 -W %d -s %d %s 2>/dev/null", pingTimeout, pingPacketSize, pingAddr)

  for try=1,pingPacketsCount do
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
  end

  return online
end

local function ifUp(interface)
	nixio.syslog("info", "Interface up")
	os.execute("ifup " .. interface)
end

local function ifDown(interface)
	nixio.syslog("info", "Interface down")
	os.execute("ifdown " .. interface)
end

local function resetModem()
	nixio.syslog("warning", "Modem reset")
	os.execute("/lib/functions/modem.sh restart")
end

function state_reset()
	nixio.syslog("debug", "MODEM_RESET")

	os.execute("killall -q -9 uqmi")
	ifDown(modemIfName)
	os.execute("killall -q -9 uqmi")
	resetModem()
	os.execute("killall -q -9 uqmi")

	socket.sleep(5)

	if waitForDevice(modemDevice, 15) == true then
		return state_detected
	end

	return state_reset
end

function state_detected()
	nixio.syslog("debug", "MODEM_DETECTED")

	socket.sleep(20)
	ifUp(modemIfName)
	socket.sleep(10)

	return state_offline
end

function state_online()
	nixio.syslog("debug", "MODEM_ONLINE")

	while true do
		if isDetected(modemDevice) == false then
			nixio.syslog("err", "Modem disconnected")
			return state_reset
		end

		if isOnline(pingAddress) == false then
			return state_offline
		end

		offlineTimeout = 300
		socket.sleep(pingInterval * 60)
	end
end

function state_offline()
	nixio.syslog("debug", "MODEM_OFFLINE")

	local timestamp = socket.gettime()

	while true do
		if isDetected(modemDevice) == false then
			nixio.syslog("err", "Modem disconnected")
			return state_reset
		end

		if isOnline(pingAddress) == false then
			local duration = socket.gettime() - timestamp

			ifDown(modemIfName)
			socket.sleep(5)
			ifUp(modemIfName)

			nixio.syslog("debug", "offline time " .. tostring(duration))

			if duration > offlineTimeout then
				nixio.syslog("warning", "Reset modem to restore connection")

				offlineTimeout = offlineTimeout * 2
				if offlineTimeout > 10800 then
					offlineTimeout = 10800
				end

				nixio.syslog("debug", "new offline timeout: " .. tostring(offlineTimeout))

				return state_reset
			end
		else
			return state_online
		end

		socket.sleep(60)
	end
end

nixio.openlog("modem", "cons", "perror")

--nixio.syslog("debug", "Sleeping for " .. initialDelay .. "sec")
--socket.sleep(initialDelay)

local state = state_reset
while true do
	state = state()
end
