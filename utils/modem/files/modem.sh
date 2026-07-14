#!/bin/sh /etc/rc.common

board=$(board_name)

case "$board" in
rockchip,zixlink-zl90)
	gpio_off=117
	gpio_pwrkey=116
	gpio_off_disabled=1
	gpio_off_enabled=0
	gpio_pwrkey_disabled=0
	gpio_pwrkey_enabled=1
	;;
esac

setup_gpio () {
	number=$1
	direction=$2

	path=/sys/class/gpio/gpio$number

	if [ ! -e $path ]; then
		echo $number > /sys/class/gpio/export
		echo $direction > $path/direction
	fi
}

set_gpio () {
	number=$1
	value=$2

	path=/sys/class/gpio/gpio$number

	echo $value > $path/value
}

start() {
	setup_gpio $gpio_off out
	setup_gpio $gpio_pwrkey out
	if [ -n "$gpio_rst" ]; then
		setup_gpio $gpio_rst out
		set_gpio $gpio_rst $gpio_rst_enabled
	fi

	set_gpio $gpio_off $gpio_off_enabled
	sleep 1

	/bin/sh -c "sleep 1; echo $gpio_pwrkey_disabled > /sys/class/gpio/gpio$gpio_pwrkey/value; sleep 1; echo $gpio_pwrkey_enabled > /sys/class/gpio/gpio$gpio_pwrkey/value" &
}


stop() {
	setup_gpio $gpio_off out
	set_gpio $gpio_off $gpio_off_disabled
	sleep 1
}
