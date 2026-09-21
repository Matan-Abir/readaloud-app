# ReadAloud - app repo

Listen to PDFs like audiobooks; summarize and ask questions with an LLM.

- `backend/` Flask API (auth, PDF upload, text chunks for TTS, Gemini summary/Q&A)
- `mobile/` Flutter Android client (uses the phone's built-in text-to-speech)
- `docker-compose.yml` local dev: Postgres + backend

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
