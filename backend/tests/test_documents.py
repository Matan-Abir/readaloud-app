import io
from unittest import mock

from app import llm


def _multipart(name, data):
    return {"data": {"file": (io.BytesIO(data), name)}, "content_type": "multipart/form-data"}


def test_upload_list_get_delete(client, auth, upload):
    r = upload()
    assert r.status_code == 201
    doc_id = r.get_json()["id"]
    assert len(client.get("/api/documents", headers=auth).get_json()) == 1
    assert client.get(f"/api/documents/{doc_id}", headers=auth).status_code == 200
    assert client.delete(f"/api/documents/{doc_id}", headers=auth).status_code == 204
    assert client.get(f"/api/documents/{doc_id}", headers=auth).status_code == 404


def test_rejects_non_pdf(client, auth):
    r = client.post("/api/documents", headers=auth, **_multipart("a.txt", b"hi"))
    assert r.status_code == 400


def test_rejects_corrupt_pdf(client, auth):
    r = client.post("/api/documents", headers=auth, **_multipart("a.pdf", b"not a pdf"))
    assert r.status_code == 422


def test_documents_are_private_per_user(client, upload):
    doc_id = upload().get_json()["id"]
    creds = {"email": "b@example.com", "password": "password123"}
    client.post("/api/auth/register", json=creds)
    token = client.post("/api/auth/login", json=creds).get_json()["access_token"]
    other = {"Authorization": f"Bearer {token}"}
    assert client.get(f"/api/documents/{doc_id}", headers=other).status_code == 404


def test_chunks_and_progress(client, auth, upload):
    doc_id = upload("Sentence one. " * 400).get_json()["id"]
    r = client.get(f"/api/documents/{doc_id}/chunks?limit=2", headers=auth).get_json()
    assert len(r["chunks"]) == 2
    assert r["chunks"][0]["offset"] == 0
    nxt = r["chunks"][1]["offset"]
    put = client.put(f"/api/documents/{doc_id}/progress", headers=auth, json={"progress_char": nxt})
    assert put.status_code == 200
    resumed = client.get(f"/api/documents/{doc_id}/chunks?limit=1", headers=auth).get_json()
    assert resumed["chunks"][0]["offset"] == nxt


def test_progress_validation(client, auth, upload):
    doc_id = upload().get_json()["id"]
    r = client.put(f"/api/documents/{doc_id}/progress", headers=auth, json={"progress_char": 10**9})
    assert r.status_code == 400


def test_summarize_and_ask(client, auth, upload):
    doc_id = upload().get_json()["id"]
    with mock.patch.object(llm, "generate", return_value="mocked"):
        r = client.post(f"/api/documents/{doc_id}/summarize", headers=auth)
        assert r.get_json()["summary"] == "mocked"
        r = client.post(f"/api/documents/{doc_id}/ask", headers=auth, json={"question": "What?"})
    assert r.status_code == 201
    hist = client.get(f"/api/documents/{doc_id}/history", headers=auth).get_json()
    assert hist[0]["answer"] == "mocked"


def test_llm_not_configured_returns_502(client, auth, upload):
    doc_id = upload().get_json()["id"]
    assert client.post(f"/api/documents/{doc_id}/summarize", headers=auth).status_code == 502


def test_ask_requires_question(client, auth, upload):
    doc_id = upload().get_json()["id"]
    assert client.post(f"/api/documents/{doc_id}/ask", headers=auth, json={}).status_code == 400


def test_chunk_offsets_point_at_chunk_text():
    from app.documents import split_chunks

    text = "First sentence here. Second one follows. Third and last."
    for offset, chunk in split_chunks(text, 0, 25):
        assert text[offset:offset + len(chunk)] == chunk
    # Starting mid-document (tap-to-read) begins exactly at the requested word.
    start = text.index("Second")
    offset, chunk = next(split_chunks(text, start, 25))
    assert offset == start and chunk.startswith("Second")
