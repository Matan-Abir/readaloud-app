from prometheus_client import Counter, Histogram

USERS_REGISTERED = Counter("readaloud_users_registered_total", "Users registered")
DOCUMENTS_UPLOADED = Counter("readaloud_documents_uploaded_total", "Documents uploaded (PDF and .txt)")
DOCUMENT_PAGES = Histogram(
    "readaloud_document_pages",
    "Pages per uploaded document",
    buckets=(1, 5, 10, 20, 50, 100, 250, 500),
)
TTS_CHUNKS_SERVED = Counter("readaloud_tts_chunks_served_total", "Text chunks served for read-aloud")
LLM_REQUESTS = Counter("readaloud_llm_requests_total", "LLM calls", ["kind", "status"])
LLM_LATENCY = Histogram("readaloud_llm_latency_seconds", "LLM call latency", ["kind"])

# Piper natural voice (POST /api/tts): one request per sentence the app reads.
TTS_REQUESTS = Counter(
    "readaloud_tts_requests_total",
    "Speech requests to the Piper voice",
    ["status"],  # ok | bad_request | unavailable | error
)
TTS_SYNTHESIS_SECONDS = Histogram(
    "readaloud_tts_synthesis_seconds",
    "Time Piper takes to turn one sentence into audio",
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10),
)
TTS_CHARACTERS = Counter("readaloud_tts_characters_total", "Characters spoken by the Piper voice")
