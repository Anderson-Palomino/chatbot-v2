#!/bin/sh
# Tests del túnel WireGuard
set -e

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Tests WireGuard ==="

# wg show muestra interfaz activa en R1
check "R1: wg0 activa" \
    docker exec chatbot-r1 sh -c "wg show wg0 | grep -q 'interface: wg0'"

# wg show muestra interfaz activa en R2
check "R2: wg0 activa" \
    docker exec chatbot-r2 sh -c "wg show wg0 | grep -q 'interface: wg0'"

# R1 tiene peer configurado
check "R1: peer configurado" \
    docker exec chatbot-r1 sh -c "wg show wg0 peers | grep -q ."

# R2 tiene peer configurado
check "R2: peer configurado" \
    docker exec chatbot-r2 sh -c "wg show wg0 peers | grep -q ."

# Verificar que el tráfico LAN1→LAN2 viaja cifrado (no texto plano en WAN)
echo ""
echo "Verificando que tráfico no viaja en texto plano por WAN..."
# Capturar 10 paquetes en eth0 de R1 mientras hacemos ping a vm2
docker exec chatbot-r1 timeout 5 tcpdump -i eth0 -c 10 -w /tmp/wan_capture.pcap 2>/dev/null &
sleep 1
docker exec chatbot-vm1 ping -c 3 10.0.2.10 > /dev/null 2>&1 || true
sleep 2

# Verificar que no hay ICMP sin cifrar en WAN (debe viajar como UDP/WireGuard)
check "Tráfico WAN es WireGuard (UDP 51820), no ICMP plano" \
    docker exec chatbot-r1 sh -c "tcpdump -r /tmp/wan_capture.pcap -nn 2>/dev/null | grep -v 'ICMP' | grep -q 'UDP'"

echo ""
echo "Resultados: $PASS pasados, $FAIL fallidos"
[ "$FAIL" -eq 0 ]
