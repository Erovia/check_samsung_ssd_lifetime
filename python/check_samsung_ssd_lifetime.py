#!/bin/python

import argparse
from shutil import which
import os
from pathlib import Path
import subprocess

##########################################
# Colours
##########################################

RED = '\033[31m'
GREEN = '\033[32m'
BLUE = '\033[34m'
RESET = '\033[0m'

##########################################
# Sanity checks
##########################################

SUDO = ''
SMARTCTL = ''

def sanity_checks(device):
    if not check_if_drive(device):
        print(f'{RED}ERROR:{RESET} "{device}" does not seem to be a drive!')
        exit(2)
    global SUDO
    if (SUDO := check_for_sudo()) is None:
        print('{RED}ERROR:{RESET} "sudo" is either not installed or not in PATH!')
        exit(3)
    global SMARTCTL
    if (SMARTCTL := check_smartctl()) is None:
        print('{RED}ERROR:{RESET} "smartctl" is either not installed or not in PATH!')
        exit(3)

def check_if_drive(device):
    if 'nvme' in device:
        device += 'n1'
    return Path(device).is_block_device()

def check_for_sudo():
    if os.geteuid() != 0:
        return which('sudo')
    return ''

def check_smartctl():
    return which('smartctl')

##########################################
# SMART attributes
##########################################

def get_smart_attrs(device):
    attrs = {}
    exe = subprocess.run([SUDO, SMARTCTL, '-x', device], text = True, capture_output = True)
    if exe.returncode != 0:
        print(f'{RED}ERROR:{RESET}\n{exe.stdout}')
        exit(3)

    for line in exe.stdout.split('\n'):
        # SATA SSDs
        if line.startswith('Device Model'):
            attrs['device_model'] = ' '.join(line.split()[2:])
        elif line.startswith('Sector Size'):
            attrs['lba_size'] = int(line.split()[2])
        elif 'Power_On_Hours' in line:
            attrs['power_on_hours'] = int(line.split()[7])
        elif 'Wear_Leveling_Count' in line:
            attrs['wear_leveling_count'] = int(line.split()[3])
        elif 'Total_LBAs_Written' in line:
            attrs['total_lbas_written'] = int(line.split()[7])

        # NVMe SSDs
        elif line.startswith('Model Number'):
            attrs['device_model'] = ' '.join(line.split()[2:])
        elif line.startswith('Namespace 1 Formatted LBA Size'):
            attrs['lba_size'] = int(line.split()[-1])
        elif line.startswith('Power On Hours'):
            attrs['power_on_hours'] = int(line.split()[3])
        elif line.startswith('Percentage Used'):
            attrs['wear_leveling_count'] = 100 - int(line.split()[2][:-1])
        elif line.startswith('Data Units Written'):
            attrs['total_lbas_written'] = int(line.split()[3].replace(',', ''))
        elif line.startswith('Available Spare:'):
            attrs['available_spare'] = line.split()[2]

        # Common
        elif line.startswith('Serial Number'):
            attrs['serial_number'] = line.split()[2]

    if 'samsung' not in attrs.get('device_model', '').lower():
        print(f'{RED}ERROR:{RESET} This script is only compatible with Samsung SSDs!')
        exit(4)

    return attrs


##########################################
# Calculations
##########################################

def calculate_usage(smart_attrs):
    usage = {}
    usage['total_bytes_written'] = smart_attrs['total_lbas_written'] * smart_attrs['lba_size']
    usage['total_mb_written'] = usage['total_bytes_written'] / 1000
    usage['total_mib_written'] = usage['total_bytes_written'] / 1024
    usage['total_gb_written'] = usage['total_mb_written'] / 1000
    usage['total_gib_written'] = usage['total_mib_written'] / 1024
    usage['total_tb_written'] = usage['total_gb_written'] / 1000
    usage['total_tib_written'] = usage['total_gib_written'] / 1024
    usage['mean_write_rate'] = usage['total_mb_written'] / smart_attrs['power_on_hours']
    return usage


##########################################
# Output
##########################################

def health_colour(health):
    if health < 30:
        return RED
    elif health < 60:
        return BLUE
    else:
        return GREEN

def print_output(device, smart_attrs, usage):
    if available_spare := smart_attrs.get('available_spare', False):
        available_spare = f'Available spare capacity: {available_spare}\n'
    else:
        available_spare = ''

    print(f'''Device: {device}
Model: {smart_attrs['device_model']}
Serial number: {smart_attrs['serial_number']}
Power on time: {smart_attrs['power_on_hours']:,} hours
Data written:
    MB: {int(usage['total_mb_written']):,} [{int(usage['total_mib_written']):,} MiB]
    GB: {int(usage['total_gb_written']):,} [{int(usage['total_gib_written']):,} GiB]
    TB: {int(usage['total_tb_written']):,} [{int(usage['total_tib_written']):,} TiB]
Mean write rate:
    MB/hr: {int(usage['mean_write_rate']):,}
{available_spare}Estimated drive health: {health_colour(smart_attrs['wear_leveling_count'])}{smart_attrs['wear_leveling_count']}{RESET}%''')


def main():
    parser = argparse.ArgumentParser(
        description = 'This tool checks the lifetime of Samsung SSDs with "smartctl" as its only external dependency.',
        )
    parser.add_argument('device')
    args = parser.parse_args()

    sanity_checks(args.device)
    smart_attrs = get_smart_attrs(args.device)
    usage = calculate_usage(smart_attrs)
    print_output(args.device, smart_attrs, usage)

if __name__ == '__main__':
    main()

