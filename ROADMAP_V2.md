# Chatbot Telegram v2 — Stack Mejorado
## Respuesta a: "¿Cómo mejorarías la infraestructura inicial?"

---

## ¿Qué cambió y por qué?

| Componente | v1 (original) | v2 (mejorado) | Razón |
|---|---|---|---|
| Backend | Laravel 11 + PHP | FastAPI + Python | Async nativo, menos overhead, mejor ecosistema de testing |
| Base de datos | MySQL 8.0 | PostgreSQL 16 | Mejor soporte JSON, más estándar en producción |
| Bot handler | Webhook manual en Laravel | `python-telegram-bot` | Maneja polling/webhook, contexto y handlers nativamente |
| Compose | 2 archivos separados | 1 solo `docker-compose.yml` | Un solo `docker compose up` levanta todo |
| Imagen routers | Custom grande | Alpine Linux (~7 MB) | 10x más liviana, mismas herramientas |
| Tests | Scripts bash | `pytest` + `httpx` | Reportes, fixtures, assert legibles |
| Orquestador | k3s (eliminado) | — | Docker Compose es suficiente |
| VMs | VirtualBox (eliminado) | — | Docker simula la red igual |

**Lo que NO cambia:** Ollama + Qwen 2.5:1.5b · WireGuard · iptables (F1) · nftables (F2) · topología LAN1/WAN/LAN2

---

## Estructura del proyecto

```
chatbot-v2/
├── docker-compose.yml          ← UN solo archivo levanta todo
├── .env                        ← variables (token, passwords)
│
├── bot/                        ← FastAPI + python-telegram-bot
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                 ← FastAPI app + webhook endpoint
│   ├── bot_handler.py          ← handlers de Telegram
│   ├── ollama_client.py        ← llamadas a Ollama
│   └── models.py               ← SQLAlchemy models
│
├── router/                     ← Alpine Linux con wg/iptables/nftables
│   ├── Dockerfile              ← Alpine + wireguard-tools + iptables + nftables
│   ├── r1-entrypoint.sh        ← WireGuard + iptables (F1)
│   └── r2-entrypoint.sh        ← WireGuard + nftables (F2)
│
├── tests/
│   ├── test_api.py             ← pytest: endpoints FastAPI
│   ├── test_bot.py             ← pytest: lógica del bot
│   ├── test_network.sh         ← ping/nmap entre contenedores
│   └── test_wireguard.sh       ← verificar túnel cifrado
│
└── init.sql                    ← schema PostgreSQL inicial
```

---

## Topología de red (igual que v1)

```
[Telegram]
    ↓ webhook
[bot:8000] ──── chatbot-net ──── [postgres:5432]
    ↓
[vm1-sim: 10.0.1.10]
    ↓
[R1: 10.0.1.1 | 10.0.0.1]  ← iptables F1
    ↓ WireGuard wg0 (10.0.3.1 ↔ 10.0.3.2)
[R2: 10.0.0.2 | 10.0.2.1]  ← nftables F2
    ↓
[vm2-sim: 10.0.2.10]
    ↓
[Ollama: host.docker.internal:11434]
```

Redes Docker:
- `chatbot-net` — app (bot + postgres)
- `lan1` — 10.0.1.0/24
- `wan`  — 10.0.0.0/24
- `lan2` — 10.0.2.0/24

---

## Roadmap — 5 días (vs 7 días del v1)

### Día 1 — Setup base

| Tarea | Detalle |
|---|---|
| Crear carpeta `chatbot-v2/` | Estructura de directorios |
| `bot/requirements.txt` | `fastapi uvicorn python-telegram-bot sqlalchemy asyncpg httpx pytest` |
| `bot/Dockerfile` | `python:3.12-slim` + requirements |
| `docker-compose.yml` | Servicios: bot, postgres, r1, r2, vm1-sim, vm2-sim, test-runner |
| `.env` | `TELEGRAM_TOKEN`, `POSTGRES_*`, `OLLAMA_URL` |
| Verificar Ollama local | `curl http://localhost:11434/api/tags` |

**Entregable:** `docker compose up` levanta bot + postgres sin errores.

---

### Día 2 — Bot funcional

| Tarea | Detalle |
|---|---|
| `main.py` | FastAPI con `POST /webhook` y `GET /health` |
| `bot_handler.py` | Handler `/start`, `/help`, mensaje libre → Ollama |
| `ollama_client.py` | `httpx.AsyncClient` → `POST /api/generate` |
| `models.py` | Tablas `conversations` y `messages` con SQLAlchemy async |
| Migrations | `init.sql` ejecutado al iniciar postgres |
| Registrar webhook | `curl .../setWebhook?url=https://...` (ngrok si es local) |

**Entregable:** Mensaje en Telegram → respuesta de Qwen 2.5:1.5b → guardado en PostgreSQL.

---

### Día 3 — Infraestructura de red + WireGuard

| Tarea | Detalle |
|---|---|
| `router/Dockerfile` | `alpine:latest` + `wireguard-tools iptables nftables iproute2` |
| `r1-entrypoint.sh` | IP forwarding, WireGuard wg0 (10.0.3.1), iptables F1 |
| `r2-entrypoint.sh` | IP forwarding, WireGuard wg0 (10.0.3.2), nftables F2 |
| Redes Docker | lan1, wan, lan2 con subnets fijas en compose |
| Verificar túnel | `docker exec chatbot-r1 wg show` |
| Verificar cifrado | `docker exec chatbot-r1 tcpdump -i wg0 -c 5` |

**Entregable:** Túnel WireGuard activo, F1 ≠ F2, tráfico LAN1→LAN2 pasa por el túnel.

---

### Día 4 — Tests con pytest

| Tarea | Detalle |
|---|---|
| `tests/test_api.py` | `httpx.AsyncClient` → `/health`, `/webhook`, respuesta Ollama |
| `tests/test_bot.py` | Lógica de handlers mockeando Telegram |
| `tests/test_network.sh` | ping R1→R2, traceroute, nmap puertos cerrados |
| `tests/test_wireguard.sh` | `wg show` confirma peers, tcpdump sin texto plano |
| Correr desde test-runner | `docker exec chatbot-test-runner pytest /tests -v` |

**Entregable:** Suite de pruebas corriendo desde contenedor dedicado, reporte pytest.

---

### Día 5 — Demo y documentación

| Tarea | Detalle |
|---|---|
| Flujo E2E completo | Telegram → bot → R1 → túnel → R2 → Ollama → respuesta |
| Hardening | Solo puertos necesarios en F1 y F2 |
| `README.md` | Cómo levantar: `docker compose up --build` |
| Diagrama topología | Actualizar con IPs reales |
| Demo al profe | `docker compose up` desde cero, mensaje Telegram, `pytest` |

---

## Comandos clave

```bash
# Levantar todo
docker compose up --build -d

# Ver logs del bot
docker logs chatbot-bot -f

# Correr tests
docker exec chatbot-test-runner pytest /tests -v

# Verificar WireGuard
docker exec chatbot-r1 wg show
docker exec chatbot-r2 wg show

# Ver reglas firewall F1
docker exec chatbot-r1 iptables -L -n -v

# Ver reglas firewall F2
docker exec chatbot-r2 nft list ruleset

# Probar Ollama directo
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen2.5:1.5b","prompt":"Hola","stream":false}'
```

---

## Ventaja principal frente al profe

> "Tomamos la arquitectura original de 2 VMs + k3s + Laravel y la simplificamos a **un solo `docker-compose.yml`** que cualquiera levanta en un comando. La red segmentada, los firewalls diferenciados y el túnel WireGuard son idénticos — solo eliminamos las capas innecesarias."
