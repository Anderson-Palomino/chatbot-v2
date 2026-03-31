#!/bin/bash
set -e

# ── R2: nftables (Firewall 2) ─────────────────────────────────────────────────
# WireGuard: wg0 (10.0.3.2) ↔ R1 (10.0.3.1)

echo "[R2] Habilitando IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 || echo "[R2] sysctl ya activo (Docker Desktop)"

# Resolver IP de R1 en la red WAN via DNS de Docker
R1_WAN_IP=$(getent hosts chatbot-r1 | awk '{print $1}' | head -1)
echo "[R2] IP de R1 (WAN): ${R1_WAN_IP}"

# ── WireGuard keys ────────────────────────────────────────────────────────────
R2_PRIVATE="4Ge3iX9mZcQ3lW3fR2IKq4f8u9n1D8aB5T6vMrHgJFI="
R1_PUBLIC="IHyFQrYEiTpHEgI7EVd+j7xZ0JyxD1uBuDr1WbITTnA="

echo "[R2] Configurando WireGuard wg0..."
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

# Detectar interfaces de red
WAN_IF=$(ip route | grep 172.28.0 | awk '{print $3}' | head -1)
LAN2_IF=$(ip route | grep 172.28.2 | awk '{print $3}' | head -1)
[ -z "$WAN_IF" ] && WAN_IF="eth0"
[ -z "$LAN2_IF" ] && LAN2_IF="eth1"
echo "[R2] WAN_IF=${WAN_IF}  LAN2_IF=${LAN2_IF}"

# ── nftables (F2) ─────────────────────────────────────────────────────────────
echo "[R2] Aplicando reglas nftables (F2)..."

nft flush ruleset

nft -f - <<NFTEOF
table ip filter {
    chain input {
        type filter hook input priority 0; policy accept;
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        ct state established,related accept

        iifname "wg0" oifname "${LAN2_IF}" accept
        iifname "${LAN2_IF}" oifname "wg0" accept

        iifname "${WAN_IF}" oifname "${LAN2_IF}" drop
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100;
        oifname "${WAN_IF}" masquerade
        oifname "wg0" masquerade
    }
}
NFTEOF

echo "[R2] Configuración completa."
nft list ruleset

exec sleep infinity
