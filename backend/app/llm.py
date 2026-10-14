"""Shared OpenAI helpers: chat answers and embeddings."""
import json
from functools import cache
from openai import OpenAI

from . import store
from .config import settings

KEY_NAME = "openai_api_key"


def api_key() -> tuple[str, str]:
    """(key, source): the key an administrator set in the app wins over the one in .env."""
    saved = store.get_secret(KEY_NAME)
    if saved:
        return saved[0], "admin"
    return settings.openai_api_key, "env" if settings.openai_api_key else "none"


@cache
def _client(key: str) -> OpenAI:
    return OpenAI(api_key=key)


def client() -> OpenAI:
    return _client(api_key()[0])  # read per call, so a new key takes effect without a restart


def check_key(key: str) -> str | None:
    """None if OpenAI accepts the key, else why not. Listing models costs nothing."""
    try:
        OpenAI(api_key=key, max_retries=0, timeout=15).models.list()
        return None
    except Exception as e:  # noqa: BLE001 — any failure means the key can't be used
        status = getattr(e, "status_code", None)
        return "OpenAI rejected this key." if status == 401 else f"Couldn't check the key with OpenAI ({type(e).__name__})."


def chat(system: str, user: str, as_json: bool = False, model: str | None = None, temperature: float = 0.2):
    """One system+user turn. Returns text, or a parsed dict when as_json=True. A low temperature keeps
    answers to the same question consistent."""
    reply = client().chat.completions.create(
        model=model or settings.chat_model, temperature=temperature,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        response_format={"type": "json_object"} if as_json else None,
    )
    text = reply.choices[0].message.content
    return json.loads(text) if as_json else text


def embed(texts: list[str], batch: int = 256) -> list[list[float]]:
    """Sent in batches, so a long document stays under the API's per-request limits."""
    out: list[list[float]] = []
    for i in range(0, len(texts), batch):
        res = client().embeddings.create(model=settings.embed_model, input=texts[i:i + batch])
        out += [d.embedding for d in res.data]
    return out
