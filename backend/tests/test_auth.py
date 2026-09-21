def test_register_and_login(client):
    creds = {"email": "User@Example.com", "password": "password123"}
    r = client.post("/api/auth/register", json=creds)
    assert r.status_code == 201
    assert r.get_json()["email"] == "user@example.com"
    assert client.post("/api/auth/login", json=creds).status_code == 200


def test_duplicate_email_rejected(client):
    creds = {"email": "a@example.com", "password": "password123"}
    client.post("/api/auth/register", json=creds)
    assert client.post("/api/auth/register", json=creds).status_code == 409


def test_validation(client):
    bad_email = {"email": "bad", "password": "password123"}
    short_pw = {"email": "a@b.com", "password": "short"}
    assert client.post("/api/auth/register", json=bad_email).status_code == 400
    assert client.post("/api/auth/register", json=short_pw).status_code == 400


def test_wrong_password(client):
    client.post("/api/auth/register", json={"email": "a@b.com", "password": "password123"})
    r = client.post("/api/auth/login", json={"email": "a@b.com", "password": "nope"})
    assert r.status_code == 401


def test_documents_require_auth(client):
    assert client.get("/api/documents").status_code == 401
