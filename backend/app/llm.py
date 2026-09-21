import requests
from flask import current_app

API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


class LLMError(Exception):
    pass


def generate(prompt):
    key = current_app.config["GEMINI_API_KEY"]
    if not key:
        raise LLMError("LLM is not configured (GEMINI_API_KEY missing)")
    url = API_URL.format(model=current_app.config["GEMINI_MODEL"])
    try:
        resp = requests.post(
            url,
            headers={"x-goog-api-key": key},
            json={"contents": [{"parts": [{"text": prompt}]}]},
            timeout=60,
        )
    except requests.RequestException as exc:
        raise LLMError(f"LLM request failed: {exc}") from exc
    if resp.status_code != 200:
        raise LLMError(f"LLM returned HTTP {resp.status_code}")
    try:
        return resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
    except (KeyError, IndexError, ValueError) as exc:
        raise LLMError("Unexpected LLM response format") from exc


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
