#!/bin/bash

#Script by GuN®
# Colors for better readability
RED=$(printf '\033[1;31m')
GREEN=$(printf '\033[1;32m')
NOCOLOR=$(printf '\033[0m')

# Function to handle errors
handle_error() {
    printf "%sAn error occurred. Aborting.%s\n" "$RED" "$NOCOLOR"
    exit 1
}

# Function to display step information
display_step() {
    printf "\nStep %s: %s%s%s\n" "$1" "$GREEN" "$2" "$NOCOLOR"
}

# Step 1: Pre-configure packages
display_step 1 "Pre-configuring packages"
sudo dpkg --configure -a || handle_error

# Step 2: Fix and correct system with broken dependencies
display_step 2 "Fixing and correcting system dependencies"
sudo apt-get install -f -y || handle_error

# Step 3: Update apt cache
display_step 3 "Updating apt cache"
sudo apt-get update || handle_error

# Step 4: Upgrade packages
display_step 4 "Upgrading packages"
sudo apt-get upgrade -y || handle_error

# Step 5: Distribution upgrade
display_step 5 "Performing distribution upgrade"
sudo apt-get dist-upgrade -y || handle_error

# Step 6: Remove unused packages
display_step 6 "Removing unused packages"
sudo apt-get autoremove --purge -y || handle_error

# Step 7: Clean up package cache
display_step 7 "Cleaning up"
sudo apt-get autoclean || handle_error

# Step 8: Update file search database
display_step 8 "Updating database"
sudo updatedb || handle_error

# Final message
printf "\n%sMaintenance tasks completed successfully.%s\n" "$GREEN" "$NOCOLOR"
