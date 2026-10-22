def test_analytics_empty(client, auth):
    r = client.get("/api/analytics", headers=auth)
    assert r.status_code == 200
    assert r.get_json()["documents"] == 0


def test_analytics_counts_documents_and_progress(client, auth, upload):
    doc_id = upload().get_json()["id"]
    client.put(f"/api/documents/{doc_id}/progress", headers=auth, json={"progress_char": 10})
    data = client.get("/api/analytics", headers=auth).get_json()
    assert data["documents"] == 1
    assert data["listened_percent"] > 0


def test_analytics_requires_login(client):
    assert client.get("/api/analytics").status_code == 401
