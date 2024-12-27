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

# Print current hostname
CURRENT_HOSTNAME="$(get_hostname)"
echo "Current hostname: $CURRENT_HOSTNAME"

CHANGE_HOSTNAME=$(read_with_timeout 30 "Would you like to change the hostname? This will require a reboot. (y/n): " "n")
if [ "$CHANGE_HOSTNAME" = "y" ] || [ "$CHANGE_HOSTNAME" = "Y" ]; then
    NEW_HOSTNAME=$(read_with_timeout 30 "Enter new hostname: " "")
    if [ -n "$NEW_HOSTNAME" ]; then
        echo "The system will reboot with the new hostname: $NEW_HOSTNAME"
        PROCEED=$(read_with_timeout 30 "Proceed? (y/n): " "n")
        if [ "$PROCEED" = "y" ] || [ "$PROCEED" = "Y" ]; then
            # Update hostname using UCI
            uci set system.@system[0].hostname="$NEW_HOSTNAME"
            uci commit system

            # Update runtime hostname so prompt changes immediately
            echo "$NEW_HOSTNAME" > /proc/sys/kernel/hostname
            sync

            echo "Rebooting in 5 seconds..."
            sleep 5
            reboot
            exit 0
        fi
    fi
fi

PROCEED_INSTALL=$(read_with_timeout 30 "Proceed with Tailscale installation? (Y/n): " "y")
if [ "$PROCEED_INSTALL" = "n" ] || [ "$PROCEED_INSTALL" = "N" ]; then
    echo "Installation cancelled."
    exit 0
fi

# Check if tskey file exists
if [ ! -f "./tskey" ]; then
    echo "Error: tskey file not found in current directory"
    exit 1
fi

# Read the auth key
TSKEY=$(cat ./tskey)
if [ -z "$TSKEY" ]; then
    echo "Error: tskey file is empty"
    exit 1
fi

opkg update
opkg install ca-bundle kmod-tun tailscale

service tailscale start
service tailscale enable

tailscale up --authkey "$TSKEY"

# Securely remove the tskey file
dd if=/dev/urandom of=./tskey bs=1 count=$(stat -c %s ./tskey) conv=notrunc 2>/dev/null
rm -f ./tskey

# Configure firewall for Tailscale
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

# Optional IP forwarding for subnet routing
# echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
# echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
# sysctl -p /etc/sysctl.conf

echo "Installation and configuration complete!"
echo "The auth key file has been securely deleted."
echo "Checking Tailscale status..."
echo "--------------------------"
tailscale status
echo "--------------------------"
echo "You can check connection status anytime with: tailscale status"
