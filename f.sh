#!/usr/bin/env bash
# Activity 4-1 firewall for External Gateway
# Default interfaces: eth0 = Internet (public), eth1 = LAN
set -euo pipefail

EXT_IF=${EXT_IF:-eth0}
INT_IF=${INT_IF:-eth1}
WEB_IP=${WEB_IP:-192.168.1.80}
PUB_IP=${PUB_IP:-$(ip -4 addr show dev "$EXT_IF" | awk '/inet /{print $2}' | cut -d/ -f1)}

# 0) Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# 1) Flush existing rules/chains
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# 2) Default policies = DROP (all chains)
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# 3) Baseline safety
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# OPTIONAL: allow SSH mgmt on the gateway
# iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT

# 4) DNS for the gateway itself
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A INPUT  -p tcp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# 5) NAT for LAN to Internet (MASQUERADE)
iptables -t nat -A POSTROUTING -o "$EXT_IF" -j MASQUERADE

# 6) Forward NEW traffic:
#    - LAN -> Internet: web (80/443) + DNS (53)
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p tcp --syn --dport 80  -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p tcp --syn --dport 443 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -p tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
#    - Internet -> LAN: web to internal server (for DNAT below)
iptables -A FORWARD -i "$EXT_IF" -o "$INT_IF" -p tcp --syn --dport 80  -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i "$EXT_IF" -o "$INT_IF" -p tcp --syn --dport 443 -m conntrack --ctstate NEW -j ACCEPT

#    - Allow established flows both ways
iptables -A FORWARD -i "$EXT_IF" -o "$INT_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "$INT_IF" -o "$EXT_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 7) DNAT: publish web server externally (80/443 -> WEB_IP)
iptables -t nat -A PREROUTING -i "$EXT_IF" -p tcp --dport 80  -j DNAT --to-destination "$WEB_IP"
iptables -t nat -A PREROUTING -i "$EXT_IF" -p tcp --dport 443 -j DNAT --to-destination "$WEB_IP"

# 8) SNAT (hairpin): ensure server replies return via the firewall
iptables -t nat -A POSTROUTING -o "$INT_IF" -p tcp --dport 80  -d "$WEB_IP" -j SNAT --to-source "$PUB_IP"
iptables -t nat -A POSTROUTING -o "$INT_IF" -p tcp --dport 443 -d "$WEB_IP" -j SNAT --to-source "$PUB_IP"

# 9) Persist rules if possible
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
else
  iptables-save > /etc/iptables.rules
fi

# 10) Show summary
echo "==== FILTER ===="; iptables -L -v -n
echo "==== NAT    ===="; iptables -t nat -L -v -n
