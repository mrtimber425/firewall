#!/bin/bash

echo "[*] Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sed -i '/^#*net.ipv4.ip_forward=/c\net.ipv4.ip_forward=1' /etc/sysctl.conf

echo "[*] Flushing old rules..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -X

echo "[*] Setting default policies to DROP..."
sudo iptables -P INPUT DROP
sudo iptables -P OUTPUT DROP
sudo iptables -P FORWARD DROP

echo "[*] Allowing loopback..."
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# DNS (for firewall itself)
echo "[*] Allowing DNS resolution..."
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --sport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --sport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow outgoing HTTP/HTTPS from firewall
echo "[*] Allowing outbound HTTP/HTTPS from gateway..."
sudo iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# ------------------------------
# External Access to Web Server
# ------------------------------

WEB_SERVER="192.168.1.80"
FIREWALL_PUBLIC_IP="172.16.10.100"

echo "[*] Setting up DNAT for web server..."
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination $WEB_SERVER
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination $WEB_SERVER

echo "[*] Allowing FORWARDING for web server traffic..."
sudo iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "[*] Setting up SNAT for return traffic from web server..."
sudo iptables -t nat -A POSTROUTING -o eth1 -p tcp --dport 80 -d $WEB_SERVER -j SNAT --to-source $FIREWALL_PUBLIC_IP
sudo iptables -t nat -A POSTROUTING -o eth1 -p tcp --dport 443 -d $WEB_SERVER -j SNAT --to-source $FIREWALL_PUBLIC_IP

# ----------------------------------
# Allow Proxy Clients to Access Web
# ----------------------------------

INTERNAL_PROXY="10.10.1.254"

echo "[*] Allowing FORWARDING for proxy clients to access web..."
sudo iptables -A FORWARD -i eth1 -o eth0 -s $INTERNAL_PROXY -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -s $INTERNAL_PROXY -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT

echo "[*] Allowing return traffic to proxy clients..."
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "[*] Enabling NAT (MASQUERADE) for proxy traffic..."
sudo iptables -t nat -A POSTROUTING -s 10.10.1.0/24 -o eth0 -j MASQUERADE

# ----------------------------
# Save rules to persist reboot
# ----------------------------

echo "[*] Saving rules..."
sudo apt install -y netfilter-persistent
sudo netfilter-persistent save

echo "[✓] External Gateway Firewall Configuration Complete."
