#!/bin/bash
# Script by GuN®
# Change MachineID of Ubuntu server after clone VM.

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Check if /etc/machine-id exists
if [[ ! -f /etc/machine-id ]]; then
    echo "Error: /etc/machine-id not found"
    exit 1
fi

# Backup existing machine ID files
echo "Backing up existing machine ID files"
[[ -f /etc/machine-id ]] && cp /etc/machine-id /etc/machine-id.bak
[[ -f /var/lib/dbus/machine-id ]] && cp /var/lib/dbus/machine-id /var/lib/dbus/machine-id.bak

# Generate new machine ID
echo "Generating new machine ID"
new_machine_id=$(cat /proc/sys/kernel/random/uuid | tr -d '-')

# Update /etc/machine-id
echo "Updating /etc/machine-id"
echo "$new_machine_id" > /etc/machine-id

# Update or create /var/lib/dbus/machine-id
echo "Updating /var/lib/dbus/machine-id"
mkdir -p /var/lib/dbus
echo "$new_machine_id" > /var/lib/dbus/machine-id

# Verify changes
echo "New machine ID set to: $new_machine_id"
echo "Verifying files..."
cat /etc/machine-id
cat /var/lib/dbus/machine-id

echo "Machine ID change completed."
echo "Please reboot the system to ensure all changes take effect."
