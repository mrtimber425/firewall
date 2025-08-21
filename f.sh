#!/bin/bash

# Simplified OpenVPN Firewall Configuration Script
# Run this script on the External Gateway

echo "=========================================="
echo "Simplified OpenVPN Firewall Setup"
echo "=========================================="

# Configuration based on your network setup:
# External Gateway eth0: 172.16.10.100 (external interface)
# External Gateway eth1: 192.168.1.254 (internal interface)  
# Internal Gateway: 192.168.1.1 (OpenVPN server)
EXTERNAL_IP="172.16.10.100"  # Your External Gateway public IP
INTERNAL_GATEWAY="192.168.1.1"

# IP address is now correctly set above

echo "Configuration:"
echo "  External IP: $EXTERNAL_IP"
echo "  Internal Gateway: $INTERNAL_GATEWAY"
echo ""

# Confirm
read -p "Apply firewall rules? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Check for existing rules
echo "Checking for existing OpenVPN rules..."
EXISTING_RULES=$(sudo iptables -L -v -n | grep -c "1194")
EXISTING_NAT=$(sudo iptables -t nat -L -v -n | grep -c "1194")

if [ $EXISTING_RULES -gt 0 ] || [ $EXISTING_NAT -gt 0 ]; then
    echo "⚠️  Found $EXISTING_RULES existing FORWARD rules and $EXISTING_NAT existing NAT rules for port 1194"
    echo ""
    echo "Options:"
    echo "1. Clear existing rules and apply fresh (recommended)"
    echo "2. Add missing rules only (keeps duplicates)"
    echo "3. Show current rules and exit"
    echo ""
    read -p "Choose option (1/2/3): " choice
    
    case $choice in
        1)
            echo "Clearing existing OpenVPN rules..."
            # Remove OpenVPN-specific rules (safer than full flush)
            sudo iptables -D FORWARD -i eth0 -o eth1 -p tcp --syn --dport 1194 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i eth1 -o eth0 -p tcp --syn --sport 1194 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i eth0 -o eth1 -p udp --dport 1194 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i eth1 -o eth0 -p udp --sport 1194 -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || true
            sudo iptables -t nat -D PREROUTING -p udp --dport 1194 -j DNAT --to-destination $INTERNAL_GATEWAY 2>/dev/null || true
            sudo iptables -t nat -D POSTROUTING -o eth1 -p udp --dport 1194 -d $INTERNAL_GATEWAY -j SNAT --to-source $EXTERNAL_IP 2>/dev/null || true
            echo "✅ Existing rules cleared"
            ;;
        2)
            echo "Will add missing rules (may create duplicates)..."
            ;;
        3)
            echo "Current FORWARD rules for port 1194:"
            sudo iptables -L -v -n | grep 1194
            echo ""
            echo "Current NAT rules for port 1194:"  
            sudo iptables -t nat -L -v -n | grep 1194
            echo ""
            echo "Exiting without changes."
            exit 0
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
fi

echo "Applying OpenVPN iptables rules..."

# Function to add rule if it doesn't exist
add_rule_if_missing() {
    local table=""
    local rule_check=""
    local rule_add=""
    
    if [[ $1 == "-t" ]]; then
        table="-t $2"
        shift 2
    fi
    
    rule_check="$table -C $@"
    rule_add="$table -A $@"
    
    if ! sudo iptables $rule_check 2>/dev/null; then
        echo "Adding: iptables $rule_add"
        sudo iptables $rule_add
    else
        echo "Rule already exists: $@"
    fi
}

# Essential rules only
echo "1. Adding UDP forwarding rules..."
add_rule_if_missing FORWARD -i eth0 -o eth1 -p udp --dport 1194 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
add_rule_if_missing FORWARD -i eth1 -o eth0 -p udp --sport 1194 -m conntrack --ctstate ESTABLISHED -j ACCEPT

echo "2. Adding NAT rules..."
add_rule_if_missing -t nat PREROUTING -p udp --dport 1194 -j DNAT --to-destination $INTERNAL_GATEWAY
add_rule_if_missing -t nat POSTROUTING -o eth1 -p udp --dport 1194 -d $INTERNAL_GATEWAY -j SNAT --to-source $EXTERNAL_IP

echo "✅ Rules applied successfully!"

# Show rules
echo ""
echo "Current rules:"
sudo iptables -L -v -n | grep 1194
echo ""
sudo iptables -t nat -L -v -n | grep 1194

# Save rules
echo ""
echo "Saving rules..."
sudo sh -c 'iptables-save > /etc/iptables.rules'
echo "✅ Rules saved to /etc/iptables.rules"

echo ""
echo "🎉 OpenVPN firewall setup complete!"
echo ""
echo "To restore after reboot:"
echo "sudo iptables-restore < /etc/iptables.rules"
