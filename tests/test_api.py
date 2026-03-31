import pytest
import httpx

BASE_URL = "http://bot:8000"


@pytest.mark.asyncio
async def test_health():
    async with httpx.AsyncClient() as client:
        r = await client.get(f"{BASE_URL}/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_webhook_rejects_bad_json():
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{BASE_URL}/webhook",
            content=b"not-json",
            headers={"Content-Type": "application/json"},
        )
    assert r.status_code in (400, 422)


@pytest.mark.asyncio
async def test_webhook_accepts_valid_update():
    """Un update de Telegram bien formado debe devolver 200."""
    update = {
        "update_id": 1,
        "message": {
            "message_id": 1,
            "date": 0,
            "chat": {"id": 999, "type": "private"},
            "from": {"id": 999, "is_bot": False, "first_name": "Test"},
            "text": "/start",
        },
    }
    async with httpx.AsyncClient() as client:
        r = await client.post(f"{BASE_URL}/webhook", json=update)
    assert r.status_code == 200
