#!/bin/bash
#Script by GuN®
# Change hostname of Ubuntu server after clone VM.
# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Prompt for new hostname
read -p "Enter the new hostname: " new_hostname

# Validate hostname (non-empty, no spaces, letters/numbers/hyphens only)
if [[ -z "$new_hostname" || "$new_hostname" =~ \  || ! "$new_hostname" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]*$ ]]; then
    echo "Hostname cannot be empty, contain spaces, or include invalid characters (use letters, numbers, or hyphens)"
    exit 1
fi

# Backup /etc/hosts
echo "Backing up /etc/hosts to /etc/hosts.bak"
cp /etc/hosts /etc/hosts.bak

# Get current hostname
current_hostname=$(hostname)

# Change hostname
echo "Changing hostname from $current_hostname to $new_hostname"
hostnamectl set-hostname "$new_hostname"

# Update /etc/hosts
echo "Updating /etc/hosts"
# Remove all lines containing the old hostname
sed -i "/$current_hostname/d" /etc/hosts
# Remove any 127.0.1.1 entries (common for old hostnames)
sed -i "/127.0.1.1/d" /etc/hosts
# Add new hostname to 127.0.0.1, ensuring no duplicates
if ! grep -q "127.0.0.1.*$new_hostname" /etc/hosts; then
    sed -i "/127.0.0.1.*localhost/a 127.0.0.1   $new_hostname" /etc/hosts
fi

# Verify changes
echo "New hostname set to: $new_hostname"
hostnamectl status | grep "Static hostname"
echo "Current /etc/hosts content:"
cat /etc/hosts

echo "Hostname change completed."
echo "Please reboot the system to ensure all changes take effect."
