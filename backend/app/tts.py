import io
import os
import threading
import wave

from flask import Blueprint, Response, current_app, jsonify, request
from flask_jwt_extended import jwt_required

bp = Blueprint("tts", __name__, url_prefix="/api/tts")

# Longest text accepted in one request; the app sends one sentence at a time.
MAX_TEXT_CHARS = 2000

_voice = None
_voice_path = None
_lock = threading.Lock()


def _load_voice():
    """The Piper voice, loaded once. None if Piper or the voice file is missing."""
    global _voice, _voice_path
    path = current_app.config["PIPER_VOICE"]
    if _voice is not None and _voice_path == path:
        return _voice
    if not path or not os.path.exists(path) or not os.path.exists(path + ".json"):
        return None
    try:
        from piper import PiperVoice
    except ImportError:
        return None
    with _lock:
        if _voice is None or _voice_path != path:
            _voice = PiperVoice.load(path)
            _voice_path = path
    return _voice


def synthesize(text):
    """WAV bytes for `text`, spoken by the Piper voice."""
    voice = _load_voice()
    buf = io.BytesIO()
    # One synthesis at a time: the model is shared by all request threads.
    with _lock, wave.open(buf, "wb") as wav:
        voice.synthesize_wav(text, wav)
    return buf.getvalue()


@bp.get("")
def status():
    """Tells the app whether the natural voice is available."""
    path = current_app.config["PIPER_VOICE"]
    available = _load_voice() is not None
    return jsonify(available=available, voice=os.path.basename(path) if available else None)


@bp.post("")
@jwt_required()
def speak():
    text = ((request.get_json(silent=True) or {}).get("text") or "").strip()
    if not text or len(text) > MAX_TEXT_CHARS:
        return jsonify(error=f"text is required (max {MAX_TEXT_CHARS} chars)"), 400
    if _load_voice() is None:
        return jsonify(error="Piper voice is not installed on the server"), 503
    return Response(synthesize(text), mimetype="audio/wav")
