import time

import requests
from flask import current_app

API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

RETRYABLE = {429, 503}
MAX_ATTEMPTS = 3


class LLMError(Exception):
    pass


def model_name():
    """Configured model, tolerant of quotes, spaces and a 'models/' prefix."""
    name = (current_app.config["GEMINI_MODEL"] or "").strip().strip("'\"").strip()
    if name.startswith("models/"):
        name = name[len("models/"):]
    return name


def _google_error(resp):
    try:
        return resp.json()["error"]["message"]
    except (KeyError, ValueError, TypeError):
        return resp.text[:300]


def generate(prompt):
    key = current_app.config["GEMINI_API_KEY"]
    if not key:
        raise LLMError("LLM is not configured (GEMINI_API_KEY missing)")
    model = model_name()
    url = API_URL.format(model=model)
    resp = None
    for attempt in range(MAX_ATTEMPTS):
        try:
            resp = requests.post(
                url,
                headers={"x-goog-api-key": key},
                json={"contents": [{"parts": [{"text": prompt}]}]},
                timeout=current_app.config["LLM_TIMEOUT_SECONDS"],
            )
        except requests.RequestException as exc:
            current_app.logger.warning("Gemini request to %s (model %r) failed: %s", url, model, exc)
            raise LLMError(f"LLM request failed: {exc}") from exc
        if resp.status_code not in RETRYABLE or attempt == MAX_ATTEMPTS - 1:
            break
        time.sleep(2 ** attempt)
    if resp.status_code != 200:
        # The key travels in a header, so neither the URL nor Google's message contain it.
        current_app.logger.warning(
            "Gemini HTTP %s from %s (model %r): %s",
            resp.status_code, url, model, _google_error(resp))
        raise LLMError(f"LLM returned HTTP {resp.status_code}")
    try:
        parts = resp.json()["candidates"][0]["content"]["parts"]
        text = "".join(p["text"] for p in parts if "text" in p and not p.get("thought"))
    except (KeyError, IndexError, ValueError, TypeError) as exc:
        raise LLMError("Unexpected LLM response format") from exc
    if not text.strip():
        raise LLMError("LLM returned an empty response")
    return text.strip()


def summarize(text):
    limit = current_app.config["LLM_CONTEXT_CHARS"]
    return generate(
        "Summarize the following article for a student in 5-8 bullet points, "
        "then give a one-sentence takeaway.\n\n" + text[:limit]
    )


def answer(text, question):
    limit = current_app.config["LLM_CONTEXT_CHARS"]
    return generate(
        "Answer the question using only the document below. If the document "
        "does not contain the answer, say so.\n\n"
        f"DOCUMENT:\n{text[:limit]}\n\nQUESTION: {question}"
    )
