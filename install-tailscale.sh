#!/bin/sh
# Remember to make the script executable using...
# chmod +x install-tailscale.sh
# Run it using...
# ./install-tailscale.sh

# Function to read input with timeout
read_with_timeout() {
    local timeout=$1
    local prompt=$2
    local default=$3
    local result

    # Start reading in background
    read -t "$timeout" -p "$prompt" result
    
    if [ $? -eq 0 ]; then
        echo "${result:-$default}"
    else
        echo ""
        echo "Timeout reached, using default: $default"
        echo "${default}"
    fi
}

# Hostname Management
echo "Current hostname: $(hostname)"
CHANGE_HOSTNAME=$(read_with_timeout 30 "Would you like to change the hostname? This will require a reboot. (y/N): " "n")

if [ "$CHANGE_HOSTNAME" = "y" ] || [ "$CHANGE_HOSTNAME" = "Y" ]; then
    NEW_HOSTNAME=$(read_with_timeout 30 "Enter new hostname: " "")
    if [ -n "$NEW_HOSTNAME" ]; then
        echo "The system will reboot with the new hostname: $NEW_HOSTNAME"
        PROCEED=$(read_with_timeout 30 "Proceed? (y/N): " "n")
        if [ "$PROCEED" = "y" ] || [ "$PROCEED" = "Y" ]; then
            echo "$NEW_HOSTNAME" > /etc/hostname
            sync
            echo "Rebooting in 5 seconds..."
            sleep 5
            reboot
            exit 0
        fi
    fi
fi

# Ask about proceeding with Tailscale installation
PROCEED_INSTALL=$(read_with_timeout 30 "Proceed with Tailscale installation? (Y/n): " "y")

# Exit if user doesn't want to proceed
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

# Update package lists
opkg update

# Install required dependencies
opkg install ca-bundle kmod-tun tailscale

# Start Tailscale service
service tailscale start

# Enable Tailscale to start on boot
service tailscale enable

# Log into Tailscale using the auth key
tailscale up --authkey "$TSKEY"

# Securely removes the key file by first overwriting with random data...
dd if=/dev/urandom of=./tskey bs=1 count=$(stat -c %s ./tskey) conv=notrunc 2>/dev/null
# ... then deleting
rm -f ./tskey

# Configure firewall for Tailscale
echo "Configuring firewall for Tailscale..."

# Create a new Tailscale zone
uci add firewall zone
uci set firewall.@zone[-1].name='tailscale'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci set firewall.@zone[-1].device='tailscale0'

# Add forwarding rules
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='tailscale'
uci set firewall.@forwarding[-1].dest='lan'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='tailscale'

# Commit firewall changes and restart
uci commit firewall
/etc/init.d/firewall restart

# Optionally enable IP forwarding for subnet routing, uncomment:
#echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
#echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
#sysctl -p /etc/sysctl.conf

echo "Installation and configuration complete!"
echo "The auth key file has been securely deleted."
echo "Checking Tailscale status..."
echo "--------------------------"
tailscale status
echo "--------------------------"
echo "You can check your connection status anytime by running: tailscale status"
