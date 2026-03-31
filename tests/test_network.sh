#!/bin/sh
# Tests de red entre contenedores
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

echo "=== Tests de red ==="

# Ping R1 → R2 (WAN)
check "R1 puede hacer ping a R2 (WAN)" \
    docker exec chatbot-r1 ping -c 2 -W 3 172.28.0.2

# Ping R2 → R1 (WAN)
check "R2 puede hacer ping a R1 (WAN)" \
    docker exec chatbot-r2 ping -c 2 -W 3 172.28.0.1

# Ping vm1 → R1
check "vm1 puede hacer ping a R1" \
    docker exec chatbot-vm1 ping -c 2 -W 3 172.28.1.1

# Ping vm2 → R2
check "vm2 puede hacer ping a R2" \
    docker exec chatbot-vm2 ping -c 2 -W 3 172.28.2.1

# Ping vm1 → vm2 (a través del túnel)
check "vm1 puede hacer ping a vm2 (túnel WireGuard)" \
    docker exec chatbot-vm1 ping -c 2 -W 5 172.28.2.10

# Bot responde en health
check "Bot /health responde 200" \
    curl -sf http://localhost:8000/health

echo ""
echo "Resultados: $PASS pasados, $FAIL fallidos"
[ "$FAIL" -eq 0 ]
