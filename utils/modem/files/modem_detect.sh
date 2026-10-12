#!/bin/sh

# === GPIO CONFIGURATION ===
GPIO_POWER=117
GPIO_PWRKEY=116

# === SIGNAL POLARITY CONFIGURATION ===
# Set to 1 for Active High (1 = ON/Active, 0 = OFF/Inactive)
# Set to 0 for Active Low  (0 = ON/Active, 1 = OFF/Inactive)
POWER_ACTIVE_LEVEL=0
PWRKEY_ACTIVE_LEVEL=0

# === USB PORT PATHS ===
PORT1_PATH="/sys/devices/platform/usbdrd/ffb00000.usb/xhci-hcd.0.auto/usb1/1-1/1-1.4"
PORT2_PATH="/sys/devices/platform/usbdrd/ffb00000.usb/xhci-hcd.0.auto/usb1/1-1/1-1.3"

# Calculate inactive levels automatically based on active levels
POWER_INACTIVE_LEVEL=$((1 - POWER_ACTIVE_LEVEL))
PWRKEY_INACTIVE_LEVEL=$((1 - PWRKEY_ACTIVE_LEVEL))

# Initialize GPIO pins
init_gpio() {
	[ ! -d "/sys/class/gpio/gpio${GPIO_POWER}" ] && echo "$GPIO_POWER" > /sys/class/gpio/export
	[ ! -d "/sys/class/gpio/gpio${GPIO_PWRKEY}" ] && echo "$GPIO_PWRKEY" > /sys/class/gpio/export
	echo out > "/sys/class/gpio/gpio${GPIO_POWER}/direction"
	echo out > "/sys/class/gpio/gpio${GPIO_PWRKEY}/direction"
}

# Control modem power line considering polarity
set_power() {
	local state="$1" # 1 = Enable Power, 0 = Disable Power
	if [ "$state" -eq 1 ]; then
		#echo "Power > $POWER_ACTIVE_LEVEL"
		echo "$POWER_ACTIVE_LEVEL" > "/sys/class/gpio/gpio${GPIO_POWER}/value"
	else
		#echo "Power > $POWER_INACTIVE_LEVEL"
		echo "$POWER_INACTIVE_LEVEL" > "/sys/class/gpio/gpio${GPIO_POWER}/value"
	fi
}

# Control modem PWRKEY line considering polarity
set_pwrkey() {
	local state="$1" # 1 = Assert Active PWRKEY, 0 = Deassert PWRKEY
	if [ "$state" -eq 1 ]; then
		#echo "Pwrkey > $PWRKEY_ACTIVE_LEVEL"
		echo "$PWRKEY_ACTIVE_LEVEL" > "/sys/class/gpio/gpio${GPIO_PWRKEY}/value"
	else
		#echo "Pwrkey > $PWRKEY_INACTIVE_LEVEL"
		echo "$PWRKEY_INACTIVE_LEVEL" > "/sys/class/gpio/gpio${GPIO_PWRKEY}/value"
	fi
}

# Collect details of detected modem
get_modem_info() {
	local path="$1"
	local port_name="$2"
	local port_type="$3"
	local vid pid serial
	
	vid=$(cat "${path}/idVendor" 2>/dev/null || echo "unknown")
	pid=$(cat "${path}/idProduct" 2>/dev/null || echo "unknown")
	serial=$(cat "${path}/serial" 2>/dev/null || echo "none")
	
	echo "TYPE=${port_type}"
	echo "PORT=${port_name}"
	echo "SYSFS_PATH=${path}"
	echo "VID=${vid}"
	echo "PID=${pid}"
	echo "SERIAL=${serial}"
}

wait_for_port() {
	local path="$1"
	local timeout=20
	local count=0

	while [ $count -lt $timeout ]; do
			# Use -e instead of -d to correctly detect symlinks/sysfs nodes
			if [ -e "$path" ]; then
					return 0
			fi
			sleep 1
			count=$((count + 1))
	done
	return 1
}

# === MAIN DETECTION SEQUENCE ===
init_gpio

# ----------------------------------------------------
# STAGE 1: Check Port 1 (Modem powers on directly)
# ----------------------------------------------------
# Power cycle: Turn OFF power
set_power 0
set_pwrkey 0
sleep 1

# Turn ON power with PWRKEY held inactive
set_pwrkey 1
sleep 1
set_power 1

# Check if modem enumerated on Port 1
if wait_for_port "$PORT1_PATH"; then
	get_modem_info "$PORT1_PATH" "port1" "m2"
	exit 0
fi

# ----------------------------------------------------
# STAGE 2: Check Port 2 (Modem requires PWRKEY pulse)
# ----------------------------------------------------
# Prepare PWRKEY state
set_pwrkey 0

# Power cycle: Turn OFF power
set_power 0
sleep 5

# Turn ON power and pulse PWRKEY
set_power 1
sleep 1

# Pulse PWRKEY line (Active state for 1 second)
set_pwrkey 1
sleep 1
set_pwrkey 0

# Check if modem enumerated on Port 2
if wait_for_port "$PORT2_PATH"; then
	get_modem_info "$PORT2_PATH" "port2" "generic"
	exit 0
fi

# ----------------------------------------------------
# STAGE 3: No modem detected
# ----------------------------------------------------
echo "PORT=none"
echo "ERROR=Modem not found on any port"
exit 1
