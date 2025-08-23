#!/bin/bash

# Complete Firewall Setup Script - Activities 4-1 & 4-2 Combined
# Includes web server rules, OpenVPN rules, and performance optimizations

echo "Setting up complete optimized iptables firewall rules..."
echo "Includes: Web server forwarding, OpenVPN support, and performance optimizations"

# Variables
WEB_SERVER_IP="192.168.1.80"
OPENVPN_SERVER_IP="192.168.1.1"
EXTERNAL_GATEWAY_PUBLIC_IP="172.16.10.100"

# Clear existing rules
echo "Clearing existing rules..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -X
sudo iptables -t nat -X

# Set default policies to DROP
echo "Setting default policies to DROP..."
sudo iptables --policy INPUT DROP
sudo iptables --policy OUTPUT DROP
sudo iptables --policy FORWARD DROP

# Allow loopback traffic (essential for system operation)
echo "Allowing loopback traffic..."
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# PERFORMANCE OPTIMIZATION: Allow established and related connections FIRST
echo "Setting up efficient connection tracking (PERFORMANCE OPTIMIZATION)..."
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# PERFORMANCE OPTIMIZATION: Allow ICMP (crucial for performance - path MTU discovery, ping, etc.)
echo "Allowing ICMP traffic (PERFORMANCE OPTIMIZATION)..."
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A OUTPUT -p icmp -j ACCEPT
sudo iptables -A FORWARD -p icmp -j ACCEPT

# Set up masquerading for outgoing packets
echo "Setting up masquerading..."
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Allow External Gateway internet access
echo "Allowing External Gateway internet access..."
sudo iptables -A OUTPUT -o eth0 -j ACCEPT
sudo iptables -A INPUT -i eth0 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# Allow DNS traffic (essential for performance)
echo "Allowing DNS traffic..."
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --sport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --sport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# FORWARD rules for DNS (internal network needs DNS)
sudo iptables -A FORWARD -p udp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -p udp --sport 53 -j ACCEPT
sudo iptables -A FORWARD -p tcp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -p tcp --sport 53 -j ACCEPT

# Allow internal network to access internet (NEW connections)
echo "Allowing internal to external traffic..."
sudo iptables -A FORWARD -i eth1 -o eth0 -m conntrack --ctstate NEW -j ACCEPT

# ========================================
# WEB SERVER RULES (Activity 4-1)
# ========================================
echo "Setting up web server port forwarding rules..."

# DNAT rules for web server (HTTP and HTTPS)
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination $WEB_SERVER_IP
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination $WEB_SERVER_IP

# Allow incoming web traffic to web server
sudo iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 80 -d $WEB_SERVER_IP -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 443 -d $WEB_SERVER_IP -m conntrack --ctstate NEW -j ACCEPT

# SNAT for web server traffic
sudo iptables -t nat -A POSTROUTING -o eth1 -p tcp --dport 80 -d $WEB_SERVER_IP -j SNAT --to-source $EXTERNAL_GATEWAY_PUBLIC_IP
sudo iptables -t nat -A POSTROUTING -o eth1 -p tcp --dport 443 -d $WEB_SERVER_IP -j SNAT --to-source $EXTERNAL_GATEWAY_PUBLIC_IP

# ========================================
# OPENVPN RULES (Activity 4-2)
# ========================================
echo "Setting up OpenVPN firewall rules..."

# TCP rules for OpenVPN (though OpenVPN typically uses UDP)
sudo iptables -A FORWARD -i eth0 -o eth1 -p tcp --syn --dport 1194 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -p tcp --syn --sport 1194 -m conntrack --ctstate NEW -j ACCEPT

# DNAT rule for OpenVPN UDP traffic (main OpenVPN traffic)
sudo iptables -t nat -A PREROUTING -p udp --dport 1194 -j DNAT --to-destination $OPENVPN_SERVER_IP

# SNAT rule for OpenVPN UDP traffic
sudo iptables -t nat -A POSTROUTING -o eth1 -p udp --dport 1194 -d $OPENVPN_SERVER_IP -j SNAT --to-source $EXTERNAL_GATEWAY_PUBLIC_IP

# FORWARD rules for OpenVPN UDP traffic
sudo iptables -A FORWARD -p udp --dport 1194 -d $OPENVPN_SERVER_IP -j ACCEPT
sudo iptables -A FORWARD -p udp --dport 1194 -j ACCEPT
sudo iptables -A FORWARD -p udp --sport 1194 -j ACCEPT

# Interface-specific FORWARD rules for OpenVPN UDP
sudo iptables -A FORWARD -i eth0 -o eth1 -p udp --dport 1194 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -p udp --sport 1194 -m conntrack --ctstate ESTABLISHED -j ACCEPT

# Save the rules
echo "Saving iptables rules..."
sudo netfilter-persistent save

# Alternative save method if netfilter-persistent is not available
sudo su -c 'iptables-save > /etc/iptables.rules'

echo ""
echo "================================================"
echo "Complete firewall setup finished!"
echo "================================================"
echo ""
echo "Configured services:"
echo "✓ Web Server: HTTP/HTTPS forwarding to $WEB_SERVER_IP"
echo "✓ OpenVPN: UDP/TCP port 1194 forwarding to $OPENVPN_SERVER_IP"
echo "✓ Performance optimizations enabled"
echo ""
echo "Key optimizations applied:"
echo "✓ ICMP traffic allowed (crucial for performance)"
echo "✓ Efficient connection tracking (ESTABLISHED,RELATED first)"
echo "✓ Optimized rule ordering"
echo "✓ Proper DNS handling"
echo ""
echo "IP Addresses configured:"
echo "- External Gateway Public IP: $EXTERNAL_GATEWAY_PUBLIC_IP"
echo "- Web Server Internal IP: $WEB_SERVER_IP"
echo "- OpenVPN Server Internal IP: $OPENVPN_SERVER_IP"
echo ""
echo "To verify the configuration:"
echo "sudo iptables -L -v -n"
echo "sudo iptables -t nat -L -v -n"
echo ""
echo "Test checklist:"
echo "□ Web server accessible from external (port 80/443)"
echo "□ Internal Ubuntu Desktop has fast internet access"
echo "□ OpenVPN clients can connect (port 1194)"
