# syntax=docker/dockerfile:1
# ---- build: compile the Flutter web app ----
FROM debian:13.7-slim AS build
ARG FLUTTER_VERSION=3.44.9
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 10001 builder
USER 10001
WORKDIR /home/builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ \
    && git config --global --add safe.directory /home/builder/flutter
ENV PATH="/home/builder/flutter/bin:${PATH}"
RUN flutter --disable-analytics && flutter precache --web
WORKDIR /home/builder/app
COPY --chown=builder pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY --chown=builder . .
# --no-web-resources-cdn: fonts and CanvasKit are served by nginx, not fetched from Google.
RUN flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=same-origin

# ---- runtime: nginx (non-root) serving the static files ----
# The slim variant leaves out curl and other extras (fewer CVEs).
FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24-slim AS runtime
ENV BACKEND_HOST=backend BACKEND_PORT=8000 NGINX_ENVSUBST_FILTER=^BACKEND_
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /home/builder/app/build/web /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["wget", "-qO-", "http://127.0.0.1:8080/nginx-health"]
