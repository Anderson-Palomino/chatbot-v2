import os
import httpx

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://host.docker.internal:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:7b")

SYSTEM_PROMPT = (
    "Eres un asistente útil y conversacional. "
    "Responde siempre en el mismo idioma que el usuario."
)


async def generate(history: list[dict]) -> str:
    """
    history: lista de dicts con 'role' ('user'|'assistant') y 'content'.
    El último elemento debe ser el mensaje del usuario.
    """
    payload = {
        "model": OLLAMA_MODEL,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}] + history,
        "stream": False,
    }
    async with httpx.AsyncClient(timeout=120.0) as client:
        response = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)
        response.raise_for_status()
        return response.json()["message"]["content"]
