import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, Request, Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from telegram import Update

from bot_handler import build_application

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── DB ────────────────────────────────────────────────────────────────────────

DATABASE_URL = (
    f"postgresql+asyncpg://"
    f"{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}"
    f"@{os.environ['POSTGRES_HOST']}:{os.environ['POSTGRES_PORT']}"
    f"/{os.environ['POSTGRES_DB']}"
)

engine = create_async_engine(DATABASE_URL, echo=False)
SessionFactory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

# ── Telegram app ──────────────────────────────────────────────────────────────

TELEGRAM_TOKEN = os.environ["TELEGRAM_TOKEN"]
ADMIN_CHAT_ID = os.getenv("ADMIN_CHAT_ID")

telegram_app = build_application(TELEGRAM_TOKEN, SessionFactory)

# ── FastAPI ───────────────────────────────────────────────────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI):
    await telegram_app.initialize()
    webhook_url = os.getenv("WEBHOOK_URL")
    if webhook_url:
        await telegram_app.bot.set_webhook(webhook_url)
        logger.info("Webhook set to %s", webhook_url)
    yield
    await telegram_app.shutdown()


app = FastAPI(title="Chatbot v2", lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/test-alert")
async def test_alert():
    """Endpoint para verificar que las alertas llegan a Telegram."""
    fake = FirewallAlert(
        router="R2", firewall="nftables",
        src="172.28.0.1", dst="172.28.2.10",
        proto="ICMP", port="—"
    )
    await firewall_alert(fake)
    return {"sent": True}


@app.post("/webhook")
async def webhook(request: Request):
    data = await request.json()
    update = Update.de_json(data, telegram_app.bot)
    await telegram_app.process_update(update)
    return Response(status_code=200)


# ── Firewall alert endpoint ───────────────────────────────────────────────────

class FirewallAlert(BaseModel):
    router: str
    firewall: str
    src: str
    dst: str
    proto: str
    port: str


FIREWALL_ICONS = {"iptables": "🛡️", "nftables": "🔥"}
PROTO_ICONS = {"TCP": "🔵", "UDP": "🟡", "ICMP": "🟢"}


@app.post("/alert")
async def firewall_alert(alert: FirewallAlert):
    if not ADMIN_CHAT_ID:
        logger.warning("ADMIN_CHAT_ID no configurado, alerta descartada: %s", alert)
        return Response(status_code=200)

    fw_icon = FIREWALL_ICONS.get(alert.firewall, "⚙️")
    proto_icon = PROTO_ICONS.get(alert.proto.upper(), "⚪")
    ts = datetime.now().strftime("%H:%M:%S")

    text = (
        f"🚨 *Paquete bloqueado*\n"
        f"{fw_icon} *{alert.router}* ({alert.firewall})\n"
        f"\n"
        f"📤 *Origen:* `{alert.src}`\n"
        f"📥 *Destino:* `{alert.dst}`\n"
        f"{proto_icon} *Proto:* `{alert.proto}`  *Puerto:* `{alert.port}`\n"
        f"⏰ `{ts}`"
    )

    try:
        await telegram_app.bot.send_message(
            chat_id=int(ADMIN_CHAT_ID),
            text=text,
            parse_mode="Markdown",
        )
    except Exception as exc:
        logger.error("Error enviando alerta: %s", exc)

    return Response(status_code=200)
