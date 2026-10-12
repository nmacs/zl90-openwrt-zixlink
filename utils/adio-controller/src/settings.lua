local argparse        = require("argparse")
local ini             = require("ini")
local uciconfig       = require("uciconfig")

local settings = {}
local parser = argparse("adio-controller", "ZL90 Analog/Digital IO controller")
local conf_file = "/etc/adio-controller.conf"

parser:option("-c --config", "Configuration file path", conf_file)
parser:flag("--stdout",      "Output log messages to standard output")
parser:flag("--trace",       "Enable trace messages")

local args = parser:parse()
local ucisettings = uciconfig.settingsGetFromFile("adio-controller")

local settings = {}

settings.general = {}
settings.general.enabled          = true

settings.api = {}
settings.api.host                 = "127.0.0.1"
settings.api.port                 = 60001

settings.debug = {}
settings.debug.stdout             = false
settings.debug.trace              = false

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end


local function tobool(v)
	if (v==nil) then
		return false
	end

	if (type(v) == "boolean") then
		return v
	end

	local numeric = tonumber(v)
	if (numeric ~= nil) then
		return numeric>0
	end

	if ((type(v)=="string") and (v=="true")) then
		return true
	end

	return false
end

local function merge(to, from)
	for k, v in pairs(from) do
		--print("Merge " .. tostring(k) .. " " .. tostring(v))
		
		if type(v) == "table" then
			if type(to[k]) == "table" then
				merge(to[k], v)
			end
		else
			if to[k] ~= nil then
				local vartype = type(to[k])
				if (vartype == "string") then
					to[k] = tostring(v)
				elseif (vartype == "boolean") then
					to[k] = tobool(v)
				elseif (vartype == "number") then
					to[k] = tonumber(v)
				else
					to[k] = v
				end
			else
				to[k] = v
			end
		end
	end
end

local function print_settings(s, prefix)
	prefix = prefix or ""
	for k, v in pairs(s) do
		if type(v) == "table" then
			print(string.format("[%s]", tostring(k)))
			print_settings(v, "\t" .. prefix)
		else
			print(string.format("%s%s = '%s'", prefix, tostring(k), tostring(v)))
		end
	end
end

if (file_exists(conf_file)) then
	print("Loading configuration from:", args.config)
	local f, err = ini.load(args.config)
	if f then
		merge(settings, f)
	else
		error("Settings load error: " .. tostring(err))
	end
end

if (ucisettings) then
	print("Merge settings from UCI config file")  
	merge(settings, ucisettings)
else
	print("UCI Settings load error")
end

if args.stdout then
	settings.debug.stdout = true
end

if args.trace then
	settings.debug.trace = true
end

return settings
