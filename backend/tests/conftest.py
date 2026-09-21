import io

import pytest

from app import create_app
from app.config import TestConfig
from app.models import db


def make_pdf(text="Hello world. This is a test document about DevOps pipelines. " * 5):
    """Build a minimal single-page PDF containing `text`."""
    esc = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    stream = f"BT /F1 12 Tf 50 700 Td ({esc}) Tj ET".encode()
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for i, body in enumerate(objs, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n" % (len(objs) + 1, xref)
    out += b"%%EOF"
    return out


@pytest.fixture()
def app():
    app = create_app(TestConfig)
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def auth(client):
    creds = {"email": "a@example.com", "password": "password123"}
    client.post("/api/auth/register", json=creds)
    token = client.post("/api/auth/login", json=creds).get_json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def upload(client, auth):
    def _upload(text=None, headers=None):
        pdf = make_pdf(text) if text else make_pdf()
        return client.post(
            "/api/documents",
            headers=headers or auth,
            data={"file": (io.BytesIO(pdf), "paper.pdf")},
            content_type="multipart/form-data",
        )
    return _upload
