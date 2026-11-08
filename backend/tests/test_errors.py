import io

from flask_jwt_extended import create_access_token


def test_unknown_route_is_json_404(client):
    r = client.get("/api/nope")
    assert r.status_code == 404
    assert "error" in r.get_json()


def test_wrong_method_is_json_405(client):
    r = client.delete("/api/auth/login")
    assert r.status_code == 405
    assert "error" in r.get_json()


def test_missing_token_is_json_401(client):
    r = client.get("/api/documents")
    assert r.status_code == 401
    assert r.get_json() == {"error": "Missing or malformed Authorization header"}


def test_garbage_token_is_json_401(client):
    r = client.get("/api/documents", headers={"Authorization": "Bearer not-a-jwt"})
    assert r.status_code == 401
    assert r.get_json() == {"error": "Invalid token"}


def test_expired_token_is_json_401(app, client):
    from datetime import timedelta
    token = create_access_token(identity="1", expires_delta=timedelta(seconds=-1))
    r = client.get("/api/documents", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401
    assert "expired" in r.get_json()["error"]


def test_missing_document_is_json_404(client, auth):
    r = client.get("/api/documents/9999", headers=auth)
    assert r.status_code == 404
    assert r.get_json() == {"error": "Document not found"}


def test_upload_over_limit_is_json_413(app, client, auth):
    app.config["MAX_CONTENT_LENGTH"] = 1024 * 1024
    r = client.post("/api/documents", headers=auth,
                    data={"file": (io.BytesIO(b"x" * (2 * 1024 * 1024)), "big.pdf")},
                    content_type="multipart/form-data")
    assert r.status_code == 413
    assert r.get_json() == {"error": "File is too large (max 1 MB)"}


def test_unexpected_exception_is_json_500(app, client):
    app.config["PROPAGATE_EXCEPTIONS"] = False

    @app.get("/boom")
    def boom():
        raise RuntimeError("kaboom")

    r = client.get("/boom")
    assert r.status_code == 500
    assert r.get_json() == {"error": "Internal server error"}
