#!/bin/bash
set -e

# ── R1: iptables (Firewall 1) ─────────────────────────────────────────────────
# WireGuard: wg0 (10.0.3.1) ↔ R2 (10.0.3.2)

echo "[R1] Habilitando IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 || echo "[R1] sysctl ya activo (Docker Desktop)"

# Resolver IP de R2 en la red WAN via DNS de Docker
R2_WAN_IP=$(getent hosts chatbot-r2 | awk '{print $1}' | head -1)
echo "[R1] IP de R2 (WAN): ${R2_WAN_IP}"

# ── WireGuard keys ────────────────────────────────────────────────────────────
R1_PRIVATE="qHNLFRe8GHnNP2x1VrKWrRFLM8PjAR8QLpGIJbbJaEQ="
R2_PUBLIC="CaQ5LnF9qKlKp9rBXXv2c5aFl3SLzLjQz7c0UYYgixY="

echo "[R1] Configurando WireGuard wg0..."
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${R1_PRIVATE}
Address = 10.0.3.1/30
ListenPort = 51820

[Peer]
PublicKey = ${R2_PUBLIC}
AllowedIPs = 10.0.3.2/32, 172.28.2.0/24
Endpoint = ${R2_WAN_IP}:51820
PersistentKeepalive = 25
EOF

wg-quick up wg0 || true

# Detectar interfaces de red
LAN1_IF=$(ip route | grep 172.28.1 | awk '{print $3}' | head -1)
WAN_IF=$(ip route | grep 172.28.0 | awk '{print $3}' | head -1)
[ -z "$LAN1_IF" ] && LAN1_IF="eth0"
[ -z "$WAN_IF" ] && WAN_IF="eth1"
echo "[R1] LAN1_IF=${LAN1_IF}  WAN_IF=${WAN_IF}"

# ── iptables (F1) ─────────────────────────────────────────────────────────────
echo "[R1] Aplicando reglas iptables (F1)..."

iptables -F
iptables -t nat -F
iptables -P FORWARD DROP

iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "${LAN1_IF}" -o "${WAN_IF}" -j ACCEPT
iptables -A FORWARD -i "${LAN1_IF}" -o wg0 -j ACCEPT
iptables -A FORWARD -i wg0 -o "${LAN1_IF}" -j ACCEPT
iptables -t nat -A POSTROUTING -o "${WAN_IF}" -j MASQUERADE
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE

echo "[R1] Configuración completa."
iptables -L -n -v

exec sleep infinity
