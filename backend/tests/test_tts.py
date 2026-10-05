from unittest import mock

import pytest
import requests

WAV = b"RIFF....WAVEfmt fake"


@pytest.fixture()
def piper(app):
    app.config["PIPER_URL"] = "http://tts:5000"
    return app


def _ok(content=b"", json=None):
    resp = mock.Mock(status_code=200, content=content)
    resp.raise_for_status.return_value = None
    resp.json.return_value = json or {}
    return resp


def test_requires_login(client):
    assert client.post("/api/tts", json={"text": "Hi."}).status_code == 401


def test_disabled_without_piper(client, auth):
    assert client.get("/api/tts", headers=auth).get_json() == {"available": False, "voice": None}
    assert client.post("/api/tts", headers=auth, json={"text": "Hi."}).status_code == 503


def test_validation(client, auth, piper):
    assert client.post("/api/tts", headers=auth, json={"text": "  "}).status_code == 400
    assert client.post("/api/tts", headers=auth, json={"text": "x" * 1001}).status_code == 400
    assert client.post("/api/tts", headers=auth, json={"text": "Hi.", "speed": 9}).status_code == 400


def test_status_reports_voice(client, auth, piper):
    info = _ok(json={"voice": {"name": "en_US-lessac-medium"}})
    with mock.patch("app.tts.requests.get", return_value=info):
        r = client.get("/api/tts", headers=auth).get_json()
    assert r == {"available": True, "voice": "en_US-lessac-medium"}


def test_synthesize_returns_wav_and_maps_speed(client, auth, piper):
    with mock.patch("app.tts.requests.post", return_value=_ok(content=WAV)) as post:
        r = client.post("/api/tts", headers=auth, json={"text": "Hello there.", "speed": 2.0})
    assert r.status_code == 200
    assert r.mimetype == "audio/wav"
    assert r.data == WAV
    url, kwargs = post.call_args.args[0], post.call_args.kwargs
    assert url == "http://tts:5000/synthesize"
    assert kwargs["json"] == {"text": "Hello there.", "length_scale": 0.5}
    assert "readaloud_tts_requests_total{status=\"ok\"}" in client.get("/metrics").get_data(as_text=True)


def test_piper_down_is_503(client, auth, piper):
    with mock.patch("app.tts.requests.post", side_effect=requests.ConnectionError()):
        r = client.post("/api/tts", headers=auth, json={"text": "Hello."})
    assert r.status_code == 503
    assert r.get_json()["error"] == "Natural voice is unavailable"
