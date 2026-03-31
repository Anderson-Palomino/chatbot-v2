#!/bin/bash
set -e

echo "[R1] Habilitando IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 || echo "[R1] sysctl ya activo (Docker Desktop)"

R2_WAN_IP="172.28.0.20"
echo "[R1] IP de R2 (WAN): ${R2_WAN_IP}"

# ── Interfaces ────────────────────────────────────────────────────────────────
LAN1_IF=$(ip route | grep "172.28.1.0/24" | grep -oP 'dev \K\S+' | head -1)
WAN_IF=$(ip route  | grep "172.28.0.0/24" | grep -oP 'dev \K\S+' | head -1)
[ -z "$LAN1_IF" ] && LAN1_IF="eth0"
[ -z "$WAN_IF"  ] && WAN_IF="eth1"
echo "[R1] LAN1=${LAN1_IF}  WAN=${WAN_IF}"

# ── WireGuard ─────────────────────────────────────────────────────────────────
R1_PRIVATE="qHNLFRe8GHnNP2x1VrKWrRFLM8PjAR8QLpGIJbbJaEQ="
R2_PUBLIC="CaQ5LnF9qKlKp9rBXXv2c5aFl3SLzLjQz7c0UYYgixY="

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

# ── iptables (F1) ─────────────────────────────────────────────────────────────
iptables -F
iptables -t nat -F
iptables -P FORWARD DROP

iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "${LAN1_IF}" -o "${WAN_IF}" -j ACCEPT
iptables -A FORWARD -i "${LAN1_IF}" -o wg0 -j ACCEPT
iptables -A FORWARD -i wg0 -o "${LAN1_IF}" -j ACCEPT
iptables -t nat -A POSTROUTING -o "${WAN_IF}" -j MASQUERADE
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
iptables -A FORWARD -i "${WAN_IF}" -o "${LAN1_IF}" -j DROP

ip route replace 172.28.2.0/24 via "${R2_WAN_IP}" dev "${WAN_IF}" || true
echo "[R1] iptables (F1) configurado."

# ── Monitor de contadores iptables ────────────────────────────────────────────
BOT_URL="http://host.docker.internal:8000/alert"
PREV=0
echo "[R1] Monitor de contadores iniciado..."

while true; do
    CURR=$(iptables -L FORWARD -n -v 2>/dev/null \
        | awk '/DROP/ && /eth1.*eth0/{print $1; exit}')
    CURR=${CURR:-0}

    if [ "$CURR" -gt "$PREV" ] 2>/dev/null; then
        DIFF=$((CURR - PREV))
        TARGETS=$(ip neigh show dev "${LAN1_IF}" 2>/dev/null \
            | grep -v FAILED | grep -oP '^\S+' | head -3 | tr '\n' ' ')
        [ -z "$TARGETS" ] && TARGETS="172.28.1.0/24"

        echo "[R1-BLOCK] ${DIFF} paquetes bloqueados WAN→LAN1 | targets: ${TARGETS}"
        curl -sf -X POST "$BOT_URL" \
            -H "Content-Type: application/json" \
            -d "{\"router\":\"R1\",\"firewall\":\"iptables\",\"src\":\"WAN\",\"dst\":\"${TARGETS}\",\"proto\":\"DROP\",\"port\":\"${DIFF} pkts\"}" \
            >/dev/null 2>&1 &
        PREV=$CURR
    fi
    sleep 2
done
