from unittest import mock

from app import tts


def test_status_without_voice(client):
    assert client.get("/api/tts").get_json() == {"available": False, "voice": None}


def test_speak_without_voice(client, auth):
    r = client.post("/api/tts", headers=auth, json={"text": "Hello."})
    assert r.status_code == 503


def test_speak_requires_login_and_text(client, auth):
    assert client.post("/api/tts", json={"text": "Hello."}).status_code == 401
    assert client.post("/api/tts", headers=auth, json={"text": " "}).status_code == 400
    assert client.post("/api/tts", headers=auth, json={"text": "a" * 2001}).status_code == 400


def test_speak_returns_wav(client, auth):
    def fake_wav(text, wav):
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(22050)
        wav.writeframes(b"\0\0" * 100)

    voice = mock.Mock(synthesize_wav=fake_wav)
    with mock.patch.object(tts, "_load_voice", return_value=voice):
        assert client.get("/api/tts").get_json()["available"] is True
        r = client.post("/api/tts", headers=auth, json={"text": "Hello."})
    assert r.status_code == 200
    assert r.mimetype == "audio/wav"
    assert r.data[:4] == b"RIFF"
