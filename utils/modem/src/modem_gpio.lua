
local base_gpio_path = "/sys/class/gpio/"

local M = {}

M.board_gpio = {}

local function write_file(path, value)
	local f = io.open(path, "w")
	if f then
		f:write(value)
		f:close()
		return true
	end
	return false
end

function M.gpio_init(pin, direction)
	if not io.open(base_gpio_path .. "gpio" .. pin) then
		write_file(base_gpio_path .. "export", pin)
	end
	
	os.execute("usleep 100000")
	return write_file(base_gpio_path .. "gpio" .. pin .. "/direction", direction)
end

function M.gpio_write(pin, value)
	local path = base_gpio_path .. "gpio" .. pin .. "/value"
	return write_file(path, tostring(value))
end

function M.gpio_read(pin)
	local path = base_gpio_path .. "gpio" .. pin .. "/value"
	local f = io.open(path, "r")
	if f then
		local val = f:read("*all")
		f:close()
		return tonumber(val:match("%d"))
	end
	return nil
end

function M.board_gpio_init()
	for _l1, g in ipairs(M.board_gpio) do
		M.gpio_init(g.gpio, g.direction)
	end
end

function M.gpio_get(name)
	for _l1, g in ipairs(M.board_gpio) do
		if (g.name == name) then
			return M.gpio_read(g.gpio)
		end
	end
	return nil
end

function M.gpio_set(name, value)
	for _l1, g in ipairs(M.board_gpio) do
		if (g.name == name) then
			return M.gpio_write(g.gpio, tostring(value))
		end
	end
	return nil
end

function M.sim_selected_read(id)
	local value = M.gpio_get("sim_switch")
	
	if (value == 1) then
		return 1
	else
		return 2
	end
end

function M.sim_select(id)
	if (id == 1) then
		M.gpio_set("sim_switch", 1)
	elseif (id == 2) then
		M.gpio_set("sim_switch", 0)
	else
		return false
	end
	return true
end

function M.sim_detect(id)
	if (id == 1) then
		return (1 - M.gpio_get("sim1_detector"))
	elseif (id == 2) then
		return (1 - M.gpio_get("sim2_detector"))
	else
		return nil
	end
	return nil
end

function M.init(ucicursor)
	local sim_switch_gpio = tonumber(ucicursor:get("modem", "gpio", "sim_switch")) or -1
	local sim1_detector_gpio = tonumber(ucicursor:get("modem", "gpio", "sim1_detector")) or -1
	local sim2_detector_gpio = tonumber(ucicursor:get("modem", "gpio", "sim2_detector")) or -1

	if (sim_switch_gpio >= 0) then table.insert(M.board_gpio, {name="sim_switch", direction="out", gpio=tostring(sim_switch_gpio)}) end
	if (sim1_detector_gpio >= 0) then table.insert(M.board_gpio, {name="sim1_detector", direction="in", gpio=tostring(sim1_detector_gpio)}) end
	if (sim2_detector_gpio >= 0) then table.insert(M.board_gpio, {name="sim2_detector", direction="in", gpio=tostring(sim2_detector_gpio)}) end
	
	M.board_gpio_init()
end

return M
