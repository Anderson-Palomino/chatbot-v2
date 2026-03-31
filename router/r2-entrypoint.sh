#!/bin/bash
set -e

echo "[R2] Habilitando IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 || echo "[R2] sysctl ya activo (Docker Desktop)"

R1_WAN_IP="172.28.0.10"
echo "[R2] IP de R1 (WAN): ${R1_WAN_IP}"

# ── Interfaces ────────────────────────────────────────────────────────────────
WAN_IF=$(ip route  | grep "172.28.0.0/24" | grep -oP 'dev \K\S+' | head -1)
LAN2_IF=$(ip route | grep "172.28.2.0/24" | grep -oP 'dev \K\S+' | head -1)
[ -z "$WAN_IF"  ] && WAN_IF="eth1"
[ -z "$LAN2_IF" ] && LAN2_IF="eth0"
echo "[R2] WAN=${WAN_IF}  LAN2=${LAN2_IF}"

# ── WireGuard ─────────────────────────────────────────────────────────────────
R2_PRIVATE="4Ge3iX9mZcQ3lW3fR2IKq4f8u9n1D8aB5T6vMrHgJFI="
R1_PUBLIC="IHyFQrYEiTpHEgI7EVd+j7xZ0JyxD1uBuDr1WbITTnA="

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${R2_PRIVATE}
Address = 10.0.3.2/30
ListenPort = 51820

[Peer]
PublicKey = ${R1_PUBLIC}
AllowedIPs = 10.0.3.1/32, 172.28.1.0/24
Endpoint = ${R1_WAN_IP}:51820
PersistentKeepalive = 25
EOF

wg-quick up wg0 || true

# ── nftables (F2) con contadores ──────────────────────────────────────────────
nft flush ruleset

nft -f - <<NFTEOF
table ip filter {
    chain input {
        type filter hook input priority 0; policy accept;
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        ct state established,related accept

        iifname "wg0"        oifname "${LAN2_IF}" accept
        iifname "${LAN2_IF}" oifname "wg0"        accept

        # Bloquear WAN→LAN2 directo con contador
        iifname "${WAN_IF}"  oifname "${LAN2_IF}" counter drop
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100;
        oifname "${WAN_IF}" masquerade
        oifname "wg0"       masquerade
    }
}
NFTEOF

ip route replace 172.28.1.0/24 via "${R1_WAN_IP}" dev "${WAN_IF}" || true
echo "[R2] nftables (F2) configurado."

# ── Monitor de contadores nftables ────────────────────────────────────────────
BOT_URL="http://host.docker.internal:8000/alert"
PREV=0
echo "[R2] Monitor de contadores iniciado..."

while true; do
    CURR=$(nft list table ip filter 2>/dev/null \
        | grep "counter packets" \
        | sed 's/.*packets //' | awk '{print $1}' | head -1)
    CURR=${CURR:-0}

    if [ "$CURR" -gt "$PREV" ]; then
        DIFF=$((CURR - PREV))
        # Últimas IPs en tabla ARP de LAN2 (posibles víctimas del ataque)
        TARGETS=$(ip neigh show dev "${LAN2_IF}" 2>/dev/null \
            | grep -v FAILED | grep -oP '^\S+' | head -3 | tr '\n' ' ')
        [ -z "$TARGETS" ] && TARGETS="172.28.2.0/24"

        echo "[R2-BLOCK] ${DIFF} paquetes bloqueados WAN→LAN2 | targets: ${TARGETS}"
        curl -sf -X POST "$BOT_URL" \
            -H "Content-Type: application/json" \
            -d "{\"router\":\"R2\",\"firewall\":\"nftables\",\"src\":\"WAN\",\"dst\":\"${TARGETS}\",\"proto\":\"DROP\",\"port\":\"${DIFF} pkts\"}" \
            >/dev/null 2>&1 &
        PREV=$CURR
    fi
    sleep 2
done
