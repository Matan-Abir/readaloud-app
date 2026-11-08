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
# Prometheus metric files shared by the gunicorn workers (see gunicorn.conf.py).
ENV PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus-metrics
# Debian security fixes published after the base image was built (Trivy gate).
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /data/uploads "$PROMETHEUS_MULTIPROC_DIR" \
    && chown appuser /data/uploads "$PROMETHEUS_MULTIPROC_DIR"
WORKDIR /app
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
COPY --from=voice /voices ./voices
COPY --chown=appuser app ./app
COPY --chown=appuser wsgi.py gunicorn.conf.py gunicorn_filters.py ./
COPY --chown=appuser migrations ./migrations
ENV FLASK_APP=wsgi:app
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s \
    CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://localhost:8000/healthz')"]
# Bind address, workers, timeout and logging are in gunicorn.conf.py.
CMD ["gunicorn", "wsgi:app"]
