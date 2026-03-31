import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete

from ollama_client import generate
from models import Conversation, Message

logger = logging.getLogger(__name__)

HISTORY_LIMIT = 20  # últimos N mensajes enviados a Ollama como contexto


async def _get_or_create_conversation(
    session: AsyncSession, chat_id: int, username: str | None
) -> Conversation:
    result = await session.execute(
        select(Conversation).where(Conversation.chat_id == chat_id)
    )
    conv = result.scalar_one_or_none()
    if conv is None:
        conv = Conversation(chat_id=chat_id, username=username)
        session.add(conv)
        await session.flush()
    return conv


async def _get_history(session: AsyncSession, conversation_id: int) -> list[dict]:
    result = await session.execute(
        select(Message)
        .where(Message.conversation_id == conversation_id)
        .order_by(Message.id.desc())
        .limit(HISTORY_LIMIT)
    )
    messages = result.scalars().all()
    return [{"role": m.role, "content": m.content} for m in reversed(messages)]


async def _save_message(
    session: AsyncSession, conversation_id: int, role: str, content: str
) -> None:
    session.add(Message(conversation_id=conversation_id, role=role, content=content))


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "Hola! Soy un asistente impulsado por Qwen 2.5:7b. "
        "Recuerdo el hilo de nuestra conversación. Escríbeme algo.\n\n"
        "Comandos:\n/help — ayuda\n/reset — borrar historial"
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "/start — Iniciar\n"
        "/help — Mostrar ayuda\n"
        "/myid — Ver tu Chat ID (para alertas de firewall)\n"
        "/reset — Borrar historial de conversación\n"
        "Cualquier mensaje — Chatear con Qwen 2.5:7b"
    )


async def myid_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id
    await update.message.reply_text(
        f"Tu Chat ID es: `{chat_id}`\n\n"
        f"Ponlo en el `.env` como:\n`ADMIN_CHAT_ID={chat_id}`\n\n"
        f"Luego reinicia el bot con:\n`docker compose restart bot`",
        parse_mode="Markdown",
    )


async def reset_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    db_session = context.bot_data["db_session"]
    chat_id = update.effective_chat.id

    async with db_session() as session:
        result = await session.execute(
            select(Conversation).where(Conversation.chat_id == chat_id)
        )
        conv = result.scalar_one_or_none()
        if conv:
            await session.execute(
                delete(Message).where(Message.conversation_id == conv.id)
            )
            await session.commit()

    await update.message.reply_text("Historial borrado. Empezamos de cero.")


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    db_session = context.bot_data["db_session"]
    chat_id = update.effective_chat.id
    username = update.effective_user.username if update.effective_user else None
    text = update.message.text

    async with db_session() as session:
        conv = await _get_or_create_conversation(session, chat_id, username)
        await _save_message(session, conv.id, "user", text)
        await session.commit()

    async with db_session() as session:
        conv = await _get_or_create_conversation(session, chat_id, username)
        history = await _get_history(session, conv.id)

    await update.message.chat.send_action("typing")

    try:
        reply = await generate(history)
    except Exception as exc:
        logger.error("Ollama error: %s", exc)
        reply = "Lo siento, hubo un error al procesar tu mensaje."

    async with db_session() as session:
        conv = await _get_or_create_conversation(session, chat_id, username)
        await _save_message(session, conv.id, "assistant", reply)
        await session.commit()

    # Telegram limita a 4096 chars por mensaje
    if len(reply) > 4096:
        for i in range(0, len(reply), 4096):
            await update.message.reply_text(reply[i:i + 4096])
    else:
        await update.message.reply_text(reply)


def build_application(token: str, db_session_factory) -> Application:
    app = Application.builder().token(token).build()
    app.bot_data["db_session"] = db_session_factory

    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("myid", myid_command))
    app.add_handler(CommandHandler("reset", reset_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    return app
