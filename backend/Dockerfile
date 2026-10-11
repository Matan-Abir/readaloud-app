# ---- builder: compile wheels once ----
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---- runtime: minimal, non-root ----
FROM python:3.12-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# Pick up Debian security fixes newer than the base image (Trivy gate).
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /data/uploads && chown appuser /data/uploads
WORKDIR /app
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
COPY --chown=appuser app ./app
COPY --chown=appuser wsgi.py .
COPY --chown=appuser migrations ./migrations
ENV FLASK_APP=wsgi:app
USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request as u; u.urlopen('http://localhost:8000/healthz')"
# One process per container keeps Prometheus counters consistent; scale with replicas.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", "--timeout", "120", "--access-logfile", "-", "wsgi:app"]
