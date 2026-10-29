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


def test_analytics_most_asked_and_summary_length(app, client, auth, upload):
    from app.models import Document, Question, db
    first = upload().get_json()["id"]
    second = upload().get_json()["id"]
    with app.app_context():
        db.session.add_all([Question(document_id=second, question="q", answer="a"),
                            Question(document_id=second, question="q", answer="a"),
                            Question(document_id=first, question="q", answer="a")])
        db.session.get(Document, first).summary = "x" * 100
        db.session.get(Document, second).summary = "x" * 300
        db.session.commit()
    data = client.get("/api/analytics", headers=auth).get_json()
    assert [d["id"] for d in data["most_asked"]] == [second, first]
    assert data["most_asked"][0]["questions"] == 2
    assert data["avg_summary_chars"] == 200
    assert data["questions_asked"] == 3
