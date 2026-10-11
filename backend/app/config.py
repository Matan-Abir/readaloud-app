import os
import tempfile


class Config:
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL", "postgresql://readaloud:readaloud@db:5432/readaloud"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "dev-only-change-me")
    UPLOAD_DIR = os.environ.get("UPLOAD_DIR", "/data/uploads")
    MAX_CONTENT_LENGTH = int(os.environ.get("MAX_UPLOAD_MB", "25")) * 1024 * 1024
    GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
    GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-latest")
    # Characters of document text sent to the LLM as context.
    LLM_CONTEXT_CHARS = int(os.environ.get("LLM_CONTEXT_CHARS", "60000"))
    # Approximate size of one chunk handed to the device TTS engine.
    TTS_CHUNK_CHARS = int(os.environ.get("TTS_CHUNK_CHARS", "1500"))
    # Piper natural-voice server (empty = disabled, app uses the device voice).
    PIPER_URL = os.environ.get("PIPER_URL", "")
    # Longest text accepted per synthesis request (the app sends one sentence).
    TTS_MAX_CHARS = int(os.environ.get("TTS_MAX_CHARS", "1000"))


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    JWT_SECRET_KEY = "test-secret-key-that-is-long-enough-32b"
    UPLOAD_DIR = os.path.join(tempfile.gettempdir(), "readaloud-test-uploads")
    GEMINI_API_KEY = ""
    PIPER_URL = ""
