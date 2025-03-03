#!/bin/bash

##########################################
# Colours
##########################################

RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
RESET="\e[0m"

##########################################
# Sanity checks
##########################################

if [[ "$#" -ne "1" ]]; then
	echo -e "${RED}ERROR:${RESET} No drive was provided!"
	echo "Usage: $0 /dev/sd[a-z]"
	exit 1
fi
DEVICE="$1"
if [[ ! -b "$DEVICE" ]]; then
	echo -e "${RED}ERROR:${RESET} '$DEVICE' does not seem to be a drive!"
	exit 2
fi
SUDO=''
if [[ "$EUID" -ne "0" ]]; then
	SUDO=$(command -v sudo 2>&1)
	if [[ -z "$SUDO" ]]; then
		echo -e "${RED}ERROR:${RESET} 'sudo' is either not installed or not in PATH!"
		exit 3
	fi
fi
SMARTCTL=$(command -v smartctl 2>&1)
if [[ -z "$SMARTCTL" ]]; then
	echo -e "${RED}ERROR:${RESET} 'smartctl' is either not installed or not in PATH!"
	exit 3
fi

##########################################
# SMART attributes
##########################################

trim_whitespaces() {
	tmp="${1#"${1%%[![:space:]]*}"}"
	echo "${tmp%"${tmp##*[![:space:]]}"}"
}

get_smart_value() {
	tmp=($1)
	echo "$(trim_whitespaces ${tmp[$2]})"
}

SMART_INFO=$($SUDO $SMARTCTL -x "$DEVICE")

while read line; do
	if [[ "$line" == "Device Model"* ]]; then
		DEVICE_MODEL="${line/"Device Model:"/}"
		DEVICE_MODEL="$(trim_whitespaces "$DEVICE_MODEL")"
	elif [[ "$line" == "Serial Number"* ]]; then
		SERIAL_NUMBER="${line/"Serial Number:"/}"
		SERIAL_NUMBER="$(trim_whitespaces "$SERIAL_NUMBER")"
	elif [[ "$line" == "Sector Size"* ]]; then
		LBA_SIZE="${line/"Sector Size:"/}"
		LBA_SIZE="${LBA_SIZE/"bytes logical/physical"/}"
		LBA_SIZE="$(trim_whitespaces "$LBA_SIZE")"
	elif [[ "$line" == *"Power_On_Hours"* ]]; then
		POWER_ON_HOURS="$(get_smart_value "$line" 7)"
	elif [[ "$line" == *"Wear_Leveling_Count"* ]]; then
		WEAR_LEVELING_COUNT="$(get_smart_value "$line" 3)"
	elif [[ "$line" == *"Total_LBAs_Written"* ]]; then
		TOTAL_LBAS_WRITTEN="$(get_smart_value "$line" 7)"
	fi
done <<< $SMART_INFO

if [[ "${DEVICE_MODEL,,}" != *"samsung"* ]]; then
	echo -e "${RED}ERROR:${RESET} This script is only compatible with Samsung SSDs!"
	exit 4
fi

##########################################
# Calculations
##########################################

TOTAL_BYTES_WRITTEN=$(( $TOTAL_LBAS_WRITTEN * $LBA_SIZE ))
TOTAL_MB_WRITTEN=$(( $TOTAL_BYTES_WRITTEN / 1024 ))
TOTAL_GB_WRITTEN=$(( $TOTAL_MB_WRITTEN / 1024 ))
TOTAL_TB_WRITTEN=$(( $TOTAL_GB_WRITTEN / 1024 ))
MEAN_WRITE_RATE=$(( $TOTAL_MB_WRITTEN / $POWER_ON_HOURS ))

# Convert the value to Base10 in order to trim the leading 0
HEALTH_PERCENTAGE=$(( 10#$WEAR_LEVELING_COUNT ))
if [[ "$HEALTH_PERCENTAGE" -lt "30" ]]; then
	HEALTH_COLOUR=$RED
elif [[ "$HEALTH_PERCENTAGE" -lt "60" ]]; then
	HEALTH_COLOUR=$BLUE
else
	HEALTH_COLOUR=$GREEN
fi

##########################################
# Output
##########################################

echo "Device: $DEVICE"
echo "Model: $DEVICE_MODEL"
echo "Serial number: $SERIAL_NUMBER"
printf "Power on time: %'d hours\n" "$POWER_ON_HOURS"
echo "Data written:"
printf "    MB: %'d\n" "$TOTAL_MB_WRITTEN"
printf "    GB: %'d\n" "$TOTAL_GB_WRITTEN"
printf "    TB: %'d\n" "$TOTAL_TB_WRITTEN"
echo "Mean write rate:"
printf "    MB/hr: %'d\n" "$MEAN_WRITE_RATE"
echo -e "Estimated drive health: ${HEALTH_COLOUR}${HEALTH_PERCENTAGE}${RESET}%"
