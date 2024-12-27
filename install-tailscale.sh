#!/bin/sh
# make script executable using...
# chmod +x install-tailscale.sh
# run using...
# ./install-tailscale.sh

# Function to read input with timeout
read_with_timeout() {
    local timeout=$1
    local prompt=$2
    local default=$3
    local result

    read -t "$timeout" -p "$prompt" result
    if [ $? -eq 0 ]; then
        echo "${result:-$default}"
    else
        echo ""
        echo "Timeout reached, using default: $default"
        echo "${default}"
    fi
}

# Fallback for hostname
get_hostname() {
    if command -v hostname >/dev/null 2>&1; then
        hostname
    else
        cat /proc/sys/kernel/hostname
    fi
}

echo "Current hostname: $(get_hostname)"

CHANGE_HOSTNAME=$(read_with_timeout 30 "Change hostname? (y/N): " "n")
if [ "$CHANGE_HOSTNAME" = "y" ] || [ "$CHANGE_HOSTNAME" = "Y" ]; then
    read -p "Enter new hostname: " NEW_HOSTNAME
    if [ -n "$NEW_HOSTNAME" ]; then
        echo "Setting new hostname to $NEW_HOSTNAME..."
        uci set system.@system[0].hostname="$NEW_HOSTNAME"
        uci commit system
        echo "$NEW_HOSTNAME" >/proc/sys/kernel/hostname
        echo "Reboot now to apply hostname change? (y/N): "
        read REBOOT_NOW
        if [ "$REBOOT_NOW" = "y" ] || [ "$REBOOT_NOW" = "Y" ]; then
            reboot
            exit 0
        fi
    fi
fi

PROCEED_INSTALL=$(read_with_timeout 30 "Install Tailscale now? (Y/n): " "y")
if [ "$PROCEED_INSTALL" = "n" ] || [ "$PROCEED_INSTALL" = "N" ]; then
    echo "Installation cancelled."
    exit 0
fi

# Check if tskey file exists and read it
if [ ! -f ./tskey ]; then
    echo "Error: tskey file not found."
    exit 1
fi

TSKEY=$(cat ./tskey)
if [ -z "$TSKEY" ]; then
    echo "Error: tskey file is empty."
    exit 1
fi

# Basic install of Tailscale
opkg update
opkg install ca-bundle kmod-tun tailscale

# Start Tailscale and log in
service tailscale start
service tailscale enable
tailscale up --authkey "$TSKEY"

# Just remove the key file (no fancy secure delete)
rm -f ./tskey

echo "Tailscale installation complete."
echo "Key file removed."
echo "Checking Tailscale status..."
tailscale status
