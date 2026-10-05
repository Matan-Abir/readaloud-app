from prometheus_client import Counter, Histogram

USERS_REGISTERED = Counter("readaloud_users_registered_total", "Users registered")
DOCUMENTS_UPLOADED = Counter("readaloud_documents_uploaded_total", "PDF documents uploaded")
DOCUMENT_PAGES = Histogram(
    "readaloud_document_pages",
    "Pages per uploaded document",
    buckets=(1, 5, 10, 20, 50, 100, 250, 500),
)
TTS_CHUNKS_SERVED = Counter("readaloud_tts_chunks_served_total", "Text chunks served for read-aloud")
LLM_REQUESTS = Counter("readaloud_llm_requests_total", "LLM calls", ["kind", "status"])
LLM_LATENCY = Histogram("readaloud_llm_latency_seconds", "LLM call latency", ["kind"])
TTS_REQUESTS = Counter("readaloud_tts_requests_total", "Natural-voice synthesis calls", ["status"])
TTS_LATENCY = Histogram(
    "readaloud_tts_latency_seconds",
    "Natural-voice synthesis latency per sentence",
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10),
)
