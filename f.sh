#!/bin/bash

# OpenVPN Firewall Configuration Script
# Run this script on the External Gateway

echo "=========================================="
echo "OpenVPN Firewall Configuration Script"
echo "=========================================="

# Configuration Variables - Based on your network setup:
# External Gateway eth0: 172.16.10.100 (external interface)
# External Gateway eth1: 192.168.1.254 (internal interface)  
# Internal Gateway: 192.168.1.1 (OpenVPN server)
EXTERNAL_IP="172.16.10.100"  # Your External Gateway public IP
INTERNAL_GATEWAY="192.168.1.1"
OPENVPN_PORT="1194"
EXTERNAL_INTERFACE="eth0"
INTERNAL_INTERFACE="eth1"

# Check if running as root or with sudo
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Function to check if command was successful
check_result() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ Failed: $1"
        exit 1
    fi
}

# Check for existing rules
echo "Checking for existing OpenVPN rules..."
EXISTING_RULES=$(sudo iptables -L -v -n | grep -c "1194")
EXISTING_NAT=$(sudo iptables -t nat -L -v -n | grep -c "1194")

if [ $EXISTING_RULES -gt 0 ] || [ $EXISTING_NAT -gt 0 ]; then
    echo "⚠️  Found $EXISTING_RULES existing FORWARD rules and $EXISTING_NAT existing NAT rules for port 1194"
    echo ""
    echo "Options:"
    echo "1. Clear existing rules and apply fresh (recommended)"
    echo "2. Add all rules anyway (may create duplicates)"
    echo "3. Show current rules and exit"
    echo ""
    read -p "Choose option (1/2/3): " choice
    
    case $choice in
        1)
            echo "Clearing existing OpenVPN rules..."
            # Remove OpenVPN-specific rules (safer than full flush)
            sudo iptables -D FORWARD -i eth0 -o eth1 -p tcp --syn --dport 1194 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i eth1 -o eth0 -p tcp --syn --sport 1194 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -p udp --dport 1194 -d 192.168.1.1 -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -p udp --dport 1194 -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -p udp --sport 1194 -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i eth0 -o eth1 -p udp --dport 1194 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i eth1 -o eth0 -p udp --sport 1194 -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || true
            sudo iptables -t nat -D PREROUTING -p udp --dport 1194 -j DNAT --to-destination $INTERNAL_GATEWAY 2>/dev/null || true
            sudo iptables -t nat -D POSTROUTING -o eth1 -p udp --dport 1194 -d $INTERNAL_GATEWAY -j SNAT --to-source $EXTERNAL_IP 2>/dev/null || true
            echo "✅ Existing rules cleared"
            ;;
        2)
            echo "Will add all rules (may create duplicates)..."
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

echo ""
echo "Applying ALL original OpenVPN iptables rules..."

# Complete set of rules as specified in your original instructions
echo "1. Adding TCP forwarding rules..."
$SUDO iptables -A FORWARD -i $EXTERNAL_INTERFACE -o $INTERNAL_INTERFACE -p tcp --syn --dport $OPENVPN_PORT -m conntrack --ctstate NEW -j ACCEPT
check_result "TCP forward rule (eth0 -> eth1)"

$SUDO iptables -A FORWARD -i $INTERNAL_INTERFACE -o $EXTERNAL_INTERFACE -p tcp --syn --sport $OPENVPN_PORT -m conntrack --ctstate NEW -j ACCEPT
check_result "TCP forward rule (eth1 -> eth0)"

echo "2. Adding UDP NAT rules..."
$SUDO iptables -t nat -A PREROUTING -p udp --dport $OPENVPN_PORT -j DNAT --to-destination $INTERNAL_GATEWAY
check_result "UDP DNAT rule"

$SUDO iptables -t nat -A POSTROUTING -o $INTERNAL_INTERFACE -p udp --dport $OPENVPN_PORT -d $INTERNAL_GATEWAY -j SNAT --to-source $EXTERNAL_IP
check_result "UDP SNAT rule"

echo "3. Adding UDP forwarding rules..."
$SUDO iptables -A FORWARD -p udp --dport $OPENVPN_PORT -d $INTERNAL_GATEWAY -j ACCEPT
check_result "UDP forward rule (destination specific)"

$SUDO iptables -A FORWARD -p udp --dport $OPENVPN_PORT -j ACCEPT
check_result "UDP forward rule (general destination)"

$SUDO iptables -A FORWARD -p udp --sport $OPENVPN_PORT -j ACCEPT
check_result "UDP forward rule (source port)"

$SUDO iptables -A FORWARD -i $EXTERNAL_INTERFACE -o $INTERNAL_INTERFACE -p udp --dport $OPENVPN_PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
check_result "UDP forward rule with conntrack (eth0 -> eth1)"

$SUDO iptables -A FORWARD -i $INTERNAL_INTERFACE -o $EXTERNAL_INTERFACE -p udp --sport $OPENVPN_PORT -m conntrack --ctstate ESTABLISHED -j ACCEPT
check_result "UDP forward rule with conntrack (eth1 -> eth0)"

echo ""
echo "✅ All 9 OpenVPN iptables rules applied successfully!"
echo ""
echo "Rules Applied:"
echo "1. TCP FORWARD eth0->eth1 (port 1194)"
echo "2. TCP FORWARD eth1->eth0 (port 1194)" 
echo "3. UDP DNAT to 192.168.1.1 (port 1194)"
echo "4. UDP SNAT from 172.16.10.100 (port 1194)"
echo "5. UDP FORWARD to 192.168.1.1 (port 1194)"
echo "6. UDP FORWARD general (port 1194)"
echo "7. UDP FORWARD source port 1194"
echo "8. UDP FORWARD eth0->eth1 with conntrack"
echo "9. UDP FORWARD eth1->eth0 with conntrack"
echo ""

# Display current rules
echo "Current iptables rules:"
echo "======================"
echo "FILTER table:"
$SUDO iptables -L -v -n --line-numbers

echo ""
echo "NAT table:"
$SUDO iptables -t nat -L -v -n --line-numbers

echo ""

# Save rules
echo "Saving iptables rules..."
$SUDO sh -c 'iptables-save > /etc/iptables.rules'
check_result "Saving iptables rules"

# Create restore script
cat << 'EOF' | $SUDO tee /etc/init.d/iptables-restore > /dev/null
#!/bin/bash
# Restore iptables rules on boot
iptables-restore < /etc/iptables.rules
EOF

$SUDO chmod +x /etc/init.d/iptables-restore
check_result "Creating restore script"

echo ""
echo "🎉 Complete OpenVPN firewall configuration completed!"
echo "   All 9 original rules have been applied successfully!"
echo ""
echo "Rules have been saved to /etc/iptables.rules"
echo "Restore script created at /etc/init.d/iptables-restore"
echo ""
echo "To restore rules after reboot, run:"
echo "sudo /etc/init.d/iptables-restore"
