"""Natural-voice text-to-speech via a Piper container (see ../tts).

The app reads a document sentence by sentence: it posts each sentence here and
plays the returned WAV. When Piper isn't configured or is down, the app falls
back to the device's own voice.
"""
import time

import requests
from flask import Blueprint, Response, current_app, jsonify, request
from flask_jwt_extended import jwt_required

from .metrics import TTS_LATENCY, TTS_REQUESTS

bp = Blueprint("tts", __name__, url_prefix="/api/tts")


def _piper_url():
    return current_app.config["PIPER_URL"].rstrip("/")


@bp.get("")
@jwt_required()
def status():
    """Whether the natural voice is available, and which voice it is."""
    if not _piper_url():
        return jsonify(available=False, voice=None)
    try:
        resp = requests.get(f"{_piper_url()}/info", timeout=3)
        resp.raise_for_status()
        voice = (resp.json().get("voice") or {}).get("name")
    except (requests.RequestException, ValueError):
        return jsonify(available=False, voice=None)
    return jsonify(available=True, voice=voice)


@bp.post("")
@jwt_required()
def synthesize():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify(error="text is required"), 400
    max_chars = current_app.config["TTS_MAX_CHARS"]
    if len(text) > max_chars:
        return jsonify(error=f"text must be at most {max_chars} characters"), 400
    speed = data.get("speed", 1.0)
    if not isinstance(speed, (int, float)) or not 0.5 <= speed <= 3.0:
        return jsonify(error="speed must be a number between 0.5 and 3.0"), 400
    if not _piper_url():
        return jsonify(error="Natural voice is not configured"), 503

    start = time.perf_counter()
    try:
        resp = requests.post(
            f"{_piper_url()}/synthesize",
            # Piper's length_scale is duration: smaller = faster speech.
            json={"text": text, "length_scale": round(1.0 / speed, 3)},
            timeout=30,
        )
        resp.raise_for_status()
    except requests.RequestException:
        TTS_REQUESTS.labels("error").inc()
        return jsonify(error="Natural voice is unavailable"), 503
    TTS_REQUESTS.labels("ok").inc()
    TTS_LATENCY.observe(time.perf_counter() - start)
    return Response(resp.content, mimetype="audio/wav")
