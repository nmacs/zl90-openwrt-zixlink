local copas    = require("copas")
local posix    = require("posix")
local settings = require("settings")
local log      = require("log")
local uci      = require("uci")

-------------------------------------------------------------------------------
-- Module data
-------------------------------------------------------------------------------
local dbg = true

local M = {}
M.__index = M

M.app_name = "adio-controller"

M.DEV_ADC_INT = 0
M.DEV_ADC = 1
M.DEV_DAC = 2

M.ADC_CURRENT_4_20mA_100R_ID = "4-20ma_100r"
M.ADC_VOLTAGE_TEMP_10000R_ID = "temp_10000r"
M.ADC_VOLTAGE_0_10V_ID = "0-10v"
M.ADC_VOLTAGE_0_50V_ID = "0-50v"

M.DAC_VOLTAGE_0_5V_ID = "0-5v"
M.DAC_VOLTAGE_0_10V_ID = "0-10v"

M.GPIO_EXPANDER_OFFSET = 512
M.GPIO_EXPANDER_K2_1M = M.GPIO_EXPANDER_OFFSET + 0
M.GPIO_EXPANDER_K2_150K = M.GPIO_EXPANDER_OFFSET + 1
M.GPIO_EXPANDER_K2_10K = M.GPIO_EXPANDER_OFFSET + 2
M.GPIO_EXPANDER_K2_100R = M.GPIO_EXPANDER_OFFSET + 3

M.GPIO_EXPANDER_K1_1M = M.GPIO_EXPANDER_OFFSET + 4
M.GPIO_EXPANDER_K1_150K = M.GPIO_EXPANDER_OFFSET + 5
M.GPIO_EXPANDER_K1_10K = M.GPIO_EXPANDER_OFFSET + 6
M.GPIO_EXPANDER_K1_100R = M.GPIO_EXPANDER_OFFSET + 7

M.GPIO_EXPANDER_RL1 =  M.GPIO_EXPANDER_OFFSET + 8
M.GPIO_EXPANDER_RL2 =  M.GPIO_EXPANDER_OFFSET + 9

M.GPIO_EXPANDER_DAC_10V =  M.GPIO_EXPANDER_OFFSET + 10

local function internal_gpio_num(port, letter, gpio)
	local letter_offset = string.byte(letter:upper()) - string.byte("A")
	return port * 32 + (letter_offset * 8) + gpio
end

M.GPIO_DIGITAL_OUT1 = internal_gpio_num(2, 'A', 2)
M.GPIO_DIGITAL_OUT2 = internal_gpio_num(2, 'A', 5)
M.GPIO_DIGITAL_IN1 = internal_gpio_num(2, 'A', 4)
M.GPIO_DIGITAL_IN2 = internal_gpio_num(2, 'A', 3)

local gpio = {}
local adc = {}
local dac = {}
local cfg = {}

M.UCI_OPTION_MAP = {
	["name"] = {
		uci_option = "name"
	},
	
	["value"] = {
		uci_option = "value"
	},
	
	["mode"] = {
		uci_option = "mode",
		on_change = function(id, new_val)
			log.info("DIO %s mode changed to %s", tostring(id), tostring(new_val))
             
			if id == "dio1" then
				if (new_val == "input") then
					gpio.write(M.GPIO_DIGITAL_OUT1, 1) --logic inverted
				end
			elseif id == "dio2" then
				if (new_val == "input") then
					gpio.write(M.GPIO_DIGITAL_OUT2, 1) --logic inverted
				end
			end
		end
	},
	
	["scale.selected"] = {
		uci_option = "scale",
		on_change = function(id, new_val)
			log.info("ADC/DAC %s scale changed to %s", tostring(id), tostring(new_val))

			if id == "adc1" then
				gpio.write(M.GPIO_EXPANDER_K1_1M, 0)
				gpio.write(M.GPIO_EXPANDER_K1_150K, 0)
				gpio.write(M.GPIO_EXPANDER_K1_10K, 0)
				gpio.write(M.GPIO_EXPANDER_K1_100R, 0)
                       
				if new_val == M.ADC_CURRENT_4_20mA_100R_ID then
					gpio.write(M.GPIO_EXPANDER_K1_100R, 1)
				elseif new_val == M.ADC_VOLTAGE_0_10V_ID then
					gpio.write(M.GPIO_EXPANDER_K1_1M, 1)
				elseif new_val == M.ADC_VOLTAGE_0_50V_ID then
					gpio.write(M.GPIO_EXPANDER_K1_150K, 1)
				elseif new_val == M.ADC_VOLTAGE_TEMP_10000R_ID then
					gpio.write(M.GPIO_EXPANDER_K1_10K, 1)
				end
			elseif id == "adc2" then
				gpio.write(M.GPIO_EXPANDER_K2_1M, 0)
				gpio.write(M.GPIO_EXPANDER_K2_150K, 0)
				gpio.write(M.GPIO_EXPANDER_K2_10K, 0)
				gpio.write(M.GPIO_EXPANDER_K2_100R, 0)
                       
				if new_val == M.ADC_CURRENT_4_20mA_100R_ID then
					gpio.write(M.GPIO_EXPANDER_K2_100R, 1)
				elseif new_val == M.ADC_VOLTAGE_0_10V_ID then
					gpio.write(M.GPIO_EXPANDER_K2_1M, 1)
				elseif new_val == M.ADC_VOLTAGE_0_50V_ID then
					gpio.write(M.GPIO_EXPANDER_K2_150K, 1)
				elseif new_val == M.ADC_VOLTAGE_TEMP_10000R_ID then
					gpio.write(M.GPIO_EXPANDER_K2_10K, 1)
				end
			elseif id == "dac1" then
				if new_val == M.DAC_VOLTAGE_0_5V_ID then
					gpio.write(M.GPIO_EXPANDER_DAC_10V, 1)
				elseif new_val == M.DAC_VOLTAGE_0_10V_ID then
					gpio.write(M.GPIO_EXPANDER_DAC_10V, 0)
				end
			end
		end
	}
}

-------------------------------------------------------------------------------
-- Generic functions
-------------------------------------------------------------------------------

local BALANCE_RESISTOR = 10000.0
local ROOM_RESISTANCE  = 100000.0
local ROOM_TEMP_KELVIN = 298.15   -- 25°C in Kelvin (273.15 + 25)
local BETA_COEFFICIENT = 3950.0   -- B

local function input_divider_voltage(u_out, r1, r2)
	if not u_out or not r1 or not r2 then
		return nil, "Missing arguments"
	end
	
	if r2 == 0 then
		return nil, "R2 cannot be zero (division by zero)"
	end

	local u_in = u_out * (r1 + r2) / r2
	return u_in
end

local function getTemperatureFromVoltage(vMeas, vTotal)
	if vMeas <= 0 then vMeas = 0.001 end
	if vMeas >= vTotal then vMeas = vTotal - 0.001 end

	local rNtc = BALANCE_RESISTOR * ((vTotal / vMeas) - 1.0)
	
	local tempKelvin = 1.0 / ((1.0 / ROOM_TEMP_KELVIN) + (1.0 / BETA_COEFFICIENT) * math.log(rNtc / ROOM_RESISTANCE))
	return tempKelvin - 273.15, rNtc
end

local function adc_read_value(id, channel)
	local chcfg = cfg["adc"][id]
	local voltage = adc.read_voltage(M.DEV_ADC, channel)
	local value = 0
	
	if (chcfg.scale.selected == M.ADC_CURRENT_4_20mA_100R_ID) then
		value = voltage / 100.0
	elseif (chcfg.scale.selected == M.ADC_VOLTAGE_0_10V_ID) then
		value = input_divider_voltage(voltage, 3300000, 1000000)
	elseif (chcfg.scale.selected == M.ADC_VOLTAGE_0_50V_ID) then
		value = input_divider_voltage(voltage, 3300000, 150000)
	elseif (chcfg.scale.selected == M.ADC_VOLTAGE_TEMP_10000R_ID) then
		value = input_divider_voltage(voltage, 100000, 10000)
		value = getTemperatureFromVoltage(value, 12.0)
	end
	
	return value
end

local VALUE_READERS = {
	power_supply = {
		system_power = function() return input_divider_voltage(adc.read_voltage(M.DEV_ADC_INT, 1), 30000, 1000) end,
		aux_power    = function() return input_divider_voltage(adc.read_voltage(M.DEV_ADC, 0), 1000000, 100000) end,
	},
	
	adc = {
		adc1 = function()
						return adc_read_value("adc1", 2)
					end,
		adc2 = function() 
						return adc_read_value("adc2", 3)
					end,
	},
	
	dac = {
		dac1 = function() return dac.read_raw(M.DEV_DAC, 0) end,
	},
	
	relay = {
		relay1 = function() return gpio.read(M.GPIO_EXPANDER_RL1) end,
		relay2 = function() return gpio.read(M.GPIO_EXPANDER_RL2) end,
	},
	
	dio = {
		dio1 = function()
						if (cfg.dio.dio1.mode == "output") then
							return gpio.read(M.GPIO_DIGITAL_OUT1)
						else
							return gpio.read(M.GPIO_DIGITAL_IN1)
						end
					end,
		dio2 = function()
						if (cfg.dio.dio2.mode == "output") then
							return gpio.read(M.GPIO_DIGITAL_OUT2)
						else
							return gpio.read(M.GPIO_DIGITAL_IN2)
						end
					end,
	}
}

local VALUE_WRITERS = {
	relay = {
		relay1 = function(val) gpio.write(M.GPIO_EXPANDER_RL1, val) end,
		relay2 = function(val) gpio.write(M.GPIO_EXPANDER_RL2, val) end,
	},

	dac = {
	 	dac1 = function(val) dac.write_raw(M.DEV_DAC, 0, val) end,
	},

	dio = {
		dio1 = function(val)
						if (cfg.dio.dio1.mode == "output") then
							gpio.write(M.GPIO_DIGITAL_OUT1, val)
						end
					end,
		dio2 = function(val)
						if (cfg.dio.dio2.mode == "output") then
							gpio.write(M.GPIO_DIGITAL_OUT2, val)
						end
					end,
	}
}

-------------------------------------------------------------------------------
-- Generic functions
-------------------------------------------------------------------------------

function tablecopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[tablecopy(orig_key)] = tablecopy(orig_value)
		end
		setmetatable(copy, tablecopy(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

local function get_nested_val(tbl, path)
	local current = tbl
	for key in string.gmatch(path, "[^.]+") do
		if type(current) ~= "table" then return nil end
		current = current[key]
	end
	return current
end

local function set_nested_val(tbl, path, val)
	local keys = {}
	for key in string.gmatch(path, "[^.]+") do
		table.insert(keys, key)
	end

	local current = tbl
	for i = 1, #keys - 1 do
		local k = keys[i]
		if type(current[k]) ~= "table" then
			current[k] = {}
		end
		current = current[k]
	end
	current[keys[#keys]] = val
end

local function write_file(path, value)
	local f = io.open(path, "w")
	if not f then return false, "Failed to open " .. path end
	f:write(tostring(value))
	f:close()
	return true
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then return nil, "Failed to open " .. path end
	local val = f:read("*all")
	f:close()
	return val:gsub("%s+", "")
end

local function read_file_number(path)
	local text = read_file(path)
	--print(path .. ": " .. tostring(text))
	return tonumber(text)
end

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-------------------------------------------------------------------------------
-- GPIO functions
-------------------------------------------------------------------------------

function gpio.export(pin)
	local path = string.format("/sys/class/gpio/gpio%d", pin)
	if file_exists(path) then
		return true
	end
	return write_file("/sys/class/gpio/export", pin)
end

function gpio.set_direction(pin, direction)
	local path = string.format("/sys/class/gpio/gpio%d/direction", pin)
	return write_file(path, direction)
end

function gpio.set_active_low(pin, value)
	local path = string.format("/sys/class/gpio/gpio%d/active_low", pin)
	return write_file(path, value)
end

function gpio.write(pin, value)
	local path = string.format("/sys/class/gpio/gpio%d/value", pin)
	return write_file(path, value)
end

function gpio.read(pin)
	local path = string.format("/sys/class/gpio/gpio%d/value", pin)
	return read_file_number(path)
end

function gpio.unexport(pin)
	return write_file("/sys/class/gpio/unexport", pin)
end

function gpio.gpio_init(num, dir, value, invert)
	local success, err = gpio.export(num)
	if not success then return false, err end

	if dir then
		success, err = gpio.set_direction(num, dir)
		if not success then return false, err end
	end

	if (invert) then
		success, err = gpio.set_active_low(num, "1")
		if not success then return false, err end
	end
	
	if value and dir == "out" then
		success, err = gpio.write(num, value)
		if not success then return false, err end
	end

	return true
end

-------------------------------------------------------------------------------
-- ADC functions
-------------------------------------------------------------------------------

function adc.read_raw(device_num, channel)
	local path = string.format("/sys/bus/iio/devices/iio:device%d/in_voltage%d_raw", device_num, channel)
	return read_file_number(path)
end

function adc.get_scale(device_num, channel)
	local path = string.format("/sys/bus/iio/devices/iio:device%d/in_voltage%d_scale", device_num, channel)
	local scale = read_file_number(path)
	if not scale then
			path = string.format("/sys/bus/iio/devices/iio:device%d/in_voltage_scale", device_num)
			scale = read_file_number(path)
	end
	return scale or 1.0
end

function adc.read_voltage(device_num, channel)
	local raw = adc.read_raw(device_num, channel)
	local scale = adc.get_scale(device_num, channel)
	if not raw then return nil, "Failed to read ADC raw value" end
	return (raw * scale) / 1000
end

-------------------------------------------------------------------------------
-- DAC functions
-------------------------------------------------------------------------------

local function write_file(path, value)
	local f = io.open(path, "w")
	if not f then return false, "Failed to open " .. path end
	f:write(tostring(value))
	f:close()
	return true
end

function dac.write_raw(device_num, channel, value)
	local path = string.format("/sys/bus/iio/devices/iio:device%d/out_voltage%d_raw", device_num, channel)
	return write_file(path, value)
end

function dac.read_raw(device_num, channel, value)
	local path = string.format("/sys/bus/iio/devices/iio:device%d/out_voltage%d_raw", device_num, channel)
	return read_file_number(path, value)
end

-------------------------------------------------------------------------------
-- Module functions
-------------------------------------------------------------------------------
		
local function apply_configuration_hooks()
	for section_name, units in pairs(cfg) do
		for id, target_unit in pairs(units) do
			for field_path, map_info in pairs(M.UCI_OPTION_MAP) do
				if type(map_info) == "table" and type(map_info.on_change) == "function" then
					local current_val = get_nested_val(target_unit, field_path)
					if current_val ~= nil then
						local ok, err = pcall(map_info.on_change, id, current_val, target_unit)
						if not ok then
							log.error("Init hook error for %s.%s: %s", tostring(id), tostring(field_path), tostring(err))
						end
					end
				end
			end
		end
	end
end

local function apply_initial_values()
	for section_name, devices in pairs(VALUE_WRITERS) do
		local cfg_section = cfg[section_name]
		if cfg_section then
			for id, writer in pairs(devices) do
				local unit = cfg_section[id]
				if unit and unit.value ~= nil then
					local ok, err = pcall(writer, unit.value)
					if not ok then
						log.error("Init writer error for %s: %s", tostring(id), tostring(err))
					end
				end
			end
		end
	end
end

local function cfg_init()
	cfg = {
		power_supply = {},
		adc = {},
		dac = {},
		relay = {},
		dio = {}
	}

	local function add_unit(section, id, default_name, extra)
		local unit = {
			id = id,
			name = uci.get(M.app_name, id, "name") or default_name
		}
		if extra then
			for k, v in pairs(extra) do unit[k] = v end
		end
		cfg[section][id] = unit
	end

	add_unit("power_supply", "system_power", "System Power")
	add_unit("power_supply", "aux_power", "AUX Power")

	add_unit("adc", "adc1", "ADC 1", {
		bits = 15,
		scale = {
			selected = uci.get(M.app_name, "adc1", "scale") or M.ADC_VOLTAGE_0_50V_ID,
			available = {
				{id = M.ADC_CURRENT_4_20mA_100R_ID, type = "current_4_20", shut = 100.0, min = 0.0, max = 0.020},
				{id = M.ADC_VOLTAGE_TEMP_10000R_ID, type = "temperature", resistor = 10000.0, min = -1000.0, max = 1000.0},
				{id = M.ADC_VOLTAGE_0_10V_ID, type = "voltage", min = 0, max = 10},
				{id = M.ADC_VOLTAGE_0_50V_ID, type = "voltage", min = 0, max = 50}
			}
		}
	})

	add_unit("adc", "adc2", "ADC 2", {
		bits = 15,
		scale = {
			selected = uci.get(M.app_name, "adc2", "scale") or M.ADC_VOLTAGE_0_50V_ID,
			available = {
				{id = M.ADC_CURRENT_4_20mA_100R_ID, type = "current_4_20", shut = 100.0, min = 0.0, max = 0.020},
				{id = M.ADC_VOLTAGE_TEMP_10000R_ID, type = "temperature", resistor = 10000.0, min = -1000.0, max = 1000.0},
				{id = M.ADC_VOLTAGE_0_10V_ID, type = "voltage", min = 0, max = 10},
				{id = M.ADC_VOLTAGE_0_50V_ID, type = "voltage", min = 0, max = 50}
			}
		}
	})

	add_unit("dac", "dac1", "DAC 1", {
		bits = 12,
		scale = {
			selected = uci.get(M.app_name, "dac1", "scale") or M.DAC_VOLTAGE_0_5V_ID,
			available = {
				{id = M.DAC_VOLTAGE_0_5V_ID, type = "voltage", min = 0, max = 5.0},
				{id = M.DAC_VOLTAGE_0_10V_ID, type = "voltage", min = 0, max = 10.0}
			}
		},
		value = uci.get(M.app_name, "dac1", "value") or 0,
	})

	add_unit("relay", "relay1", "RELAY 1", {
		type = "NO",
		value = uci.get(M.app_name, "relay1", "value") or 0,
	})
	add_unit("relay", "relay2", "RELAY 2", {
		type = "NO",
		value = uci.get(M.app_name, "relay2", "value") or 0,
	})

	add_unit("dio", "dio1", "IO 1", {
		mode = uci.get(M.app_name, "dio1", "mode") or "input",
		value = uci.get(M.app_name, "dio1", "value") or 0,
	})
	add_unit("dio", "dio2", "IO 2", {
		mode = uci.get(M.app_name, "dio2", "mode") or "input",
		value = uci.get(M.app_name, "dio2", "value") or 0,
	})

	return cfg
end
		
local function gpio_init()
	gpio.gpio_init(M.GPIO_EXPANDER_K2_1M, "out", 0)
	gpio.gpio_init(M.GPIO_EXPANDER_K2_150K, "out", 0)
	gpio.gpio_init(M.GPIO_EXPANDER_K2_10K, "out", 0)
	gpio.gpio_init(M.GPIO_EXPANDER_K2_100R, "out", 0)
	
	gpio.gpio_init(M.GPIO_EXPANDER_K1_1M, "out", 0)
	gpio.gpio_init(M.GPIO_EXPANDER_K1_150K, "out", 0)
	gpio.gpio_init(M.GPIO_EXPANDER_K1_10K, "out", 0)
	gpio.gpio_init(M.GPIO_EXPANDER_K1_100R, "out", 0)
	
	gpio.gpio_init(M.GPIO_EXPANDER_RL1, "out", 0)
	gpio.gpio_init(M.GPIO_EXPANDER_RL2, "out", 0)
	
	gpio.gpio_init(M.GPIO_EXPANDER_DAC_10V, "out", 0)
	
	gpio.gpio_init(M.GPIO_DIGITAL_OUT1, "out", 0, true)
	gpio.gpio_init(M.GPIO_DIGITAL_IN1, "in", 0, true)
	
	gpio.gpio_init(M.GPIO_DIGITAL_OUT2, "out", 0, true)
	gpio.gpio_init(M.GPIO_DIGITAL_IN2, "in", 0, true)
end

function M.get_configuration()
	local outcfg = tablecopy(cfg)
	
	return outcfg
end

function M.set_configuration(new_cfg)
	if type(new_cfg) ~= "table" then
		return false, "Invalid configuration argument"
	end

	local uci_changed = false

	for section_name, units in pairs(new_cfg) do
		if cfg[section_name] then
			for id, unit_data in pairs(units) do
				local target = cfg[section_name][id]
				
				if target and type(unit_data) == "table" then
					for field_path, map_info in pairs(M.UCI_OPTION_MAP) do
						local new_val = get_nested_val(unit_data, field_path)
						
						if new_val ~= nil then
							local uci_option = type(map_info) == "table" and map_info.uci_option or map_info
							local on_change  = type(map_info) == "table" and map_info.on_change or nil

							local current_uci_val = uci.get(M.app_name, id, uci_option)
							local new_str_val = tostring(new_val)

							if current_uci_val ~= new_str_val then
								set_nested_val(target, field_path, new_val)
								uci.set(M.app_name, id, uci_option, new_str_val)
								uci_changed = true

								if type(on_change) == "function" then
									local ok, err = pcall(on_change, id, new_val, target)
									if not ok then
										log.error("Hook error for %s.%s: %s", tosrting(id), tosrting(field_path), tostring(err))
									end
								end
							end
						end
					end
				end
			end
		end
	end

	if uci_changed then
		uci.save(M.app_name)
		uci.commit(M.app_name)
	end

	return true
end

function M.get_values()
	local data = {}

	for section_name, devices in pairs(VALUE_READERS) do
		data[section_name] = {}
		for id, getter in pairs(devices) do
			data[section_name][id] = {
				value = getter()
			}
		end
	end

	return data
end

function M.set_values(data)
	if type(data) ~= "table" then
		return false, "Invalid argument: expected table"
	end

	local uci_changed = false

	for section_name, devices in pairs(data) do
		local section_writers = VALUE_WRITERS[section_name]
		
		if section_writers and type(devices) == "table" then
			for id, unit_data in pairs(devices) do
				local writer = section_writers[id]
				
				if writer and type(unit_data) == "table" and unit_data.value ~= nil then
					local new_val = unit_data.value

					local ok, err = pcall(writer, new_val)
					if not ok then
						log.error("Failed to write value for %s: %s", tostring(id), tostring(err))
					else
						if cfg[section_name] and cfg[section_name][id] then
							cfg[section_name][id].value = new_val
						end

						uci.set(M.app_name, id, "value", tostring(new_val))
						uci_changed = true
					end
				end
			end
		end
	end

	if uci_changed then
		uci.save(M.app_name)
		uci.commit(M.app_name)
	end

	return true
end

function M.init()
	cfg_init()
	gpio_init()
	
	apply_configuration_hooks()
	apply_initial_values()
	
	copas.addthread(function()
		while true do
			copas.sleep(30)
			collectgarbage("step", 1000)
			log.trace(dbg, "Memory used: %.1f KiB", collectgarbage("count"))
		end
	end)
end

return M
