# ReadAloud - app repo

Listen to PDFs like audiobooks; summarize and ask questions with an LLM.

- `backend/` Flask API (auth, PDF upload, text chunks for TTS, Gemini summary/Q&A)
- `mobile/` Flutter Android client (uses the phone's built-in text-to-speech)
- `docker-compose.yml` the whole app in containers: Postgres + backend + web app

## Run everything in containers

```bash
cp .env.example .env      # then fill in secrets, incl. GEMINI_API_KEY
docker compose up --build # web app on http://localhost:8080, API on http://localhost:8000
```

The backend image downloads the Piper voice while it builds, so Listen speaks
with the natural voice out of the box. The web image builds the Flutter web app
and serves it from nginx, which also forwards `/api` to the backend, so the
browser only ever talks to `localhost:8080`.

## Natural voice (Piper)

In the web app the Listen tab reads with a Piper voice when the backend has one,
and with the browser's own voice otherwise. The backend loads
`backend/voices/en_US-lessac-medium.onnx` (or the file in `PIPER_VOICE`):

```bash
cd backend
python -m piper.download_voices --download-dir voices en_US-lessac-medium
```

`GET /api/tts` says whether the voice is available; `POST /api/tts {"text": ...}`
returns WAV audio. The app fetches one sentence at a time and the next one
while the current one plays.

## Run the tests

```bash
cd backend && pip install -r requirements-dev.txt && flake8 . && pytest
cd mobile  && flutter analyze && flutter test
```

## Run the Android app

The client needs the API address at build time:

```bash
# Android emulator (10.0.2.2 = your PC)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Physical phone on the same Wi-Fi (use your PC's LAN IP)
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

Windows may ask to allow port 8000 through the firewall for the phone to connect.
