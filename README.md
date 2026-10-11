# ReadAloud - app repo

Listen to PDFs like audiobooks; summarize and ask questions with an LLM.

- `backend/` Flask API (auth, PDF upload, text chunks for TTS, Gemini summary/Q&A)
- `mobile/` Flutter Android/web client
- `tts/` Piper natural-voice TTS server (Dockerfile; voice baked in at build time)
- `docker-compose.yml` local dev: Postgres + backend + Piper

## Voices

The Listen tab uses the **natural voice** (Piper, `en_US-lessac-medium`) by
default: the app sends one sentence at a time to `POST /api/tts`, the backend
forwards it to the `tts` container and returns a WAV. If Piper isn't running
(or fails mid-way) the app falls back to the phone/browser voice; the
"Natural voice" switch on the Listen tab toggles between the two. Tap any word
in the displayed passage to read from there. Another voice:
`docker compose build --build-arg VOICE=en_GB-alba-medium tts`.

## Run the backend

```bash
cp .env.example .env      # then fill in secrets, incl. GEMINI_API_KEY
docker compose up --build # API on http://localhost:8000
```

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
