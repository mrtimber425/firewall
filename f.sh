#!/bin/bash

# Firewall Setup Script - Activity 4-1
# This script restores the iptables configuration for the External Gateway

echo "Setting up iptables firewall rules..."

# Clear existing rules
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -X
sudo iptables -t nat -X

# Set default policies to DROP
echo "Setting default policies..."
sudo iptables --policy INPUT DROP
sudo iptables --policy OUTPUT DROP
sudo iptables --policy FORWARD DROP

# Set up masquerading for outgoing packets
echo "Setting up masquerading..."
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Allow DNS traffic
echo "Allowing DNS traffic..."
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --sport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --sport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Set up port forwarding for incoming packets
echo "Setting up FORWARD rules..."
sudo iptables -A FORWARD -i eth1 -o eth0 -p tcp --syn --dport 80 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -p tcp --syn --dport 80 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -p tcp --syn --dport 443 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -p tcp --syn --dport 443 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -p udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -p tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Set up DNAT for web server (port forwarding)
echo "Setting up DNAT rules..."
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.80
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination 192.168.1.80

# Set up SNAT for web server traffic 
echo "Setting up SNAT rules..."
sudo iptables -t nat -A POSTROUTING -o eth1 -p tcp --dport 80 -d 192.168.1.80 -j SNAT --to-source 172.16.10.100
sudo iptables -t nat -A POSTROUTING -o eth1 -p tcp --dport 443 -d 192.168.1.80 -j SNAT --to-source 172.16.10.100

# Save the rules
echo "Saving iptables rules..."
sudo netfilter-persistent save

# Alternative save method if netfilter-persistent is not available
# sudo su -c 'iptables-save > /etc/iptables.rules'

echo "Firewall setup complete!"
echo ""
echo "To verify the configuration, run:"
echo "sudo iptables -L -v -n"
echo "sudo iptables -t nat -L -v -n"
