local log = require("posix.syslog")

local settings = require("settings")

local M = {}
M.__index = M

local enable_trace  = settings.debug.trace
local stdout = settings.debug.stdout

log.openlog("collector", log.LOG_CONS)

local function output(level, fmt, ...)
	local args = {...}

	local str = os.date("!%Y-%m-%dT%TZ",t) .. ": " .. string.format(fmt, unpack(args))
	if stdout then
		print(str)
	end

	log.syslog(level, str)
end

function M.error(fmt, ...)
	output(log.LOG_ERR, fmt, ...)
-- 	if stdout then
-- 		print(debug.traceback())
-- 	end
end

function M.warning(fmt, ...)
	output(log.LOG_WARNING, fmt, ...)
-- 	if stdout then
-- 		print(debug.traceback())
-- 	end
end

function M.notice(fmt, ...)
	output(log.LOG_NOTICE, fmt, ...)
end

function M.info(fmt, ...)
	output(log.LOG_INFO, fmt, ...)
end

function M.trace(debug, fmt, ...)
	if enable_trace and debug then
		output(log.LOG_DEBUG, fmt, ...)
	end
end

return M
