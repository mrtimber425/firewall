#!/usr/bin/env bash
# External Gateway firewall — Activity 4-1 (+ optional VPN publish)
# Defaults: EXT_IF=eth0 (Internet), INT_IF=eth1 (LAN)
set -euo pipefail

EXT_IF=${EXT_IF:-eth0}
INT_IF=${INT_IF:-eth1}
WEB_IP=${WEB_IP:-192.168.1.80}

# Optional OpenVPN publish (set VPN_SERVER_IP to enable)
VPN_SERVER_IP=${VPN_SERVER_IP:-}   # e.g. 192.168.1.1
VPN_PORT=${VPN_PORT:-1194}
VPN_PROTO=${VPN_PROTO:-udp}        # or tcp

PUB_IP=${PUB_IP:-$(ip -4 addr show dev "$EXT_IF" | awk '/inet /{print $2}' | cut -d/ -f1)}

# 0) IP forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# 1) Fresh tables
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# 2) Default DROP
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# 3) Baseline
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT  # (optional SSH)

# 4) DNS for the gateway itself
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT  -p tcp --sport 53 -j ACCEPT

# 5) NAT for LAN -> Internet
iptables -t nat -A POSTROUTING -o "$EXT_IF" -j MASQUERADE

# 6) FORWARD rules
# Allow returns first
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# LAN -> Internet: web + DNS
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p tcp --dport 80  -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p udp --dport 53  -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p tcp --dport 53  -m conntrack --ctstate NEW -j ACCEPT

# Internet -> LAN for DNATed web
iptables -A FORWARD -i "$EXT_IF" -o "$INT_IF" -p tcp --dport 80  -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$EXT_IF" -o "$INT_IF" -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT

# 7) DNAT: publish internal web
iptables -t nat -A PREROUTING -i "$EXT_IF" -p tcp --dport 80  -j DNAT --to-destination "$WEB_IP"
iptables -t nat -A PREROUTING -i "$EXT_IF" -p tcp --dport 443 -j DNAT --to-destination "$WEB_IP"

# 8) Hairpin SNAT: ensure replies exit via firewall's public IP
iptables -t nat -A POSTROUTING -o "$INT_IF" -p tcp --dport 80  -d "$WEB_IP" -j SNAT --to-source "$PUB_IP"
iptables -t nat -A POSTROUTING -o "$INT_IF" -p tcp --dport 443 -d "$WEB_IP" -j SNAT --to-source "$PUB_IP"

# 9) OPTIONAL: OpenVPN publish (set VPN_SERVER_IP to enable)
if [[ -n "$VPN_SERVER_IP" ]]; then
  iptables -t nat -A PREROUTING -i "$EXT_IF" -p "$VPN_PROTO" --dport "$VPN_PORT" \
    -j DNAT --to-destination "$VPN_SERVER_IP"
  iptables -A FORWARD -i "$EXT_IF" -o "$INT_IF" -p "$VPN_PROTO" --dport "$VPN_PORT" \
    -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p "$VPN_PROTO" --sport "$VPN_PORT" \
    -m conntrack --ctstate ESTABLISHED -j ACCEPT
  # Also allow TCP/1194 if needed
  iptables -A FORWARD -i "$EXT_IF" -o "$INT_IF" -p tcp --dport "$VPN_PORT" \
    -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p tcp --sport "$VPN_PORT" \
    -m conntrack --ctstate ESTABLISHED -j ACCEPT
  # Hairpin SNAT for VPN
  iptables -t nat -A POSTROUTING -o "$INT_IF" -p "$VPN_PROTO" --dport "$VPN_PORT" \
    -d "$VPN_SERVER_IP" -j SNAT --to-source "$PUB_IP"
fi

# 10) Persist
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
else
  iptables-save > /etc/iptables.rules
fi

# 11) Show summary
echo "==== FILTER ===="; iptables -L -v -n
echo "==== NAT    ===="; iptables -t nat -L -v -n
