import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
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


@app.post("/webhook")
async def webhook(request: Request):
    data = await request.json()
    update = Update.de_json(data, telegram_app.bot)
    await telegram_app.process_update(update)
    return Response(status_code=200)
