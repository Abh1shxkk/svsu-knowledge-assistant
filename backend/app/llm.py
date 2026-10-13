"""Shared OpenAI helpers: chat answers and embeddings."""
import json
from functools import cache
from openai import OpenAI

from .config import settings


@cache
def client() -> OpenAI:
    return OpenAI(api_key=settings.openai_api_key)


def chat(system: str, user: str, as_json: bool = False, model: str | None = None):
    """One system+user turn. Returns text, or a parsed dict when as_json=True."""
    reply = client().chat.completions.create(
        model=model or settings.chat_model,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        response_format={"type": "json_object"} if as_json else None,
    )
    text = reply.choices[0].message.content
    return json.loads(text) if as_json else text


def embed(texts: list[str]) -> list[list[float]]:
    res = client().embeddings.create(model=settings.embed_model, input=texts)
    return [d.embedding for d in res.data]
