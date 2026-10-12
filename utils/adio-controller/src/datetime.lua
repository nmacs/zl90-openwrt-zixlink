local posix = require("posix")

local M = {}
M.__index = M

M.SECONDS_PER_DAY = 24 * 3600
M.LOCALTIME_OFFSET = 0

function M.day_start_time(timestamp)
	return math.floor(timestamp / M.SECONDS_PER_DAY) * M.SECONDS_PER_DAY
end

function M.iso8601_to_unix(iso_date)
	local pattern = "(%d+)%-(%d+)%-(%d+)%a(%d+)%:(%d+)%:([%d%.]+)([%+%-])(%d?%d?)%:?(%d?%d?)"
	local year, month, day, hour, minute, seconds, offsetsign, offsethour, offsetmin = iso_date:match(pattern)

	local timestamp = os.time({year=year, month=month, day=day, hour=hour, min=minute, sec=seconds})

	local offset = tonumber(offsethour) * 3600 + tonumber(offsetmin) * 60
	if offsetsign == "-" then
		offset = -offset
	end

	return timestamp - offset, offset
end

function M.random_timeout(timeout, dispersion)
	if not dispersion then
		dispersion = timeout / 2
	end
	return timeout + math.floor(dispersion * math.random())
end

function M.monotonic_seconds()
	return posix.clock_gettime(1).tv_sec
end

function M.monotonic()
	local now = posix.clock_gettime(1)
	return now.tv_sec + now.tv_nsec / 1000000000
end

function M.realtime_seconds()
  return posix.clock_gettime(0).tv_sec
end

function M.ts_to_gmt_ts(ts)
  local res = 0
  
  res = ts - M.LOCALTIME_OFFSET
  return res
end

function M.ts_to_local_ts(ts)
  local res = 0
  
  res = ts + M.LOCALTIME_OFFSET
  return res
end

function M.local_tm_to_ts(tm)
  local res = 0
  
  res = posix.mktime(tm) - M.LOCALTIME_OFFSET
  return res
end

function M.tm_to_ts(tm)
  local res = 0
  
  res = posix.mktime(tm)
  return res
end

function M.ts_to_tm(ts)
  return posix.gmtime(ts)
end

function M.ts_to_local_tm(ts)
  return posix.gmtime(ts + M.LOCALTIME_OFFSET)
end

function M.now_gmtime()
  local time = posix.time()
  local tm = posix.gmtime(time)
  
  return tm
end

function M.now_localtime()
  local time = posix.time() + M.LOCALTIME_OFFSET
  local tm = posix.localtime(time)
  
  --for key,value in pairs(tm) do
  --  print("found member " .. key .. " " .. value);
  --end
  
  return tm
end

function M.init()
  local timet = posix.time()
  local tm = posix.gmtime(timet)
  
  local t1 = posix.mktime(tm)
  posix.setenv("TZ", "GMT")
  local t2 = posix.mktime(tm)
  
  M.LOCALTIME_OFFSET = t2 - t1
  print("Local time offset: "..M.LOCALTIME_OFFSET)
end

function M.test()
	local iso8601 = "2020-01-02T00:00:00+03:00"
	local timestamp, offset = M.iso8601_to_unix(iso8601)
	assert(timestamp == 1577912400)
	assert(offset == 10800)
	
	local iso8601 = "2020-01-02T00:00:00-03:00"
	local timestamp, offset = M.iso8601_to_unix(iso8601)
	assert(timestamp == 1577934000)
	assert(offset == -10800)
end

return M
