#!/bin/sh
# make script executable using:
#   chmod +x install-tailscale.sh
# run using:
#   ./install-tailscale.sh

# Function to read input with a timeout
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

# Fallback for hostname (in case 'hostname' cmd is missing)
get_hostname() {
    if command -v hostname >/dev/null 2>&1; then
        hostname
    else
        cat /proc/sys/kernel/hostname
    fi
}

# Show current hostname
CURRENT_HOSTNAME="$(get_hostname)"
echo "Current hostname: $CURRENT_HOSTNAME"

# Ask if user wants to change the hostname (30-second timeout)
CHANGE_HOSTNAME=$(read_with_timeout 30 "Would you like to change the hostname? (y/N): " "n")
if [ "$CHANGE_HOSTNAME" = "y" ] || [ "$CHANGE_HOSTNAME" = "Y" ]; then
    # No timeout here—let user think of a clever hostname
    read -p "Enter new hostname: " NEW_HOSTNAME
    if [ -n "$NEW_HOSTNAME" ]; then
        echo "New hostname will be: $NEW_HOSTNAME"
        read -p "Proceed and reboot? (y/N): " PROCEED
        if [ "$PROCEED" = "y" ] || [ "$PROCEED" = "Y" ]; then
            # Update hostname using UCI
            uci set system.@system[0].hostname="$NEW_HOSTNAME"
            uci commit system
            # Update runtime hostname immediately
            echo "$NEW_HOSTNAME" > /proc/sys/kernel/hostname
            sync

            echo "Rebooting now..."
            reboot
            exit 0
        fi
    fi
fi

# Ask if user wants to install Tailscale (30-second timeout)
PROCEED_INSTALL=$(read_with_timeout 30 "Install Tailscale now? (Y/n): " "y")
if [ "$PROCEED_INSTALL" = "n" ] || [ "$PROCEED_INSTALL" = "N" ]; then
    echo "Installation cancelled."
    exit 0
fi

# Check for tskey file
if [ ! -f "./tskey" ]; then
    echo "Error: tskey file not found in current directory"
    exit 1
fi

# Read the auth key
TSKEY="$(cat ./tskey)"
if [ -z "$TSKEY" ]; then
    echo "Error: tskey file is empty"
    exit 1
fi

# Update package lists and install Tailscale + firewall packages
opkg update
opkg install ca-bundle kmod-tun tailscale iptables ip6tables

# Start Tailscale and enable on boot
service tailscale start
service tailscale enable

# Authenticate Tailscale
tailscale up --authkey "$TSKEY"

# Remove the key file (no secure overwrite)
rm -f ./tskey

# Optional: Configure a firewall zone for Tailscale
echo "Configuring firewall for Tailscale..."
uci add firewall zone
uci set firewall.@zone[-1].name='tailscale'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci set firewall.@zone[-1].device='tailscale0'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='tailscale'
uci set firewall.@forwarding[-1].dest='lan'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='tailscale'

uci commit firewall
/etc/init.d/firewall restart

# (Uncomment if you want to enable IP forwarding)
# echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
# echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
# sysctl -p /etc/sysctl.conf

echo "Tailscale installation and configuration complete!"
echo "The tskey file has been deleted."
echo "Checking Tailscale status..."
echo "--------------------------"
tailscale status
echo "--------------------------"
echo "You can check connection status anytime with: tailscale status"
