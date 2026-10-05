# Piper natural-voice TTS server (https://github.com/OHF-Voice/piper1-gpl, GPL-3).
# The voice model (~60 MB) is baked in at build time so the container starts
# offline and fast. Change voice with: --build-arg VOICE=en_GB-alba-medium
FROM python:3.12-slim

ARG PIPER_VERSION=1.8.0
ARG VOICE=en_US-lessac-medium
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 VOICE=${VOICE}

# Pick up Debian security fixes newer than the base image (Trivy gate).
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "piper-tts[http]==${PIPER_VERSION}"
RUN useradd --create-home --uid 10001 piper \
    && mkdir /voices \
    && python -m piper.download_voices --data-dir /voices "${VOICE}" \
    && chown -R piper /voices

USER piper
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request as u; u.urlopen('http://localhost:5000/info')"
CMD ["sh", "-c", "exec python -m piper.http_server --host 0.0.0.0 --port 5000 --data-dir /voices -m \"$VOICE\""]
