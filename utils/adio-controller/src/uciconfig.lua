local os     = require("os")
local io     = require("io")

local dbg = false

local UciConfig = {}
UciConfig.__index = UciConfig

UciConfig.DIRECTORY = "/etc/config/"

local function exec(cmd)
	local ok, output = pcall(io.popen, cmd)
	if (not ok) then
		return ""
	end
	return output:read("*all")
end

local function file_exists(file)
	local f = io.open(file, "rb")
	if f then
		f:close()
	end
	return f ~= nil
end

local function lines_from(file)
	if not file_exists(file) then
		return nil
	end
	lines = {}
	for line in io.lines(file) do 
		lines[#lines + 1] = line
	end
	return lines
end

function string.startswith(String,Start)
	return string.sub(String,1,string.len(Start))==Start
end

local function _getvaluebykey(str, key)
	str=str:gsub("%s(%S-)=","\n%1=")
	for name, value in string.gmatch(str, "(%S-)=(.-)\n") do
		if (name == key) then
			return value
		end
	end
	return ""
end

local function split(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t={}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		table.insert(t, str)
	end
	return t
end


local function keyvalue_parse(configname, lines)
	local result = {}
	local result_tmp = {}
	local config_path

	str=lines:gsub("%s(%S-)=","\n%1=")
	for name, value in string.gmatch(str, "(%S-)=(.-)\n") do
		if (string.startswith(name, configname..".")) then
			name = string.sub(name, string.len(configname)+2)
		end
		
		value = value:gsub("\"", "")
		value = value:gsub("\'", "")

		config_path = split(name, ".")
		--print("Path: " .. name .. ", value: " .. value)
		
		result_tmp = result
		for n,path in pairs(config_path) do
			--print(n .. "/" .. #config_path .. " " .. path .. " ")
			if (n == #config_path) then
				result_tmp[path] = value
			elseif ((not result_tmp[path]) or (type(result_tmp[path]) ~= "table")) then
				result_tmp[path] = {}
				result_tmp = result_tmp[path]
			else
				result_tmp = result_tmp[path]
			end
		end

		--print(name,"'"..value.."'")
		--result_tmp = value
	end

	return result
end

local function ltrim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function configlines_parse(configname, lines)
	local result = {}
	local result_tmp = {}

	for n,line in pairs(lines) do
		line = line:gsub("\"", "")
		line = line:gsub("\'", "")
		line = line:gsub("\r", "")
		line = line:gsub("\n", "")
		line = line:gsub("\t", " ")
		line = line:gsub("%s+"," ") --clear extra spaces
		line = ltrim(line)
		
		if (string.startswith(line, "config")) then
			local config_section_info = split(line, " ")
			if (#config_section_info == 3) then
				if (not result[config_section_info[3]]) then
					result[config_section_info[3]] = {}
				end
				
				--print("Create section: " .. config_section_info[3])
				result_tmp = result[config_section_info[3]]
			end
		elseif (string.startswith(line, "option")) then
			local option_section_info = split(line, " ")
			if (#option_section_info >= 3) then
				local option_name = option_section_info[2]
				local option_value = option_section_info[3]
				if (#option_section_info > 3) then
					for i = 4,#option_section_info do
						option_value = option_value .. " " .. option_section_info[i]
					end
				end
				
				--print("Add option in section: " .. option_name .. ": " .. option_value)
				result_tmp[option_name] = option_value
			end
		elseif (string.startswith(line, "list")) then
			local option_section_info = split(line, " ")
			if (#option_section_info == 3) then
				local option_name = option_section_info[2]
				local option_value = option_section_info[3]
				
				--print("Add list in section: " .. option_name .. ": " .. option_value)
				if (not result_tmp[option_name]) then
					result_tmp[option_name] = {}
				end
				
				table.insert(result_tmp[option_name], option_value)
			end
		end
	end

	return result
end

local function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

function UciConfig.settingsMerge(t1, t2)
	for k, v in pairs(t2) do
		if (type(v) == "table") and (type(t1[k] or false) == "table") then
			merge(t1[k], t2[k])
		else
			t1[k] = v
		end
	end
	return t1
end

function UciConfig.settingsGetFromFile(configname)
	local config_lines = lines_from(UciConfig.DIRECTORY .. configname)
	if (not config_lines) then
		print("Nil uci config file data")
		return nil
	end

	local config = configlines_parse(configname, config_lines)
	return config  
end

function UciConfig.settingsGet(configname)
	local config_data = exec("uci show " .. configname)
	if (string.len(config_data) == 0) then
		print("Nil uci config")
		return nil
	end

	--print("UCI config response: " .. config_data)
	local config = keyvalue_parse(configname, config_data)
	return config
end

return UciConfig
