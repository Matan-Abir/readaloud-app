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


def test_rejects_unsupported_type(client, auth):
    r = client.post("/api/documents", headers=auth, **_multipart("a.docx", b"hi"))
    assert r.status_code == 400


def _upload_txt(client, auth, data, name="notes.txt"):
    return client.post("/api/documents", headers=auth, **_multipart(name, data))


def _full_text(client, auth, doc_id):
    chunks = client.get(f"/api/documents/{doc_id}/chunks?limit=50", headers=auth).get_json()
    return " ".join(c["text"] for c in chunks["chunks"])


def test_upload_txt_feeds_chunks(client, auth):
    r = _upload_txt(client, auth, "First sentence. Second one!\r\nThird?".encode(), "My Notes.TXT")
    assert r.status_code == 201
    doc = r.get_json()
    assert doc["title"] == "My Notes"
    assert doc["page_count"] == 0
    assert _full_text(client, auth, doc["id"]) == "First sentence. Second one!\nThird?"


def test_txt_decoding_fallbacks(client, auth):
    cases = {
        "utf-8": "Café déjà vu.".encode("utf-8"),
        "utf-8 bom": "\ufeffCafé déjà vu.".encode("utf-8"),
        "utf-16": "Café déjà vu.".encode("utf-16"),
        "cp1252": "Café déjà vu.".encode("cp1252"),
    }
    for name, data in cases.items():
        doc_id = _upload_txt(client, auth, data).get_json()["id"]
        assert _full_text(client, auth, doc_id) == "Café déjà vu.", name


def test_txt_one_paragraph_per_line_becomes_paragraphs(client, auth):
    para = "This is a long paragraph that sits on a single line of the file. " * 3
    doc_id = _upload_txt(client, auth, f"{para}\n{para}".encode()).get_json()["id"]
    chunks = client.get(f"/api/documents/{doc_id}/chunks", headers=auth).get_json()
    assert "\n\n" in chunks["chunks"][0]["text"]


def test_txt_rejects_empty_binary_and_too_large(client, auth, app):
    assert _upload_txt(client, auth, b"  \n\t ").status_code == 422
    assert _upload_txt(client, auth, b"\x00\x01\x02binary").status_code == 422
    app.config["MAX_TEXT_BYTES"] = 10
    assert _upload_txt(client, auth, b"x" * 11).status_code == 413


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
