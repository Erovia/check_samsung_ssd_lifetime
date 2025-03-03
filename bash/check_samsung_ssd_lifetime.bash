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
if [[ "$DEVICE" == "/dev/nvme"* ]]; then
	if [[ ! -b "${DEVICE}n1" ]]; then
		echo -e "${RED}ERROR:${RESET} '$DEVICE' does not seem to be a drive!"
		exit 2
	fi
elif [[ ! -b "$DEVICE" ]]; then
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
	# SATA SSDs
	if [[ "$line" == "Device Model"* ]]; then
		DEVICE_MODEL="${line/"Device Model:"/}"
		DEVICE_MODEL="$(trim_whitespaces "$DEVICE_MODEL")"
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

	# NVMe SSDs
	elif [[ "$line" == "Model Number"* ]]; then
		DEVICE_MODEL="${line/"Model Number:"/}"
		DEVICE_MODEL="$(trim_whitespaces "$DEVICE_MODEL")"
	elif [[ "$line" == "Namespace 1 Formatted LBA Size"* ]]; then
		LBA_SIZE="${line/"Namespace 1 Formatted LBA Size:"/}"
		LBA_SIZE="$(trim_whitespaces "$LBA_SIZE")"
	elif [[ "$line" == "Power On Hours"* ]]; then
		POWER_ON_HOURS="${line/"Power On Hours:"/}"
		POWER_ON_HOURS="$(trim_whitespaces "$POWER_ON_HOURS")"
	elif [[ "$line" == "Percentage Used"* ]]; then
		WEAR_LEVELING_COUNT="${line/"Percentage Used:"/}"
		WEAR_LEVELING_COUNT="${WEAR_LEVELING_COUNT%\%}"    # Remove % sign from the end
		WEAR_LEVELING_COUNT="$(trim_whitespaces "$WEAR_LEVELING_COUNT")"
		WEAR_LEVELING_COUNT=$(( 100 - WEAR_LEVELING_COUNT ))    # NVMe drives provide the used percentage
	elif [[ "$line" == "Data Units Written"* ]]; then
		TOTAL_LBAS_WRITTEN="${line/"Data Units Written:"/}"
		TOTAL_LBAS_WRITTEN="${TOTAL_LBAS_WRITTEN%[*}"    # Remove the trailing TB conversion
		TOTAL_LBAS_WRITTEN="${TOTAL_LBAS_WRITTEN//,}"    # Remove the , delimiters
		TOTAL_LBAS_WRITTEN="$(trim_whitespaces "$TOTAL_LBAS_WRITTEN")"
	elif [[ "$line" == "Available Spare:"* ]]; then    # The ':' is necessary to avoid matching other spare-related entries
		AVAILABLE_SPARE="${line/"Available Spare:"/}"
		AVAILABLE_SPARE="$(trim_whitespaces "$AVAILABLE_SPARE")"

	# Common
	elif [[ "$line" == "Serial Number"* ]]; then
		SERIAL_NUMBER="${line/"Serial Number:"/}"
		SERIAL_NUMBER="$(trim_whitespaces "$SERIAL_NUMBER")"
	fi
done <<< $SMART_INFO

if [[ "${DEVICE_MODEL,,}" != *"samsung"* ]]; then
	echo -e "${RED}ERROR:${RESET} This script is only compatible with Samsung SSDs!"
	exit 4
fi

##########################################
# Calculations
##########################################

TOTAL_BYTES_WRITTEN=$(( TOTAL_LBAS_WRITTEN * LBA_SIZE ))
TOTAL_MB_WRITTEN=$(( TOTAL_BYTES_WRITTEN / 1000 ))
TOTAL_MIB_WRITTEN=$(( TOTAL_BYTES_WRITTEN / 1024 ))
TOTAL_GB_WRITTEN=$(( TOTAL_MB_WRITTEN / 1000 ))
TOTAL_GIB_WRITTEN=$(( TOTAL_MIB_WRITTEN / 1024 ))
TOTAL_TB_WRITTEN=$(( TOTAL_GB_WRITTEN / 1000 ))
TOTAL_TIB_WRITTEN=$(( TOTAL_GIB_WRITTEN / 1024 ))
MEAN_WRITE_RATE=$(( TOTAL_MB_WRITTEN / POWER_ON_HOURS ))

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
printf "    MB: %'d [%'d MiB]\n" "$TOTAL_MB_WRITTEN" "$TOTAL_MIB_WRITTEN"
printf "    GB: %'d [%'d GiB]\n" "$TOTAL_GB_WRITTEN" "$TOTAL_GIB_WRITTEN"
printf "    TB: %'d [%'d TiB]\n" "$TOTAL_TB_WRITTEN" "$TOTAL_TIB_WRITTEN"
echo "Mean write rate:"
printf "    MB/hr: %'d\n" "$MEAN_WRITE_RATE"
[[ -n "$AVAILABLE_SPARE" ]] && echo "Available spare capacity: $AVAILABLE_SPARE"
echo -e "Estimated drive health: ${HEALTH_COLOUR}${HEALTH_PERCENTAGE}${RESET}%"
