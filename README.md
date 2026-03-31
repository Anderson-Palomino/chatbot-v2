# Chatbot Telegram v2

Bot de Telegram conversacional con memoria de historial, impulsado por **Qwen 2.5:7b** (Ollama local), **FastAPI**, **PostgreSQL** y red simulada con **WireGuard + iptables/nftables**, todo levantado con un solo comando.

---

## Stack

| Capa | Tecnología |
|---|---|
| Bot / API | FastAPI + python-telegram-bot |
| LLM | Ollama — Qwen 2.5:7b |
| Base de datos | PostgreSQL 16 |
| Router F1 | Alpine + iptables |
| Router F2 | Alpine + nftables |
| Túnel cifrado | WireGuard |
| Orquestación | Docker Compose |
| Tests | pytest + httpx + bash |

---

## Requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Ollama](https://ollama.com/) corriendo localmente con `qwen2.5:7b`
- Token de bot de Telegram — [@BotFather](https://t.me/BotFather)
- [ngrok](https://ngrok.com/) para exponer el webhook en local

---

## Configuración rápida

```bash
# 1. Clonar el repositorio
git clone https://github.com/Anderson-Palomino/chatbot-v2.git
cd chatbot-v2

# 2. Editar variables de entorno
#    Poner TELEGRAM_TOKEN y WEBHOOK_URL
nano .env

# 3. Descargar el modelo LLM
ollama pull qwen2.5:7b

# 4. Exponer el puerto con ngrok (nueva terminal)
ngrok http 8000
#    Copiar la URL https://xxxx.ngrok-free.app al campo WEBHOOK_URL del .env

# 5. Levantar todo
docker compose up --build -d
```

---

## Variables de entorno (`.env`)

```env
TELEGRAM_TOKEN=tu_token_aqui

POSTGRES_USER=chatbot
POSTGRES_PASSWORD=chatbot_pass
POSTGRES_DB=chatbot_db
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

OLLAMA_URL=http://host.docker.internal:11434
OLLAMA_MODEL=qwen2.5:7b

WEBHOOK_URL=https://xxxx.ngrok-free.app/webhook
```

---

## Comandos del bot

| Comando | Descripción |
|---|---|
| `/start` | Inicia la conversación |
| `/help` | Muestra ayuda |
| `/reset` | Borra el historial de conversación |
| _(cualquier texto)_ | Chat con Qwen 2.5:7b con memoria de los últimos 20 mensajes |

---

## Topología de red

```
[Telegram]
    ↓ HTTPS webhook
[bot:8000] ──── chatbot-net ──── [postgres:5432]

[vm1-sim: 172.28.1.10]
    ↓
[R1: 172.28.1.1 | 172.28.0.1]  ← iptables (F1)
    ↓ WireGuard wg0 (10.0.3.1 ↔ 10.0.3.2)
[R2: 172.28.0.2 | 172.28.2.1]  ← nftables (F2)
    ↓
[vm2-sim: 172.28.2.10]
    ↓
[Ollama: host.docker.internal:11434]
```

| Red Docker  | Subnet          | Contenedores              |
|-------------|-----------------|---------------------------|
| chatbot-net | bridge          | bot, postgres             |
| lan1        | 172.28.1.0/24   | R1 (eth0), vm1-sim        |
| wan         | 172.28.0.0/24   | R1 (eth1), R2 (eth0)      |
| lan2        | 172.28.2.0/24   | R2 (eth1), vm2-sim        |

---

## Comandos útiles

```bash
# Ver logs del bot en tiempo real
docker logs chatbot-bot -f

# Correr suite de tests
docker exec chatbot-test-runner pytest /tests -v

# Tests de red entre contenedores
bash tests/test_network.sh

# Tests WireGuard
bash tests/test_wireguard.sh

# Estado del túnel WireGuard
docker exec chatbot-r1 wg show
docker exec chatbot-r2 wg show

# Reglas firewall F1 (iptables)
docker exec chatbot-r1 iptables -L -n -v

# Reglas firewall F2 (nftables)
docker exec chatbot-r2 nft list ruleset

# Probar Ollama directo
curl http://localhost:11434/api/chat \
  -d '{"model":"qwen2.5:7b","messages":[{"role":"user","content":"Hola"}],"stream":false}'

# Bajar todo
docker compose down
```

---

## Estructura del proyecto

```
chatbot-v2/
├── docker-compose.yml       ← un solo comando levanta todo
├── .env                     ← variables (no subir al repo)
├── init.sql                 ← schema PostgreSQL
│
├── bot/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py              ← FastAPI + webhook endpoint
│   ├── bot_handler.py       ← handlers Telegram + historial
│   ├── ollama_client.py     ← cliente Ollama con contexto
│   └── models.py            ← SQLAlchemy (conversations + messages)
│
├── router/
│   ├── Dockerfile           ← Alpine + wireguard + iptables + nftables
│   ├── r1-entrypoint.sh     ← WireGuard + iptables (F1)
│   └── r2-entrypoint.sh     ← WireGuard + nftables (F2)
│
└── tests/
    ├── test_api.py          ← pytest: endpoints FastAPI
    ├── test_bot.py          ← pytest: lógica handlers
    ├── test_network.sh      ← ping/traceroute entre contenedores
    └── test_wireguard.sh    ← verificar túnel cifrado
```
