# syntax=docker/dockerfile:1
# ---- builder: compile wheels once ----
FROM python:3.12.16-slim-trixie AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---- voice: download the Piper voice model (about 60 MB) ----
FROM python:3.12.16-slim-trixie AS voice
# Pinned to the v1.0.0 release of rhasspy/piper-voices.
ARG VOICE_URL=https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx
WORKDIR /voices
RUN python -c "import sys, urllib.request as u; \
[u.urlretrieve(sys.argv[1] + ext, 'en_US-lessac-medium.onnx' + ext) for ext in ('', '.json')]" \
    "$VOICE_URL"

# ---- runtime: minimal, non-root, Piper voice included ----
FROM python:3.12.16-slim-trixie AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /data/uploads && chown appuser /data/uploads
WORKDIR /app
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
COPY --from=voice /voices ./voices
COPY --chown=appuser app ./app
COPY --chown=appuser wsgi.py .
COPY --chown=appuser migrations ./migrations
ENV FLASK_APP=wsgi:app
USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request as u; u.urlopen('http://localhost:8000/healthz')"
# Long timeout: big PDFs take a while to extract on upload.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "120", \
     "--access-logfile", "-", "wsgi:app"]
