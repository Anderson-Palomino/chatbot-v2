import pytest
from unittest.mock import AsyncMock, MagicMock, patch


@pytest.mark.asyncio
async def test_start_command_replies():
    from bot_handler import start_command

    update = MagicMock()
    update.message.reply_text = AsyncMock()
    context = MagicMock()

    await start_command(update, context)

    update.message.reply_text.assert_awaited_once()
    reply_text = update.message.reply_text.call_args[0][0]
    assert "Hola" in reply_text or "hola" in reply_text.lower()


@pytest.mark.asyncio
async def test_help_command_replies():
    from bot_handler import help_command

    update = MagicMock()
    update.message.reply_text = AsyncMock()
    context = MagicMock()

    await help_command(update, context)

    update.message.reply_text.assert_awaited_once()
    reply_text = update.message.reply_text.call_args[0][0]
    assert "/start" in reply_text


@pytest.mark.asyncio
async def test_handle_message_calls_ollama():
    from bot_handler import handle_message

    mock_session_cm = AsyncMock()
    mock_session_cm.__aenter__ = AsyncMock(return_value=AsyncMock(
        execute=AsyncMock(return_value=MagicMock(scalar_one_or_none=MagicMock(return_value=None))),
        flush=AsyncMock(),
        add=MagicMock(),
        commit=AsyncMock(),
    ))
    mock_session_cm.__aexit__ = AsyncMock(return_value=False)
    mock_factory = MagicMock(return_value=mock_session_cm)

    update = MagicMock()
    update.effective_chat.id = 123
    update.effective_user.username = "testuser"
    update.message.text = "Hola bot"
    update.message.reply_text = AsyncMock()
    update.message.chat.send_action = AsyncMock()

    context = MagicMock()
    context.bot_data = {"db_session": mock_factory}

    with patch("bot_handler.generate", new=AsyncMock(return_value="Respuesta de prueba")):
        await handle_message(update, context)

    update.message.reply_text.assert_awaited_once_with("Respuesta de prueba")


@pytest.mark.asyncio
async def test_handle_message_ollama_error():
    from bot_handler import handle_message

    mock_session_cm = AsyncMock()
    mock_session_cm.__aenter__ = AsyncMock(return_value=AsyncMock(
        execute=AsyncMock(return_value=MagicMock(scalar_one_or_none=MagicMock(return_value=None))),
        flush=AsyncMock(),
        add=MagicMock(),
        commit=AsyncMock(),
    ))
    mock_session_cm.__aexit__ = AsyncMock(return_value=False)
    mock_factory = MagicMock(return_value=mock_session_cm)

    update = MagicMock()
    update.effective_chat.id = 456
    update.effective_user.username = "erroruser"
    update.message.text = "Mensaje que falla"
    update.message.reply_text = AsyncMock()
    update.message.chat.send_action = AsyncMock()

    context = MagicMock()
    context.bot_data = {"db_session": mock_factory}

    with patch("bot_handler.generate", new=AsyncMock(side_effect=Exception("timeout"))):
        await handle_message(update, context)

    reply = update.message.reply_text.call_args[0][0]
    assert "error" in reply.lower()
